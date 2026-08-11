import SwiftData
import SwiftUI

@main
struct SleepDashboardApp: App {
	var body: some Scene {
		WindowGroup {
			Text("Sleep Dashboard")
		}
		.modelContainer(for: [ImportedSleepRecord.self, SleepNight.self])
	}
}
