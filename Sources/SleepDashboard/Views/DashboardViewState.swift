import Foundation
import Observation

enum DashboardRangePreset: String, CaseIterable, Identifiable, Sendable {
	case sevenDays = "7D"
	case thirtyDays = "30D"
	case ninetyDays = "90D"
	case all = "All"

	var id: Self { self }

	var dayCount: Int? {
		switch self {
		case .sevenDays:
			7
		case .thirtyDays:
			30
		case .ninetyDays:
			90
		case .all:
			nil
		}
	}
}

enum DashboardImportState: Equatable, Sendable {
	case idle
	case importing(fileName: String)
	case succeeded(SleepImportSummary)
	case failed(String)
}

struct DashboardNightDetails: Equatable, Sendable {
	let nightDate: Date
	let timeZoneIdentifier: String
	let bedtime: Date
	let wakeTime: Date
	let inBedDuration: TimeInterval
	let awakeDuration: TimeInterval
	let asleepDuration: TimeInterval
	let deepDuration: TimeInterval
	let deepSleepPercentage: Double?
	let efficiency: Double
	let sleepBPM: Double?
	let hrv: Double?
	let spo2Avg: Double?
	let spo2Min: Double?
	let spo2Max: Double?
	let respAvg: Double?
	let respMin: Double?
	let respMax: Double?
	let apneaHypopneaIndex: Double?
	let sessionsInNight: Int

	init(night: SleepNight) {
		nightDate = night.nightDate
		timeZoneIdentifier = night.timeZoneIdentifier
		bedtime = night.bedtime
		wakeTime = night.wakeTime
		inBedDuration = night.inBedDuration
		awakeDuration = night.awakeDuration
		asleepDuration = night.asleepDuration
		deepDuration = night.deepDuration
		deepSleepPercentage = night.deepSleepPercentage
		efficiency = night.efficiency
		sleepBPM = night.sleepBPM
		hrv = night.hrv
		spo2Avg = night.spo2Avg
		spo2Min = night.spo2Min
		spo2Max = night.spo2Max
		respAvg = night.respAvg
		respMin = night.respMin
		respMax = night.respMax
		apneaHypopneaIndex = night.apneaHypopneaIndex
		sessionsInNight = night.sessionsInNight
	}
}

@MainActor
@Observable
final class DashboardViewState {
	private var all_nights: [SleepNight]
	private var calendar: Calendar

	private(set) var isUsingSampleData: Bool
	private(set) var selectedRange: DashboardRangePreset = .thirtyDays
	private(set) var selectedDate: Date?
	private(set) var importState: DashboardImportState = .idle

	var activeDateRange: ClosedRange<Date>? {
		guard let day_count = selectedRange.dayCount,
			let latest_date = all_nights.last?.nightDate,
			let start_date = calendar.date(
				byAdding: .day,
				value: -(day_count - 1),
				to: latest_date
			)
		else {
			return nil
		}

		return start_date ... latest_date
	}

	var visibleNights: [SleepNight] {
		guard let date_range = activeDateRange else {
			return all_nights
		}

		return all_nights.filter { date_range.contains($0.nightDate) }
	}

	var snapshot: SleepAnalyticsSnapshot {
		SleepAnalyticsEngine.makeSnapshot(from: all_nights, in: activeDateRange)
	}

	var selectedNightDetails: DashboardNightDetails? {
		guard let selected_date = selectedDate,
			let night = visibleNights.first(where: { $0.nightDate == selected_date })
		else {
			return nil
		}

		return DashboardNightDetails(night: night)
	}

	init(persistedNights: [SleepNight]) {
		let is_empty = persistedNights.isEmpty
		let nights = is_empty ? SampleSleepData.makeNights() : persistedNights
		let sorted_nights = nights.sorted { $0.nightDate < $1.nightDate }

		all_nights = sorted_nights
		isUsingSampleData = is_empty
		calendar = Self.makeCalendar(from: sorted_nights.last)
		selectedDate = is_empty
			? Self.makeSampleSelection(from: sorted_nights, calendar: calendar)
			: sorted_nights.last?.nightDate
	}

	func setRange(_ range: DashboardRangePreset) {
		selectedRange = range
		guard let selected_date = selectedDate,
			!visibleNights.contains(where: { $0.nightDate == selected_date })
		else {
			return
		}

		selectNearestDate(to: selected_date)
	}

	func selectNearestDate(to date: Date) {
		selectedDate = visibleNights.min { first_night, second_night in
			abs(first_night.nightDate.timeIntervalSince(date))
				< abs(second_night.nightDate.timeIntervalSince(date))
		}?.nightDate
	}

	func moveSelection(by offset: Int) {
		let nights = visibleNights
		guard !nights.isEmpty else {
			selectedDate = nil
			return
		}
		guard let selected_date = selectedDate,
			let selected_index = nights.firstIndex(
				where: { $0.nightDate == selected_date }
			)
		else {
			selectedDate = nights.last?.nightDate
			return
		}

		let target_index = min(max(selected_index + offset, 0), nights.count - 1)
		selectedDate = nights[target_index].nightDate
	}

	func beginImport(fileName: String) {
		importState = .importing(fileName: fileName)
	}

	func finishImport(summary: SleepImportSummary) {
		importState = .succeeded(summary)
	}

	func failImport(message: String) {
		importState = .failed(message)
	}

	func dismissImportStatus() {
		importState = .idle
	}

	func replacePersistedNights(_ persistedNights: [SleepNight]) {
		let is_empty = persistedNights.isEmpty
		let nights = is_empty ? SampleSleepData.makeNights() : persistedNights
		let sorted_nights = nights.sorted { $0.nightDate < $1.nightDate }

		all_nights = sorted_nights
		isUsingSampleData = is_empty
		calendar = Self.makeCalendar(from: sorted_nights.last)

		if is_empty {
			selectedDate = Self.makeSampleSelection(from: sorted_nights, calendar: calendar)
		} else if !sorted_nights.contains(where: { $0.nightDate == selectedDate }) {
			selectedDate = sorted_nights.last?.nightDate
		}
	}

	private static func makeCalendar(from night: SleepNight?) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.locale = Locale(identifier: "en_US_POSIX")
		calendar.timeZone = TimeZone(identifier: night?.timeZoneIdentifier ?? "") ?? .current
		return calendar
	}

	private static func makeSampleSelection(
		from nights: [SleepNight],
		calendar: Calendar
	) -> Date? {
		guard let latest_date = nights.last?.nightDate,
			let preferred_date = calendar.date(byAdding: .day, value: -1, to: latest_date)
		else {
			return nights.last?.nightDate
		}

		return nights.first(where: { $0.nightDate == preferred_date })?.nightDate
			?? nights.last?.nightDate
	}
}
