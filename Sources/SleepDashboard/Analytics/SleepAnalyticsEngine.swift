import Foundation

struct SleepRangeSummary: Equatable, Sendable {
	let averageAsleepDuration: TimeInterval?
	let averageEfficiency: Double?
	let averageHRV: Double?
	let averageBedtimeAxisHour: Double?
}

struct SleepNightPoint: Equatable, Identifiable, Sendable {
	var id: Date { nightDate }

	let nightDate: Date
	let bedtime: Date
	let wakeTime: Date
	let asleepDuration: TimeInterval
	let deepDuration: TimeInterval
	let averageAsleepDuration7Day: TimeInterval
	let bedtimeAxisHour: Double
	let deepSleepPercentage: Double?
	let efficiency: Double
	let sleepBPM: Double?
	let hrv: Double?
}

struct SleepAnalyticsSnapshot: Equatable, Sendable {
	let summary: SleepRangeSummary
	let points: [SleepNightPoint]
}

enum SleepAnalyticsEngine {
	static func makeSnapshot(
		from nights: [SleepNight],
		in date_range: ClosedRange<Date>? = nil
	) -> SleepAnalyticsSnapshot {
		let sorted_nights = nights.sorted { $0.nightDate < $1.nightDate }
		let range_nights = sorted_nights.filter { night in
			date_range?.contains(night.nightDate) ?? true
		}
		let points = range_nights.map { night in
			makePoint(for: night, from: sorted_nights)
		}

		return SleepAnalyticsSnapshot(
			summary: makeSummary(from: points),
			points: points
		)
	}

	static func calculateAverage(of values: [Double?]) -> Double? {
		let present_values = values.compactMap { $0 }
		return calculateAverage(ofPresent: present_values)
	}

	private static func makePoint(
		for night: SleepNight,
		from all_nights: [SleepNight]
	) -> SleepNightPoint {
		SleepNightPoint(
			nightDate: night.nightDate,
			bedtime: night.bedtime,
			wakeTime: night.wakeTime,
			asleepDuration: night.asleepDuration,
			deepDuration: night.deepDuration,
			averageAsleepDuration7Day: calculateTrailingAverage(
				for: night,
				from: all_nights
			),
			bedtimeAxisHour: calculateBedtimeAxisHour(
				for: night.bedtime,
				timeZoneIdentifier: night.timeZoneIdentifier
			),
			deepSleepPercentage: calculateDeepSleepPercentage(for: night),
			efficiency: night.efficiency,
			sleepBPM: night.sleepBPM,
			hrv: night.hrv
		)
	}

	private static func makeSummary(from points: [SleepNightPoint]) -> SleepRangeSummary {
		SleepRangeSummary(
			averageAsleepDuration: calculateAverage(
				ofPresent: points.map(\.asleepDuration)
			),
			averageEfficiency: calculateAverage(
				ofPresent: points.map(\.efficiency)
			),
			averageHRV: calculateAverage(of: points.map(\.hrv)),
			averageBedtimeAxisHour: calculateAverage(
				ofPresent: points.map(\.bedtimeAxisHour)
			)
		)
	}

	private static func calculateTrailingAverage(
		for night: SleepNight,
		from all_nights: [SleepNight]
	) -> TimeInterval {
		let calendar = makeCalendar(timeZoneIdentifier: night.timeZoneIdentifier)
		let day_end = calendar.startOfDay(for: night.nightDate)
		guard let window_start = calendar.date(byAdding: .day, value: -6, to: day_end),
			let window_end = calendar.date(byAdding: .day, value: 1, to: day_end)
		else {
			return night.asleepDuration
		}
		let window_values = all_nights.filter { candidate in
			candidate.nightDate >= window_start && candidate.nightDate < window_end
		}.map(\.asleepDuration)

		return calculateAverage(ofPresent: window_values) ?? night.asleepDuration
	}

	private static func calculateBedtimeAxisHour(
		for bedtime: Date,
		timeZoneIdentifier: String
	) -> Double {
		let calendar = makeCalendar(timeZoneIdentifier: timeZoneIdentifier)
		let components = calendar.dateComponents(
			[.hour, .minute, .second, .nanosecond],
			from: bedtime
		)
		let hour = Double(components.hour ?? 0)
		let minute = Double(components.minute ?? 0) / 60
		let second = Double(components.second ?? 0) / 3_600
		let nanosecond = Double(components.nanosecond ?? 0) / 3_600_000_000_000
		let local_hour = hour + minute + second + nanosecond

		// Local times before noon continue the prior evening's axis beyond hour 24.
		return hour < 12 ? local_hour + 24 : local_hour
	}

	private static func calculateDeepSleepPercentage(for night: SleepNight) -> Double? {
		guard night.asleepDuration > 0 else {
			return nil
		}

		return night.deepDuration / night.asleepDuration * 100
	}

	private static func calculateAverage(ofPresent values: [Double]) -> Double? {
		guard !values.isEmpty else {
			return nil
		}

		return values.reduce(0, +) / Double(values.count)
	}

	private static func makeCalendar(timeZoneIdentifier: String) -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.locale = Locale(identifier: "en_US_POSIX")
		calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
		return calendar
	}
}
