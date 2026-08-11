import SwiftUI

struct NightInspectorView: View {
	let state: DashboardViewState
	let onShowDetails: () -> Void

	var body: some View {
		ScrollView {
			Group {
				if let details = state.selectedNightDetails {
					VStack(alignment: .leading, spacing: 0) {
					Text(
						DashboardFormatting.formatDate(
							details.nightDate,
							timeZoneIdentifier: details.timeZoneIdentifier
						)
					)
					.font(.title2.weight(.semibold))
					Text("Selected night")
						.foregroundStyle(.secondary)
						.padding(.top, 4)
					Divider().padding(.vertical, 20)

					NightDefinitionRow(
						label: "Asleep",
						value: DashboardFormatting.formatDuration(details.asleepDuration)
					)
					NightDefinitionRow(
						label: "Bedtime",
						value: DashboardFormatting.formatTime(
							details.bedtime,
							timeZoneIdentifier: details.timeZoneIdentifier
						)
					)
					NightDefinitionRow(
						label: "Wake time",
						value: DashboardFormatting.formatTime(
							details.wakeTime,
							timeZoneIdentifier: details.timeZoneIdentifier
						)
					)
					NightDefinitionRow(
						label: "Deep sleep",
						value: DashboardFormatting.formatDeepSleep(details)
					)
					NightDefinitionRow(
						label: "Efficiency",
						value: DashboardFormatting.formatPercent(details.efficiency)
					)
					NightDefinitionRow(
						label: "Sleep BPM",
						value: DashboardFormatting.formatNumber(details.sleepBPM, unit: "bpm")
					)
					NightDefinitionRow(
						label: "HRV",
						value: DashboardFormatting.formatNumber(details.hrv, unit: "ms")
					)

					Button("Show Details", action: onShowDetails)
						.frame(maxWidth: .infinity)
						.padding(.top, 24)
						.keyboardShortcut("d", modifiers: [.command])
						.help("Open Detail Metrics for this selected night")
					}
					.padding(24)
				} else {
					ContentUnavailableView(
						"No Night Selected",
						systemImage: "moon.zzz",
						description: Text(
							"Choose a night in a timeline to inspect its exact values."
						)
					)
					.padding()
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Color(nsColor: .controlBackgroundColor))
	}
}

struct NightDefinitionRow: View {
	let label: String
	let value: String

	var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .firstTextBaseline, spacing: 12) {
				Text(label)
				Spacer()
				Text(value)
					.foregroundStyle(.secondary)
					.monospacedDigit()
					.multilineTextAlignment(.trailing)
			}
			.padding(.vertical, 14)
			Divider()
		}
		.accessibilityElement(children: .combine)
	}
}
