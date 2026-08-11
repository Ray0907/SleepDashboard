import Foundation

struct AutoSleepCSVImporter: SleepDataSource {
	private let time_zone_identifier: String

	init(timeZone: TimeZone = .current) {
		self.time_zone_identifier = timeZone.identifier
	}

	func parse(fileURL: URL) -> SleepRecordStream {
		let time_zone_identifier = self.time_zone_identifier
		let parse_task = Task.detached {
			try Self.parseFile(
				fileURL: fileURL,
				timeZoneIdentifier: time_zone_identifier
			)
		}
		let records = AsyncThrowingStream<ParsedSleepRecord, Error> { continuation in
			let delivery_task = Task {
				do {
					let output = try await parse_task.value

					for record in output.records {
						try Task.checkCancellation()
						continuation.yield(record)
					}

					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}

			continuation.onTermination = { termination in
				if case .cancelled = termination {
					delivery_task.cancel()
				}
			}
		}
		let summary_task = Task {
			try await parse_task.value.summary
		}

		return SleepRecordStream(records: records, summaryTask: summary_task)
	}

	private static func parseFile(
		fileURL: URL,
		timeZoneIdentifier: String
	) throws -> ParsedFileOutput {
		let data: Data

		do {
			data = try Data(contentsOf: fileURL)
		} catch {
			throw AutoSleepCSVImportError.unreadableFile(fileURL.lastPathComponent)
		}

		guard var text = String(data: data, encoding: .utf8) else {
			throw AutoSleepCSVImportError.invalidUTF8
		}

		if text.first == "\u{FEFF}" {
			text.removeFirst()
		}

		let directive = removeSeparatorDirective(from: text)
		text = directive.text
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw AutoSleepCSVImportError.emptyFile
		}

		let delimiter = directive.delimiter ?? detectDelimiter(in: text)
		let csv_records = parseCSV(text, delimiter: delimiter)
		guard let header_record = csv_records.first else {
			throw AutoSleepCSVImportError.emptyFile
		}
		guard header_record.issue == nil else {
			throw AutoSleepCSVImportError.invalidHeader(
				header_record.issue ?? "unknown quoting error"
			)
		}

		let columns = try resolveColumns(header_record.fields)
		let parser = RowParser(
			columns: columns,
			timeZoneIdentifier: timeZoneIdentifier,
			sourceFile: fileURL.lastPathComponent
		)
		var parsed_records: [ParsedSleepRecord] = []
		var skipped_rows: [SleepSkippedRow] = []

		for csv_record in csv_records.dropFirst() where !csv_record.isBlank {
			do {
				try Task.checkCancellation()
				let record = try parser.parse(csv_record, headerCount: header_record.fields.count)
				parsed_records.append(record)
			} catch is CancellationError {
				throw CancellationError()
			} catch {
				skipped_rows.append(
					SleepSkippedRow(
						rowNumber: csv_record.rowNumber,
						reason: error.localizedDescription
					)
				)
			}
		}

		return ParsedFileOutput(
			records: parsed_records,
			summary: SleepParseSummary(
				parsedCount: parsed_records.count,
				skippedRows: skipped_rows
			)
		)
	}

	private static func removeSeparatorDirective(
		from text: String
	) -> (text: String, delimiter: Character?) {
		let scalars = text.unicodeScalars
		let line_end = scalars.firstIndex { $0.value == 10 } ?? scalars.endIndex
		let first_line = String(scalars[..<line_end])
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()
		let delimiter: Character?

		if first_line == "sep=;" {
			delimiter = ";"
		} else if first_line == "sep=," {
			delimiter = ","
		} else {
			return (text, nil)
		}

		guard line_end != scalars.endIndex else {
			return ("", delimiter)
		}

		let content_start = scalars.index(after: line_end)
		return (String(scalars[content_start...]), delimiter)
	}

