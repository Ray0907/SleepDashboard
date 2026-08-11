import Foundation
import XCTest
@testable import SleepDashboard

@MainActor
final class DashboardViewStateTests: XCTestCase {
	func testSevenDayRangeIncludesLatestNightAndSixPriorCalendarDays() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())

		state.setRange(.sevenDays)

		XCTAssertEqual(state.visibleNights.count, 7)
		XCTAssertEqual(
			state.visibleNights.first?.nightDate,
			try makeDate(year: 2026, month: 8, day: 3)
		)
		XCTAssertEqual(
			state.visibleNights.last?.nightDate,
			try makeDate(year: 2026, month: 8, day: 9)
		)
	}

	func testThirtyDayRangeIncludesBothCalendarBoundaries() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())

		state.setRange(.thirtyDays)

		XCTAssertEqual(state.visibleNights.count, 30)
		XCTAssertEqual(
			state.visibleNights.first?.nightDate,
			try makeDate(year: 2026, month: 7, day: 11)
		)
		XCTAssertEqual(
			state.visibleNights.last?.nightDate,
			try makeDate(year: 2026, month: 8, day: 9)
		)
	}

	func testNinetyDayRangeIncludesAllThirtySampleNights() {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())

		state.setRange(.ninetyDays)

		XCTAssertEqual(state.visibleNights.count, 30)
	}

	func testAllRangeDoesNotApplyAStartBoundary() {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())

		state.setRange(.all)

		XCTAssertNil(state.activeDateRange)
		XCTAssertEqual(state.visibleNights.count, 30)
	}

	func testNearestDateSelectionUsesVisibleNightDates() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())
		let pointer_date = try makeDate(
			year: 2026,
			month: 8,
			day: 7,
			hour: 18
		)

		state.selectNearestDate(to: pointer_date)

		XCTAssertEqual(
			state.selectedDate,
			try makeDate(year: 2026, month: 8, day: 8)
		)
	}

	func testRangeChangeMovesSelectionToNearestVisibleNight() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())
		state.selectNearestDate(to: try makeDate(year: 2026, month: 7, day: 11))

		state.setRange(.sevenDays)

		XCTAssertEqual(
			state.selectedDate,
			try makeDate(year: 2026, month: 8, day: 3)
		)
	}

	func testKeyboardSelectionMovesAcrossVisibleNightsAndStopsAtBoundary() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())
		state.selectNearestDate(to: try makeDate(year: 2026, month: 8, day: 8))

		state.moveSelection(by: 1)
		XCTAssertEqual(state.selectedDate, try makeDate(year: 2026, month: 8, day: 9))

		state.moveSelection(by: 1)
		XCTAssertEqual(state.selectedDate, try makeDate(year: 2026, month: 8, day: 9))

		state.moveSelection(by: -1)
		XCTAssertEqual(state.selectedDate, try makeDate(year: 2026, month: 8, day: 8))
	}

	func testAugustEightInspectorMatchesApprovedExactValues() throws {
		let state = DashboardViewState(persistedNights: SampleSleepData.makeNights())
		state.selectNearestDate(to: try makeDate(year: 2026, month: 8, day: 8))

		let details = try XCTUnwrap(state.selectedNightDetails)

		XCTAssertEqual(details.nightDate, try makeDate(year: 2026, month: 8, day: 8))
		XCTAssertEqual(details.asleepDuration, 7 * 3_600 + 42 * 60)
		XCTAssertEqual(
			details.bedtime,
			try makeDate(year: 2026, month: 8, day: 8, hour: 23, minute: 18)
		)
		XCTAssertEqual(
			details.wakeTime,
			try makeDate(year: 2026, month: 8, day: 9, hour: 7, minute: 28)
		)
		XCTAssertEqual(details.deepDuration, 1 * 3_600 + 45 * 60)
		XCTAssertEqual(try XCTUnwrap(details.deepSleepPercentage), 23, accuracy: 0.5)
		XCTAssertEqual(details.efficiency, 86)
		XCTAssertEqual(details.sleepBPM, 54)
		XCTAssertEqual(details.hrv, 56)
	}

	func testEmptyPersistentStoreUsesSampleDataAndApprovedDefaultSelection() throws {
		let state = DashboardViewState(persistedNights: [])

		XCTAssertTrue(state.isUsingSampleData)
		XCTAssertEqual(state.selectedRange, .thirtyDays)
		XCTAssertEqual(state.visibleNights.count, 30)
		XCTAssertEqual(
			state.selectedDate,
			try makeDate(year: 2026, month: 8, day: 8)
		)
	}

	func testImportSummaryTransitionsFromImportingToSuccess() {
		let state = DashboardViewState(persistedNights: [])
		let summary = SleepImportSummary(
			importedCount: 28,
			skippedCount: 2,
			duplicateCount: 1
		)

		state.beginImport(fileName: "AutoSleep.csv")
		XCTAssertEqual(state.importState, .importing(fileName: "AutoSleep.csv"))

		state.finishImport(summary: summary)
		XCTAssertEqual(state.importState, .succeeded(summary))
	}

	func testImportErrorReplacesProgressStateAndCanBeDismissed() {
		let state = DashboardViewState(persistedNights: [])

		state.beginImport(fileName: "Unreadable.csv")
		state.failImport(message: "The CSV could not be read.")
		XCTAssertEqual(state.importState, .failed("The CSV could not be read."))

		state.dismissImportStatus()
		XCTAssertEqual(state.importState, .idle)
	}

	func testReplacingSampleDataWithPersistentNightsSelectsLatestNight() {
		let state = DashboardViewState(persistedNights: [])
		let imported_nights = Array(SampleSleepData.makeNights().prefix(2))

		state.replacePersistedNights(imported_nights)

		XCTAssertFalse(state.isUsingSampleData)
		XCTAssertEqual(state.visibleNights.count, 2)
		XCTAssertEqual(state.selectedDate, imported_nights.last?.nightDate)
	}

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
