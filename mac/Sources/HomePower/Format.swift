import Foundation

enum Format {
    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    static let weekdayDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// "820 Wh", "3.21 kWh".
    static func energy(_ wh: Double) -> String {
        wh < 999.5 ? "\(Int(wh.rounded())) Wh" : String(format: "%.2f kWh", wh / 1000)
    }

    static func percent(_ share: Double) -> String {
        let p = share * 100
        return p > 0 && p < 1 ? "<1%" : "\(Int(p.rounded()))%"
    }

    /// "6 h 30 min", "12 min", "45 s".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min" }
        let (h, m) = (s / 3600, (s % 3600) / 60)
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Power-axis ticks: "0", "500 W", "−1 kW".
    static func axisWatts(_ w: Double) -> String {
        let sign = w < 0 ? "−" : ""
        let a = abs(w)
        if a == 0 { return "0" }
        if a >= 1000 { return sign + String(format: "%g kW", (a / 100).rounded() / 10) }
        return sign + "\(Int(a.rounded())) W"
    }

    static func watts(_ w: Int) -> String {
        abs(w) >= 1000 ? String(format: "%.2f kW", Double(w) / 1000) : "\(w) W"
    }

    static func kWh(_ wh: Double) -> String {
        String(format: "%.2f", wh / 1000)
    }

    /// "≈ 13 h 20 min", "≈ 45 min"; rounded to 10 minutes past an hour, since
    /// the draw moves more than that between polls.
    static func hours(_ h: Double) -> String {
        let minutes = Int((h * 60).rounded())
        if minutes < 60 { return "≈ \(max(minutes, 1)) min" }
        let rounded = Int((Double(minutes) / 10).rounded()) * 10
        let (hh, mm) = (rounded / 60, rounded % 60)
        if hh >= 48 { return "≈ \(hh / 24) days" }
        return mm == 0 ? "≈ \(hh) h" : "≈ \(hh) h \(mm) min"
    }

    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return "at \(clock.string(from: date))"
    }
}
