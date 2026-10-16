import Foundation

/// Built-in cases for `--selftest`. Replies are JSON text, decoded the way the
/// socket decodes them, so numbers and booleans arrive as the same NSNumber
/// types the station produces.
enum SelfTest {

    private static var failed = 0

    static func run() -> Bool {
        parsing()
        quirks()
        estimates()
        states()
        addresses()
        history()
        notifications()
        print(failed == 0 ? "all checks passed" : "\(failed) check(s) FAILED")
        return failed == 0
    }

    private static func check(_ name: String, _ ok: Bool, _ got: Any? = nil) {
        if ok {
            print("  ok    \(name)")
        } else {
            failed += 1
            print("  FAIL  \(name)" + (got.map { "  (got \($0))" } ?? ""))
        }
    }

    private static func reading(_ replies: [StationReading.Method: String],
                                previous: StationReading? = nil) -> StationReading? {
        var results: [StationReading.Method: [String: Any]] = [:]
        for (method, text) in replies {
            results[method] = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        }
        return StationReading.parse(results, previous: previous)
    }

    // The station on 2026-10-14: firmware 148, unplugged, ~144 W on BACKUP.
    private static let unplugged: [StationReading.Method: String] = [
        .status: #"{"id":0,"bat_soc":43,"bat_cap":5120,"pv_power":0,"ongrid_power":0,"offgrid_power":144,"total_pv_energy":0,"total_grid_output_energy":0,"total_grid_input_energy":0,"total_load_energy":0}"#,
        .battery: #"{"id":0,"soc":43,"charg_flag":true,"dischrg_flag":true,"bat_temp":17.0,"bat_capacity":2211.0,"rated_capacity":5120.0}"#,
        .mode: #"{"id":0,"mode":"Manual","ongrid_power":0,"offgrid_power":144,"bat_soc":43}"#,
        .wifi: #"{"id":0,"wifi_mac":"02005e10a7f3","ssid":"home-2.4","rssi":-40,"sta_ip":"192.168.0.46"}"#,
        .device: #"{"device":"VenusE 3.0","ver":148,"ble_mac":"02005e3c0e89","wifi_mac":"02005e10a7f3","wifi_name":"home-2.4","ip":"192.168.0.46"}"#,
    ]

