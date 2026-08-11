import Foundation
import XCTest
@testable import SleepDashboard

final class AutoSleepCSVImporterTests: XCTestCase {
	func testParsesHappyPathInExplicitTimeZone() async throws {
		let file_url = try makeCSVFile(lines: [
			makeHeader(),
			makeRow()
		])
		defer { removeTemporaryFile(file_url) }
		let importer = AutoSleepCSVImporter(
			timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Taipei"))
		)

		let parse_stream = importer.parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)
		let summary = try await parse_stream.summary()
		let record = try XCTUnwrap(records.first)

		XCTAssertEqual(records.count, 1)
		XCTAssertEqual(summary.parsedCount, 1)
		XCTAssertEqual(summary.skippedCount, 0)
		XCTAssertEqual(record.timeZoneIdentifier, "Asia/Taipei")
		XCTAssertEqual(record.inBedDuration, 29_400)
		XCTAssertEqual(record.awakeDuration, 1_680)
		XCTAssertEqual(record.asleepDuration, 27_720)
		XCTAssertEqual(record.deepDuration, 6_300)
		XCTAssertEqual(record.efficiency, 86)
		XCTAssertEqual(record.sleepBPM, 54)
		XCTAssertEqual(record.hrv, 56)
		XCTAssertEqual(record.sessionsInNight, 1)
		XCTAssertEqual(
			record.sourceRowFingerprint,
			"9e8a9eb55d7b25f183ff352260ae0c4e3b8e70c212df0c52c24a4e633d257728"
		)
	}

	func testDetectsSemicolonDelimiterAndMatchesHeadersCaseInsensitively() async throws {
		let file_url = try makeCSVFile(lines: [
			makeHeader(delimiter: ";").uppercased(),
			makeRow(delimiter: ";")
		])
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)

		XCTAssertEqual(records.count, 1)
		XCTAssertEqual(records.first?.asleepDuration, 27_720)
	}

	func testHonorsSepDirectiveAndStripsUTF8BOM() async throws {
		let text = "\u{FEFF}sep=;\r\n" + [
			makeHeader(delimiter: ";"),
			makeRow(delimiter: ";")
		].joined(separator: "\r\n")
		let file_url = try makeCSVFile(text: text)
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)
		let summary = try await parse_stream.summary()

		XCTAssertEqual(records.count, 1)
		XCTAssertEqual(summary.skippedCount, 0)
	}

	func testQuotedCommaNewlineAndEscapedQuotePreserveAlignment() async throws {
		let headers = [
			"startDate", "endDate", "bedtime", "wakeTime", "inBed", "awake",
			"asleep", "deep", "notes", "efficiency", "sessions"
		]
		let values = [
			"2026-08-08 23:18:00", "2026-08-09 07:28:00",
			"2026-08-08 23:18:00", "2026-08-09 07:28:00", "08:10:00",
			"00:28:00", "07:42:00", "01:45:00",
			"\"comma, newline\nand escaped \"\"quote\"\"\"", "86", "2"
		]
		let file_url = try makeCSVFile(
			text: headers.joined(separator: ",") + "\r\n" + values.joined(separator: ",")
		)
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)

		XCTAssertEqual(records.count, 1)
		XCTAssertEqual(records.first?.efficiency, 86)
		XCTAssertEqual(records.first?.sessionsInNight, 2)
	}

	func testMissingOptionalColumnsProduceNilMetrics() async throws {
		let headers = requiredHeaders
		let values = requiredValues
		let file_url = try makeCSVFile(lines: [
			headers.joined(separator: ","),
			values.joined(separator: ",")
		])
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)
		let record = try XCTUnwrap(records.first)

		XCTAssertNil(record.sleepBPM)
		XCTAssertNil(record.hrv)
		XCTAssertNil(record.spo2Avg)
		XCTAssertNil(record.spo2Min)
		XCTAssertNil(record.spo2Max)
		XCTAssertNil(record.respAvg)
		XCTAssertNil(record.respMin)
		XCTAssertNil(record.respMax)
		XCTAssertNil(record.apneaHypopneaIndex)
	}

	func testMalformedRowIsSkippedAndReported() async throws {
		var bad_values = requiredValues
		bad_values[4] = "eight hours"
		let file_url = try makeCSVFile(lines: [
			requiredHeaders.joined(separator: ","),
			bad_values.joined(separator: ","),
			requiredValues.joined(separator: ",")
		])
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)
		let records = try await collectRecords(from: parse_stream)
		let summary = try await parse_stream.summary()

		XCTAssertEqual(records.count, 1)
		XCTAssertEqual(summary.parsedCount, 1)
		XCTAssertEqual(summary.skippedCount, 1)
		XCTAssertEqual(summary.skippedRows.first?.rowNumber, 2)
		XCTAssertTrue(summary.skippedRows.first?.reason.contains("inBed") == true)
	}

	func testMissingRequiredColumnFailsBeforeYielding() async throws {
		let headers = requiredHeaders.filter { $0 != "efficiency" }
		let values = Array(requiredValues.dropLast(2)) + [requiredValues.last!]
		let file_url = try makeCSVFile(lines: [
			headers.joined(separator: ","),
			values.joined(separator: ",")
		])
		defer { removeTemporaryFile(file_url) }

		let parse_stream = makeImporter().parse(fileURL: file_url)

		do {
			_ = try await collectRecords(from: parse_stream)
			XCTFail("Expected a missing-required-column error")
		} catch {
			XCTAssertTrue(error.localizedDescription.contains("efficiency"))
		}
	}

	func testFingerprintIsStableForTheSameRawRow() async throws {
		let first_url = try makeCSVFile(lines: [makeHeader(), makeRow()])
		let second_url = try makeCSVFile(lines: [makeHeader(), makeRow()])
		defer {
			removeTemporaryFile(first_url)
			removeTemporaryFile(second_url)
		}

		let first_stream = makeImporter().parse(fileURL: first_url)
		let second_stream = makeImporter().parse(fileURL: second_url)
		let first_records = try await collectRecords(from: first_stream)
		let second_records = try await collectRecords(from: second_stream)
		let first_record = try XCTUnwrap(first_records.first)
		let second_record = try XCTUnwrap(second_records.first)

		XCTAssertEqual(
			first_record.sourceRowFingerprint,
			second_record.sourceRowFingerprint
		)
	}

	private var requiredHeaders: [String] {
		[
			"startDate", "endDate", "bedtime", "wakeTime", "inBed", "awake",
			"asleep", "deep", "efficiency", "sessions"
		]
	}

	private var requiredValues: [String] {
		[
			"2026-08-08 23:18:00", "2026-08-09 07:28:00",
			"2026-08-08 23:18:00", "2026-08-09 07:28:00", "08:10:00",
			"00:28:00", "07:42:00", "01:45:00", "86", "1"
		]
	}

	private func makeHeader(delimiter: String = ",") -> String {
		(requiredHeaders + [
			"sleepBPM", "hrv", "spo2Avg", "spo2Min", "spo2Max", "respAvg",
			"respMin", "respMax", "apnea", "notes"
		]).joined(separator: delimiter)
	}

	private func makeRow(delimiter: String = ",") -> String {
		(requiredValues + [
			"54", "56", "96", "94", "98", "14.2", "12.9", "15.4", "2.1",
			"ordinary note"
		]).joined(separator: delimiter)
	}

	private func makeImporter() -> AutoSleepCSVImporter {
		AutoSleepCSVImporter(timeZone: TimeZone(identifier: "Asia/Taipei")!)
	}

	private func collectRecords(
		from stream: SleepRecordStream
	) async throws -> [ParsedSleepRecord] {
		var records: [ParsedSleepRecord] = []

		for try await record in stream {
			records.append(record)
		}

		return records
	}

	private func makeCSVFile(lines: [String]) throws -> URL {
		try makeCSVFile(text: lines.joined(separator: "\r\n"))
	}

	private func makeCSVFile(text: String) throws -> URL {
		let directory_url = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(
			at: directory_url,
			withIntermediateDirectories: true
		)
		let file_url = directory_url.appendingPathComponent("AutoSleep.csv")
		try Data(text.utf8).write(to: file_url)
		return file_url
	}

	private func removeTemporaryFile(_ file_url: URL) {
		try? FileManager.default.removeItem(at: file_url.deletingLastPathComponent())
	}
}
