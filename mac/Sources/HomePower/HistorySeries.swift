import Foundation

/// The periods the History window offers, with the bucket each is drawn in:
/// about 200–360 points across, whatever the period.
enum HistoryRange: String, CaseIterable, Identifiable {
    case sixHours = "6 h"
    case day = "24 h"
    case week = "7 d"
    case month = "30 d"

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .sixHours: return 6 * 3600
        case .day:      return 24 * 3600
        case .week:     return 7 * 86_400
        case .month:    return 30 * 86_400
        }
    }

    var bucket: TimeInterval {
        switch self {
        case .sixHours: return 120
        case .day:      return 300
        case .week:     return 1800
        case .month:    return 7200
        }
    }

    init?(flag: String) {
        switch flag {
        case "6h": self = .sixHours
        case "24h", "1d": self = .day
        case "7d": self = .week
        case "30d": self = .month
        default: return nil
        }
    }
}

/// How a stretch between two readings was turned into values.
enum Fill: Equatable {
    /// Readings close enough together to count as measured.
    case measured
    /// A short gap: power and charge drawn straight across.
    case linear
    /// A long gap: charge drawn straight across, power held at the average
    /// that explains the change in stored energy.
    case energy
}

/// Charged and discharged energy, in Wh, and how much of it is approximated.
struct EnergyTotals: Equatable {
    var charged = 0.0
    var discharged = 0.0
    var approxCharged = 0.0
    var approxDischarged = 0.0
    /// Seconds of data, and how many of them fill a gap.
    var covered = 0.0
    var approximated = 0.0

    var approxShare: Double { covered > 0 ? approximated / covered : 0 }

    mutating func add(_ other: EnergyTotals) {
        charged += other.charged
        discharged += other.discharged
        approxCharged += other.approxCharged
        approxDischarged += other.approxDischarged
        covered += other.covered
        approximated += other.approximated
    }
}

/// History turned into what the window draws: time-weighted buckets, energy
/// totals for the period and per day, and the gaps that were filled.
///
/// Between two readings the station is modelled piecewise-linearly. Readings
/// at most `maxStep` apart are measured. A wider stretch is a gap — the app
/// was not running, the Mac slept, the station did not answer — and is
/// approximated:
/// - up to `shortGap`, power and charge are drawn straight across;
/// - longer, charge is drawn straight across, and power is held at the
///   average that explains the change in stored energy across the gap
///   (Wh from `Bat.GetStatus`, else charge × rated capacity). That keeps the
///   energy totals right; what the battery did inside the gap nets out.
/// Nothing is invented before the first reading or after the last one.
struct HistorySeries {

    struct Bucket: Identifiable, Equatable {
        let id: Int
        let start: Date
        let end: Date
        let soc: Double
        let batteryW: Double
        let approximated: Bool

        var mid: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }

    struct Day: Identifiable, Equatable {
        let day: Date
        let totals: EnergyTotals
        var id: Date { day }
    }

    struct Gap: Equatable {
        let start: Date
        let end: Date
        let fill: Fill
    }

    /// Polls are 30 s apart; up to five misses still count as measured.
    static let maxStep: TimeInterval = 150
    static let shortGap: TimeInterval = 15 * 60

    let range: HistoryRange
    let start: Date
    let end: Date
    /// Only buckets that have data; an empty stretch has no bucket.
    let buckets: [Bucket]
    let totals: EnergyTotals
    let days: [Day]
    let gaps: [Gap]
    let readings: Int

    // MARK: - Model

    /// One stretch between consecutive readings, linear in charge and power.
    struct Segment: Equatable {
        let t0: Double, t1: Double
        let soc0: Double, soc1: Double
        let w0: Double, w1: Double
        let fill: Fill

        var approximated: Bool { fill != .measured }

        func soc(at t: Double) -> Double { soc0 + (soc1 - soc0) * (t - t0) / (t1 - t0) }
        func w(at t: Double) -> Double { w0 + (w1 - w0) * (t - t0) / (t1 - t0) }
    }