    private static func parsing() {
        print("parsing")
        guard let r = reading(unplugged) else { check("fw 148 reading parses", false); return }
        check("state of charge", r.soc == 43, r.soc)
        check("remaining Wh from Bat.GetStatus", r.remainingWh == 2211, r.remainingWh)
        check("rated Wh", r.ratedWh == 5120, r.ratedWh)
        check("0 W grid is a number, not a boolean", r.gridW == 0, r.gridW)
        check("BACKUP load", r.backupW == 144, r.backupW)
        check("no bat_power → energy balance", r.batteryW == 144 && r.batteryEstimated, r.batteryW)
        check("discharging", r.flow == .discharging, r.flow)
        check("mode", r.mode == "Manual", r.mode)
        check("device and firmware", r.device == "VenusE 3.0" && r.firmware == 148, r.firmware)
        check("identity is the Bluetooth MAC", r.bleMac == "02005e3c0e89", r.bleMac)
        check("Wi-Fi", r.ssid == "home-2.4" && r.rssi == -40, r.rssi)
        check("grid state not inferred yet", r.grid == .unknown, r.grid)

        // A later poll without Wi-Fi and device keeps what the last one learned.
        var later = unplugged
        later[.wifi] = nil
        later[.device] = nil
        later[.status] = #"{"bat_soc":42,"ongrid_power":0,"offgrid_power":150}"#
        let next = reading(later, previous: r)
        check("rarely asked fields carry over", next?.rssi == -40 && next?.firmware == 148, next?.rssi)
        check("fresh fields replace old ones", next?.soc == 42 && next?.backupW == 150, next?.soc)

        // A Bat.GetStatus that timed out leaves only ES.GetStatus.
        let bare = reading([.status: #"{"bat_soc":43,"bat_cap":5120,"ongrid_power":0,"offgrid_power":0}"#])
        check("ES.GetStatus alone is a reading", bare?.soc == 43 && bare?.remainingWh == nil, bare?.soc)
        check("no load, no grid → idle", bare?.flow == .idle, bare?.flow)

        check("no state of charge → no reading",
              reading([.status: #"{"ongrid_power":0}"#]) == nil)
    }

    private static func quirks() {
        print("firmware quirks")
        let charging = reading([.status: #"{"bat_soc":78,"bat_cap":5120,"ongrid_power":-1250,"offgrid_power":60}"#])
        check("grid import charges the battery", charging?.batteryW == -1190 && charging?.flow == .charging,
              charging?.batteryW)

        let direct = reading([.status: #"{"bat_soc":60,"bat_power":-800,"ongrid_power":-860,"offgrid_power":60}"#])
        check("bat_power wins when reported (fw 150+)",
              direct?.batteryW == -800 && direct?.batteryEstimated == false, direct?.batteryW)

        let unsigned = reading([.status: #"{"bat_soc":50,"ongrid_power":64286,"offgrid_power":0}"#])
        check("u16 negative power", unsigned?.gridW == -1250, unsigned?.gridW)

        let pv = reading([.status: #"{"bat_soc":50,"pv_power":300,"ongrid_power":0,"offgrid_power":100}"#])
        check("PV covers part of the load", pv?.batteryW == -200, pv?.batteryW)

        check("integer mode 4 is UPS", StationReading.modeName(4) == "UPS")
        check("unknown integer mode is named", StationReading.modeName(7) == "Mode 7")
        check("boolean is not a number", StationReading.number(true) == nil)

        let scaled = reading([.status: #"{"bat_soc":43,"bat_cap":5120}"#,
                              .battery: #"{"soc":43,"bat_temp":170,"bat_capacity":22110,"rated_capacity":5120}"#])
        check("bat_capacity ×10 is rescaled", scaled?.remainingWh == 2211, scaled?.remainingWh)
        check("temperature ×10 is rescaled", scaled?.batteryTempC == 17, scaled?.batteryTempC)

        check("threshold: 15 W is idle", Flow(batteryW: 15) == .idle)
        check("threshold: 16 W discharges", Flow(batteryW: 16) == .discharging)
        check("threshold: −16 W charges", Flow(batteryW: -16) == .charging)
    }

    private static func estimates() {
        print("estimates")
        let r = reading(unplugged)
        // (2211 − 12 % of 5120) / 144 W = 11.09 h
        let left = r?.hoursLeft(cutoffPercent: 12) ?? -1
        check("time left to the cutoff", abs(left - 11.088) < 0.01, left)
        check("time left reads well", Format.hours(left) == "≈ 11 h 10 min", Format.hours(left))
        check("below the cutoff → 0", r?.hoursLeft(cutoffPercent: 50) == 0, r?.hoursLeft(cutoffPercent: 50))
        check("no time to full while discharging", r?.hoursToFull() == nil)

        let charging = reading([.status: #"{"bat_soc":78,"bat_cap":5120,"ongrid_power":-1250,"offgrid_power":60}"#,
                                .battery: #"{"soc":78,"bat_capacity":3994,"rated_capacity":5120}"#])
        let full = charging?.hoursToFull() ?? -1
        check("time to full", abs(full - 0.946) < 0.01, full)
        check("under an hour reads in minutes", Format.hours(full) == "≈ 57 min", Format.hours(full))
        check("days past 48 h", Format.hours(50) == "≈ 2 days", Format.hours(50))
        check("kilowatts past 1000 W", Format.watts(1190) == "1.19 kW", Format.watts(1190))
    }

    private static func states() {
        print("states")
        let now = Date()
        check("no address → searching", PowerSnapshot().state == .searching)
        check("discovery found nothing → not found",
              PowerSnapshot(host: "", failure: .noReply, failures: 1).state == .notFound)
        check("refused send → blocked",
              PowerSnapshot(host: "192.168.0.46", failure: .blocked("x"), failures: 1).state == .blocked)
        check("address, no answer yet → connecting",
              PowerSnapshot(host: "192.168.0.46").state == .connecting)
        check("two misses are still connecting",
              PowerSnapshot(host: "192.168.0.46", failure: .noReply, failures: 2).state == .connecting)

        for name in PowerSnapshot.demoStates {
            let s = PowerSnapshot.demo(name, at: now)
            let expected: PowerState = [
                "discharging": .discharging, "charging": .charging, "idle": .idle, "low": .discharging,
                "offline": .offline, "blocked": .blocked, "searching": .searching,
            ][name]!
            check("demo \(name) → \(expected)", s.state == expected, s.state)
        }
        check("offline keeps the last reading", PowerSnapshot.demo("offline", at: now).reading?.soc == 43)
        check("low at 14 %", PowerSnapshot.demo("low", at: now).isLow)
        check("not low at 43 %", !PowerSnapshot.demo("discharging", at: now).isLow)
        check("offline is never low", !PowerSnapshot.demo("offline", at: now).isLow)
        check("every problem state has a hint",
              ["offline", "blocked"].allSatisfy { PowerSnapshot.demo($0, at: now).hint != nil }
              && PowerSnapshot(host: "", failures: 1).hint != nil)
    }

    private static func addresses() {
        print("addresses")
        let (host, port) = StationService.split(" 192.168.0.46:30001\n")
        check("ip:port, trimmed", host == "192.168.0.46" && port == 30001, "\(host):\(port)")
        let (bare, standard) = StationService.split("192.168.0.46")
        check("port defaults to 30000", bare == "192.168.0.46" && standard == 30000, standard)
        check("empty means discover", StationService.split("").0.isEmpty)
    }

    // MARK: - History

    private static func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_760_000_000 + seconds) }

    private static func history() {
        print("history")
        let sample = HistorySample(time: at(0), soc: 43, wh: nil, batteryW: 144, backupW: nil, gridW: 0)
        check("CSV keeps empty fields empty", sample.line == "1760000000,43,,144,,0", sample.line)
        check("CSV round trip", HistorySample(line: Substring(sample.line)) == sample)
        check("a torn line is no sample", HistorySample(line: "17600000") == nil)

        // On disk: a torn line, a reading out of order and one past retention
        // are dropped on load, and the file is rewritten without them.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("home-power-selftest-\(getpid())")
        let file = dir.appendingPathComponent("history.csv")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = at(40 * 86_400)
        let old = HistorySample(time: at(0), soc: 50)
        let a = HistorySample(time: now.addingTimeInterval(-90), soc: 44, wh: 2250, batteryW: 140)
        let b = HistorySample(time: now.addingTimeInterval(-60), soc: 44, wh: 2245, batteryW: 141)
        try? ([old.line, a.line, b.line, a.line, "1760"].joined(separator: "\n") + "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let loaded = PowerHistory(fileURL: file, now: now)
        check("load keeps good, ordered, recent readings", loaded.samples == [a, b], loaded.samples.count)
        let rewritten = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check("file rewritten without the dropped lines", rewritten == a.line + "\n" + b.line + "\n")
        loaded.record(HistorySample(time: now, soc: 44, wh: 2240, batteryW: 142))
        loaded.record(a)
        let appended = (try? String(contentsOf: file, encoding: .utf8))?.split(separator: "\n").count ?? 0
        check("record appends, ignores the past", loaded.samples.count == 3 && appended == 3, appended)
        try? FileManager.default.removeItem(at: dir)

        // Energy.
        let (out, into) = HistorySeries.energy(from: 100, to: -100, over: 3600)
        check("a zero crossing splits the energy", abs(out - 25) < 1e-9 && abs(into - 25) < 1e-9, (out, into))

        let steady = (0...120).map { HistorySample(time: at(Double($0) * 30), soc: 50, wh: 2560, batteryW: 144) }
        let measured = HistorySeries.totals(HistorySeries.segments(steady, ratedWh: 5120), from: at(0).timeIntervalSince1970,
                                            to: at(3600).timeIntervalSince1970)
        check("an hour at 144 W is 144 Wh", abs(measured.discharged - 144) < 1e-6 && measured.approximated == 0,
              measured.discharged)

        let short = HistorySeries.segments([HistorySample(time: at(0), soc: 50, batteryW: 100),
                                            HistorySample(time: at(600), soc: 49, batteryW: 300)], ratedWh: 5120)
        check("a 10-minute gap is filled straight across", short.first?.fill == .linear && short.first?.w1 == 300)

        let long = HistorySeries.segments([HistorySample(time: at(0), soc: 59, wh: 3000, batteryW: 900),
                                           HistorySample(time: at(3 * 3600), soc: 50, wh: 2550, batteryW: 20)], ratedWh: 5120)
        check("a 3-hour gap holds the energy average", long.first?.fill == .energy && long.first?.w0 == 150, long.first?.w0)
        let longTotals = HistorySeries.totals(long, from: at(0).timeIntervalSince1970, to: at(3 * 3600).timeIntervalSince1970)
        check("…and accounts for exactly the energy lost", abs(longTotals.discharged - 450) < 1e-6
              && longTotals.approxDischarged == longTotals.discharged, longTotals.discharged)

        let charged = HistorySeries.segments([HistorySample(time: at(0), soc: 39, wh: 2000),
                                              HistorySample(time: at(7200), soc: 59, wh: 3000)], ratedWh: 5120)
        check("a gap the battery charged through is charging", charged.first?.w0 == -500, charged.first?.w0)

        let noWh = HistorySeries.segments([HistorySample(time: at(0), soc: 50), HistorySample(time: at(7200), soc: 40)],
                                          ratedWh: 5120)
        check("without Wh the charge × capacity stands in", noWh.first?.w0 == 256, noWh.first?.w0)

        // Across midnight: the energy splits by the hours on each side.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = calendar.startOfDay(for: at(86_400 * 3))
        let night = [HistorySample(time: midnight.addingTimeInterval(-3600), soc: 50, wh: 2600),
                     HistorySample(time: midnight.addingTimeInterval(3600), soc: 46, wh: 2400)]
        let overnight = HistorySeries.build(night, range: .week, now: midnight.addingTimeInterval(7200),
                                            ratedWh: 5120, calendar: calendar)
        let split = overnight.days.map { Int($0.totals.discharged.rounded()) }
        check("a gap over midnight is shared by both days", split == [100, 100], split)

        // Buckets: nothing before the first reading or after the last.
        let middle = (0..<60).map { HistorySample(time: at(7200 + Double($0) * 30), soc: 50, wh: 2560, batteryW: 100) }
        let six = HistorySeries.build(middle, range: .sixHours, now: at(6 * 3600), ratedWh: 5120)
        let firstBucket = six.buckets.first?.start ?? .distantPast
        let lastBucket = six.buckets.last?.end ?? .distantFuture
        check("no bucket before the first reading", firstBucket <= at(7200) && firstBucket > at(7200 - 120))
        check("no bucket after the last reading", lastBucket >= middle.last!.time && lastBucket < middle.last!.time.addingTimeInterval(240))

        var withGap = middle
        withGap += (0..<60).map { HistorySample(time: at(3 * 3600 + 7200 + Double($0) * 30), soc: 40, wh: 2050, batteryW: 100) }
        let gapped = HistorySeries.build(withGap, range: .sixHours, now: at(6 * 3600), ratedWh: 5120)
        let inGap = gapped.buckets.filter { $0.start >= at(9000) && $0.end <= at(3 * 3600 + 7200) }
        check("buckets inside a gap are approximated", !inGap.isEmpty && inGap.allSatisfy(\.approximated), inGap.count)
        check("…and the gap is listed as filled from energy", gapped.gaps.map(\.fill) == [.energy])

        // Chart parts.
        func bucket(_ id: Int, _ w: Double, approx: Bool = false) -> HistorySeries.Bucket {
            HistorySeries.Bucket(id: id, start: at(Double(id) * 300), end: at(Double(id + 1) * 300), soc: 50,
                                 batteryW: w, approximated: approx)
        }
        let flip = ChartParts.power([bucket(0, 300), bucket(1, 280), bucket(2, -900), bucket(3, -950)])
        check("a sign change starts a part at zero",
              flip.count == 2 && flip[0].points.last?.value == 0 && flip[1].points.first?.value == 0
              && flip[0].sign == 1 && flip[1].sign == -1, flip.map(\.sign))
        let dashed = ChartParts.power([bucket(0, 300), bucket(1, 280, approx: true)])
        check("a fill change shares the joint", dashed.count == 2 && dashed[1].points.first?.date == dashed[0].points.last?.date
              && dashed[1].approximated)
        let broken = ChartParts.charge([bucket(0, 0), bucket(1, 0), bucket(5, 0)])
        check("missing buckets break the line", broken.count == 2 && broken[1].points.count == 1, broken.count)

        // The demo week: its three gaps, and energy that adds up.
        let today = calendar.startOfDay(for: Date())
        let demoNow = today.addingTimeInterval(23 * 3600)
        let demo = HistorySeries.demoSamples(now: demoNow, calendar: calendar)
        let week = HistorySeries.build(demo, range: .week, now: demoNow, ratedWh: 5120, calendar: calendar)
        check("demo week has its three gaps", week.gaps.map(\.fill) == [.energy, .linear, .energy], week.gaps.map(\.fill))
        let span = HistorySeries.build(demo, range: .month, now: demoNow, ratedWh: 5120, calendar: calendar)
        let net = span.totals.charged - span.totals.discharged
        let stored = (demo.last!.wh ?? 0) - (demo.first!.wh ?? 0)
        let throughput = span.totals.charged + span.totals.discharged
        check("charged − discharged matches the change in stored energy",
              abs(net - stored) < throughput * 0.02, "net \(Int(net)) vs stored \(Int(stored))")
    }

    // MARK: - Notifications

    private static func notifications() {
        print("notifications")
        check("steps: 89 → 90, 90 → 90, 80 → 80, 1 → 10",
              [89, 90, 80, 1, 100, 0].map(Warnings.step) == [90, 90, 80, 10, 100, 0])

        // A discharge from 95 %, step by step.
        var notified: Int? = nil
        var said: [Int] = []
        func reading(_ soc: Int, discharging: Bool = true) {
            let (notify, keep) = Warnings.due(soc: soc, discharging: discharging, notified: notified)
            notified = keep
            if let notify { said.append(notify) }
        }
        for soc in [95, 94, 91, 90, 89, 81, 80, 79, 61] { reading(soc) }
        check("first run is a baseline, then 90 and 80 once each; a gap over 70 says 70",
              said == [90, 80, 70], said)
        reading(62, discharging: false)
        reading(61)
        check("going 61 → 62 → 61 says nothing more", said == [90, 80, 70], said)
        reading(75, discharging: false)
        check("charging 5 % above re-arms", notified == 80, notified)
        reading(70)
        check("…so 70 is said again", said.last == 70 && said.count == 4, said)
        reading(68, discharging: false)
        reading(60, discharging: false)
        check("a drop while idle moves the mark silently", said.count == 4 && notified == 60, notified)
        reading(48)
        check("a jump over a step notifies once, for where it is", said.last == 50 && said.count == 5, said)
        check("100 % is never a step", Warnings.due(soc: 99, discharging: true, notified: 100).notify == nil)
        check("0 % isn't either", Warnings.due(soc: 0, discharging: true, notified: 10).notify == nil)

        // The text.
        var r = PowerSnapshot.demo().reading!
        r.soc = 90
        r.remainingWh = 4608
        let info = Warnings.content(reading: r, draw: .init(watts: 157, minutes: 60), cutoff: 12)
        check("90 %: plain title", info.title == "Home battery 90%" && info.level == .info, info.title)
        check("90 %: last hour's draw and time left",
              info.body == "Average draw over the last hour: 157 W. About 25 h 30 min left at this rate.", info.body)
        r.soc = 40
        r.remainingWh = 2048
        let warning = Warnings.content(reading: r, draw: .init(watts: 300, minutes: 40), cutoff: 12)
        check("40 %: a warning", warning.level == .warning && warning.title == "Home battery down to 40%", warning.title)
        check("40 %: a short window says so, and the cutoff is named",
              warning.body == "Average draw over the last 40 min: 300 W. About 4 h 50 min left at this rate before it stops at 12%.",
              warning.body)
        check("50 % is still silent", Warnings.level(50) == .info)
        check("20 % is low", Warnings.level(20) == .low)
        r.soc = 20
        r.remainingWh = 1024
        r.batteryW = 144
        let low = Warnings.content(reading: r, draw: nil, cutoff: 12)
        check("no history: the current draw stands in",
              low.title == "Home battery low: 20%" && low.body.hasPrefix("Drawing 144 W now."), low.body)
        r.soc = 12
        r.remainingWh = 614
        let cut = Warnings.content(reading: r, draw: .init(watts: 144, minutes: 60), cutoff: 12)
        check("at the cutoff it says so", cut.body.hasSuffix("It is at its 12% cutoff and will stop discharging."), cut.body)

        // The average draw.
        let hour = (0...120).map { HistorySample(time: at(Double($0) * 30), soc: 50, wh: 2560, batteryW: 157) }
        let steady = HistorySeries.averageDraw(hour, now: at(3600), ratedWh: 5120)
        check("an hour at 157 W averages 157 W",
              abs((steady?.watts ?? 0) - 157) < 1e-6 && steady?.minutes == 60, steady)
        let short = Array(hour.suffix(20))
        check("under 15 min of readings: no average", HistorySeries.averageDraw(short, now: at(3600), ratedWh: 5120) == nil)
        let mixed = (0...120).map { HistorySample(time: at(Double($0) * 30), soc: 50, batteryW: $0 < 60 ? 300 : -100) }
        let net = HistorySeries.averageDraw(mixed, now: at(3600), ratedWh: 5120)?.watts ?? 0
        check("charging inside the hour nets out", abs(net - 100) < 7, net)
    }
}
