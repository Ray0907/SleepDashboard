import Foundation
import SwiftData

struct SleepImportSummary: Sendable, Equatable {
	let importedCount: Int
	let skippedCount: Int
	let duplicateCount: Int
}

enum ImportCoordinatorError: LocalizedError, Sendable {
	case invalidTimeZone(String)

	var errorDescription: String? {
		switch self {
		case .invalidTimeZone(let identifier):
			return "The import time zone \(identifier) is not available on this Mac."
		}
	}
}

@ModelActor
actor ImportCoordinator {
	func importFile(
		at fileURL: URL,
		using dataSource: any SleepDataSource
	) async throws -> SleepImportSummary {
		let parse_stream = dataSource.parse(fileURL: fileURL)
		var parsed_records: [ParsedSleepRecord] = []

		for try await record in parse_stream {
			try Task.checkCancellation()
			parsed_records.append(record)
		}

		let parse_summary = try await parse_stream.summary()
		try Task.checkCancellation()
		return try persist(parsed_records, parseSummary: parse_summary)
	}

	private func persist(
		_ parsedRecords: [ParsedSleepRecord],
		parseSummary: SleepParseSummary
	) throws -> SleepImportSummary {
		let existing_records = try modelContext.fetch(
			FetchDescriptor<ImportedSleepRecord>()
		)
		var known_fingerprints = Set(
			existing_records.map(\.sourceRowFingerprint)
		)
		var new_records: [ParsedSleepRecord] = []
		var duplicate_count = 0

		for parsed_record in parsedRecords {
			if known_fingerprints.insert(parsed_record.sourceRowFingerprint).inserted {
				new_records.append(parsed_record)
			} else {
				duplicate_count += 1
			}
		}

		try modelContext.transaction {
			try insertAndRecompute(new_records)
		}

		return SleepImportSummary(
			importedCount: new_records.count,
			skippedCount: parseSummary.skippedCount,
			duplicateCount: duplicate_count
		)
	}

	private func insertAndRecompute(_ records: [ParsedSleepRecord]) throws {
		var touched_keys = Set<NightKey>()

		for record in records {
			try Task.checkCancellation()
			let night_key = try makeNightKey(
				date: record.startDate,
				timeZoneIdentifier: record.timeZoneIdentifier
			)
			touched_keys.insert(night_key)
			modelContext.insert(ImportedSleepRecord(parsedRecord: record))
		}

		guard !touched_keys.isEmpty else {
			return
		}

		let all_records = try modelContext.fetch(FetchDescriptor<ImportedSleepRecord>())
		let all_nights = try modelContext.fetch(FetchDescriptor<SleepNight>())

		for night_key in touched_keys.sorted(by: { $0.date < $1.date }) {
			try Task.checkCancellation()
			let source_records = try all_records.filter {
				try makeNightKey(
					date: $0.startDate,
					timeZoneIdentifier: $0.timeZoneIdentifier
				) == night_key
			}
			let values = try aggregate(source_records, for: night_key)

			if let night = all_nights.first(where: { $0.nightDate == night_key.date }) {
				apply(values, to: night)
			} else {
				modelContext.insert(makeSleepNight(values))
			}
		}
	}

	private func makeNightKey(
		date: Date,
		timeZoneIdentifier: String
	) throws -> NightKey {
		guard let time_zone = TimeZone(identifier: timeZoneIdentifier) else {
			throw ImportCoordinatorError.invalidTimeZone(timeZoneIdentifier)
		}

		var calendar = Calendar(identifier: .gregorian)
		calendar.locale = Locale(identifier: "en_US_POSIX")
		calendar.timeZone = time_zone
		return NightKey(
			date: calendar.startOfDay(for: date),
			timeZoneIdentifier: timeZoneIdentifier
		)
	}

	private func aggregate(
		_ sourceRecords: [ImportedSleepRecord],
		for nightKey: NightKey
	) throws -> AggregatedNight {
		let records = sourceRecords.sorted {
			$0.sourceRowFingerprint < $1.sourceRowFingerprint
		}
		guard let first_record = records.first else {
			throw ImportCoordinatorError.invalidTimeZone(nightKey.timeZoneIdentifier)
		}

		return AggregatedNight(
			nightDate: nightKey.date,
			timeZoneIdentifier: nightKey.timeZoneIdentifier,
			bedtime: records.map(\.bedtime).min() ?? first_record.bedtime,
			wakeTime: records.map(\.wakeTime).max() ?? first_record.wakeTime,
			inBedDuration: records.reduce(0) { $0 + $1.inBedDuration },
			awakeDuration: records.reduce(0) { $0 + $1.awakeDuration },
			asleepDuration: records.reduce(0) { $0 + $1.asleepDuration },
			deepDuration: records.reduce(0) { $0 + $1.deepDuration },
			efficiency: weightedAverage(
				records,
				value: { $0.efficiency },
				weight: { $0.inBedDuration }
			) ?? first_record.efficiency,
			sleepBPM: weightedAverage(
				records,
				value: { $0.sleepBPM },
				weight: { $0.asleepDuration }
			),
			hrv: weightedAverage(
				records,
				value: { $0.hrv },
				weight: { $0.asleepDuration }
			),
			spo2Avg: weightedAverage(
				records,
				value: { $0.spo2Avg },
				weight: { $0.asleepDuration }
			),
			spo2Min: records.compactMap(\.spo2Min).min(),
			spo2Max: records.compactMap(\.spo2Max).max(),
			respAvg: weightedAverage(
				records,
				value: { $0.respAvg },
				weight: { $0.asleepDuration }
			),
			respMin: records.compactMap(\.respMin).min(),
			respMax: records.compactMap(\.respMax).max(),
			apneaHypopneaIndex: weightedAverage(
				records,
				value: { $0.apneaHypopneaIndex },
				weight: { $0.asleepDuration }
			),
			sessionsInNight: records.reduce(0) { $0 + $1.sessionsInNight }
		)
	}

	private func weightedAverage(
		_ records: [ImportedSleepRecord],
		value: (ImportedSleepRecord) -> Double?,
		weight: (ImportedSleepRecord) -> Double
	) -> Double? {
		let available_values = records.compactMap { record -> (Double, Double)? in
			guard let metric = value(record) else {
				return nil
			}

			return (metric, max(0, weight(record)))
		}
		guard !available_values.isEmpty else {
			return nil
		}

		let total_weight = available_values.reduce(0) { $0 + $1.1 }
		guard total_weight > 0 else {
			return available_values.reduce(0) { $0 + $1.0 }
				/ Double(available_values.count)
		}

		return available_values.reduce(0) { $0 + $1.0 * $1.1 } / total_weight
	}

	private func makeSleepNight(_ values: AggregatedNight) -> SleepNight {
		SleepNight(
			nightDate: values.nightDate,
			timeZoneIdentifier: values.timeZoneIdentifier,
			bedtime: values.bedtime,
			wakeTime: values.wakeTime,
			inBedDuration: values.inBedDuration,
			awakeDuration: values.awakeDuration,
			asleepDuration: values.asleepDuration,
			deepDuration: values.deepDuration,
			efficiency: values.efficiency,
			sleepBPM: values.sleepBPM,
			hrv: values.hrv,
			spo2Avg: values.spo2Avg,
			spo2Min: values.spo2Min,
			spo2Max: values.spo2Max,
			respAvg: values.respAvg,
			respMin: values.respMin,
			respMax: values.respMax,
			apneaHypopneaIndex: values.apneaHypopneaIndex,
			sessionsInNight: values.sessionsInNight
		)
	}

	private func apply(_ values: AggregatedNight, to night: SleepNight) {
		night.timeZoneIdentifier = values.timeZoneIdentifier
		night.bedtime = values.bedtime
		night.wakeTime = values.wakeTime
		night.inBedDuration = values.inBedDuration
		night.awakeDuration = values.awakeDuration
		night.asleepDuration = values.asleepDuration
		night.deepDuration = values.deepDuration
		night.efficiency = values.efficiency
		night.sleepBPM = values.sleepBPM
		night.hrv = values.hrv
		night.spo2Avg = values.spo2Avg
		night.spo2Min = values.spo2Min
		night.spo2Max = values.spo2Max
		night.respAvg = values.respAvg
		night.respMin = values.respMin
		night.respMax = values.respMax
		night.apneaHypopneaIndex = values.apneaHypopneaIndex
		night.sessionsInNight = values.sessionsInNight
	}
}

private struct NightKey: Hashable {
	let date: Date
	let timeZoneIdentifier: String
}

private struct AggregatedNight {
	let nightDate: Date
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
}
