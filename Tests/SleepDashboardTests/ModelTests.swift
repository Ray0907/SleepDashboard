import Foundation
import SwiftData
import XCTest
@testable import SleepDashboard

final class ModelTests: XCTestCase {
	func testParsedRecordIsSendableAndPreservesMissingHealthMetrics() throws {
		assertSendable(ParsedSleepRecord.self)

		let calendar = SampleSleepData.calendar
		let bedtime = try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		let wake_time = try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)
		let parsed_record = ParsedSleepRecord(
			sourceFile: "AutoSleep.csv",
			sourceRowFingerprint: "row-1",
			startDate: bedtime,
			endDate: wake_time,
			timeZoneIdentifier: calendar.timeZone.identifier,
			bedtime: bedtime,
			wakeTime: wake_time,
			inBedDuration: 8 * 3_600 + 10 * 60,
			awakeDuration: 28 * 60,
			asleepDuration: 7 * 3_600 + 42 * 60,
			deepDuration: 1 * 3_600 + 45 * 60,
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

		XCTAssertEqual(parsed_record.sourceFile, "AutoSleep.csv")
		XCTAssertEqual(parsed_record.sourceRowFingerprint, "row-1")
		XCTAssertEqual(parsed_record.startDate, bedtime)
		XCTAssertEqual(parsed_record.endDate, wake_time)
		XCTAssertEqual(parsed_record.timeZoneIdentifier, calendar.timeZone.identifier)
		XCTAssertNil(parsed_record.sleepBPM)
		XCTAssertNil(parsed_record.hrv)
		XCTAssertNil(parsed_record.spo2Avg)
		XCTAssertNil(parsed_record.spo2Min)
		XCTAssertNil(parsed_record.spo2Max)
		XCTAssertNil(parsed_record.respAvg)
		XCTAssertNil(parsed_record.respMin)
		XCTAssertNil(parsed_record.respMax)
		XCTAssertNil(parsed_record.apneaHypopneaIndex)
	}

	func testImportedRecordInitializerPreservesMissingHealthMetrics() throws {
		let bedtime = try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		let wake_time = try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)
		let imported_record = ImportedSleepRecord(
			sourceFile: "AutoSleep.csv",
			sourceRowFingerprint: "row-1",
			startDate: bedtime,
			endDate: wake_time,
			timeZoneIdentifier: SampleSleepData.calendar.timeZone.identifier,
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

		XCTAssertNil(imported_record.sleepBPM)
		XCTAssertNil(imported_record.hrv)
		XCTAssertNil(imported_record.spo2Avg)
		XCTAssertNil(imported_record.spo2Min)
		XCTAssertNil(imported_record.spo2Max)
		XCTAssertNil(imported_record.respAvg)
		XCTAssertNil(imported_record.respMin)
		XCTAssertNil(imported_record.respMax)
		XCTAssertNil(imported_record.apneaHypopneaIndex)
	}

	func testSampleDataCoversThirtyConsecutiveNightsDeterministically() throws {
		let first_sample = SampleSleepData.makeNights()
		let second_sample = SampleSleepData.makeNights()
		let calendar = SampleSleepData.calendar

		XCTAssertEqual(first_sample.count, 30)
		XCTAssertEqual(first_sample.first?.nightDate, try makeDate(year: 2026, month: 7, day: 11))
		XCTAssertEqual(first_sample.last?.nightDate, try makeDate(year: 2026, month: 8, day: 9))
		XCTAssertEqual(first_sample.map(\.nightDate), second_sample.map(\.nightDate))
		XCTAssertEqual(first_sample.map(\.asleepDuration), second_sample.map(\.asleepDuration))

		for index in first_sample.indices.dropFirst() {
			let previous_date = first_sample[index - 1].nightDate
			let current_date = first_sample[index].nightDate
			let day_delta = calendar.dateComponents(
				[.day],
				from: previous_date,
				to: current_date
			).day
			XCTAssertEqual(day_delta, 1)
		}
	}

	func testAugustEightSampleMatchesApprovedMockup() throws {
		let sample_nights = SampleSleepData.makeNights()
		let expected_date = try makeDate(year: 2026, month: 8, day: 8)
		let august_eight = try XCTUnwrap(
			sample_nights.first { $0.nightDate == expected_date }
		)

		XCTAssertEqual(august_eight.asleepDuration, 7 * 3_600 + 42 * 60)
		XCTAssertEqual(
			august_eight.bedtime,
			try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		)
		XCTAssertEqual(
			august_eight.wakeTime,
			try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)
		)
		XCTAssertEqual(august_eight.deepDuration, 1 * 3_600 + 45 * 60)
		XCTAssertEqual(try XCTUnwrap(august_eight.deepSleepPercentage).rounded(), 23)
		XCTAssertEqual(august_eight.efficiency, 86)
		XCTAssertEqual(august_eight.sleepBPM, 54)
		XCTAssertEqual(august_eight.hrv, 56)
	}

	@MainActor
	func testSwiftDataModelsPersistInMemory() throws {
		let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
		let container = try ModelContainer(
			for: ImportedSleepRecord.self,
			SleepNight.self,
			configurations: configuration
		)
		let write_context = ModelContext(container)
		let parsed_record = try makeParsedRecord()
		let imported_record = ImportedSleepRecord(parsedRecord: parsed_record)
		let night = SleepNight(parsedRecord: parsed_record)

		write_context.insert(imported_record)
		write_context.insert(night)
		try write_context.save()

		let read_context = ModelContext(container)
		let imported_records = try read_context.fetch(FetchDescriptor<ImportedSleepRecord>())
		let sleep_nights = try read_context.fetch(FetchDescriptor<SleepNight>())

		XCTAssertEqual(imported_records.count, 1)
		XCTAssertEqual(imported_records.first?.sourceRowFingerprint, "row-round-trip")
		XCTAssertEqual(imported_records.first?.hrv, 56)
		XCTAssertEqual(sleep_nights.count, 1)
		XCTAssertEqual(sleep_nights.first?.asleepDuration, 27_720)
		XCTAssertEqual(sleep_nights.first?.spo2Avg, nil)
	}

	private func assertSendable<T: Sendable>(_: T.Type) {}

	private func makeDate(
		year: Int,
		month: Int,
		day: Int,
		hour: Int = 0,
		minute: Int = 0
	) throws -> Date {
		try XCTUnwrap(
			SampleSleepData.calendar.date(
				from: DateComponents(
					year: year,
					month: month,
					day: day,
					hour: hour,
					minute: minute
				)
			)
		)
	}

	private func makeParsedRecord() throws -> ParsedSleepRecord {
		let bedtime = try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		let wake_time = try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)

		return ParsedSleepRecord(
			sourceFile: "AutoSleep.csv",
			sourceRowFingerprint: "row-round-trip",
			startDate: bedtime,
			endDate: wake_time,
			timeZoneIdentifier: SampleSleepData.calendar.timeZone.identifier,
			bedtime: bedtime,
			wakeTime: wake_time,
			inBedDuration: 29_400,
			awakeDuration: 1_680,
			asleepDuration: 27_720,
			deepDuration: 6_300,
			efficiency: 86,
			sleepBPM: 54,
			hrv: 56,
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
