import AppKit
import os

/// Debug flags write nothing to the installed app's log.
enum Log {
    static let station: Logger = CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") }
        ? Logger(OSLog.disabled)
        : Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.local.home-power", category: "station")
}

/// Polls the station and turns its replies into a `PowerSnapshot`.
///
/// A poll is ES.GetStatus, Bat.GetStatus and ES.GetMode, about 2 s apart
/// because of the firmware's quiet window; Wi-Fi and the device are asked every
/// `detailEvery` polls. All socket work runs on one serial utility queue.
///
/// Cost profile: one poll every 30 s with timer tolerance, nothing while the
/// Mac sleeps, backoff while the station is silent, and the callback fires only
/// when the snapshot changed.
final class StationService {

    static let interval: TimeInterval = 30
    static let detailEvery = 10
    /// While the station is silent, look for it again this often: DHCP may
    /// have moved it.
    static let rediscoverEvery: TimeInterval = 300

    /// Main thread, only when the snapshot changed.
    var onChange: ((PowerSnapshot) -> Void)?
    /// Main thread: a station was found at a new address, or told us its
    /// Bluetooth MAC — the identity used to find it again.
    var onStation: ((_ host: String, _ bleMac: String?) -> Void)?

    private(set) var snapshot = PowerSnapshot()
    private let link = MarstekLink()
    private let queue = DispatchQueue(label: "dev.local.home-power.link", qos: .utility)
    private var timer: Timer?
    private var inFlight = false
    private var polls = 0
    private var nextAllowed = Date.distantPast
    private var lastDiscovery = Date.distantPast
    private var host: String
    private var port: UInt16
    private var bleMac: String?

    init(address: String, bleMac: String?) {
        (host, port) = Self.split(address)
        self.bleMac = bleMac
        snapshot.host = host
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        observeSleepWake()
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        nextAllowed = .distantPast
        poll()
    }

    /// Point the poller at another address ("ip" or "ip:port"; empty means
    /// discover). The old reading is dropped: it may be another station.
    func configure(address: String) {
        let (host, port) = Self.split(address)
        guard host != self.host || port != self.port else { return }
        self.host = host
        self.port = port
        bleMac = nil
        polls = 0
        lastDiscovery = .distantPast
        publish(PowerSnapshot(host: host))
        refreshNow()
    }

    /// Runs discovery for Settings. Queued behind any poll in progress.
    func discover(completion: @escaping ([MarstekLink.Station]) -> Void) {
        queue.async { [link] in
            let found = link.discover()
            DispatchQueue.main.async { completion(found) }
        }
    }

    private var sleepObservers: [NSObjectProtocol] = []

    private func observeSleepWake() {
        guard sleepObservers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            },
            nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.start()
                self?.refreshNow()
            },
        ]
    }

    // MARK: - Polling

    private func tick() {
        guard Date() >= nextAllowed else { return }
        poll()
    }

    private func poll() {
        guard !inFlight else { return }
        inFlight = true

        let host = self.host, port = self.port, bleMac = self.bleMac
        let previous = snapshot.reading
        let detail = polls % Self.detailEvery == 0 || previous?.device == nil
        let rediscover = host.isEmpty
            || (snapshot.failures >= PowerSnapshot.offlineAfter && bleMac != nil
                && Date().timeIntervalSince(lastDiscovery) >= Self.rediscoverEvery)

        queue.async { [link] in
            var target = host
            var discovered: MarstekLink.Station?
            if rediscover {
                let stations = link.discover()
                // A known station is followed by its MAC; with no address at all,
                // the first one that answers is taken.
                discovered = bleMac.flatMap { mac in stations.first { $0.bleMac == mac } }
                    ?? (host.isEmpty ? stations.first : nil)
                if let discovered { target = discovered.ip }
            }

            var results: [StationReading.Method: [String: Any]] = [:]
            var failure: MarstekLink.Failure? = target.isEmpty ? .noReply : nil
            if failure == nil {
                switch link.call(StationReading.Method.status.rawValue, host: target, port: port) {
                case .success(let result): results[.status] = result
                case .failure(let error):  failure = error
                }
            }
            if failure == nil {
                var methods: [StationReading.Method] = [.battery, .mode]
                if detail { methods += [.wifi, .device] }
                for method in methods {
                    let params: [String: Any] = method == .device ? ["ble_mac": "0"] : ["id": 0]
                    if case .success(let result) = link.call(method.rawValue, params: params, host: target, port: port) {
                        results[method] = result
                    }
                }
            }

            DispatchQueue.main.async {
                self.inFlight = false
                if rediscover { self.lastDiscovery = Date() }
                // Settings moved the poller elsewhere meanwhile: this answer is
                // stale, and the poll the move asked for was refused as in flight.
                guard host == self.host, port == self.port else { self.poll(); return }
                self.finish(results: results, failure: failure, previous: previous, discovered: discovered)
            }
        }
    }

    private func finish(results: [StationReading.Method: [String: Any]], failure: MarstekLink.Failure?,
                        previous: StationReading?, discovered: MarstekLink.Station?) {
        if let discovered, discovered.ip != host {
            Log.station.notice("station found at \(discovered.ip, privacy: .public)")
            host = discovered.ip
            onStation?(discovered.ip, discovered.bleMac.isEmpty ? nil : discovered.bleMac)
        }

        var next = snapshot
        next.host = host
        if let reading = StationReading.parse(results, previous: previous) {
            if next.failures >= PowerSnapshot.offlineAfter {
                Log.station.notice("station answers again after \(next.failures) silent polls")
            }
            next.reading = reading
            next.updatedAt = Date()
            next.failure = nil
            next.failures = 0
            polls += 1
            nextAllowed = .distantPast
            if let mac = reading.bleMac, mac != bleMac {
                bleMac = mac
                onStation?(host, mac)
            }
        } else {
            next.failure = failure ?? .rpc(code: 0, message: "Reply without a state of charge")
            next.failures += 1
            if next.failures == PowerSnapshot.offlineAfter {
                Log.station.notice("station silent: \(next.failure?.text ?? "", privacy: .public)")
            }
            // 1, 2, 4 missed polls at most: a LAN device that comes back should
            // show up within two minutes.
            let skipped = min(pow(2.0, Double(next.failures - 1)), 4)
            nextAllowed = Date().addingTimeInterval(Self.interval * skipped - 1)
        }
        publish(next)
    }

    private func publish(_ next: PowerSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    /// "192.168.0.46:30000" → host and port; the port defaults to 30000.
    static func split(_ address: String) -> (String, UInt16) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let port = UInt16(parts[1]) { return (parts[0], port) }
        return (trimmed, MarstekLink.defaultPort)
    }
}