	private static func detectDelimiter(in text: String) -> Character {
		let scalars = Array(text.unicodeScalars)
		var comma_count = 0
		var semicolon_count = 0
		var is_quoted = false
		var index = 0

		while index < scalars.count {
			let scalar = scalars[index]

			if scalar.value == 34 {
				if is_quoted, index + 1 < scalars.count, scalars[index + 1].value == 34 {
					index += 2
					continue
				}

				is_quoted.toggle()
			} else if !is_quoted {
				if scalar.value == 44 {
					comma_count += 1
				} else if scalar.value == 59 {
					semicolon_count += 1
				} else if scalar.value == 10 || scalar.value == 13 {
					break
				}
			}

			index += 1
		}

		return semicolon_count > comma_count ? ";" : ","
	}

	private static func resolveColumns(_ headers: [String]) throws -> [CSVColumn: Int] {
		var columns: [CSVColumn: Int] = [:]

		for (index, header) in headers.enumerated() {
			let normalized_header = normalizeHeader(header)

			for column in CSVColumn.allCases where column.aliases.contains(normalized_header) {
				if columns[column] == nil {
					columns[column] = index
				}
			}
		}

		let missing_columns = CSVColumn.required
			.filter { columns[$0] == nil }
			.map(\.displayName)

		guard missing_columns.isEmpty else {
			throw AutoSleepCSVImportError.missingRequiredColumns(missing_columns)
		}

		return columns
	}

	private static func normalizeHeader(_ header: String) -> String {
		header.lowercased().filter { $0.isLetter || $0.isNumber }
	}
}

private struct ParsedFileOutput: Sendable {
	let records: [ParsedSleepRecord]
	let summary: SleepParseSummary
}

private struct RowParser: Sendable {
	let columns: [CSVColumn: Int]
	let timeZoneIdentifier: String
	let sourceFile: String

	func parse(_ csv_record: CSVRecord, headerCount: Int) throws -> ParsedSleepRecord {
		if let issue = csv_record.issue {
			throw RowParseError(reason: issue)
		}
		guard csv_record.fields.count == headerCount else {
			throw RowParseError(
				reason: "Expected \(headerCount) columns but found \(csv_record.fields.count)."
			)
		}
		guard let time_zone = TimeZone(identifier: timeZoneIdentifier) else {
			throw RowParseError(reason: "The import time zone is unavailable.")
		}

		let start_date = try parseDate(.startDate, fields: csv_record.fields, timeZone: time_zone)
		let end_date = try parseDate(.endDate, fields: csv_record.fields, timeZone: time_zone)
		let bedtime = try parseDate(.bedtime, fields: csv_record.fields, timeZone: time_zone)
		let wake_time = try parseDate(.wakeTime, fields: csv_record.fields, timeZone: time_zone)
		let in_bed = try parseDuration(.inBed, fields: csv_record.fields)
		let awake = try parseDuration(.awake, fields: csv_record.fields)
		let asleep = try parseDuration(.asleep, fields: csv_record.fields)
		let deep = try parseDuration(.deep, fields: csv_record.fields)
		let efficiency = try parseEfficiency(fields: csv_record.fields)
		let sessions = try parseSessions(fields: csv_record.fields)

		return ParsedSleepRecord(
			sourceFile: sourceFile,
			sourceRowFingerprint: StableSHA256.hexDigest(csv_record.raw),
			startDate: start_date,
			endDate: end_date,
			timeZoneIdentifier: timeZoneIdentifier,
			bedtime: bedtime,
			wakeTime: wake_time,
			inBedDuration: in_bed,
			awakeDuration: awake,
			asleepDuration: asleep,
			deepDuration: deep,
			efficiency: efficiency,
			sleepBPM: try parseOptionalDouble(.sleepBPM, fields: csv_record.fields),
			hrv: try parseOptionalDouble(.hrv, fields: csv_record.fields),
			spo2Avg: try parseOptionalDouble(.spo2Avg, fields: csv_record.fields),
			spo2Min: try parseOptionalDouble(.spo2Min, fields: csv_record.fields),
			spo2Max: try parseOptionalDouble(.spo2Max, fields: csv_record.fields),
			respAvg: try parseOptionalDouble(.respAvg, fields: csv_record.fields),
			respMin: try parseOptionalDouble(.respMin, fields: csv_record.fields),
			respMax: try parseOptionalDouble(.respMax, fields: csv_record.fields),
			apneaHypopneaIndex: try parseOptionalDouble(.apnea, fields: csv_record.fields),
			sessionsInNight: sessions
		)
	}

