import AppKit
import UserNotifications

/// A notification each time the charge falls past another tenth while the
/// battery discharges: 90, 80 … 10. Each says the average draw over the last
/// hour and how long the station lasts at it. Below 50 % they turn serious:
/// a sound, a warning title and an orange or red battery picture; from 50 %
/// up they arrive silently.
///
/// The last notified step is kept across launches, so a restart doesn't
/// repeat it. Charging back 5 % above it re-arms the steps. A drop over
/// several steps (the Mac was asleep) notifies once, for where it is now.
final class Warnings: NSObject, UNUserNotificationCenterDelegate {

    /// Under this the notifications are warnings.
    static let seriousBelow = 50
    /// Under this they say "low".
    static let lowAt = 20
    private static let key = "notifiedStep"

    private let defaults: UserDefaults?

    /// Pass nil to keep nothing (the demo, the debug flags).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        super.init()
    }

    /// The owner said no to notifications: the menu offers the way back.
    /// Read asynchronously, so a change shows from the next menu open.
    private(set) var denied = false

    func start(then: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().delegate = self
        Self.authorize { granted in
            self.refresh()
            then?(granted)
        }
    }

    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { self.denied = denied }
        }
    }

    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "dev.local.home-power"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks once; the answer comes back on a background queue.
    static func authorize(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in done(granted) }
    }

    // MARK: - When

    /// The tenth a charge has come down to: 89 → 90, 90 → 90, 80 → 80.
    static func step(_ soc: Int) -> Int {
        min(max(Int((Double(soc) / 10).rounded(.up)) * 10, 0), 100)
    }

    /// The step to notify about now, if any, and the step to remember.
    static func due(soc: Int, discharging: Bool, notified: Int?) -> (notify: Int?, keep: Int) {
        let now = step(soc)
        // First run: the current step is the baseline, nothing to say yet.
        guard let notified else { return (nil, now) }
        // Charged a good way back up: the steps below re-arm.
        if soc >= notified + 5 { return (nil, now) }
        guard now < notified else { return (nil, notified) }
        // A drop while idle (the BMS recalibrating) moves the mark silently.
        guard discharging, (10...90).contains(now) else { return (nil, now) }
        return (now, now)
    }

    /// Called with every good reading. The step is tracked even with
    /// notifications off, so turning them on doesn't bring a stale one.
    func check(_ reading: StationReading, history: [HistorySample], cutoff: Int, enabled: Bool, now: Date = Date()) {
        let notified = defaults?.object(forKey: Self.key) as? Int
        let (notify, keep) = Self.due(soc: reading.soc, discharging: reading.flow == .discharging, notified: notified)
        if keep != notified { defaults?.set(keep, forKey: Self.key) }
        guard enabled, notify != nil else { return }
        let draw = HistorySeries.averageDraw(history, now: now, ratedWh: reading.ratedWh ?? 5120)
        post(Self.content(reading: reading, draw: draw, cutoff: cutoff))
        Log.station.notice("notified at \(reading.soc)%")
    }

    // MARK: - What

    enum Level: Equatable {
        case info, warning, low
    }

    struct Content: Equatable {
        let level: Level
        let title: String
        let body: String
        let soc: Int
    }

    static func level(_ soc: Int) -> Level {
        soc <= lowAt ? .low : (soc < seriousBelow ? .warning : .info)
    }

    /// "Home battery 90%" — "Average draw over the last hour: 157 W. About
    /// 26 h left at this rate." With less than 15 min of history the current
    /// draw stands in.
    static func content(reading: StationReading, draw: HistorySeries.Draw?, cutoff: Int) -> Content {
        let soc = reading.soc
        let level = level(soc)
        let title: String
        switch level {
        case .info:    title = "Home battery \(soc)%"
        case .warning: title = "Home battery down to \(soc)%"
        case .low:     title = "Home battery low: \(soc)%"
        }

        var sentences: [String] = []
        let watts: Double?
        if let draw, draw.watts > 0 {
            watts = draw.watts
            let window = draw.minutes >= 55 ? "the last hour" : "the last \(draw.minutes) min"
            sentences.append("Average draw over \(window): \(Format.watts(Int(draw.watts.rounded()))).")
        } else if let w = reading.batteryW, w > Flow.threshold {
            watts = Double(w)
            sentences.append("Drawing \(Format.watts(w)) now.")
        } else {
            watts = nil
        }

        let rated = reading.ratedWh ?? 5120
        let remaining = reading.remainingWh ?? rated * Double(soc) / 100
        if let watts {
            let usable = remaining - rated * Double(cutoff) / 100
            if usable > 0 {
                let left = Format.hours(usable / watts).replacingOccurrences(of: "≈ ", with: "")
                sentences.append(level == .info
                    ? "About \(left) left at this rate."
                    : "About \(left) left at this rate before it stops at \(cutoff)%.")
            } else {
                sentences.append("It is at its \(cutoff)% cutoff and will stop discharging.")
            }
        }
        return Content(level: level, title: title, body: sentences.joined(separator: " "), soc: soc)
    }

    func post(_ content: Content) {
        let note = UNMutableNotificationContent()
        note.title = content.title
        note.body = content.body
        note.threadIdentifier = "home-power.charge"
        // Silent while there is plenty left; the serious ones make a sound.
        note.sound = content.level == .info ? nil : .default
        if let attachment = Self.picture(content) { note.attachments = [attachment] }
        // One identifier: a newer step replaces the older in Notification Centre.
        deliver(UNNotificationRequest(identifier: "home-power.charge", content: note, trigger: nil))
    }

    /// The battery at that charge, green, orange or red, shown at the side of
    /// the banner — the "other icon" of the serious ones. The system moves the
    /// file into its own store, so each post writes a new one.
    static func picture(_ content: Content) -> UNNotificationAttachment? {
        let size = NSSize(width: 256, height: 256)
        let colour: NSColor
        switch content.level {
        case .info:    colour = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .warning: colour = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .low:     colour = NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        }
        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: 28, y: 78, width: 184, height: 100)
            let outline = NSBezierPath(roundedRect: body, xRadius: 22, yRadius: 22)
            outline.lineWidth = 12
            NSColor(white: 0.45, alpha: 1).setStroke()
            outline.stroke()
            NSColor(white: 0.45, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 10, y: 108, width: 16, height: 40),
                         xRadius: 6, yRadius: 6).fill()
            let inner = body.insetBy(dx: 18, dy: 18)
            let width = max(inner.width * CGFloat(content.soc) / 100, 10)
            colour.setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height),
                         xRadius: 8, yRadius: 8).fill()
            if content.level != .info {
                // An exclamation mark under the battery: the warning reads by shape too.
                let mark = NSAttributedString(string: "!", attributes: [
                    .font: NSFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: colour,
                ])
                mark.draw(at: NSPoint(x: size.width / 2 - mark.size().width / 2, y: 4))
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("home-power-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "battery", url: url)
        } catch {
            return nil
        }
    }

    // MARK: - Delivery

    /// Held while the screen is locked, keyed by identifier, so a newer one
    /// replaces an older one as it would in Notification Centre. Main thread.
    private var held: [String: UNNotificationRequest] = [:]
    private var unlockWatch: NSObjectProtocol?

    /// A banner posted on the lock screen is shown there for its few seconds
    /// and goes to Notification Centre unseen. So while the screen is locked,
    /// wait for the unlock.
    private func deliver(_ request: UNNotificationRequest) {
        guard Self.screenIsLocked else { return UNUserNotificationCenter.current().add(request) }
        held[request.identifier] = request
        guard unlockWatch == nil else { return }
        unlockWatch = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            // A moment for the desktop to come up before the banner.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.release() }
        }
    }

    /// On the unlock notification itself: the session flag can lag behind it.
    private func release() {
        if let unlockWatch { DistributedNotificationCenter.default().removeObserver(unlockWatch) }
        unlockWatch = nil
        let requests = held.values
        held = [:]
        requests.forEach { UNUserNotificationCenter.current().add($0) }
    }

    static var screenIsLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // A menu-bar app counts as frontmost often enough that banners would
    // otherwise be swallowed.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

extension HistorySeries {
    /// Average battery power over a recent window.
    struct Draw: Equatable {
        /// Positive while discharging, net of any charging in the window.
        let watts: Double
        /// How much of the window had readings, in minutes.
        let minutes: Int
    }

    /// The average draw over the last hour, net of charging, from the same
    /// model the History window uses — gaps included. Nil with less than
    /// 15 min of readings in the hour.
    static func averageDraw(_ samples: [HistorySample], now: Date, ratedWh: Double) -> Draw? {
        let from = now.addingTimeInterval(-3600).timeIntervalSince1970
        let first = samples.firstIndex { $0.time.timeIntervalSince1970 >= from } ?? samples.count
        let recent = Array(samples[max(first - 1, 0)...])
        let t = totals(segments(recent, ratedWh: ratedWh), from: from, to: now.timeIntervalSince1970)
        guard t.covered >= 15 * 60 else { return nil }
        return Draw(watts: (t.discharged - t.charged) / (t.covered / 3600), minutes: Int((t.covered / 60).rounded()))
    }
}
