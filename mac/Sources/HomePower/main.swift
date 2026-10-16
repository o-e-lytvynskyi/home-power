import AppKit
import SwiftUI

// Debug flags are parsed before `NSApplication.shared` so they never spin up a
// UI. `key=value` tokens after a flag override its defaults.
private let args = CommandLine.arguments

private func value(_ key: String) -> String? {
    args.first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
}

private func positional(after flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag) else { return nil }
    return args[(idx + 1)...].first { !$0.contains("=") && !$0.hasPrefix("--") }
}

/// The address a flag talks to: `host=` (with an optional `:port`), else the
/// installed app's setting, else the station seen on 2026-10-14.
private func address() -> String {
    value("host") ?? UserDefaults(suiteName: "dev.local.home-power")?.string(forKey: Preferences.Keys.address)
        ?? "192.168.0.46"
}

/// The menu's text for a snapshot, line by line — what `--probe` and
/// `--selftest file.json` print, so the wording is checked without a screen.
private func describe(_ s: PowerSnapshot, cutoff: Int = Preferences.defaultCutoff) {
    print("state: \(s.state)  |  \(s.title)")
    if let hint = s.hint { print("hint:  \(hint)") }
    guard let r = s.reading else { return }
    print("  \(r.soc)%" + (PowerView.energy(r).map { "  ·  \($0)" } ?? "")
          + (PowerView.estimate(r, cutoff: cutoff).map { "  ·  \($0)" } ?? ""))
    for row in PowerView.rows(r, cutoff: cutoff) {
        print("  \(row.label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(row.value)")
    }
}

// `--selftest [fixture.json]` — without a file, runs the built-in cases that
// cover every state, including ones the live station can't be put into on
// demand. With a file of `{"ES.GetStatus": {…result…}, …}`, parses it and
// prints the menu's text.
if args.contains("--selftest") {
    if let path = positional(after: "--selftest") {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            print("can't read \(path) as {method: result}"); exit(1)
        }
        var results: [StationReading.Method: [String: Any]] = [:]
        for (key, result) in json {
            guard let method = StationReading.Method(rawValue: key) else { print("unknown method \(key)"); exit(1) }
            results[method] = result
        }
        guard let reading = StationReading.parse(results) else { print("parse failed: no state of charge"); exit(1) }
        describe(PowerSnapshot(reading: reading, updatedAt: Date(), host: "fixture"))
        exit(0)
    }
    exit(SelfTest.run() ? 0 : 1)
}

// `--probe [host=ip[:port]]` — one full poll of the live station, every
// method with its time, then the menu's text. Runs from the terminal under
// the terminal's Local Network permission, not the app's.
if args.contains("--probe") {
    let (host, port) = StationService.split(address())
    let link = MarstekLink()
    var results: [StationReading.Method: [String: Any]] = [:]
    print("station \(host):\(port)")
    for method in StationReading.Method.allCases {
        let started = Date()
        let params: [String: Any] = method == .device ? ["ble_mac": "0"] : ["id": 0]
        let outcome = link.call(method.rawValue, params: params, host: host, port: port)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        switch outcome {
        case .success(let result):
            results[method] = result
            let keys = result.keys.sorted().filter { $0 != "id" }
                .map { "\($0)=\(result[$0].map { "\($0)" } ?? "")" }.joined(separator: " ")
            print("  \(method.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(ms) ms  \(keys)")
        case .failure(let failure):
            print("  \(method.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(ms) ms  FAILED: \(failure.text)")
        }
    }
    guard let reading = StationReading.parse(results) else { print("no reading"); exit(1) }
    print("")
    describe(PowerSnapshot(reading: reading, updatedAt: Date(), host: host),
             cutoff: value("cutoff").flatMap(Int.init) ?? Preferences.defaultCutoff)
    exit(0)
}

// `--discover` — every station that answers a broadcast on the local networks.
if args.contains("--discover") {
    let found = MarstekLink().discover(timeout: value("seconds").flatMap(Double.init) ?? 8)
    if found.isEmpty { print("no station answered on UDP \(MarstekLink.defaultPort)"); exit(1) }
    for station in found { print("\(station.ip)  \(station.device)  ble \(station.bleMac)") }
    exit(0)
}

