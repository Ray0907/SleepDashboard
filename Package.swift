// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "SleepDashboard",
	platforms: [
		.macOS(.v14)
	],
	products: [
		.executable(name: "SleepDashboard", targets: ["SleepDashboard"])
	],
	targets: [
		.executableTarget(name: "SleepDashboard"),
		.testTarget(
			name: "SleepDashboardTests",
			dependencies: ["SleepDashboard"]
		)
	]
)
