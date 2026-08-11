import Foundation
import XCTest
@testable import SleepDashboard

final class AnalyticsTests: XCTestCase {
	func testAnalyticsDTOsAreSendable() {
		assertSendable(SleepAnalyticsSnapshot.self)
		assertSendable(SleepRangeSummary.self)
		assertSendable(SleepNightPoint.self)
	}

	func testCustomRangeIncludesExactStartAndEndBoundaries() throws {
		let sample_nights = SampleSleepData.makeNights()
		let start_date = try makeDate(year: 2026, month: 8, day: 7)
		let end_date = try makeDate(year: 2026, month: 8, day: 8)

		let snapshot = SleepAnalyticsEngine.makeSnapshot(
			from: sample_nights,
			in: start_date ... end_date
		)

		XCTAssertEqual(snapshot.points.map(\.nightDate), [start_date, end_date])
	}

	func testSummaryAveragesPresentNightsAndIgnoresMissingHRV() throws {
		let sample_nights = Array(SampleSleepData.makeNights().prefix(3))
		sample_nights[0].hrv = nil
		sample_nights[2].hrv = nil

		let summary = SleepAnalyticsEngine.makeSnapshot(from: sample_nights).summary

		XCTAssertEqual(
			try XCTUnwrap(summary.averageAsleepDuration),
			TimeInterval((432 + 390 + 335) * 60) / 3,
			accuracy: 0.001
		)
		XCTAssertEqual(
			try XCTUnwrap(summary.averageEfficiency),
			(85 + 89 + 91) / 3,
			accuracy: 0.001
		)
		XCTAssertEqual(try XCTUnwrap(summary.averageHRV), 50, accuracy: 0.001)
	}

	func testEmptyRangeProducesNilSummaryValues() {
		let summary = SleepAnalyticsEngine.makeSnapshot(from: []).summary

		XCTAssertNil(summary.averageAsleepDuration)
		XCTAssertNil(summary.averageEfficiency)
		XCTAssertNil(summary.averageHRV)
		XCTAssertNil(summary.averageBedtimeAxisHour)
	}

	func testSevenDayMovingAverageUsesCalendarWindowAndExcludesGaps() throws {
		let sample_nights = Array(SampleSleepData.makeNights().prefix(8))
		let nights_with_gaps = sample_nights.enumerated().compactMap { index, night in
			[2, 5].contains(index) ? nil : night
		}
		let target_date = try makeDate(year: 2026, month: 7, day: 18)

		let snapshot = SleepAnalyticsEngine.makeSnapshot(from: nights_with_gaps)
		let target_point = try XCTUnwrap(
			snapshot.points.first { $0.nightDate == target_date }
		)

		XCTAssertEqual(
			target_point.averageAsleepDuration7Day,
			TimeInterval((390 + 505 + 452 + 255 + 342) * 60) / 5,
			accuracy: 0.001
		)
	}

	func testAllNilOptionalMetricProducesNilAverageAndChartGaps() {
		let sample_nights = Array(SampleSleepData.makeNights().prefix(3))
		for night in sample_nights {
			night.hrv = nil
		}

		let snapshot = SleepAnalyticsEngine.makeSnapshot(from: sample_nights)

		XCTAssertNil(snapshot.summary.averageHRV)
		XCTAssertTrue(snapshot.points.allSatisfy { $0.hrv == nil })
	}

	func testZeroAsleepDurationProducesDeepSleepGap() {
		let night = SampleSleepData.makeNights()[0]
		night.asleepDuration = 0

		let point = SleepAnalyticsEngine.makeSnapshot(from: [night]).points[0]

		XCTAssertNil(point.deepSleepPercentage)
	}

	func testPostMidnightBedtimeSortsAfterElevenPM() throws {
		let sample_nights = Array(SampleSleepData.makeNights().prefix(2))
		sample_nights[0].bedtime = try makeDate(
			year: 2026,
			month: 7,
			day: 11,
			hour: 23
		)
		sample_nights[1].bedtime = try makeDate(
			year: 2026,
			month: 7,
			day: 13,
			hour: 1
		)

		let points = SleepAnalyticsEngine.makeSnapshot(from: sample_nights).points

		XCTAssertEqual(points[0].bedtimeAxisHour, 23, accuracy: 0.001)
		XCTAssertEqual(points[1].bedtimeAxisHour, 25, accuracy: 0.001)
		XCTAssertGreaterThan(points[1].bedtimeAxisHour, points[0].bedtimeAxisHour)
	}

	func testAugustEightSampleInspectorValuesMatchApprovedMockup() throws {
		let expected_date = try makeDate(year: 2026, month: 8, day: 8)
		let snapshot = SleepAnalyticsEngine.makeSnapshot(from: SampleSleepData.makeNights())
		let point = try XCTUnwrap(
			snapshot.points.first { $0.nightDate == expected_date }
		)

		XCTAssertEqual(point.asleepDuration, 7 * 3_600 + 42 * 60)
		XCTAssertEqual(
			point.bedtime,
			try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		)
		XCTAssertEqual(
			point.wakeTime,
			try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)
		)
		XCTAssertEqual(point.deepDuration, 1 * 3_600 + 45 * 60)
		XCTAssertEqual(
			try XCTUnwrap(point.deepSleepPercentage),
			6_300.0 / 27_720.0 * 100,
			accuracy: 0.001
		)
		XCTAssertEqual(point.efficiency, 86)
		XCTAssertEqual(point.sleepBPM, 54)
		XCTAssertEqual(point.hrv, 56)
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
}