// `--history [range=6h|24h|7d|30d] [demo] [file=…]` — what the History
// window shows for a period, as text: totals, every approximated gap with the
// way it was filled, and the day table. Reads the installed app's file.
if args.contains("--history") {
    let range = value("range").flatMap(HistoryRange.init(flag:)) ?? .day
    let now = Date()
    let samples: [HistorySample]
    let source: String
    if args.contains("demo") {
        samples = HistorySeries.demoSamples(now: now)
        source = "demo"
    } else {
        let url = value("file").map { URL(fileURLWithPath: $0) } ?? PowerHistory.defaultURL
        samples = PowerHistory(fileURL: url, now: now).samples
        source = url.path
    }
    guard let first = samples.first, let last = samples.last else { print("no history in \(source)"); exit(1) }
    let stamp = DateFormatter()
    stamp.dateFormat = "d MMM HH:mm"
    print("\(source): \(samples.count) readings, \(stamp.string(from: first.time)) → \(stamp.string(from: last.time))")

    let series = HistorySeries.build(samples, range: range, now: now, ratedWh: 5120)
    let total = Int(series.end.timeIntervalSince(series.start) / range.bucket)
    print("period \(range.rawValue), \(Format.duration(range.bucket)) buckets: \(series.buckets.count) of \(total) have data, "
          + "\(series.buckets.filter(\.approximated).count) approximated, \(series.readings) readings")
    let t = series.totals
    print("charged \(Format.energy(t.charged)) (\(Format.energy(t.approxCharged)) approximated) · "
          + "discharged \(Format.energy(t.discharged)) (\(Format.energy(t.approxDischarged)) approximated) · "
          + "gaps \(Format.percent(t.approxShare)) of the time with data")
    if !series.gaps.isEmpty {
        print("gaps:")
        for gap in series.gaps {
            let fill = gap.fill == .energy ? "from stored energy" : "straight across"
            print("  \(stamp.string(from: gap.start)) – \(Format.clock.string(from: gap.end))  "
                  + "\(Format.duration(gap.end.timeIntervalSince(gap.start)).padding(toLength: 12, withPad: " ", startingAt: 0)) \(fill)")
        }
    }
    print("days:")
    for day in series.days.reversed() {
        let d = day.totals
        print("  \(Format.weekdayDay.string(from: day.day).padding(toLength: 12, withPad: " ", startingAt: 0)) "
              + "charged \(Format.energy(d.charged).padding(toLength: 10, withPad: " ", startingAt: 0)) "
              + "discharged \(Format.energy(d.discharged).padding(toLength: 10, withPad: " ", startingAt: 0)) "
              + "approximated \(d.approximated > 0 ? Format.percent(d.approxShare) : "—")")
    }
    exit(0)
}

// `--render [dir]` — the menu header and the status icon for every demo
// state, light and dark, as PNGs: the layout is checked without Screen
// Recording.
if args.contains("--render") {
    let dir = positional(after: "--render")
        ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("home-power-render")
    exit(Render.all(into: dir) ? 0 : 1)
}

// `--notify [soc=40] [draw=157] [cutoff=12]` — posts the notification the app
// would post at that charge and draw, and prints it. Notifications need the
// app's bundle and its permission, so run it through LaunchServices:
// `open -n -W --stdout /tmp/out.txt /Applications/HomePower.app --args --notify soc=40`
if args.contains("--notify") {
    let soc = value("soc").flatMap(Int.init) ?? 40
    let draw = value("draw").flatMap(Double.init) ?? 157
    let cutoff = value("cutoff").flatMap(Int.init) ?? Preferences.defaultCutoff
    var reading = PowerSnapshot.demo().reading!
    reading.soc = soc
    reading.remainingWh = 5120 * Double(soc) / 100
    reading.batteryW = Int(draw)
    let content = Warnings.content(reading: reading, draw: .init(watts: draw, minutes: 60), cutoff: cutoff)
    print("\(content.level): \(content.title)\n\(content.body)")
    fflush(stdout)
    let warnings = Warnings(defaults: nil)
    warnings.start { granted in
        print("notifications allowed: \(granted ? "yes" : "no"); screen locked: \(Warnings.screenIsLocked ? "yes" : "no")")
        fflush(stdout)
        DispatchQueue.main.async { warnings.post(content) }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    exit(0)
}

// `--login-item [on|off]` reports, and optionally changes, the login item
// registration without launching the UI.
if args.contains("--login-item") {
    let launch = LaunchAtLogin()
    switch positional(after: "--login-item") {
    case "on":  launch.apply(true)
    case "off": launch.apply(false)
    case .some(let other): print("usage: --login-item [on|off] (got \(other))"); exit(2)
    case nil:   break
    }
    launch.refresh()
    print("launch at login: \(launch.isEnabled ? "enabled" : "disabled")")
    if let err = launch.errorText { print("note: \(err)") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
