import Charts
import Combine
import SwiftUI

/// Keeps the History window's series current: rebuilt when the period changes
/// or a reading arrives, never per frame — hovering only reads it.
final class HistoryModel: ObservableObject {
    @Published var range: HistoryRange { didSet { if range != oldValue { rebuild(history.samples) } } }
    @Published private(set) var series: HistorySeries

    private let history: PowerHistory
    private let ratedWh: () -> Double
    private var watch: AnyCancellable?

    init(history: PowerHistory, range: HistoryRange = .day, ratedWh: @escaping () -> Double) {
        self.history = history
        self.range = range
        self.ratedWh = ratedWh
        series = HistorySeries.build(history.samples, range: range, now: Date(), ratedWh: ratedWh())
        // `$samples` publishes the new array before the property is set; use it.
        watch = history.$samples.dropFirst().sink { [weak self] samples in self?.rebuild(samples) }
    }

    private func rebuild(_ samples: [HistorySample]) {
        series = HistorySeries.build(samples, range: range, now: Date(), ratedWh: ratedWh())
    }
}

// MARK: - Chart parts

struct ChartPoint: Identifiable, Equatable {
    let id: Int
    let date: Date
    let value: Double
}

/// A run of points drawn as one line: contiguous buckets with the same fill
/// and, for power, the same sign. Neighbouring parts share their boundary
/// point, so the line stays unbroken where only its style changes.
struct ChartPart: Identifiable, Equatable {
    let id: Int
    let approximated: Bool
    /// Power: 1 discharging, −1 charging, 0 idle (not drawn). Charge: 0.
    let sign: Int
    var points: [ChartPoint]
}

enum ChartParts {

    static func charge(_ buckets: [HistorySeries.Bucket]) -> [ChartPart] {
        build(buckets, value: { $0.soc }, sign: { _ in 0 })
    }

    static func power(_ buckets: [HistorySeries.Bucket]) -> [ChartPart] {
        build(buckets, value: { $0.batteryW }, sign: { w in
            w > Double(Flow.threshold) ? 1 : (w < -Double(Flow.threshold) ? -1 : 0)
        })
    }

    private static func build(_ buckets: [HistorySeries.Bucket], value: (HistorySeries.Bucket) -> Double,
                              sign: (Double) -> Int) -> [ChartPart] {
        var parts: [ChartPart] = []
        var pointID = 0
        func point(_ date: Date, _ v: Double) -> ChartPoint {
            pointID += 1
            return ChartPoint(id: pointID, date: date, value: v)
        }

        for (i, b) in buckets.enumerated() {
            let v = value(b)
            let s = sign(v)
            let here = point(b.mid, v)
            let contiguous = i > 0 && buckets[i - 1].id == b.id - 1
            guard contiguous, let last = parts.last else {
                parts.append(ChartPart(id: parts.count, approximated: b.approximated, sign: s, points: [here]))
                continue
            }
            if last.sign == s && last.approximated == b.approximated {
                parts[parts.count - 1].points.append(here)
            } else if last.sign == s {
                // Same side, other fill: the dash starts where the solid ends.
                let joint = point(last.points.last!.date, last.points.last!.value)
                parts.append(ChartPart(id: parts.count, approximated: b.approximated, sign: s, points: [joint, here]))
            } else {
                // Changing sides goes through zero at the bucket edge.
                let zero = point(b.start, 0)
                if last.sign != 0 { parts[parts.count - 1].points.append(zero) }
                let opening = s != 0 ? [point(b.start, 0), here] : [here]
                parts.append(ChartPart(id: parts.count, approximated: b.approximated, sign: s, points: opening))
            }
        }
        return parts
    }
}

// MARK: - Colours

