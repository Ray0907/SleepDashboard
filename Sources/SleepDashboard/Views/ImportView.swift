import SwiftUI

struct ImportView: View {
	let state: DashboardViewState
	let hasImportedData: Bool
	let deletionMessage: String?
	let onChooseFile: () -> Void
	let onRequestDelete: () -> Void

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 28) {
			heading
			importAction
			statusSection
			Divider()
			deleteSection
		}
		.padding(32)
		.frame(maxWidth: 760, alignment: .leading)
		.frame(maxWidth: .infinity, alignment: .leading)
	}
	.background(Color(nsColor: .windowBackgroundColor))
	}

	private var heading: some View {
		VStack(alignment: .leading, spacing: 7) {
			Text("Imports")
				.font(.largeTitle.weight(.semibold))
			Text("Bring an AutoSleep History CSV into this private, local workspace.")
				.font(.title3)
				.foregroundStyle(.secondary)
			Label("Files and analysis stay on this Mac", systemImage: "lock")
				.font(.callout)
				.foregroundStyle(.secondary)
				.padding(.top, 4)
		}
		.accessibilityElement(children: .combine)
	}

	private var importAction: some View {
		VStack(alignment: .leading, spacing: 10) {
			Button(action: onChooseFile) {
				Label("Choose AutoSleep CSV…", systemImage: "doc.badge.plus")
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
			.disabled(is_importing)
			.keyboardShortcut("i", modifiers: [.command])
			Text("Supported format: AutoSleep CSV. No account, upload, or network is used.")
				.font(.callout)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private var statusSection: some View {
		switch state.importState {
		case .idle:
			if let deletionMessage {
				Label(deletionMessage, systemImage: "checkmark.circle")
					.foregroundStyle(.secondary)
			} else {
				Text(
					hasImportedData
						? "Imported nights are ready to explore."
						: "No imported file yet. Overview is showing clearly labelled sample data."
				)
				.foregroundStyle(.secondary)
			}
		case .importing(let file_name):
			VStack(alignment: .leading, spacing: 10) {
				ProgressView()
					.controlSize(.small)
				Text("Importing \(file_name)…")
					.font(.headline)
				Text("Reading, validating, and saving locally.")
					.foregroundStyle(.secondary)
			}
			.accessibilityElement(children: .combine)
		case .succeeded(let summary):
			ImportSummaryView(summary: summary)
		case .failed(let message):
			Label(message, systemImage: "exclamationmark.triangle")
				.foregroundStyle(.red)
				.accessibilityLabel("Import failed: \(message)")
		}
	}

	private var deleteSection: some View {
		VStack(alignment: .leading, spacing: 9) {
			Text("Local Data")
				.font(.headline)
			Button("Delete All Imported Data…", role: .destructive, action: onRequestDelete)
				.disabled(!hasImportedData || is_importing)
			Text(
				hasImportedData
					? "A confirmation is required before imported records and nightly summaries are removed."
					: "There is no imported data to delete. Sample data is built into the app."
			)
			.font(.callout)
			.foregroundStyle(.secondary)
		}
	}

	private var is_importing: Bool {
		if case .importing = state.importState {
			return true
		}
		return false
	}
}

struct ImportStatusInspector: View {
	let state: DashboardViewState

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			Text("Import Status")
				.font(.title2.weight(.semibold))
			Divider()
			switch state.importState {
			case .idle:
				Label("Ready", systemImage: "checkmark.circle")
				Text("Select an AutoSleep CSV to import it locally.")
					.foregroundStyle(.secondary)
			case .importing(let file_name):
				ProgressView()
				Text(file_name)
					.font(.headline)
				Text("Import in progress")
					.foregroundStyle(.secondary)
			case .succeeded(let summary):
				ImportSummaryView(summary: summary)
			case .failed(let message):
				Label("Import failed", systemImage: "exclamationmark.triangle")
					.foregroundStyle(.red)
				Text(message)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Label("On-device only", systemImage: "lock")
				.font(.callout)
				.foregroundStyle(.secondary)
		}
		.padding(24)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(Color(nsColor: .controlBackgroundColor))
	}
}

private struct ImportSummaryView: View {
	let summary: SleepImportSummary

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Label("Import complete", systemImage: "checkmark.circle")
				.font(.headline)
				.foregroundStyle(.green)
				.padding(.bottom, 12)
			NightDefinitionRow(label: "Imported", value: "\(summary.importedCount) rows")
			NightDefinitionRow(label: "Skipped", value: "\(summary.skippedCount) rows")
			NightDefinitionRow(label: "Duplicates", value: "\(summary.duplicateCount) rows")
		}
		.accessibilityElement(children: .contain)
	}
}