	private func parseDate(
		_ column: CSVColumn,
		fields: [String],
		timeZone: TimeZone
	) throws -> Date {
		let value = requiredValue(column, fields: fields)
		let formatter = DateFormatter()
		formatter.calendar = Calendar(identifier: .gregorian)
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = timeZone
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		formatter.isLenient = false

		guard let date = formatter.date(from: value) else {
			throw RowParseError(
				reason: "Invalid \(column.displayName) date; expected yyyy-MM-dd HH:mm:ss."
			)
		}

		return date
	}

	private func parseDuration(
		_ column: CSVColumn,
		fields: [String]
	) throws -> TimeInterval {
		let value = requiredValue(column, fields: fields)
		let components = value.split(separator: ":", omittingEmptySubsequences: false)

		guard components.count == 3,
			let hours = Int(components[0]), hours >= 0,
			let minutes = Int(components[1]), (0..<60).contains(minutes),
			let seconds = Int(components[2]), (0..<60).contains(seconds)
		else {
			throw RowParseError(
				reason: "Invalid \(column.displayName) duration; expected HH:mm:ss."
			)
		}

		return TimeInterval(hours * 3_600 + minutes * 60 + seconds)
	}

	private func parseEfficiency(fields: [String]) throws -> Double {
		var value = requiredValue(.efficiency, fields: fields)

		if value.hasSuffix("%") {
			value.removeLast()
		}

		guard let efficiency = Double(value), (0...100).contains(efficiency) else {
			throw RowParseError(reason: "Invalid efficiency; expected a value from 0 to 100.")
		}

		return efficiency
	}

	private func parseSessions(fields: [String]) throws -> Int {
		let value = requiredValue(.sessions, fields: fields)

		guard let sessions = Int(value), sessions >= 0 else {
			throw RowParseError(reason: "Invalid sessions; expected a non-negative integer.")
		}

		return sessions
	}

	private func parseOptionalDouble(
		_ column: CSVColumn,
		fields: [String]
	) throws -> Double? {
		guard let index = columns[column] else {
			return nil
		}

		let value = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
		guard !value.isEmpty else {
			return nil
		}
		guard let result = Double(value), result.isFinite else {
			throw RowParseError(reason: "Invalid optional metric \(column.displayName).")
		}

		return result
	}

