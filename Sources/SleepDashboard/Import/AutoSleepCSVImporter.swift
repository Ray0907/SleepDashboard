import Foundation

struct AutoSleepCSVImporter: SleepDataSource {
	private let time_zone_identifier: String
	private let chunk_source: any CSVChunkSource

	init(
		timeZone: TimeZone = .current,
		chunkSource: any CSVChunkSource = FileCSVChunkSource()
	) {
		self.time_zone_identifier = timeZone.identifier
		self.chunk_source = chunkSource
	}

	func parse(fileURL: URL) -> SleepRecordStream {
		let time_zone_identifier = self.time_zone_identifier
		let chunk_source = self.chunk_source
		let task_box = ParseTaskBox()
		let pair = AsyncThrowingStream<ParsedSleepRecord, Error>.makeStream(
			bufferingPolicy: .bufferingOldest(1)
		)
		pair.continuation.onTermination = { termination in
			if case .cancelled = termination {
				task_box.cancel()
			}
		}
		let parse_task = Task.detached {
			try await Self.parseFile(
				fileURL: fileURL,
				timeZoneIdentifier: time_zone_identifier,
				chunkSource: chunk_source,
				continuation: pair.continuation
			)
		}
		task_box.set(parse_task)

		return SleepRecordStream(records: pair.stream, summaryTask: parse_task)
	}

	private static func parseFile(
		fileURL: URL,
		timeZoneIdentifier: String,
		chunkSource: any CSVChunkSource,
		continuation: AsyncThrowingStream<ParsedSleepRecord, Error>.Continuation
	) async throws -> SleepParseSummary {
		let reader: any CSVChunkReader

		do {
			reader = try chunkSource.open(fileURL: fileURL)
		} catch {
			let import_error = AutoSleepCSVImportError.unreadableFile(
				fileURL.lastPathComponent
			)
			continuation.finish(throwing: import_error)
			throw import_error
		}

		do {
			let summary = try await consumeFile(
				reader: reader,
				fileURL: fileURL,
				timeZoneIdentifier: timeZoneIdentifier,
				continuation: continuation
			)
			await reader.close()
			continuation.finish()
			return summary
		} catch {
			await reader.close()
			continuation.finish(throwing: error)
			throw error
		}
	}

	private static func consumeFile(
		reader: any CSVChunkReader,
		fileURL: URL,
		timeZoneIdentifier: String,
		continuation: AsyncThrowingStream<ParsedSleepRecord, Error>.Continuation
	) async throws -> SleepParseSummary {
		var decoder = IncrementalCSVDecoder()
		var row_consumer = CSVRowConsumer(
			timeZoneIdentifier: timeZoneIdentifier,
			sourceFile: fileURL.lastPathComponent
		)

		while let chunk = try await reader.readChunk() {
			try Task.checkCancellation()
			let csv_records = try decoder.consume(chunk)
			try await consumeRows(
				csv_records,
				consumer: &row_consumer,
				continuation: continuation
			)
		}

		try await consumeRows(
			try decoder.finish(),
			consumer: &row_consumer,
			continuation: continuation
		)
		return try row_consumer.finish()
	}

	private static func consumeRows(
		_ csvRecords: [CSVRecord],
		consumer: inout CSVRowConsumer,
		continuation: AsyncThrowingStream<ParsedSleepRecord, Error>.Continuation
	) async throws {
		for csv_record in csvRecords {
			try Task.checkCancellation()

			if let parsed_record = try consumer.consume(csv_record) {
				try await yield(parsed_record, continuation: continuation)
			}
		}
	}

	private static func yield(
		_ record: ParsedSleepRecord,
		continuation: AsyncThrowingStream<ParsedSleepRecord, Error>.Continuation
	) async throws {
		while true {
			try Task.checkCancellation()

			switch continuation.yield(record) {
			case .enqueued:
				return
			case .dropped:
				await Task.yield()
			case .terminated:
				throw CancellationError()
			@unknown default:
				throw CancellationError()
			}
		}
	}

