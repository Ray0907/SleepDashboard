import AppKit
import Charts
import SwiftUI

enum SleepChartPalette {
	static let duration = Color(nsColor: .systemIndigo)
	static let bedtime = Color(nsColor: .systemBlue)
	static let deepSleep = Color(nsColor: .systemPurple)
	static let efficiency = Color(nsColor: .systemBlue)
	static let sleepBPM = Color(nsColor: .systemRed)
	static let hrv = Color(nsColor: .systemTeal)
	static let selection = Color.accentColor
	static let guide = Color(nsColor: .separatorColor).opacity(0.45)
}

struct SleepTimelineChartsView: View {
	let state: DashboardViewState

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			DurationTrack(state: state, dateDomain: date_domain)
			BedtimeTrack(state: state, dateDomain: date_domain)
			DeepSleepTrack(state: state, dateDomain: date_domain)
			EfficiencyTrack(state: state, dateDomain: date_domain)
			SleepBPMTrack(state: state, dateDomain: date_domain)
			HRVTrack(state: state, dateDomain: date_domain)
		}
		.focusable()
		.focusEffectDisabled()
		.onMoveCommand { direction in
			switch direction {
			case .left:
				state.moveSelection(by: -1)
			case .right:
				state.moveSelection(by: 1)
			default:
				break
			}
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Six aligned sleep metric charts")
		.accessibilityValue(accessibility_value)
		.accessibilityAdjustableAction { direction in
			state.moveSelection(by: direction == .increment ? 1 : -1)
		}
		.help("Hover or click a date. Use Left and Right Arrow to inspect nearby nights.")
	}

	private var date_domain: ClosedRange<Date> {
		guard let first_date = state.visibleNights.first?.nightDate,
			let last_date = state.visibleNights.last?.nightDate
		else {
			return Date() ... Date().addingTimeInterval(1)
		}

		return first_date.addingTimeInterval(-48 * 3_600)
			... last_date.addingTimeInterval(48 * 3_600)
	}

	private var accessibility_value: String {
		guard let details = state.selectedNightDetails else {
			return "No selected night"
		}

		return "Selected \(DashboardFormatting.formatDate(details.nightDate)), "
			+ "\(DashboardFormatting.formatDuration(details.asleepDuration)) asleep"
	}
}

private struct DurationTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		ChartTrack(
			title: "Sleep Duration",
			color: SleepChartPalette.duration,
			axisLabels: ["10h", "8h", "6h", "4h", "2h", "0h"],
			height: 135
		) {
			Chart {
				ForEach([0, 7_200, 14_400, 21_600, 28_800, 36_000], id: \.self) { value in
					RuleMark(y: .value("Guide", value))
						.foregroundStyle(SleepChartPalette.guide)
				}
				RuleMark(y: .value("Eight-hour target", 28_800))
					.foregroundStyle(.secondary)
					.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
				ForEach(state.snapshot.points) { point in
					BarMark(
						x: .value("Night", point.nightDate),
						y: .value("Asleep", point.asleepDuration),
						width: .fixed(12)
					)
					.foregroundStyle(SleepChartPalette.duration.opacity(0.78))
					.accessibilityLabel(point.nightDate.formatted(date: .abbreviated, time: .omitted))
					.accessibilityValue(DashboardFormatting.formatDuration(point.asleepDuration))

					LineMark(
						x: .value("Night", point.nightDate),
						y: .value("Seven-day average", point.averageAsleepDuration7Day)
					)
					.foregroundStyle(SleepChartPalette.duration)
					.lineStyle(StrokeStyle(lineWidth: 1.5))
				}
				SelectionMarks(
					selectedDate: state.selectedDate,
					selectedValue: selected_point?.averageAsleepDuration7Day,
					color: SleepChartPalette.duration
				)
			}
			.chartXScale(domain: dateDomain)
			.chartYScale(domain: 0 ... 36_000)
			.chartXAxis(.hidden)
			.chartYAxis(.hidden)
			.chartOverlay { proxy in
				ChartSelectionOverlay(proxy: proxy, state: state)
			}
		}
		.overlay(alignment: .topTrailing) {
			HStack(spacing: 14) {
				Label("7-day avg", systemImage: "minus")
				Label("8h target", systemImage: "line.3.horizontal")
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			.padding(.trailing, 2)
		}
	}

	private var selected_point: SleepNightPoint? {
		state.snapshot.points.first { $0.nightDate == state.selectedDate }
	}
}

