import Foundation

/// Whether the station has grid power. Not inferred yet.
///
/// The Local API has no field for it. With no CT meter, `ongrid_power` 0 and a
/// load on BACKUP mean either a blackout (the battery feeds the socket) or a
/// bypass (the grid feeds it straight through). On 2026-10-14 the unit was
/// unplugged and the balance read as discharge — 0 W grid, ~140 W BACKUP,
/// `bat_capacity` falling 5 Wh per ~2 min. What a plugged-in unit reports is
/// still to be recorded; until then this stays `.unknown` and the UI says
/// nothing about the grid. Modbus register 35100 (4 backup, 6 bypass) states it
/// outright, but Modbus needs the LAN cable.
enum GridState: Equatable {
    case unknown
    case on
    case off

    static func infer(from reading: StationReading) -> GridState { .unknown }
}

/// What the battery is doing, from the sign of its power.
enum Flow: Equatable {
    case charging
    case discharging
    case idle

    /// Below this the reading is noise or standby draw.
    static let threshold = 15

    init(batteryW: Int?) {
        guard let w = batteryW else { self = .idle; return }
        self = w > Self.threshold ? .discharging : (w < -Self.threshold ? .charging : .idle)
    }
}

/// One merged reading of the station, from whichever methods answered.
///
/// Sign convention, as the firmware has it: `gridW` positive means the station
/// pushes power out to the grid, negative means it draws from it; `batteryW`
/// positive means the battery discharges (the same sign Passive mode uses).
struct StationReading: Equatable {
    var soc: Int
    var ratedWh: Double?
    var remainingWh: Double?
    var batteryTempC: Double?
    var gridW: Int?
    var backupW: Int?
    var pvW: Int?
    var batteryW: Int?
    /// `bat_power` was missing (firmware 148, 150) and `batteryW` comes from the
    /// energy balance instead.
    var batteryEstimated = false
    var mode: String?
    var device: String?
    var firmware: Int?
    var bleMac: String?
    var ssid: String?
    var rssi: Int?
    var meterConnected: Bool?

    var flow: Flow { Flow(batteryW: batteryW) }
    var grid: GridState { GridState.infer(from: self) }

    // MARK: - Parsing

    /// The methods a full reading is made of, in the order they are asked.
    /// `ES.GetStatus` is the one that must answer; the rest fill in detail.
    enum Method: String, CaseIterable {
        case status = "ES.GetStatus"
        case battery = "Bat.GetStatus"
        case mode = "ES.GetMode"
        case wifi = "Wifi.GetStatus"
        case device = "Marstek.GetDevice"
    }

    /// Builds a reading from `result` objects keyed by method name. Missing
    /// methods leave their fields at `previous`'s values: mode, Wi-Fi and the
    /// device are asked less often than power. Nil when `ES.GetStatus` has no
    /// state of charge — nothing else is worth showing without it.
    static func parse(_ results: [Method: [String: Any]], previous: StationReading? = nil) -> StationReading? {
        let status = results[.status] ?? [:]
        let battery = results[.battery]
        let modeReply = results[.mode]

        guard let soc = int(status["bat_soc"]) ?? int(battery?["soc"]) ?? int(modeReply?["bat_soc"]) else {
            return nil
        }

        var r = previous ?? StationReading(soc: soc)
        r.soc = min(max(soc, 0), 100)
        r.ratedWh = number(battery?["rated_capacity"]) ?? number(status["bat_cap"]) ?? r.ratedWh

        if let battery {
            r.remainingWh = scaledWh(number(battery["bat_capacity"]), rated: r.ratedWh)
            r.batteryTempC = number(battery["bat_temp"]).map { $0 > 100 ? $0 / 10 : $0 }   // ×10 on some firmware
        }

        r.gridW = signed16(status["ongrid_power"]) ?? signed16(modeReply?["ongrid_power"])
        r.backupW = signed16(status["offgrid_power"]) ?? signed16(modeReply?["offgrid_power"])
        r.pvW = signed16(status["pv_power"])

        if let direct = signed16(status["bat_power"]) {
            r.batteryW = direct
            r.batteryEstimated = false
        } else if r.gridW != nil || r.backupW != nil {
            // What leaves through the grid port and BACKUP, minus what PV brings in.
            r.batteryW = (r.gridW ?? 0) + (r.backupW ?? 0) - max(r.pvW ?? 0, 0)
            r.batteryEstimated = true
        } else {
            r.batteryW = nil
        }

        if let modeReply { r.mode = modeName(modeReply["mode"]) ?? r.mode }

        if let wifi = results[.wifi] {
            r.ssid = (wifi["ssid"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? r.ssid
            r.rssi = int(wifi["rssi"]) ?? r.rssi
        }

        if let device = results[.device] {
            r.device = device["device"] as? String ?? r.device
            r.firmware = int(device["ver"]) ?? r.firmware
            r.bleMac = device["ble_mac"] as? String ?? r.bleMac
        }
        return r
    }

    /// `ES.GetMode` names the mode; some firmware sends 0–4 instead.
    static func modeName(_ raw: Any?) -> String? {
        if let s = raw as? String, !s.isEmpty { return s }
        guard let i = int(raw) else { return nil }
        let names = ["Auto", "AI", "Manual", "Passive", "UPS"]
        return names.indices.contains(i) ? names[i] : "Mode \(i)"
    }

    // MARK: - Number helpers

    /// JSON booleans are refused. Not with `is Bool`: any NSNumber holding 0
    /// or 1 passes that test, and 0 W is a common power.
    static func number(_ raw: Any?) -> Double? {
        if let n = raw as? NSNumber {
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : n.doubleValue
        }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    static func int(_ raw: Any?) -> Int? {
        number(raw).map { Int($0.rounded()) }
    }

    /// Some firmware sends negative powers as unsigned 16-bit values.
    static func signed16(_ raw: Any?) -> Int? {
        guard let v = int(raw) else { return nil }
        return v > 32767 && v <= 65535 ? v - 65536 : v
    }

    /// `bat_capacity` is Wh on the Venus E 3.0, but scaled differently on other
    /// hardware generations (jaapp/ha-marstek-local-api #144). A value that
    /// can't fit the battery is tried at ÷10 and ÷100 before it is dropped.
    static func scaledWh(_ raw: Double?, rated: Double?) -> Double? {
        guard let raw, raw >= 0 else { return nil }
        guard let rated, rated > 0 else { return raw }
        for scale in [1.0, 10, 100] where raw / scale <= rated * 1.05 {
            return raw / scale
        }
        return nil
    }
}
