import Foundation
import SwiftData

@Model
final class SleepNight {
	@Attribute(.unique) var nightDate: Date
	var timeZoneIdentifier: String
	var bedtime: Date
	var wakeTime: Date
	var inBedDuration: TimeInterval
	var awakeDuration: TimeInterval
	var asleepDuration: TimeInterval
	var deepDuration: TimeInterval
	var efficiency: Double
	var sleepBPM: Double?
	var hrv: Double?
	var spo2Avg: Double?
	var spo2Min: Double?
	var spo2Max: Double?
	var respAvg: Double?
	var respMin: Double?
	var respMax: Double?
	var apneaHypopneaIndex: Double?
	var sessionsInNight: Int

	var deepSleepPercentage: Double? {
		guard asleepDuration > 0 else {
			return nil
		}

		return deepDuration / asleepDuration * 100
	}

	init(
		nightDate: Date,
		timeZoneIdentifier: String,
		bedtime: Date,
		wakeTime: Date,
		inBedDuration: TimeInterval,
		awakeDuration: TimeInterval,
		asleepDuration: TimeInterval,
		deepDuration: TimeInterval,
		efficiency: Double,
		sleepBPM: Double?,
		hrv: Double?,
		spo2Avg: Double?,
		spo2Min: Double?,
		spo2Max: Double?,
		respAvg: Double?,
		respMin: Double?,
		respMax: Double?,
		apneaHypopneaIndex: Double?,
		sessionsInNight: Int
	) {
		self.nightDate = nightDate
		self.timeZoneIdentifier = timeZoneIdentifier
		self.bedtime = bedtime
		self.wakeTime = wakeTime
		self.inBedDuration = inBedDuration
		self.awakeDuration = awakeDuration
		self.asleepDuration = asleepDuration
		self.deepDuration = deepDuration
		self.efficiency = efficiency
		self.sleepBPM = sleepBPM
		self.hrv = hrv
		self.spo2Avg = spo2Avg
		self.spo2Min = spo2Min
		self.spo2Max = spo2Max
		self.respAvg = respAvg
		self.respMin = respMin
		self.respMax = respMax
		self.apneaHypopneaIndex = apneaHypopneaIndex
		self.sessionsInNight = sessionsInNight
	}

	convenience init(parsedRecord: ParsedSleepRecord) {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: parsedRecord.timeZoneIdentifier) ?? .gmt

		self.init(
			nightDate: calendar.startOfDay(for: parsedRecord.startDate),
			timeZoneIdentifier: parsedRecord.timeZoneIdentifier,
			bedtime: parsedRecord.bedtime,
			wakeTime: parsedRecord.wakeTime,
			inBedDuration: parsedRecord.inBedDuration,
			awakeDuration: parsedRecord.awakeDuration,
			asleepDuration: parsedRecord.asleepDuration,
			deepDuration: parsedRecord.deepDuration,
			efficiency: parsedRecord.efficiency,
			sleepBPM: parsedRecord.sleepBPM,
			hrv: parsedRecord.hrv,
			spo2Avg: parsedRecord.spo2Avg,
			spo2Min: parsedRecord.spo2Min,
			spo2Max: parsedRecord.spo2Max,
			respAvg: parsedRecord.respAvg,
			respMin: parsedRecord.respMin,
			respMax: parsedRecord.respMax,
			apneaHypopneaIndex: parsedRecord.apneaHypopneaIndex,
			sessionsInNight: parsedRecord.sessionsInNight
		)
	}
}
