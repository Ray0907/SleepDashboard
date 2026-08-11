import Foundation

enum DashboardFormatting {
	static func formatDuration(_ duration: TimeInterval?) -> String {
		guard let duration else {
			return "Not recorded"
		}

		let total_minutes = Int((duration / 60).rounded())
		let hours = total_minutes / 60
		let minutes = total_minutes % 60
		return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
	}

	static func formatPercent(_ value: Double?) -> String {
		guard let value else {
			return "Not recorded"
		}

		return "\(Int(value.rounded()))%"
	}

	static func formatNumber(
		_ value: Double?,
		unit: String,
		fractionDigits: Int = 0
	) -> String {
		guard let value else {
			return "Not recorded"
		}

		return value.formatted(
			.number.precision(.fractionLength(fractionDigits))
		) + " \(unit)"
	}

	static func formatTime(_ date: Date?, timeZoneIdentifier: String? = nil) -> String {
		guard let date else {
			return "Not recorded"
		}

		let formatter = DateFormatter()
		formatter.locale = .current
		formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}

	static func formatAxisTime(_ axisHour: Double?) -> String {
		guard let axisHour else {
			return "Not recorded"
		}

		let total_minutes = Int((axisHour * 60).rounded()) % (24 * 60)
		let hour = total_minutes / 60
		let minute = total_minutes % 60
		let period = hour < 12 ? "AM" : "PM"
		let display_hour = hour % 12 == 0 ? 12 : hour % 12
		return String(format: "%d:%02d %@", display_hour, minute, period)
	}

	static func formatDate(_ date: Date, timeZoneIdentifier: String? = nil) -> String {
		let formatter = DateFormatter()
		formatter.locale = .current
		formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
		formatter.dateFormat = "EEEE, MMM d"
		return formatter.string(from: date)
	}

	static func formatRange(_ nights: [SleepNight]) -> String {
		guard let first_night = nights.first, let last_night = nights.last else {
			return "No nights in this range"
		}

		let formatter = DateIntervalFormatter()
		formatter.locale = .current
		formatter.timeZone = TimeZone(identifier: last_night.timeZoneIdentifier)
		formatter.dateStyle = .medium
		formatter.timeStyle = .none
		return formatter.string(from: first_night.nightDate, to: last_night.nightDate)
	}

	static func formatDeepSleep(_ details: DashboardNightDetails) -> String {
		let duration = formatDuration(details.deepDuration)
		guard let percentage = details.deepSleepPercentage else {
			return duration
		}

		return "\(duration) · \(formatPercent(percentage))"
	}
}
