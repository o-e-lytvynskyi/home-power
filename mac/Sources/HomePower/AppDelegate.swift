import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let isDemo = CommandLine.arguments.contains("--demo")
    private lazy var preferences = Preferences(persist: !isDemo)
    private let launchAtLogin = LaunchAtLogin()
    private lazy var service = StationService(address: preferences.address, bleMac: preferences.bleMac)
    /// The demo keeps a synthetic history in memory and never touches the file.
    private lazy var history = PowerHistory(fileURL: isDemo ? nil : PowerHistory.defaultURL)
    private var lastRecorded: Date?
    private lazy var warnings = Warnings(defaults: isDemo ? nil : .standard)

    private var snapshot = PowerSnapshot()
    private var statusItem: NSStatusItem?
    private var aboutPanel:    GlassPanel?
    private var settingsPanel: GlassPanel?
    private var historyPanel:  GlassPanel?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The demo is allowed to run alongside the installed copy — otherwise
        // the single-instance guard would kill it on launch.
        guard isDemo || !handOffToRunningInstance() else { return }

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        if isDemo {
            seedDemo()
            return
        }

        preferences.onChange = { [weak self] in self?.reconfigure() }
        service.onChange = { [weak self] snapshot in self?.apply(snapshot) }
        service.onStation = { [weak self] host, bleMac in
            // Remembered so the next launch goes straight to it, and so a
            // station that DHCP moves is recognised at its new address.
            self?.preferences.address = host
            if let bleMac { self?.preferences.bleMac = bleMac }
        }
        warnings.start()
        service.start()
        apply(service.snapshot)
    }

    /// A second launch just focuses the first one and exits.
    private func handOffToRunningInstance() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.local.home-power"
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0 != NSRunningApplication.current
        }
        guard !others.isEmpty else { return false }
        others.first?.activate()
        NSApp.terminate(nil)
        return true
    }

    private func reconfigure() {
        service.configure(address: preferences.address)
        render()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        guard let btn = item.button else { return }
        btn.target = self
        btn.action = #selector(statusItemClicked)
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btn.imagePosition = .imageTrailing
    }

    /// Everything that depends on the snapshot is updated here.
    private func apply(_ snapshot: PowerSnapshot) {
        self.snapshot = snapshot
        // A new good reading goes into the history; a failed poll writes
        // nothing, and the gap it leaves is approximated when drawn.
        if !isDemo, snapshot.failure == nil, let reading = snapshot.reading,
           let at = snapshot.updatedAt, at != lastRecorded {
            lastRecorded = at
            history.record(HistorySample(reading, at: at))
            warnings.check(reading, history: history.samples, cutoff: preferences.cutoff,
                           enabled: preferences.notify, now: at)
        }
        render()
    }

    /// What the menu bar draws. Powers move on every poll; the glyph and the
    /// percentage only when one of these does.
    private struct Face: Equatable {
        let state: PowerState
        let soc: Int?
        let low: Bool
    }
    private var face: Face?

    private func render() {
        guard let btn = statusItem?.button else { return }
        let next = Face(state: snapshot.state, soc: snapshot.reading?.soc, low: snapshot.isLow)
        if next != face {
            face = next
            btn.image = StatusIcon.image(for: snapshot)
            btn.attributedTitle = StatusIcon.title(for: snapshot)
        }
        btn.toolTip = tooltip()
    }

    private func tooltip() -> String {
        var lines: [String] = []
        if snapshot.state.hasReading, let r = snapshot.reading {
            lines.append("Home battery \(r.soc)% · \(snapshot.title)")
            if let energy = PowerView.energy(r) { lines.append(energy) }
            if let estimate = PowerView.estimate(r, cutoff: preferences.cutoff) { lines.append(estimate) }
            if let w = r.backupW { lines.append("BACKUP socket \(Format.watts(w))") }
            if let at = snapshot.updatedAt { lines.append("Updated \(Format.ago(at))") }
        } else {
            lines.append(snapshot.title)
            if let hint = snapshot.hint { lines.append(hint) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Menu

    @objc private func statusItemClicked() {
        guard let btn = statusItem?.button, let event = NSApp.currentEvent else { return }
        render()
        if !isDemo { warnings.refresh() }
        // Left click opens the same menu as right, so the icon is never a dead pixel.
        NSMenu.popUpContextMenu(buildMenu(), with: event, for: btn)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Otherwise AppKit re-enables any item with a target, and Refresh
        // would stay clickable while a poll is running.
        menu.autoenablesItems = false

        let header = NSMenuItem()
        let view = NSHostingView(rootView: PowerView(snapshot: snapshot, cutoff: preferences.cutoff, now: Date()))
        view.frame.size = view.fittingSize
        header.view = view
        menu.addItem(header)

        menu.addItem(.separator())
        menu.addItem(action("Refresh", #selector(refreshNow), key: "r"))
        if snapshot.state == .blocked {
            menu.addItem(action("Open Local Network Settings…", #selector(openLocalNetworkSettings)))
        }

        menu.addItem(action("History…", #selector(showHistory), key: "y"))
        if !isDemo, preferences.notify, warnings.denied {
            menu.addItem(action("Turn On Notifications…", #selector(openNotificationSettings)))
        }

        menu.addItem(.separator())
        menu.addItem(action("Settings…", #selector(showSettings), key: ","))
        menu.addItem(action("About \(AppInfo.name)", #selector(showAbout)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        guard !isDemo else { return }
        service.refreshNow()
    }

    @objc private func openNotificationSettings() {
        Warnings.openSettings()
    }

    @objc private func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Panels

    /// Panels are rebuilt on each open: they are static cards, cheaper than
    /// keeping a hosting view alive for the lifetime of the app.
    @objc private func showAbout() {
        aboutPanel?.close()
        let panel = GlassPanel {
            AboutView(snapshot: self.snapshot,
                      onClose: { [weak self] in self?.aboutPanel?.close() })
        }
        aboutPanel = panel
        present(panel)
    }

    @objc private func showHistory() {
        historyPanel?.close()
        let model = HistoryModel(history: history, ratedWh: { [weak self] in
            self?.snapshot.reading?.ratedWh ?? 5120
        })
        let panel = GlassPanel {
            HistoryView(model: model, onClose: { [weak self] in self?.historyPanel?.close() })
        }
        // The model follows new readings only while the window is open.
        panel.onClosed = { [weak self] in self?.historyPanel = nil }
        historyPanel = panel
        present(panel)
    }

    @objc private func showSettings() {
        settingsPanel?.close()
        launchAtLogin.refresh()
        let panel = GlassPanel {
            SettingsView(preferences: self.preferences,
                         launchAtLogin: self.launchAtLogin,
                         discover: { [weak self] done in
                             guard let self, !self.isDemo else { done([]); return }
                             self.service.discover(completion: done)
                         },
                         onClose: { [weak self] in self?.settingsPanel?.close() })
        }
        settingsPanel = panel
        present(panel)
    }

    private func present(_ panel: GlassPanel) {
        // The demo is for screenshots taken while the owner keeps typing
        // elsewhere: activating would steal their keystrokes into the panel.
        guard !isDemo else { panel.orderFrontRegardless(); return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Demo

    /// `--demo [state=…] [menu|settings|about|history]`: a synthetic reading
    /// and history, no network, and the chosen surface opened for a screenshot.
    private func seedDemo() {
        let args = CommandLine.arguments
        let state = args.first { $0.hasPrefix("state=") }.map { String($0.dropFirst(6)) } ?? "discharging"
        apply(PowerSnapshot.demo(state))
        history.seed(HistorySeries.demoSamples(now: Date()))

        if args.contains("about") {
            showAbout()
        } else if args.contains("history") {
            showHistory()
        } else if args.contains("menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let btn = self.statusItem?.button else { return }
                let menu = self.buildMenu()
                menu.popUp(positioning: menu.items.first, at: NSPoint(x: 0, y: btn.bounds.height + 4), in: btn)
            }
        } else {
            showSettings()
        }
    }
}