    static func segments(_ samples: [HistorySample], ratedWh: Double) -> [Segment] {
        guard samples.count >= 2 else { return [] }
        var result: [Segment] = []
        result.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            let t0 = a.time.timeIntervalSince1970, t1 = b.time.timeIntervalSince1970
            let dt = t1 - t0
            guard dt > 0 else { continue }
            let wa = a.batteryW ?? b.batteryW ?? 0
            let wb = b.batteryW ?? a.batteryW ?? 0
            if dt <= maxStep {
                result.append(Segment(t0: t0, t1: t1, soc0: a.soc, soc1: b.soc, w0: wa, w1: wb, fill: .measured))
            } else if dt <= shortGap {
                result.append(Segment(t0: t0, t1: t1, soc0: a.soc, soc1: b.soc, w0: wa, w1: wb, fill: .linear))
            } else {
                let ea = a.wh ?? a.soc * ratedWh / 100
                let eb = b.wh ?? b.soc * ratedWh / 100
                let average = (ea - eb) / (dt / 3600)   // positive: energy left the battery
                result.append(Segment(t0: t0, t1: t1, soc0: a.soc, soc1: b.soc,
                                      w0: average, w1: average, fill: .energy))
            }
        }
        return result
    }

    /// Energy of a linear power stretch over `dt` seconds, split by sign,
    /// in Wh: (discharged, charged).
    static func energy(from w0: Double, to w1: Double, over dt: Double) -> (Double, Double) {
        guard dt > 0 else { return (0, 0) }
        if w0 >= 0 && w1 >= 0 { return ((w0 + w1) / 2 * dt / 3600, 0) }
        if w0 <= 0 && w1 <= 0 { return (0, -(w0 + w1) / 2 * dt / 3600) }
        // Crosses zero: each side is a triangle.
        let r = w0 / (w0 - w1)
        let first = abs(w0) * r * dt / 2 / 3600
        let second = abs(w1) * (1 - r) * dt / 2 / 3600
        return w0 > 0 ? (first, second) : (second, first)
    }

    /// Totals of the model between `from` and `to`.
    static func totals(_ segments: [Segment], from: Double, to: Double) -> EnergyTotals {
        var totals = EnergyTotals()
        for s in segments where s.t1 > from && s.t0 < to {
            let u = max(s.t0, from), v = min(s.t1, to)
            let (out, into) = energy(from: s.w(at: u), to: s.w(at: v), over: v - u)
            totals.discharged += out
            totals.charged += into
            totals.covered += v - u
            if s.approximated {
                totals.approxDischarged += out
                totals.approxCharged += into
                totals.approximated += v - u
            }
        }
        return totals
    }

    // MARK: - Build

    static func build(_ samples: [HistorySample], range: HistoryRange, now: Date,
                      ratedWh: Double, calendar: Calendar = .current) -> HistorySeries {
        let size = range.bucket
        // Bucket edges sit on multiples of the bucket, so the chart doesn't
        // shift sideways with every poll.
        let start = (floor((now.timeIntervalSince1970 - range.duration) / size)) * size
        let end = ceil(now.timeIntervalSince1970 / size) * size

        // One reading before the period joins it to what came earlier.
        let firstInside = samples.firstIndex { $0.time.timeIntervalSince1970 >= start } ?? samples.count
        let lower = max(firstInside - 1, 0)
        let slice = Array(samples[lower...])
        let segments = segments(slice, ratedWh: ratedWh)

        let count = Int(((end - start) / size).rounded())
        var socArea = [Double](repeating: 0, count: count)
        var wArea = [Double](repeating: 0, count: count)
        var covered = [Double](repeating: 0, count: count)
        var approx = [Double](repeating: 0, count: count)

        for s in segments where s.t1 > start && s.t0 < end {
            var first = max(Int(floor((max(s.t0, start) - start) / size)), 0)
            let last = min(Int(floor((min(s.t1, end) - start - 1e-9) / size)), count - 1)
            while first <= last {
                let b0 = start + Double(first) * size, b1 = b0 + size
                let u = max(s.t0, b0), v = min(s.t1, b1)
                if v > u {
                    let dt = v - u
                    socArea[first] += (s.soc(at: u) + s.soc(at: v)) / 2 * dt
                    wArea[first] += (s.w(at: u) + s.w(at: v)) / 2 * dt
                    covered[first] += dt
                    if s.approximated { approx[first] += dt }
                }
                first += 1
            }
        }

        var buckets: [Bucket] = []
        for i in 0..<count where covered[i] > 0 {
            let b0 = start + Double(i) * size
            buckets.append(Bucket(id: i,
                                  start: Date(timeIntervalSince1970: b0),
                                  end: Date(timeIntervalSince1970: b0 + size),
                                  soc: socArea[i] / covered[i],
                                  batteryW: wArea[i] / covered[i],
                                  approximated: approx[i] > covered[i] / 2))
        }

        // Per calendar day, oldest first, days with data only.
        var days: [Day] = []
        var day = calendar.startOfDay(for: Date(timeIntervalSince1970: start))
        while day.timeIntervalSince1970 < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let t = totals(segments, from: max(day.timeIntervalSince1970, start), to: min(next.timeIntervalSince1970, end))
            if t.covered > 0 { days.append(Day(day: day, totals: t)) }
            day = next
        }

        var gaps: [Gap] = []
        for s in segments where s.approximated && s.t1 > start && s.t0 < end {
            gaps.append(Gap(start: Date(timeIntervalSince1970: max(s.t0, start)),
                            end: Date(timeIntervalSince1970: min(s.t1, end)), fill: s.fill))
        }

        return HistorySeries(range: range,
                             start: Date(timeIntervalSince1970: start),
                             end: Date(timeIntervalSince1970: end),
                             buckets: buckets,
                             totals: totals(segments, from: start, to: end),
                             days: days,
                             gaps: gaps,
                             readings: samples.count - firstInside)
    }

    /// The bucket under a pointer, for the crosshair readout.
    func bucket(at date: Date) -> Bucket? {
        buckets.first { $0.start <= date && date < $0.end }
    }
}

