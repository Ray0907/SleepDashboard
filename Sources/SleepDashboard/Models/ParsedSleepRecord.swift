import Foundation

struct ParsedSleepRecord: Sendable {
	let sourceFile: String
	let sourceRowFingerprint: String
	let startDate: Date
	let endDate: Date
	let timeZoneIdentifier: String
	let bedtime: Date
	let wakeTime: Date
	let inBedDuration: TimeInterval
	let awakeDuration: TimeInterval
	let asleepDuration: TimeInterval
	let deepDuration: TimeInterval
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

	init(
		sourceFile: String,
		sourceRowFingerprint: String,
		startDate: Date,
		endDate: Date,
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
		self.sourceFile = sourceFile
		self.sourceRowFingerprint = sourceRowFingerprint
		self.startDate = startDate
		self.endDate = endDate
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
}