	fileprivate static func resolveColumns(_ headers: [String]) throws -> [CSVColumn: Int] {
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

private final class ParseTaskBox: @unchecked Sendable {
	private let lock = NSLock()
	private var task: Task<SleepParseSummary, Error>?
	private var is_cancelled = false

	func set(_ task: Task<SleepParseSummary, Error>) {
		lock.lock()
		self.task = task
		let should_cancel = is_cancelled
		lock.unlock()

		if should_cancel {
			task.cancel()
		}
	}

	func cancel() {
		lock.lock()
		is_cancelled = true
		let task = self.task
		lock.unlock()
		task?.cancel()
	}
}

private struct CSVRowConsumer {
	let timeZoneIdentifier: String
	let sourceFile: String
	private var row_parser: RowParser?
	private var count_headers = 0
	private var count_parsed = 0
	private var skipped_rows: [SleepSkippedRow] = []

	init(timeZoneIdentifier: String, sourceFile: String) {
		self.timeZoneIdentifier = timeZoneIdentifier
		self.sourceFile = sourceFile
	}

	mutating func consume(_ csv_record: CSVRecord) throws -> ParsedSleepRecord? {
		guard let row_parser else {
			guard csv_record.issue == nil else {
				throw AutoSleepCSVImportError.invalidHeader(
					csv_record.issue ?? "unknown quoting error"
				)
			}

			let columns = try AutoSleepCSVImporter.resolveColumns(csv_record.fields)
			self.row_parser = RowParser(
				columns: columns,
				timeZoneIdentifier: timeZoneIdentifier,
				sourceFile: sourceFile
			)
			count_headers = csv_record.fields.count
			return nil
		}

		guard !csv_record.isBlank else {
			return nil
		}

		do {
			let record = try row_parser.parse(csv_record, headerCount: count_headers)
			count_parsed += 1
			return record
		} catch {
			skipped_rows.append(
				SleepSkippedRow(
					rowNumber: csv_record.rowNumber,
					reason: error.localizedDescription
				)
			)
			return nil
		}
	}

	func finish() throws -> SleepParseSummary {
		guard row_parser != nil else {
			throw AutoSleepCSVImportError.emptyFile
		}

		return SleepParseSummary(parsedCount: count_parsed, skippedRows: skipped_rows)
	}
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

private enum IncrementalCSVStage {
	case preamble
	case records
}

private struct IncrementalCSVDecoder {
	private var stage = IncrementalCSVStage.preamble
	private var leading_bytes: [UInt8] = []
	private var did_process_leading_bytes = false
	private var preamble_bytes: [UInt8] = []
	private var csv_parser: CSVByteStateMachine?
	private var should_skip_preamble_lf = false

	mutating func consume(_ data: Data) throws -> [CSVRecord] {
		var records: [CSVRecord] = []

		for byte in data {
			try consumeLeadingByte(byte, records: &records)
		}

		return records
	}

	mutating func finish() throws -> [CSVRecord] {
		var records: [CSVRecord] = []

		if !did_process_leading_bytes {
			did_process_leading_bytes = true
			try consumeBodyBytes(leading_bytes, records: &records)
			leading_bytes.removeAll(keepingCapacity: false)
		}

		if stage == .preamble {
			try finishPreamble(terminator: nil, records: &records)
		}
		if let final_record = try csv_parser?.finish() {
			records.append(final_record)
		}

		return records
	}

	private mutating func consumeLeadingByte(
		_ byte: UInt8,
		records: inout [CSVRecord]
	) throws {
		guard !did_process_leading_bytes else {
			try consumeBodyByte(byte, records: &records)
			return
		}

		leading_bytes.append(byte)
		guard leading_bytes.count == 3 else {
			return
		}

		did_process_leading_bytes = true
		if leading_bytes != [0xEF, 0xBB, 0xBF] {
			try consumeBodyBytes(leading_bytes, records: &records)
		}
		leading_bytes.removeAll(keepingCapacity: false)
	}

	private mutating func consumeBodyBytes(
		_ bytes: [UInt8],
		records: inout [CSVRecord]
	) throws {
		for byte in bytes {
			try consumeBodyByte(byte, records: &records)
		}
	}

	private mutating func consumeBodyByte(
		_ byte: UInt8,
		records: inout [CSVRecord]
	) throws {
		if should_skip_preamble_lf {
			should_skip_preamble_lf = false
			if byte == 10 {
				return
			}
		}

		switch stage {
		case .preamble:
			if byte == 13 || byte == 10 {
				try finishPreamble(terminator: byte, records: &records)
				should_skip_preamble_lf = byte == 13
			} else {
				preamble_bytes.append(byte)
			}
		case .records:
			if let record = try csv_parser?.consume(byte) {
				records.append(record)
			}
		}
	}

	private mutating func finishPreamble(
		terminator: UInt8?,
		records: inout [CSVRecord]
	) throws {
		let directive = try separatorDirective(in: preamble_bytes)
		let delimiter = directive ?? detectDelimiter(in: preamble_bytes)
		let row_number = directive == nil ? 1 : 2
		csv_parser = CSVByteStateMachine(delimiter: delimiter, rowNumber: row_number)
		stage = .records

		if directive == nil {
			for byte in preamble_bytes {
				_ = try csv_parser?.consume(byte)
			}
			if let terminator, let record = try csv_parser?.consume(terminator) {
				records.append(record)
			}
		}

		preamble_bytes.removeAll(keepingCapacity: false)
	}

	private func separatorDirective(in bytes: [UInt8]) throws -> UInt8? {
		guard let line = String(data: Data(bytes), encoding: .utf8) else {
			throw AutoSleepCSVImportError.invalidUTF8
		}

		switch line.trimmingCharacters(in: .whitespaces).lowercased() {
		case "sep=;": return 59
		case "sep=,": return 44
		default: return nil
		}
	}

	private func detectDelimiter(in bytes: [UInt8]) -> UInt8 {
		var comma_count = 0
		var semicolon_count = 0
		var is_quoted = false
		var is_quote_pending = false

		for byte in bytes {
			if byte == 34 {
				if is_quote_pending {
					is_quote_pending = false
				} else if is_quoted {
					is_quote_pending = true
				} else {
					is_quoted = true
				}
			} else if is_quote_pending {
				is_quoted = false
				is_quote_pending = false
			}

			if !is_quoted {
				comma_count += byte == 44 ? 1 : 0
				semicolon_count += byte == 59 ? 1 : 0
			}
		}

		return semicolon_count > comma_count ? 59 : 44
	}
}

private struct CSVByteStateMachine {
	private let delimiter: UInt8
	private var fields: [[UInt8]] = []
	private var field: [UInt8] = []
	private var raw: [UInt8] = []
	private var issue: String?
	private var state = CSVState.unquoted
	private var physical_line: Int
	private var record_start_line: Int
	private var should_skip_lf = false

	init(delimiter: UInt8, rowNumber: Int) {
		self.delimiter = delimiter
		self.physical_line = rowNumber
		self.record_start_line = rowNumber
	}

	mutating func consume(_ byte: UInt8) throws -> CSVRecord? {
		if should_skip_lf {
			should_skip_lf = false
			if byte == 10 {
				return nil
			}
		}

		switch state {
		case .unquoted:
			return try consumeUnquoted(byte)
		case .quoted:
			consumeQuoted(byte)
		case .quoteClosed:
			return try consumeAfterQuote(byte)
		}

		return nil
	}

	mutating func finish() throws -> CSVRecord? {
		if state == .quoted {
			issue = issue ?? "A quoted field was not closed."
		}
		guard !fields.isEmpty || !field.isEmpty || !raw.isEmpty else {
			return nil
		}

		return try finishRecord()
	}

	private mutating func consumeUnquoted(_ byte: UInt8) throws -> CSVRecord? {
		if byte == delimiter {
			fields.append(field)
			field = []
			raw.append(byte)
		} else if byte == 34, field.isEmpty {
			state = .quoted
			raw.append(byte)
		} else if byte == 34 {
			issue = issue ?? "A quote appeared inside an unquoted field."
			field.append(byte)
			raw.append(byte)
		} else if byte == 13 || byte == 10 {
			return try finishLine(with: byte)
		} else {
			field.append(byte)
			raw.append(byte)
		}

		return nil
	}

	private mutating func consumeQuoted(_ byte: UInt8) {
		raw.append(byte)

		if byte == 34 {
			state = .quoteClosed
		} else {
			field.append(byte)
			if byte == 10 {
				physical_line += 1
			}
		}
	}

	private mutating func consumeAfterQuote(_ byte: UInt8) throws -> CSVRecord? {
		if byte == 34 {
			field.append(byte)
			raw.append(byte)
			state = .quoted
		} else if byte == delimiter {
			fields.append(field)
			field = []
			raw.append(byte)
			state = .unquoted
		} else if byte == 13 || byte == 10 {
			return try finishLine(with: byte)
		} else {
			issue = issue ?? "Unexpected text followed a closing quote."
			raw.append(byte)
		}

		return nil
	}

	private mutating func finishLine(with byte: UInt8) throws -> CSVRecord {
		let record = try finishRecord()
		physical_line += 1
		record_start_line = physical_line
		should_skip_lf = byte == 13
		return record
	}

	private mutating func finishRecord() throws -> CSVRecord {
		fields.append(field)
		let decoded_fields = try fields.map { bytes in
			guard let value = String(data: Data(bytes), encoding: .utf8) else {
				throw AutoSleepCSVImportError.invalidUTF8
			}

			return value
		}
		guard let raw_value = String(data: Data(raw), encoding: .utf8) else {
			throw AutoSleepCSVImportError.invalidUTF8
		}
		let record = CSVRecord(
			fields: decoded_fields,
			raw: raw_value,
			rowNumber: record_start_line,
			issue: issue
		)

		fields = []
		field = []
		raw = []
		issue = nil
		state = .unquoted
		return record
	}
}
