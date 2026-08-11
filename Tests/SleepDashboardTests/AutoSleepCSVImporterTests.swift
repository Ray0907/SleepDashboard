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

	func testYieldsRowBeforeEOFAcrossQuotedChunkBoundaries() async throws {
		let header_line = progressiveHeaders.joined(separator: ",")
		let first_chunk = header_line + "\r\n" + progressiveRowPrefix
		let second_chunk = "\r\nchunks, with \"\"quote\"\"\",86,2\r\n"
		let third_chunk = makeProgressiveRow(note: "later row", efficiency: 91)
		let reader = ControlledCSVChunkReader(
			chunks: [first_chunk, second_chunk, third_chunk],
			releasedCount: 2
		)
		let source = ControlledCSVChunkSource(reader: reader)
		let importer = AutoSleepCSVImporter(
			timeZone: TimeZone(identifier: "Asia/Taipei")!,
			chunkSource: source
		)
		let parse_stream = importer.parse(fileURL: URL(fileURLWithPath: "/unused.csv"))
		let collector = ParsedRecordCollector()
		let consumer = Task {
			for try await record in parse_stream {
				await collector.append(record)
			}
		}

		await collector.waitForCount(1)
		await reader.waitForReadCount(3)
		let collected_record = await collector.record(at: 0)
		let first_record = try XCTUnwrap(collected_record)
		let eof_released = await reader.isEOFReleased()

		XCTAssertEqual(first_record.efficiency, 86)
		XCTAssertEqual(first_record.sessionsInNight, 2)
		XCTAssertFalse(eof_released)

		await reader.releaseAll()
		try await consumer.value
		let summary = try await parse_stream.summary()
		let count_records = await collector.count()
		let reader_closed = await reader.isClosed()

		XCTAssertEqual(count_records, 2)
		XCTAssertEqual(summary.parsedCount, 2)
		XCTAssertTrue(reader_closed)
	}

	func testCancellationStopsFurtherChunkReadsAndClosesReader() async throws {
		let first_chunk = progressiveHeaders.joined(separator: ",")
			+ "\r\n" + makeProgressiveRow(note: "first", efficiency: 86)
		let reader = ControlledCSVChunkReader(
			chunks: [first_chunk, makeProgressiveRow(note: "blocked", efficiency: 90)],
			releasedCount: 1
		)
		let source = ControlledCSVChunkSource(reader: reader)
		let importer = AutoSleepCSVImporter(
			timeZone: TimeZone(identifier: "Asia/Taipei")!,
			chunkSource: source
		)
		let parse_stream = importer.parse(fileURL: URL(fileURLWithPath: "/unused.csv"))
		let collector = ParsedRecordCollector()
		let consumer = Task {
			for try await record in parse_stream {
				await collector.append(record)
			}
		}

		await collector.waitForCount(1)
		await reader.waitForReadCount(2)
		consumer.cancel()
		_ = try? await consumer.value
		await reader.waitUntilClosed()
		let count_reads = await reader.readCount()
		let reader_closed = await reader.isClosed()

		XCTAssertEqual(count_reads, 2)
		XCTAssertTrue(reader_closed)
		do {
			_ = try await parse_stream.summary()
			XCTFail("Expected parser cancellation")
		} catch is CancellationError {
			// Cancellation is the expected parse result.
		} catch {
			XCTFail("Unexpected cancellation error: \(error)")
		}
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

	private var progressiveHeaders: [String] {
		[
			"startDate", "endDate", "bedtime", "wakeTime", "inBed", "awake",
			"asleep", "deep", "notes", "efficiency", "sessions"
		]
	}

	private var progressiveRowPrefix: String {
		[
			"2026-08-08 23:18:00", "2026-08-09 07:28:00",
			"2026-08-08 23:18:00", "2026-08-09 07:28:00", "08:10:00",
			"00:28:00", "07:42:00", "01:45:00"
		].joined(separator: ",") + ",\"split across"
	}

	private func makeProgressiveRow(note: String, efficiency: Int) -> String {
		[
			"2026-08-09 23:00:00", "2026-08-10 07:00:00",
			"2026-08-09 23:00:00", "2026-08-10 07:00:00", "08:00:00",
			"00:30:00", "07:30:00", "01:30:00", "\"\(note)\"",
			String(efficiency), "1"
		].joined(separator: ",") + "\r\n"
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

private struct ControlledCSVChunkSource: CSVChunkSource {
	let reader: ControlledCSVChunkReader

	func open(fileURL: URL) throws -> any CSVChunkReader {
		reader
	}
}

private actor ControlledCSVChunkReader: CSVChunkReader {
	private let chunks: [Data]
	private var released_count: Int
	private var is_eof_released = false
	private var index_next = 0
	private var count_reads = 0
	private var is_closed = false
	private var chunk_waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
	private var read_waiters: [(Int, CheckedContinuation<Void, Never>)] = []
	private var close_waiters: [CheckedContinuation<Void, Never>] = []

	init(chunks: [String], releasedCount: Int) {
		self.chunks = chunks.map { Data($0.utf8) }
		self.released_count = releasedCount
	}

	func readChunk() async throws -> Data? {
		count_reads += 1
		resumeReadWaiters()

		while index_next >= released_count && !is_eof_released {
			try await waitForRelease()
		}

		try Task.checkCancellation()
		guard index_next < released_count else {
			return nil
		}

		let chunk = chunks[index_next]
		index_next += 1
		return chunk
	}

	func close() async {
		is_closed = true
		is_eof_released = true
		resumeChunkWaiters()
		let waiters = close_waiters
		close_waiters.removeAll()
		waiters.forEach { $0.resume() }
	}

	func releaseAll() {
		released_count = chunks.count
		is_eof_released = true
		resumeChunkWaiters()
	}

	func waitForReadCount(_ expected_count: Int) async {
		guard count_reads < expected_count else {
			return
		}

		await withCheckedContinuation { continuation in
			read_waiters.append((expected_count, continuation))
		}
	}

	func waitUntilClosed() async {
		guard !is_closed else {
			return
		}

		await withCheckedContinuation { continuation in
			close_waiters.append(continuation)
		}
	}

	func readCount() -> Int {
		count_reads
	}

	func isEOFReleased() -> Bool {
		is_eof_released
	}

	func isClosed() -> Bool {
		is_closed
	}

	private func waitForRelease() async throws {
		let id_waiter = UUID()

		try await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				chunk_waiters[id_waiter] = continuation
			}
			try Task.checkCancellation()
		} onCancel: {
			Task {
				await self.cancelWaiter(id_waiter)
			}
		}
	}

	private func cancelWaiter(_ id_waiter: UUID) {
		chunk_waiters.removeValue(forKey: id_waiter)?.resume()
	}

	private func resumeChunkWaiters() {
		let waiters = chunk_waiters.values
		chunk_waiters.removeAll()
		waiters.forEach { $0.resume() }
	}

	private func resumeReadWaiters() {
		let ready_waiters = read_waiters.filter { count_reads >= $0.0 }
		read_waiters.removeAll { count_reads >= $0.0 }
		ready_waiters.forEach { $0.1.resume() }
	}
}

private actor ParsedRecordCollector {
	private var records: [ParsedSleepRecord] = []
	private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

	func append(_ record: ParsedSleepRecord) {
		records.append(record)
		let ready_waiters = waiters.filter { records.count >= $0.0 }
		waiters.removeAll { records.count >= $0.0 }
		ready_waiters.forEach { $0.1.resume() }
	}

	func waitForCount(_ expected_count: Int) async {
		guard records.count < expected_count else {
			return
		}

		await withCheckedContinuation { continuation in
			waiters.append((expected_count, continuation))
		}
	}

	func record(at index: Int) -> ParsedSleepRecord? {
		records.indices.contains(index) ? records[index] : nil
	}

	func count() -> Int {
		records.count
	}
}
