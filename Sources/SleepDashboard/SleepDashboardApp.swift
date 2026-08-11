import SwiftData
import SwiftUI

@main
struct SleepDashboardApp: App {
	var body: some Scene {
		WindowGroup {
			DashboardRootView()
				.preferredColorScheme(Self.captureColorScheme)
		}
		.modelContainer(for: [ImportedSleepRecord.self, SleepNight.self])
		.defaultSize(width: 1_536, height: 1_024)
	}

	private static var captureColorScheme: ColorScheme? {
		switch ProcessInfo.processInfo.environment["SLEEP_DASHBOARD_CAPTURE_APPEARANCE"] {
		case "light":
			.light
		case "dark":
			.dark
		default:
			nil
		}
	}
}
