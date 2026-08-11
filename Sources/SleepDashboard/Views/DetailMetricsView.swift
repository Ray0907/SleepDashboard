import SwiftUI

struct DetailMetricsView: View {
	let state: DashboardViewState

	var body: some View {
		VStack(spacing: 0) {
			contextBar
			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 28) {
					heading
					if let details = state.selectedNightDetails {
						metricRows(details: details)
					} else {
						ContentUnavailableView(
							"No Night Selected",
							systemImage: "waveform.path.ecg",
							description: Text("Select a night in Overview to view detail metrics.")
						)
					}
				}
				.padding(28)
				.frame(maxWidth: 900, alignment: .leading)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}

	private var contextBar: some View {
		HStack(spacing: 8) {
			Text(state.isUsingSampleData ? "Sample data" : "Imported data")
			Circle().fill(.secondary).frame(width: 3, height: 3)
			Text(DashboardFormatting.formatRange(state.visibleNights))
			Spacer()
			Text("Same range as Overview")
		}
		.font(.callout)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 24)
		.frame(height: 44)
	}

	private var heading: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text("Detail Metrics")
				.font(.title2.weight(.semibold))
			Text("Selected-night values and averages for the active dashboard range.")
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func metricRows(details: DashboardNightDetails) -> some View {
		VStack(spacing: 0) {
			DetailMetricRow(
				label: "Blood oxygen",
				symbol: "drop",
				selectedValue: formatSpO2(details),
				rangeValue: DashboardFormatting.formatNumber(
					average(state.visibleNights.map(\.spo2Avg)),
					unit: "%",
					fractionDigits: 1
				)
			)
			DetailMetricRow(
				label: "Respiration",
				symbol: "lungs",
				selectedValue: formatRespiration(details),
				rangeValue: DashboardFormatting.formatNumber(
					average(state.visibleNights.map(\.respAvg)),
					unit: "breaths/min",
					fractionDigits: 1
				)
			)
			DetailMetricRow(
				label: "AHI",
				symbol: "waveform.path.ecg",
				selectedValue: DashboardFormatting.formatNumber(
					details.apneaHypopneaIndex,
					unit: "events/hour",
					fractionDigits: 1
				),
				rangeValue: DashboardFormatting.formatNumber(
					average(state.visibleNights.map(\.apneaHypopneaIndex)),
					unit: "events/hour",
					fractionDigits: 1
				)
			)
			DetailMetricRow(
				label: "Awake duration",
				symbol: "eye",
				selectedValue: DashboardFormatting.formatDuration(details.awakeDuration),
				rangeValue: DashboardFormatting.formatDuration(
					averageDuration(state.visibleNights.map(\.awakeDuration))
				)
			)
			DetailMetricRow(
				label: "In-bed duration",
				symbol: "bed.double",
				selectedValue: DashboardFormatting.formatDuration(details.inBedDuration),
				rangeValue: DashboardFormatting.formatDuration(
					averageDuration(state.visibleNights.map(\.inBedDuration))
				)
			)
			DetailMetricRow(
				label: "Sessions",
				symbol: "rectangle.stack",
				selectedValue: "\(details.sessionsInNight)",
				rangeValue: DashboardFormatting.formatNumber(
					average(state.visibleNights.map { Double($0.sessionsInNight) }),
					unit: "per night",
					fractionDigits: 1
				)
			)
		}
	}

	private func formatSpO2(_ details: DashboardNightDetails) -> String {
		guard let average_value = details.spo2Avg else {
			return "Not recorded"
		}

		let average_text = DashboardFormatting.formatNumber(average_value, unit: "%")
		let minimum_text = DashboardFormatting.formatNumber(details.spo2Min, unit: "%")
		let maximum_text = DashboardFormatting.formatNumber(details.spo2Max, unit: "%")
		return "\(average_text) avg · \(minimum_text) min · \(maximum_text) max"
	}

	private func formatRespiration(_ details: DashboardNightDetails) -> String {
		guard let average_value = details.respAvg else {
			return "Not recorded"
		}

		let average_text = average_value.formatted(.number.precision(.fractionLength(1)))
		let minimum_text = details.respMin?.formatted(.number.precision(.fractionLength(1)))
			?? "–"
		let maximum_text = details.respMax?.formatted(.number.precision(.fractionLength(1)))
			?? "–"
		return "\(average_text) avg · \(minimum_text) min · \(maximum_text) max breaths/min"
	}

	private func average(_ values: [Double?]) -> Double? {
		let present_values = values.compactMap { $0 }
		guard !present_values.isEmpty else {
			return nil
		}

		return present_values.reduce(0, +) / Double(present_values.count)
	}

	private func average(_ values: [Double]) -> Double? {
		guard !values.isEmpty else {
			return nil
		}

		return values.reduce(0, +) / Double(values.count)
	}

	private func averageDuration(_ values: [TimeInterval]) -> TimeInterval? {
		average(values)
	}
}

private struct DetailMetricRow: View {
	let label: String
	let symbol: String
	let selectedValue: String
	let rangeValue: String

	var body: some View {
		VStack(spacing: 0) {
			Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
				GridRow {
					Label(label, systemImage: symbol)
						.font(.headline)
					Text("Selected night")
						.font(.caption)
						.foregroundStyle(.secondary)
					Text("Range average")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				GridRow {
					Color.clear.frame(width: 190, height: 1)
					Text(selectedValue).monospacedDigit()
					Text(rangeValue).monospacedDigit()
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.vertical, 18)
			Divider()
		}
		.accessibilityElement(children: .combine)
	}
}
