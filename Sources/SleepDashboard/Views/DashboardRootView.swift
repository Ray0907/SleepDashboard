import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum DashboardSection: String, CaseIterable, Identifiable {
	case overview = "Overview"
	case trends = "Trends"
	case detailMetrics = "Detail Metrics"
	case imports = "Imports"

	var id: Self { self }

	var systemImage: String {
		switch self {
		case .overview:
			"chart.bar.xaxis"
		case .trends:
			"chart.xyaxis.line"
		case .detailMetrics:
			"chart.bar.doc.horizontal"
		case .imports:
			"square.and.arrow.down"
		}
	}
}

@MainActor
struct DashboardRootView: View {
	@Environment(\.modelContext) private var model_context
	@Query(sort: \SleepNight.nightDate) private var persisted_nights: [SleepNight]
	@Query private var imported_records: [ImportedSleepRecord]

	@State private var view_state = DashboardViewState(persistedNights: [])
	@State private var selected_section: DashboardSection? = .overview
	@State private var is_file_importer_presented = false
	@State private var is_delete_confirmation_presented = false
	@State private var is_error_presented = false
	@State private var error_message = ""
	@State private var deletion_message: String?

	var body: some View {
		NavigationSplitView {
			DashboardSidebar(selectedSection: $selected_section)
				.navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 260)
		} detail: {
			content
				.navigationTitle("Sleep Dashboard")
		}
		.navigationSplitViewStyle(.balanced)
		.inspector(isPresented: .constant(true)) {
			inspector
				.inspectorColumnWidth(min: 260, ideal: 300, max: 340)
		}
		.toolbar { dashboardToolbar }
		.fileImporter(
			isPresented: $is_file_importer_presented,
			allowedContentTypes: [.commaSeparatedText]
		) { result in
			handleFileImportResult(result)
		}
		.alert("Import Failed", isPresented: $is_error_presented) {
			Button("Dismiss") {
				view_state.dismissImportStatus()
			}
		} message: {
			Text(error_message)
		}
		.confirmationDialog(
			"Delete all imported sleep data?",
			isPresented: $is_delete_confirmation_presented
		) {
			Button("Delete All Data", role: .destructive) {
				deleteAllImportedData()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This removes every imported night from this Mac. Sample data will return.")
		}
		.frame(minWidth: 1_050, minHeight: 700)
		.task {
			if ProcessInfo.processInfo.environment["SLEEP_DASHBOARD_CAPTURE_APPEARANCE"] != nil {
				NSApplication.shared.activate(ignoringOtherApps: true)
			}
			view_state.replacePersistedNights(persisted_nights)
		}
	}

	@ViewBuilder
	private var content: some View {
		switch selected_section ?? .overview {
		case .overview:
			DashboardOverviewView(state: view_state, title: "Overview")
		case .trends:
			DashboardOverviewView(state: view_state, title: "Trends")
		case .detailMetrics:
			DetailMetricsView(state: view_state)
		case .imports:
			ImportView(
				state: view_state,
				hasImportedData: !imported_records.isEmpty,
				deletionMessage: deletion_message,
				onChooseFile: { is_file_importer_presented = true },
				onRequestDelete: { is_delete_confirmation_presented = true }
			)
		}
	}

	@ViewBuilder
	private var inspector: some View {
		if selected_section == .imports {
			ImportStatusInspector(state: view_state)
		} else {
			NightInspectorView(state: view_state) {
				selected_section = .detailMetrics
			}
		}
	}

	@ToolbarContentBuilder
	private var dashboardToolbar: some ToolbarContent {
		ToolbarItem(placement: .principal) {
			Picker("Date range", selection: rangeBinding) {
				ForEach(DashboardRangePreset.allCases) { range in
					Text(range.rawValue).tag(range)
				}
			}
			.pickerStyle(.segmented)
			.frame(width: 290)
			.accessibilityLabel("Dashboard date range")
		}

		ToolbarItem(placement: .primaryAction) {
			Button {
				is_file_importer_presented = true
			} label: {
				Label("Import CSV", systemImage: "square.and.arrow.down")
			}
			.labelStyle(.titleAndIcon)
			.buttonStyle(.borderedProminent)
			.help("Import an AutoSleep CSV from this Mac")
		}
	}

	private var rangeBinding: Binding<DashboardRangePreset> {
		Binding(
			get: { view_state.selectedRange },
			set: { view_state.setRange($0) }
		)
	}

	private func handleFileImportResult(_ result: Result<URL, Error>) {
		switch result {
		case .success(let file_url):
			selected_section = .imports
			importFile(at: file_url)
		case .failure(let error):
			presentImportError(error.localizedDescription)
		}
	}

	private func importFile(at fileURL: URL) {
		view_state.beginImport(fileName: fileURL.lastPathComponent)
		deletion_message = nil

		Task {
			let has_security_scope = fileURL.startAccessingSecurityScopedResource()
			defer {
				if has_security_scope {
					fileURL.stopAccessingSecurityScopedResource()
				}
			}

			do {
				let importer = AutoSleepCSVImporter(timeZone: .current)
				let coordinator = ImportCoordinator(modelContainer: model_context.container)
				let summary = try await coordinator.importFile(
					at: fileURL,
					using: importer
				)
				view_state.finishImport(summary: summary)
				try reloadPersistedNights()
			} catch {
				presentImportError(error.localizedDescription)
			}
		}
	}

	private func reloadPersistedNights() throws {
		let nights = try model_context.fetch(FetchDescriptor<SleepNight>())
		view_state.replacePersistedNights(nights)
	}

	private func presentImportError(_ message: String) {
		error_message = message
		view_state.failImport(message: message)
		is_error_presented = true
	}

	private func deleteAllImportedData() {
		do {
			for record in try model_context.fetch(FetchDescriptor<ImportedSleepRecord>()) {
				model_context.delete(record)
			}
			for night in try model_context.fetch(FetchDescriptor<SleepNight>()) {
				model_context.delete(night)
			}
			try model_context.save()
			view_state.replacePersistedNights([])
			view_state.dismissImportStatus()
			deletion_message = "All imported sleep data was deleted from this Mac."
		} catch {
			presentImportError("The imported data could not be deleted: \(error.localizedDescription)")
		}
	}
}

private struct DashboardSidebar: View {
	@Binding var selectedSection: DashboardSection?

	var body: some View {
		List(DashboardSection.allCases, selection: $selectedSection) { section in
			Label(section.rawValue, systemImage: section.systemImage)
				.tag(section)
		}
		.listStyle(.sidebar)
		.safeAreaInset(edge: .bottom) {
			VStack(alignment: .leading, spacing: 10) {
				Divider()
				Label("On-device only", systemImage: "lock")
					.font(.callout)
					.foregroundStyle(.secondary)
					.accessibilityLabel("All data stays on this Mac")
			}
			.padding(.horizontal, 14)
			.padding(.bottom, 10)
		}
		.navigationTitle("Sleep Dashboard")
	}
}
