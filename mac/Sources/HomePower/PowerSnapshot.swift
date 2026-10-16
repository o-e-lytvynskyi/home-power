import Foundation

/// What the status item shows, in the order problems take precedence.
enum PowerState: Equatable {
    /// No address yet; discovery is running.
    case searching
    /// Discovery found nothing on the local networks.
    case notFound
    /// macOS refused to send: Local Network permission.
    case blocked
    /// An address, but no answer yet.
    case connecting
    /// No answer for `PowerSnapshot.offlineAfter` polls in a row.
    case offline
    case charging
    case discharging
    case idle

    var hasReading: Bool { [.charging, .discharging, .idle].contains(self) }
}

/// Everything the UI needs, as plain values. Equatable so the UI is touched
/// only when something changed.
struct PowerSnapshot: Equatable {
    /// The last good reading, kept through failures so the menu can say what
    /// the station last reported.
    var reading: StationReading?
    var updatedAt: Date?
    var host = ""
    /// Why the last poll failed; nil after a good one.
    var failure: MarstekLink.Failure?
    /// Polls in a row without an answer.
    var failures = 0

    static let offlineAfter = 3
    static let lowPercent = 20

    var state: PowerState {
        if case .blocked = failure { return .blocked }
        if host.isEmpty { return failures > 0 ? .notFound : .searching }
        if failures >= Self.offlineAfter { return .offline }
        guard let reading, updatedAt != nil else { return .connecting }
        switch reading.flow {
        case .charging:    return .charging
        case .discharging: return .discharging
        case .idle:        return .idle
        }
    }

    var isLow: Bool { state.hasReading && (reading?.soc ?? 100) <= Self.lowPercent }

    // MARK: - Text

    var title: String {
        switch state {
        case .searching:   return "Looking for the station…"
        case .notFound:    return "No station found"
        case .blocked:     return "Local network access is off"
        case .connecting:  return "Connecting to \(host)…"
        case .offline:     return "No reply from the station"
        case .charging:    return "Charging" + watts(reading?.batteryW)
        case .discharging: return "Discharging" + watts(reading?.batteryW)
        case .idle:        return "Idle"
        }
    }

    /// What to do about a problem state; nil when all is well.
    var hint: String? {
        switch state {
        case .searching, .charging, .discharging, .idle:
            return nil
        case .notFound:
            return "Nothing answered on UDP 30000. Turn on Local API in the Marstek app (Settings → Local API), or enter the address in Settings."
        case .blocked:
            return "Allow HomePower in System Settings → Privacy & Security → Local Network. A reinstall asks again."
        case .connecting:
            return failures > 0 ? "No answer yet from \(host)." : nil
        case .offline:
            return "Check that the station is on and Local API is enabled in the Marstek app: firmware updates and resets switch it off."
        }
    }

    private func watts(_ w: Int?) -> String {
        guard let w, w != 0 else { return "" }
        return " · \(Format.watts(abs(w)))"
    }
}

extension StationReading {
    /// Hours until the station stops discharging at `cutoffPercent`, at the
    /// current draw. Nil unless it is discharging and the battery reports Wh.
    func hoursLeft(cutoffPercent: Int) -> Double? {
        guard flow == .discharging, let w = batteryW, w > 0, let remaining = remainingWh, let rated = ratedWh else {
            return nil
        }
        let usable = remaining - rated * Double(cutoffPercent) / 100
        return usable > 0 ? usable / Double(w) : 0
    }

    /// Hours to a full battery at the current charge power.
    func hoursToFull() -> Double? {
        guard flow == .charging, let w = batteryW, w < 0, let remaining = remainingWh, let rated = ratedWh else {
            return nil
        }
        return max(rated - remaining, 0) / Double(-w)
    }
}

// MARK: - Demo

extension PowerSnapshot {
    static let demoStates = ["discharging", "charging", "idle", "low", "offline", "blocked", "searching"]

    /// Synthetic readings for `--demo` and `--render`. The default is what the
    /// station showed on 2026-10-14: unplugged, feeding ~140 W on BACKUP.
    static func demo(_ name: String = "discharging", at now: Date = Date()) -> PowerSnapshot {
        var reading = StationReading(soc: 43)
        reading.ratedWh = 5120
        reading.remainingWh = 2211
        reading.batteryTempC = 17
        reading.gridW = 0
        reading.backupW = 144
        reading.pvW = 0
        reading.batteryW = 144
        reading.batteryEstimated = true
        reading.mode = "Manual"
        reading.device = "VenusE 3.0"
        reading.firmware = 148
        reading.bleMac = "02005e3c0e89"
        reading.ssid = "home-2.4"
        reading.rssi = -40
        reading.meterConnected = false

        var s = PowerSnapshot(reading: reading, updatedAt: now.addingTimeInterval(-12), host: "192.168.0.46")
        switch name {
        case "charging":
            reading.soc = 78
            reading.remainingWh = 3994
            reading.gridW = -1250
            reading.backupW = 60
            reading.batteryW = -1190
            reading.mode = "Manual"
            s.reading = reading
        case "idle":
            reading.soc = 100
            reading.remainingWh = 5120
            reading.backupW = 0
            reading.batteryW = 0
            s.reading = reading
        case "low":
            reading.soc = 14
            reading.remainingWh = 717
            reading.backupW = 310
            reading.batteryW = 310
            s.reading = reading
        case "offline":
            s.updatedAt = now.addingTimeInterval(-185)
            s.failures = 4
            s.failure = .noReply
        case "blocked":
            s.reading = nil
            s.updatedAt = nil
            s.failures = 1
            s.failure = .blocked("macOS blocked the request (No route to host)")
        case "searching":
            s = PowerSnapshot()
        default:
            break
        }
        return s
    }
}