private struct BedtimeTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		ChartTrack(
			title: "Bedtime",
			color: SleepChartPalette.bedtime,
			axisLabels: ["1 AM", "12 AM", "11 PM", "10 PM"],
			height: 80
		) {
			Chart {
				ForEach([22.0, 23, 24, 25], id: \.self) { value in
					RuleMark(y: .value("Guide", value))
						.foregroundStyle(SleepChartPalette.guide)
				}
				ForEach(state.snapshot.points) { point in
					LineMark(
						x: .value("Night", point.nightDate),
						y: .value("Bedtime", point.bedtimeAxisHour)
					)
					.foregroundStyle(SleepChartPalette.bedtime)
					.lineStyle(StrokeStyle(lineWidth: 1.5))
					PointMark(
						x: .value("Night", point.nightDate),
						y: .value("Bedtime", point.bedtimeAxisHour)
					)
					.foregroundStyle(SleepChartPalette.bedtime)
					.symbolSize(24)
				}
				SelectionMarks(
					selectedDate: state.selectedDate,
					selectedValue: selected_point?.bedtimeAxisHour,
					color: SleepChartPalette.bedtime
				)
			}
			.chartXScale(domain: dateDomain)
			.chartYScale(domain: 22 ... 25.2)
			.chartXAxis(.hidden)
			.chartYAxis(.hidden)
			.chartOverlay { proxy in
				ChartSelectionOverlay(proxy: proxy, state: state)
			}
		}
	}

	private var selected_point: SleepNightPoint? {
		state.snapshot.points.first { $0.nightDate == state.selectedDate }
	}
}

private struct DeepSleepTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		let metric_points = makeOptionalMetricPoints(
			state.snapshot.points,
			keyPath: \.deepSleepPercentage
		)

		ChartTrack(
			title: "Deep Sleep",
			color: SleepChartPalette.deepSleep,
			axisLabels: ["40%", "20%", "0%"],
			height: 75
		) {
			Chart {
				ForEach([0.0, 20, 40], id: \.self) { value in
					RuleMark(y: .value("Guide", value))
						.foregroundStyle(SleepChartPalette.guide)
				}
				ForEach(metric_points) { metric in
					LineMark(
						x: .value("Night", metric.nightDate),
						y: .value("Deep sleep", metric.value),
						series: .value("Recorded sequence", metric.segment)
					)
					.foregroundStyle(SleepChartPalette.deepSleep)
					.lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
					PointMark(
						x: .value("Night", metric.nightDate),
						y: .value("Deep sleep", metric.value)
					)
					.foregroundStyle(SleepChartPalette.deepSleep)
					.symbolSize(24)
				}
				SelectionMarks(
					selectedDate: state.selectedDate,
					selectedValue: selected_value,
					color: SleepChartPalette.deepSleep
				)
			}
			.chartXScale(domain: dateDomain)
			.chartYScale(domain: 0 ... 45)
			.chartXAxis(.hidden)
			.chartYAxis(.hidden)
			.chartOverlay { proxy in
				ChartSelectionOverlay(proxy: proxy, state: state)
			}
		}
	}

	private var selected_value: Double? {
		state.snapshot.points.first { $0.nightDate == state.selectedDate }?
			.deepSleepPercentage
	}
}

