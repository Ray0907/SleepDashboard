import Foundation
import SwiftData
import XCTest
@testable import SleepDashboard

final class ImportCoordinatorTests: XCTestCase {
	@MainActor
	func testImportsCSVIntoRawRecordAndNight() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		let file_url = try makeCSVFile(rows: [makeValues()])
		defer { removeTemporaryFile(file_url) }

		let summary = try await coordinator.importFile(
			at: file_url,
			using: makeImporter()
		)
		let context = ModelContext(container)
		let imported_records = try context.fetch(FetchDescriptor<ImportedSleepRecord>())
		let nights = try context.fetch(FetchDescriptor<SleepNight>())

		XCTAssertEqual(summary.importedCount, 1)
		XCTAssertEqual(summary.skippedCount, 0)
		XCTAssertEqual(summary.duplicateCount, 0)
		XCTAssertEqual(imported_records.count, 1)
		XCTAssertEqual(nights.count, 1)
		XCTAssertEqual(nights.first?.asleepDuration, 27_720)
		XCTAssertEqual(nights.first?.timeZoneIdentifier, "Asia/Taipei")
	}

	@MainActor
	func testExactReimportIsNoOp() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		let file_url = try makeCSVFile(rows: [makeValues()])
		defer { removeTemporaryFile(file_url) }

		let first_summary = try await coordinator.importFile(
			at: file_url,
			using: makeImporter()
		)
		let second_summary = try await coordinator.importFile(
			at: file_url,
			using: makeImporter()
		)
		let context = ModelContext(container)
		let imported_records = try context.fetch(FetchDescriptor<ImportedSleepRecord>())
		let nights = try context.fetch(FetchDescriptor<SleepNight>())

		XCTAssertEqual(first_summary.importedCount, 1)
		XCTAssertEqual(second_summary.importedCount, 0)
		XCTAssertEqual(second_summary.duplicateCount, 1)
		XCTAssertEqual(imported_records.count, 1)
		XCTAssertEqual(nights.count, 1)
	}

	@MainActor
	func testAggregatesAllPersistedRecordsForTouchedNight() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		let first_url = try makeCSVFile(rows: [makeValues()])
		let second_url = try makeCSVFile(rows: [makeSecondSessionValues()])
		defer {
			removeTemporaryFile(first_url)
			removeTemporaryFile(second_url)
		}

		_ = try await coordinator.importFile(at: first_url, using: makeImporter())
		_ = try await coordinator.importFile(at: second_url, using: makeImporter())
		let context = ModelContext(container)
		let nights = try context.fetch(FetchDescriptor<SleepNight>())
		let night = try XCTUnwrap(nights.first)

		XCTAssertEqual(nights.count, 1)
		XCTAssertEqual(night.asleepDuration, 29_520)
		XCTAssertEqual(night.deepDuration, 7_200)
		XCTAssertEqual(night.sessionsInNight, 2)
		XCTAssertEqual(night.bedtime, try makeDate(hour: 22, minute: 30))
		XCTAssertEqual(night.wakeTime, try makeDate(day: 9, hour: 7, minute: 28))
		XCTAssertNil(night.hrv)
		XCTAssertNil(night.spo2Avg)
	}

	@MainActor
	func testMalformedRowsContributeToSkippedSummary() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		var bad_values = makeValues()
		bad_values[6] = "not-a-duration"
		let file_url = try makeCSVFile(rows: [bad_values, makeValues()])
		defer { removeTemporaryFile(file_url) }

		let summary = try await coordinator.importFile(
			at: file_url,
			using: makeImporter()
		)

		XCTAssertEqual(summary.importedCount, 1)
		XCTAssertEqual(summary.skippedCount, 1)
		XCTAssertEqual(summary.duplicateCount, 0)
	}

	@MainActor
	func testMissingRequiredColumnLeavesStoreUntouched() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		let headers = makeHeaders().filter { $0 != "efficiency" }
		var values = makeValues()
		values.remove(at: 8)
		let file_url = try makeCSVFile(headers: headers, rows: [values])
		defer { removeTemporaryFile(file_url) }

		do {
			_ = try await coordinator.importFile(at: file_url, using: makeImporter())
			XCTFail("Expected missing-required-column failure")
		} catch {
			XCTAssertTrue(error.localizedDescription.contains("efficiency"))
		}

		try assertStoreIsEmpty(container)
	}

	@MainActor
	func testFatalStreamFailureLeavesStoreUntouched() async throws {
		let container = try makeContainer()
		let coordinator = ImportCoordinator(modelContainer: container)
		let data_source = FailingSleepDataSource(record: try makeParsedRecord())
		let unused_url = URL(fileURLWithPath: "/tmp/unused.csv")

		do {
			_ = try await coordinator.importFile(at: unused_url, using: data_source)
			XCTFail("Expected stream failure")
		} catch TestImportError.expected {
			// Expected failure proves a yielded row was not partially persisted.
		} catch {
			XCTFail("Unexpected error: \(error)")
		}

		try assertStoreIsEmpty(container)
	}

	@MainActor
	private func makeContainer() throws -> ModelContainer {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		return try ModelContainer(
			for: ImportedSleepRecord.self,
			SleepNight.self,
			configurations: configuration
		)
	}

	private func makeImporter() -> AutoSleepCSVImporter {
		AutoSleepCSVImporter(timeZone: TimeZone(identifier: "Asia/Taipei")!)
	}

	private func makeHeaders() -> [String] {
		[
			"startDate", "endDate", "bedtime", "wakeTime", "inBed", "awake",
			"asleep", "deep", "efficiency", "sessions", "hrv", "spo2Avg"
		]
	}

	private func makeValues() -> [String] {
		[
			"2026-08-08 23:18:00", "2026-08-09 07:28:00",
			"2026-08-08 23:18:00", "2026-08-09 07:28:00", "08:10:00",
			"00:28:00", "07:42:00", "01:45:00", "86", "1", "", ""
		]
	}

	private func makeSecondSessionValues() -> [String] {
		[
			"2026-08-08 22:30:00", "2026-08-08 23:05:00",
			"2026-08-08 22:30:00", "2026-08-08 23:05:00", "00:35:00",
			"00:05:00", "00:30:00", "00:15:00", "85", "1", "", ""
		]
	}

	private func makeCSVFile(
		headers: [String]? = nil,
		rows: [[String]]
	) throws -> URL {
		let header_line = (headers ?? makeHeaders()).joined(separator: ",")
		let row_lines = rows.map { $0.joined(separator: ",") }
		let text = ([header_line] + row_lines).joined(separator: "\r\n")
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

	@MainActor
	private func assertStoreIsEmpty(_ container: ModelContainer) throws {
		let context = ModelContext(container)
		let imported_records = try context.fetch(FetchDescriptor<ImportedSleepRecord>())
		let nights = try context.fetch(FetchDescriptor<SleepNight>())

		XCTAssertTrue(imported_records.isEmpty)
		XCTAssertTrue(nights.isEmpty)
	}

	private func makeDate(
		day: Int = 8,
		hour: Int,
		minute: Int
	) throws -> Date {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
		return try XCTUnwrap(
			calendar.date(
				from: DateComponents(
					year: 2026,
					month: 8,
					day: day,
					hour: hour,
					minute: minute
				)
			)
		)
	}

	private func makeParsedRecord() throws -> ParsedSleepRecord {
		let bedtime = try makeDate(hour: 23, minute: 18)
		let wake_time = try makeDate(day: 9, hour: 7, minute: 28)

		return ParsedSleepRecord(
			sourceFile: "AutoSleep.csv",
			sourceRowFingerprint: String(repeating: "a", count: 64),
			startDate: bedtime,
			endDate: wake_time,
			timeZoneIdentifier: "Asia/Taipei",
			bedtime: bedtime,
			wakeTime: wake_time,
			inBedDuration: 29_400,
			awakeDuration: 1_680,
			asleepDuration: 27_720,
			deepDuration: 6_300,
			efficiency: 86,
			sleepBPM: nil,
			hrv: nil,
			spo2Avg: nil,
			spo2Min: nil,
			spo2Max: nil,
			respAvg: nil,
			respMin: nil,
			respMax: nil,
			apneaHypopneaIndex: nil,
			sessionsInNight: 1
		)
	}
}

private enum TestImportError: Error {
	case expected
}

private struct FailingSleepDataSource: SleepDataSource {
	let record: ParsedSleepRecord

	func parse(fileURL: URL) -> SleepRecordStream {
		let records = AsyncThrowingStream<ParsedSleepRecord, Error> { continuation in
			continuation.yield(record)
			continuation.finish(throwing: TestImportError.expected)
		}
		let summary_task = Task<SleepParseSummary, Error> {
			throw TestImportError.expected
		}

		return SleepRecordStream(records: records, summaryTask: summary_task)
	}
}