/// Slots 1–3 of the dataviz reference palette, validated as a set in both
/// modes. Charging is blue, discharging orange (opposite poles of the power
/// chart), charge aqua. Light aqua sits below 3:1 on the surface, so every
/// value is also in text: the readout row and the day table.
struct HistoryPalette {
    let charging: Color
    let discharging: Color
    let charge: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        charging = Self.hex(dark ? 0x3987e5 : 0x2a78d6)
        discharging = Self.hex(dark ? 0xd95926 : 0xeb6834)
        charge = Self.hex(dark ? 0x199e70 : 0x1baf7a)
    }

    private static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
              blue: Double(v & 0xff) / 255)
    }
}

// MARK: - Window

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let onClose: () -> Void

    var body: some View {
        GlassCard(onClose: onClose) {
            HistoryContent(model: model)
        }
    }
}

/// The window's content without the glass, so `--render` can draw it.
struct HistoryContent: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.colorScheme) private var scheme
    @State private var hover: Date?

    /// `hover` lets `--render` draw the crosshair, which needs a pointer otherwise.
    init(model: HistoryModel, hover: Date? = nil) {
        self.model = model
        _hover = State(initialValue: hover)
    }

    static let width: CGFloat = 580
    private static let chartHeight: CGFloat = 132
    private static let dayRows = 4
    private static let rowHeight: CGFloat = 19

    private var series: HistorySeries { model.series }
    private var palette: HistoryPalette { HistoryPalette(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .padding(.bottom, 12)

            Picker("Period", selection: $model.range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.bottom, 16)

            tiles
                .padding(.bottom, 14)
            legend
                .padding(.bottom, 8)
            readout
                .padding(.bottom, 6)

            chartTitle("Charge")
            chargeChart
                .frame(height: Self.chartHeight)
                .padding(.bottom, 12)
            chartTitle("Battery power")
            powerChart
                .frame(height: Self.chartHeight)
                .padding(.bottom, 16)

            dayTable
            Text(verbatim: footer)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: Self.width, alignment: .leading)
    }

    private var footer: String {
        let step = String(format: "%g", HistorySeries.maxStep / 60)
        return "\(series.readings) readings in this period, kept \(Int(PowerHistory.retention / 86_400)) days. "
            + "Gaps over \(step) min are approximated: up to \(Int(HistorySeries.shortGap / 60)) min straight across, "
            + "longer from the change in stored energy."
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(alignment: .top, spacing: 28) {
            tile("Charged", swatch: palette.charging, value: Format.energy(series.totals.charged),
                 note: series.totals.approxCharged >= 1 ? "\(Format.energy(series.totals.approxCharged)) approximated" : " ")
            tile("Discharged", swatch: palette.discharging, value: Format.energy(series.totals.discharged),
                 note: series.totals.approxDischarged >= 1 ? "\(Format.energy(series.totals.approxDischarged)) approximated" : " ")
            tile("Gaps filled", swatch: nil, value: series.totals.covered > 0 ? Format.percent(series.totals.approxShare) : "—",
                 note: gapNote)
            Spacer(minLength: 0)
        }
    }

    private var gapNote: String {
        guard let longest = series.gaps.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) })
        else { return series.totals.covered > 0 ? "no gaps" : " " }
        return "\(series.gaps.count) gap\(series.gaps.count == 1 ? "" : "s"), longest \(Format.duration(longest.end.timeIntervalSince(longest.start)))"
    }

    private func tile(_ label: String, swatch: Color?, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let swatch {
                    RoundedRectangle(cornerRadius: 2).fill(swatch).frame(width: 10, height: 10)
                }
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .semibold))
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: Legend and readout

    private var legend: some View {
        HStack(spacing: 16) {
            key(palette.charging, "Charging")
            key(palette.discharging, "Discharging")
            HStack(spacing: 6) {
                DashKey().stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 3]))
                    .frame(width: 18, height: 2)
                Text("Approximated").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func key(_ colour: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(colour).frame(width: 10, height: 10)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// The crosshair's tooltip, pinned above the charts so it never covers
    /// them: the hovered bucket, else the latest one. Values lead.
    private var readout: some View {
        HStack(spacing: 10) {
            if let b = hover.flatMap(series.bucket(at:)) ?? series.buckets.last {
                Text(hover == nil ? "Latest" : bucketTime(b))
                    .foregroundStyle(.secondary)
                Text("\(Int(b.soc.rounded()))%")
                    .fontWeight(.semibold)
                Text(powerText(b.batteryW))
                    .fontWeight(.semibold)
                if b.approximated {
                    Text("approximated").foregroundStyle(.secondary)
                }
            } else {
                Text("No history yet: HomePower records a reading every 30 s while it runs.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12).monospacedDigit())
        .frame(height: 18)
    }

    private func powerText(_ w: Double) -> String {
        let flow = Flow(batteryW: Int(w.rounded()))
        switch flow {
        case .charging:    return "charging \(Format.watts(Int(-w.rounded())))"
        case .discharging: return "discharging \(Format.watts(Int(w.rounded())))"
        case .idle:        return "idle"
        }
    }

    private func bucketTime(_ b: HistorySeries.Bucket) -> String {
        let span = "\(Format.clock.string(from: b.start))–\(Format.clock.string(from: b.end))"
        return model.range == .sixHours || model.range == .day ? span : "\(Format.weekday.string(from: b.start)) \(span)"
    }

    private func chartTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
    }

    // MARK: Charts

    private var chargeChart: some View {
        let parts = ChartParts.charge(series.buckets)
        return Chart {
            ForEach(parts) { part in
                ForEach(part.points) { p in
                    AreaMark(x: .value("Time", p.date), yStart: .value("Charge", 0), yEnd: .value("Charge", p.value),
                             series: .value("Part", "area\(part.id)"))
                        .foregroundStyle(palette.charge.opacity(part.approximated ? 0.05 : 0.10))
                    LineMark(x: .value("Time", p.date), y: .value("Charge", p.value),
                             series: .value("Part", "line\(part.id)"))
                        .foregroundStyle(palette.charge)
                        .lineStyle(line(part.approximated))
                }
            }
            hoverMarks(value: { $0.soc }, colour: { _ in palette.charge })
        }
        .chartXScale(domain: series.start...series.end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel { axisText("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis { timeAxis }
        .chartOverlay { proxy in hoverLayer(proxy) }
        .overlay { if series.buckets.isEmpty { emptyNote } }
    }

    private var powerChart: some View {
        let parts = ChartParts.power(series.buckets).filter { $0.sign != 0 }
        let values = series.buckets.map(\.batteryW)
        let top = max(values.max() ?? 0, 200) * 1.1
        let bottom = min(values.min() ?? 0, -200) * 1.1
        return Chart {
            RuleMark(y: .value("Power", 0))
                .foregroundStyle(Color.primary.opacity(0.28))
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(parts) { part in
                let colour = part.sign > 0 ? palette.discharging : palette.charging
                ForEach(part.points) { p in
                    AreaMark(x: .value("Time", p.date), yStart: .value("Power", 0), yEnd: .value("Power", p.value),
                             series: .value("Part", "area\(part.id)"))
                        .foregroundStyle(colour.opacity(part.approximated ? 0.05 : 0.10))
                    LineMark(x: .value("Time", p.date), y: .value("Power", p.value),
                             series: .value("Part", "line\(part.id)"))
                        .foregroundStyle(colour)
                        .lineStyle(line(part.approximated))
                }
            }
            hoverMarks(value: { $0.batteryW }, colour: { w in w >= 0 ? palette.discharging : palette.charging })
        }
        .chartXScale(domain: series.start...series.end)
        .chartYScale(domain: bottom...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.12))
                AxisValueLabel { axisText(Format.axisWatts(value.as(Double.self) ?? 0)) }
            }
        }
        .chartXAxis { timeAxis }
        .chartOverlay { proxy in hoverLayer(proxy) }
        .overlay { if series.buckets.isEmpty { emptyNote } }
    }

    /// One width for both charts' y labels: the plot areas then line up, and
    /// the crosshair falls on the same moment in both.
    private func axisText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10).monospacedDigit())
            .frame(width: 44, alignment: .leading)
    }

    private func line(_ approximated: Bool) -> StrokeStyle {
        StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: approximated ? [4, 3] : [])
    }

    /// The crosshair and the hovered point, ringed in the surface colour.
    @ChartContentBuilder
    private func hoverMarks(value: @escaping (HistorySeries.Bucket) -> Double,
                            colour: @escaping (Double) -> Color) -> some ChartContent {
        if let hover, let b = series.bucket(at: hover) {
            RuleMark(x: .value("Time", b.mid))
                .foregroundStyle(Color.primary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1))
            PointMark(x: .value("Time", b.mid), y: .value("Value", value(b)))
                .symbolSize(110)
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            PointMark(x: .value("Time", b.mid), y: .value("Value", value(b)))
                .symbolSize(50)
                .foregroundStyle(colour(value(b)))
        }
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: axisDates) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.12))
            AxisValueLabel(centered: false) {
                if let date = value.as(Date.self) {
                    Text(axisLabel(date)).font(.system(size: 10).monospacedDigit())
                }
            }
        }
    }

    /// Whole hours or days, so the ticks don't drift with the period's edges.
    private var axisDates: [Date] {
        let calendar = Calendar.current
        let (unit, step): (Calendar.Component, Int) = {
            switch model.range {
            case .sixHours: return (.hour, 1)
            case .day:      return (.hour, 4)
            case .week:     return (.day, 1)
            case .month:    return (.day, 5)
            }
        }()
        var date = calendar.dateInterval(of: unit == .hour ? .hour : .day, for: series.start)?.start ?? series.start
        var result: [Date] = []
        while date <= series.end {
            if date >= series.start {
                let n = calendar.component(unit == .hour ? .hour : .day, from: date)
                if unit == .hour ? n % step == 0 : (step == 1 || (n - 1) % step == 0) { result.append(date) }
            }
            guard let next = calendar.date(byAdding: unit, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private func axisLabel(_ date: Date) -> String {
        switch model.range {
        case .sixHours, .day: return Format.clock.string(from: date)
        case .week:           return Format.weekday.string(from: date)
        case .month:          return Format.dayMonth.string(from: date)
        }
    }

    private func hoverLayer(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(Color.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geo[frame].origin.x
                        hover = proxy.value(atX: x, as: Date.self)
                    case .ended:
                        hover = nil
                    }
                }
        }
    }

    private var emptyNote: some View {
        Text("No readings in this period")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    // MARK: Day table

    /// The chart's table twin: every value is readable without hovering.
    private var dayTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayRow("Day", "Charged", "Discharged", "Approximated", header: true)
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(series.days.reversed()) { day in
                        dayRow(Format.weekdayDay.string(from: day.day),
                               day.totals.charged >= 0.5 ? Format.energy(day.totals.charged) : "—",
                               day.totals.discharged >= 0.5 ? Format.energy(day.totals.discharged) : "—",
                               day.totals.approximated > 0 ? Format.percent(day.totals.approxShare) : "—",
                               header: false)
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: Self.rowHeight * CGFloat(Self.dayRows))
        }
    }

    private func dayRow(_ day: String, _ charged: String, _ discharged: String, _ approx: String,
                        header: Bool) -> some View {
        HStack(spacing: 0) {
            Text(day).frame(width: 150, alignment: .leading)
            Text(charged).frame(width: 110, alignment: .trailing)
            Text(discharged).frame(width: 110, alignment: .trailing)
            Text(approx).frame(width: 120, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.system(size: header ? 10 : 11, weight: header ? .medium : .regular).monospacedDigit())
        .foregroundStyle(header ? Color.secondary : Color.primary)
        .frame(height: Self.rowHeight, alignment: .center)
    }
}

/// A short horizontal stroke for the legend's dash key.
private struct DashKey: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