private struct EfficiencyTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		ChartTrack(
			title: "Efficiency",
			color: SleepChartPalette.efficiency,
			axisLabels: ["100%", "80%", "60%"],
			height: 75
		) {
			Chart {
				ForEach([60.0, 80, 100], id: \.self) { value in
					RuleMark(y: .value("Guide", value))
						.foregroundStyle(SleepChartPalette.guide)
				}
				ForEach(state.snapshot.points) { point in
					LineMark(
						x: .value("Night", point.nightDate),
						y: .value("Efficiency", point.efficiency)
					)
					.foregroundStyle(SleepChartPalette.efficiency)
					.lineStyle(StrokeStyle(lineWidth: 1.5))
					PointMark(
						x: .value("Night", point.nightDate),
						y: .value("Efficiency", point.efficiency)
					)
					.foregroundStyle(SleepChartPalette.efficiency)
					.symbolSize(24)
				}
				SelectionMarks(
					selectedDate: state.selectedDate,
					selectedValue: selected_value,
					color: SleepChartPalette.efficiency
				)
			}
			.chartXScale(domain: dateDomain)
			.chartYScale(domain: 60 ... 100)
			.chartXAxis(.hidden)
			.chartYAxis(.hidden)
			.chartOverlay { proxy in
				ChartSelectionOverlay(proxy: proxy, state: state)
			}
		}
	}

	private var selected_value: Double? {
		state.snapshot.points.first { $0.nightDate == state.selectedDate }?.efficiency
	}
}

private struct SleepBPMTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		OptionalMetricTrack(
			state: state,
			dateDomain: dateDomain,
			title: "Sleep BPM",
			color: SleepChartPalette.sleepBPM,
			axisLabels: ["70", "50", "30"],
			yDomain: 30 ... 70,
			guides: [30, 50, 70],
			lineStyle: StrokeStyle(lineWidth: 1.5, dash: [7, 2]),
			keyPath: \.sleepBPM,
			showsDateAxis: false
		)
	}
}

private struct HRVTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>

	var body: some View {
		OptionalMetricTrack(
			state: state,
			dateDomain: dateDomain,
			title: "HRV",
			color: SleepChartPalette.hrv,
			axisLabels: ["100 ms", "50 ms", "0 ms"],
			yDomain: 0 ... 100,
			guides: [0, 50, 100],
			lineStyle: StrokeStyle(lineWidth: 1.5, dash: [2, 2]),
			keyPath: \.hrv,
			showsDateAxis: true
		)
	}
}

private struct OptionalMetricTrack: View {
	let state: DashboardViewState
	let dateDomain: ClosedRange<Date>
	let title: String
	let color: Color
	let axisLabels: [String]
	let yDomain: ClosedRange<Double>
	let guides: [Double]
	let lineStyle: StrokeStyle
	let keyPath: KeyPath<SleepNightPoint, Double?>
	let showsDateAxis: Bool

	var body: some View {
		let metric_points = makeOptionalMetricPoints(state.snapshot.points, keyPath: keyPath)

		ChartTrack(title: title, color: color, axisLabels: axisLabels, height: 76) {
			Chart {
				ForEach(guides, id: \.self) { value in
					RuleMark(y: .value("Guide", value))
						.foregroundStyle(SleepChartPalette.guide)
				}
				ForEach(metric_points) { metric in
					LineMark(
						x: .value("Night", metric.nightDate),
						y: .value(title, metric.value),
						series: .value("Recorded sequence", metric.segment)
					)
					.foregroundStyle(color)
					.lineStyle(lineStyle)
					PointMark(
						x: .value("Night", metric.nightDate),
						y: .value(title, metric.value)
					)
					.foregroundStyle(color)
					.symbolSize(24)
				}
				SelectionMarks(
					selectedDate: state.selectedDate,
					selectedValue: selected_value,
					color: color
				)
			}
			.chartXScale(domain: dateDomain)
			.chartYScale(domain: yDomain)
			.chartXAxis {
				if showsDateAxis {
					AxisMarks(values: date_axis_dates) { value in
						AxisGridLine().foregroundStyle(.clear)
						AxisTick()
						AxisValueLabel(format: .dateTime.month(.abbreviated).day())
					}
				}
			}
			.chartYAxis(.hidden)
			.chartOverlay { proxy in
				ChartSelectionOverlay(proxy: proxy, state: state)
			}
		}
	}