// MARK: - Demo

extension HistorySeries {
    /// Eight days of readings every 30 s, shaped like a household: charged
    /// from the grid overnight, a light load by day, a heavier one in the
    /// evening — with the gaps a real history has: a night the Mac slept
    /// through, a short Wi-Fi dropout, a stretch the station didn't answer,
    /// and single missed polls.
    static func demoSamples(now: Date, calendar: Calendar = .current) -> [HistorySample] {
        let rated = 5120.0
        let step: TimeInterval = 30
        let begin = calendar.startOfDay(for: now).addingTimeInterval(-7 * 86_400)
        var wh = rated * 0.62
        var samples: [HistorySample] = []
        var t = begin
        var i = 0

        let today = calendar.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Double) -> Date {
            today.addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3600)
        }
        let gaps: [(Date, Date)] = [
            (at(-2, 1.2), at(-2, 7.7)),      // the Mac slept through the night's charge
            (at(-1, 13.0), at(-1, 13.2)),    // a 12-minute Wi-Fi dropout
            (at(0, 9.5), at(0, 10.33)),      // the station didn't answer for 50 minutes
        ]

        while t <= now {
            let hour = Double(calendar.component(.hour, from: t)) + Double(calendar.component(.minute, from: t)) / 60
            let wobble = sin(Double(i) / 37) * 18 + sin(Double(i) / 11) * 7
            var w: Double
            switch hour {
            case 0.33..<5: w = wh < rated - 1 ? -1250 : 0     // off-peak charging from 00:20
            case 8..<18:  w = 140 + wobble
            case 18..<22: w = 320 + wobble * 2
            default:      w = 0
            }
            if wh <= rated * 0.12 && w > 0 { w = 0 }                 // the cutoff
            wh = min(max(wh - w * step / 3600, 0), rated)

            let skipped = gaps.contains { t >= $0.0 && t < $0.1 } || i % 97 == 0
            if !skipped {
                let quantised = (wh / 5).rounded() * 5               // the station reports 5 Wh steps
                samples.append(HistorySample(time: t, soc: (wh / rated * 100).rounded(),
                                             wh: quantised, batteryW: w.rounded(),
                                             backupW: max(w, 0).rounded(), gridW: min(w, 0).rounded()))
            }
            t = t.addingTimeInterval(step)
            i += 1
        }
        return samples
    }
}