	private func requiredValue(_ column: CSVColumn, fields: [String]) -> String {
		guard let index = columns[column] else {
			preconditionFailure("Required CSV column was validated before row parsing")
		}

		return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

private struct RowParseError: LocalizedError {
	let reason: String

	var errorDescription: String? {
		reason
	}
}

private enum CSVColumn: CaseIterable, Sendable {
	case startDate
	case endDate
	case bedtime
	case wakeTime
	case inBed
	case awake
	case asleep
	case deep
	case efficiency
	case sleepBPM
	case hrv
	case spo2Avg
	case spo2Min
	case spo2Max
	case respAvg
	case respMin
	case respMax
	case apnea
	case sessions

	static let required: [CSVColumn] = [
		.startDate, .endDate, .bedtime, .wakeTime, .inBed, .awake, .asleep, .deep,
		.efficiency, .sessions
	]

	var displayName: String {
		switch self {
		case .startDate: "startDate"
		case .endDate: "endDate"
		case .bedtime: "bedtime"
		case .wakeTime: "wakeTime"
		case .inBed: "inBed"
		case .awake: "awake"
		case .asleep: "asleep"
		case .deep: "deep"
		case .efficiency: "efficiency"
		case .sleepBPM: "sleepBPM"
		case .hrv: "hrv"
		case .spo2Avg: "spo2Avg"
		case .spo2Min: "spo2Min"
		case .spo2Max: "spo2Max"
		case .respAvg: "respAvg"
		case .respMin: "respMin"
		case .respMax: "respMax"
		case .apnea: "apnea"
		case .sessions: "sessions"
		}
	}

	var aliases: Set<String> {
		switch self {
		case .startDate: ["startdate", "start", "from", "fromdate"]
		case .endDate: ["enddate", "end", "to", "todate"]
		case .bedtime: ["bedtime", "sleepstart"]
		case .wakeTime: ["waketime", "wakeup", "sleepend"]
		case .inBed: ["inbed", "inbedduration"]
		case .awake: ["awake", "awakeduration"]
		case .asleep: ["asleep", "asleepduration", "sleepduration"]
		case .deep: ["deep", "deepduration", "deepsleep"]
		case .efficiency: ["efficiency", "sleepefficiency"]
		case .sleepBPM: ["sleepbpm", "bpm", "sleepheartrate"]
		case .hrv: ["hrv", "heartratevariability"]
		case .spo2Avg: ["spo2avg", "spo2average", "averagespo2"]
		case .spo2Min: ["spo2min", "minimumspo2"]
		case .spo2Max: ["spo2max", "maximumspo2"]
		case .respAvg: ["respavg", "respaverage", "respirationavg"]
		case .respMin: ["respmin", "respirationmin"]
		case .respMax: ["respmax", "respirationmax"]
		case .apnea: ["apnea", "ahi", "apneahypopneaindex"]
		case .sessions: ["sessions", "sessionsinnight", "sessioncount"]
		}
	}
}

private struct CSVRecord: Sendable {
	let fields: [String]
	let raw: String
	let rowNumber: Int
	let issue: String?

	var isBlank: Bool {
		fields.allSatisfy { $0.isEmpty }
	}
}

private enum CSVState {
	case unquoted
	case quoted
	case quoteClosed
}

private func parseCSV(_ text: String, delimiter: Character) -> [CSVRecord] {
	let scalars = Array(text.unicodeScalars)
	let delimiter_value = delimiter.unicodeScalars.first?.value ?? 44
	var records: [CSVRecord] = []
	var fields: [String] = []
	var field = ""
	var raw = ""
	var issue: String?
	var state = CSVState.unquoted
	var row_number = 1
	var index = 0

	func finishRecord() {
		fields.append(field)
		records.append(
			CSVRecord(fields: fields, raw: raw, rowNumber: row_number, issue: issue)
		)
		fields = []
		field = ""
		raw = ""
		issue = nil
		state = .unquoted
	}

	while index < scalars.count {
		let scalar = scalars[index]
		let scalar_text = String(scalar)

		switch state {
		case .unquoted:
			if scalar.value == delimiter_value {
				fields.append(field)
				field = ""
				raw.append(scalar_text)
			} else if scalar.value == 34, field.isEmpty {
				state = .quoted
				raw.append(scalar_text)
			} else if scalar.value == 34 {
				issue = issue ?? "A quote appeared inside an unquoted field."
				field.append(scalar_text)
				raw.append(scalar_text)
			} else if scalar.value == 13 || scalar.value == 10 {
				finishRecord()
				if scalar.value == 13,
					index + 1 < scalars.count,
					scalars[index + 1].value == 10 {
					index += 1
				}
				row_number += 1
			} else {
				field.append(scalar_text)
				raw.append(scalar_text)
			}
		case .quoted:
			if scalar.value == 34,
				index + 1 < scalars.count,
				scalars[index + 1].value == 34 {
				field.append("\"")
				raw.append("\"\"")
				index += 1
			} else if scalar.value == 34 {
				state = .quoteClosed
				raw.append(scalar_text)
			} else {
				field.append(scalar_text)
				raw.append(scalar_text)
				if scalar.value == 10 {
					row_number += 1
				}
			}
		case .quoteClosed:
			if scalar.value == delimiter_value {
				fields.append(field)
				field = ""
				state = .unquoted
				raw.append(scalar_text)
			} else if scalar.value == 13 || scalar.value == 10 {
				finishRecord()
				if scalar.value == 13,
					index + 1 < scalars.count,
					scalars[index + 1].value == 10 {
					index += 1
				}
				row_number += 1
			} else {
				issue = issue ?? "Unexpected text followed a closing quote."
				raw.append(scalar_text)
			}
		}

		index += 1
	}

	if state == .quoted {
		issue = issue ?? "A quoted field was not closed."
	}
	if !fields.isEmpty || !field.isEmpty || !raw.isEmpty {
		finishRecord()
	}

	return records
}