	private var selected_value: Double? {
		state.snapshot.points.first { $0.nightDate == state.selectedDate }?[keyPath: keyPath]
	}

	private var date_axis_dates: [Date] {
		let points = state.snapshot.points
		guard points.count > 1 else {
			return points.map(\.nightDate)
		}

		let label_count = min(6, points.count)
		return (0..<label_count).map { label_index in
			let position = Double(label_index) * Double(points.count - 1)
				/ Double(label_count - 1)
			return points[Int(position.rounded())].nightDate
		}
	}
}

private struct ChartTrack<ChartView: View>: View {
	let title: String
	let color: Color
	let axisLabels: [String]
	let height: CGFloat
	@ViewBuilder let chart: ChartView

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(title)
				.font(.headline)
				.foregroundStyle(color)
			HStack(alignment: .top, spacing: 8) {
				ChartAxisLabels(labels: axisLabels)
					.frame(width: 46, height: height)
				chart
					.frame(height: height)
			}
		}
	}
}

private struct ChartAxisLabels: View {
	let labels: [String]

	var body: some View {
		VStack(alignment: .trailing, spacing: 0) {
			ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
				Text(label)
				if index < labels.count - 1 {
					Spacer(minLength: 0)
				}
			}
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.frame(maxWidth: .infinity, alignment: .trailing)
		.accessibilityHidden(true)
	}
}

private struct SelectionMarks: ChartContent {
	let selectedDate: Date?
	let selectedValue: Double?
	let color: Color

	var body: some ChartContent {
		if let selected_date = selectedDate {
			RuleMark(x: .value("Selected night", selected_date))
				.foregroundStyle(SleepChartPalette.selection)
				.lineStyle(StrokeStyle(lineWidth: 1.25))
			if let selected_value = selectedValue {
				PointMark(
					x: .value("Selected night", selected_date),
					y: .value("Selected value", selected_value)
				)
				.symbol {
					Circle()
						.fill(Color(nsColor: .windowBackgroundColor))
						.stroke(color, lineWidth: 2)
						.frame(width: 11, height: 11)
				}
			}
		}
	}
}

private struct ChartSelectionOverlay: View {
	let proxy: ChartProxy
	let state: DashboardViewState

	var body: some View {
		GeometryReader { geometry in
			Rectangle()
				.fill(.clear)
				.contentShape(Rectangle())
				.onContinuousHover { phase in
					guard case .active(let location) = phase else {
						return
					}
					selectDate(at: location, geometry: geometry)
				}
				.simultaneousGesture(
					SpatialTapGesture().onEnded { value in
						selectDate(at: value.location, geometry: geometry)
					}
				)
		}
		.accessibilityHidden(true)
	}

	private func selectDate(at location: CGPoint, geometry: GeometryProxy) {
		guard let plot_frame = proxy.plotFrame else {
			return
		}

		let plot_rectangle = geometry[plot_frame]
		guard plot_rectangle.contains(location) else {
			return
		}

		let plot_x = location.x - plot_rectangle.origin.x
		if let date = proxy.value(atX: plot_x, as: Date.self) {
			state.selectNearestDate(to: date)
		}
	}
}

private struct OptionalMetricPoint: Identifiable {
	let nightDate: Date
	let value: Double
	let segment: Int

	var id: Date { nightDate }
}

private func makeOptionalMetricPoints(
	_ points: [SleepNightPoint],
	keyPath: KeyPath<SleepNightPoint, Double?>
) -> [OptionalMetricPoint] {
	var segment = 0
	var metric_points: [OptionalMetricPoint] = []

	for point in points {
		guard let value = point[keyPath: keyPath] else {
			segment += 1
			continue
		}
		metric_points.append(
			OptionalMetricPoint(
				nightDate: point.nightDate,
				value: value,
				segment: segment
			)
		)
	}

	return metric_points
}
