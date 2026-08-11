import Foundation

enum SampleSleepData {
	static var calendar: Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.locale = Locale(identifier: "en_US_POSIX")
		calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
		return calendar
	}

	static func makeNights() -> [SleepNight] {
		seeds.enumerated().map { index, seed in
			makeNight(dayOffset: index, seed: seed)
		}
	}

	private static func makeNight(dayOffset: Int, seed: SampleNightSeed) -> SleepNight {
		let night_date = makeDate(dayOffset: dayOffset)
		let bedtime = makeDate(
			dayOffset: dayOffset,
			minutesAfterMidnight: seed.bedtime_minutes
		)
		let in_bed_minutes = seed.asleep_minutes + seed.awake_minutes
		let wake_time = calendar.date(
			byAdding: .minute,
			value: in_bed_minutes,
			to: bedtime
		)!

		return SleepNight(
			nightDate: night_date,
			timeZoneIdentifier: calendar.timeZone.identifier,
			bedtime: bedtime,
			wakeTime: wake_time,
			inBedDuration: TimeInterval(in_bed_minutes * 60),
			awakeDuration: TimeInterval(seed.awake_minutes * 60),
			asleepDuration: TimeInterval(seed.asleep_minutes * 60),
			deepDuration: TimeInterval(seed.deep_minutes * 60),
			efficiency: seed.efficiency,
			sleepBPM: seed.sleep_bpm,
			hrv: seed.hrv,
			spo2Avg: seed.spo2_average,
			spo2Min: seed.spo2_average.map { $0 - 2 },
			spo2Max: seed.spo2_average.map { $0 + 1 },
			respAvg: seed.respiration_average,
			respMin: seed.respiration_average.map { $0 - 1.2 },
			respMax: seed.respiration_average.map { $0 + 1.4 },
			apneaHypopneaIndex: seed.apnea_hypopnea_index,
			sessionsInNight: seed.sessions
		)
	}

	private static func makeDate(
		dayOffset: Int,
		minutesAfterMidnight: Int = 0
	) -> Date {
		let components = DateComponents(year: 2026, month: 7, day: 11)
		guard let first_date = calendar.date(from: components),
			let night_date = calendar.date(byAdding: .day, value: dayOffset, to: first_date),
			let date = calendar.date(
				byAdding: .minute,
				value: minutesAfterMidnight,
				to: night_date
			)
		else {
			preconditionFailure("The fixed sample-data calendar must create valid dates")
		}

		return date
	}

	private static let seeds: [SampleNightSeed] = [
		.init(432, 38, 99, 1_410, 85, 47, 62, 96, 14.2, 2.1, 1),
		.init(390, 42, 66, 1_370, 89, 43, 50, 95, 14.6, 2.5, 1),
		.init(335, 55, 58, 1_370, 91, 49, 73, 96, 13.9, 1.8, 1),
		.init(505, 45, 128, 1_392, 78, 48, 54, 94, 15.1, 3.0, 2),
		.init(452, 36, 81, 1_395, 85, 42, 51, 95, 14.8, 2.4, 1),
		.init(300, 63, 46, 1_410, 88, 47, 64, 96, 13.7, 1.9, 1),
		.init(255, 52, 65, 1_395, 83, 45, 58, 95, 14.3, 2.8, 1),
		.init(342, 41, 69, 1_375, 84, 42, 74, 96, 14.0, 2.2, 1),
		.init(480, 49, 91, 1_380, 90, 47, 57, 97, 13.8, 1.7, 1),
		.init(300, 58, 43, 1_385, 89, 44, 65, 95, 14.4, 2.6, 2),
		.init(421, 34, 105, 1_380, 89, 54, 59, 96, 14.1, 2.0, 1),
		.init(270, 74, 49, 1_398, 77, 46, 45, 94, 15.3, 3.3, 1),
		.init(360, 69, 116, 1_378, 84, 54, 53, 95, 14.7, 2.3, 1),
		.init(388, 43, 87, 1_380, 90, 47, 69, 96, 13.9, 1.6, 1),
		.init(260, 54, 48, 1_400, 91, 45, 55, 95, 14.5, 2.7, 1),
		.init(480, 46, 110, 1_385, 83, 42, 60, 96, 14.2, 2.1, 2),
		.init(358, 39, 62, 1_380, 91, 54, 57, 97, 13.6, 1.9, 1),
		.init(278, 48, 80, 1_390, 89, 55, 68, 95, 14.8, 2.5, 1),
		.init(429, 59, 122, 1_395, 84, 47, 72, 94, 15.0, 3.1, 1),
		.init(360, 50, 103, 1_380, 80, 42, 65, 96, 14.4, 2.4, 2),
		.init(420, 44, 76, 1_405, 87, 51, 64, 95, 13.7, 1.8, 1),
		.init(330, 57, 61, 1_405, 84, 40, 46, 96, 14.3, 2.2, 1),
		.init(525, 40, 130, 1_392, 92, 50, 49, 97, 13.9, 1.5, 1),
		.init(350, 52, 59, 1_390, 89, 53, 78, 95, 14.6, 2.9, 1),
		.init(280, 65, 82, 1_390, 84, 50, 63, 94, 15.2, 3.2, 2),
		.init(390, 42, 55, 1_400, 88, 45, 69, 96, 14.1, 2.0, 1),
		.init(430, 38, 94, 1_380, 88, 52, 59, 97, 13.8, 1.6, 1),
		.init(370, 49, 68, 1_370, 89, 54, 60, 95, 14.5, 2.6, 1),
		.init(462, 28, 105, 1_398, 86, 54, 56, 96, 14.0, 2.1, 1),
		.init(468, 37, 112, 1_395, 88, 49, 68, 96, 14.2, 1.9, 1)
	]
}

private struct SampleNightSeed: Sendable {
	let asleep_minutes: Int
	let awake_minutes: Int
	let deep_minutes: Int
	let bedtime_minutes: Int
	let efficiency: Double
	let sleep_bpm: Double
	let hrv: Double
	let spo2_average: Double?
	let respiration_average: Double?
	let apnea_hypopnea_index: Double?
	let sessions: Int

	init(
		_ asleep_minutes: Int,
		_ awake_minutes: Int,
		_ deep_minutes: Int,
		_ bedtime_minutes: Int,
		_ efficiency: Double,
		_ sleep_bpm: Double,
		_ hrv: Double,
		_ spo2_average: Double?,
		_ respiration_average: Double?,
		_ apnea_hypopnea_index: Double?,
		_ sessions: Int
	) {
		self.asleep_minutes = asleep_minutes
		self.awake_minutes = awake_minutes
		self.deep_minutes = deep_minutes
		self.bedtime_minutes = bedtime_minutes
		self.efficiency = efficiency
		self.sleep_bpm = sleep_bpm
		self.hrv = hrv
		self.spo2_average = spo2_average
		self.respiration_average = respiration_average
		self.apnea_hypopnea_index = apnea_hypopnea_index
		self.sessions = sessions
	}
}
