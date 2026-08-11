import SwiftUI

struct DashboardOverviewView: View {
	let state: DashboardViewState
	let title: String

	var body: some View {
		VStack(spacing: 0) {
			contextBar
			Divider()

			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					if title == "Trends" {
						trendHeading
					}
					SummaryMetricsView(summary: state.snapshot.summary)
					SleepTimelineChartsView(state: state)
				}
				.padding(.horizontal, 28)
				.padding(.vertical, 22)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.scrollIndicators(.visible)
		}
		.background(Color(nsColor: .windowBackgroundColor))
	}

	private var contextBar: some View {
		HStack(spacing: 8) {
			Text(state.isUsingSampleData ? "Sample data" : "Imported data")
			Circle()
				.fill(.secondary)
				.frame(width: 3, height: 3)
			Text(DashboardFormatting.formatRange(state.visibleNights))
			Spacer()
			Text("\(state.visibleNights.count) nights")
		}
		.font(.callout)
		.foregroundStyle(.secondary)
		.padding(.horizontal, 24)
		.frame(height: 44)
		.accessibilityElement(children: .combine)
	}

	private var trendHeading: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Long-range patterns")
				.font(.title2.weight(.semibold))
			Text("Compare each metric on the same date axis, then inspect an exact night.")
				.foregroundStyle(.secondary)
		}
		.accessibilityElement(children: .combine)
	}
}

private struct SummaryMetricsView: View {
	let summary: SleepRangeSummary

	var body: some View {
		ViewThatFits(in: .horizontal) {
			HStack(alignment: .top, spacing: 56) {
				summaryItems
			}

			LazyVGrid(
				columns: [GridItem(.flexible()), GridItem(.flexible())],
				alignment: .leading,
				spacing: 18
			) {
				summaryItems
			}
		}
	}

	@ViewBuilder
	private var summaryItems: some View {
		SummaryMetric(
			label: "Average Sleep",
			value: DashboardFormatting.formatDuration(summary.averageAsleepDuration)
		)
		SummaryMetric(
			label: "Avg. Efficiency",
			value: DashboardFormatting.formatPercent(summary.averageEfficiency)
		)
		SummaryMetric(
			label: "Average HRV",
			value: DashboardFormatting.formatNumber(summary.averageHRV, unit: "ms")
		)
		SummaryMetric(
			label: "Avg. Bedtime",
			value: DashboardFormatting.formatAxisTime(summary.averageBedtimeAxisHour)
		)
	}
}

private struct SummaryMetric: View {
	let label: String
	let value: String

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(label)
				.font(.callout)
				.foregroundStyle(.secondary)
			Text(value)
				.font(.system(.title, design: .rounded, weight: .regular))
				.monospacedDigit()
		}
		.frame(minWidth: 150, alignment: .leading)
		.accessibilityElement(children: .combine)
	}
}
