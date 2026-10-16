import Combine
import Foundation

/// What the owner set. Persisted in UserDefaults; `onChange` fires once per
/// edit so the poller can move at once.
final class Preferences: ObservableObject {

    /// "ip" or "ip:port"; empty means find the station by broadcast.
    @Published var address: String { didSet { if address != oldValue { changed() } } }
    /// Where the station stops discharging, for the time-left estimate. The
    /// API can set the DoD but not read it back, so the owner says.
    @Published var cutoff: Int     { didSet { if cutoff  != oldValue { changed() } } }
    /// A notification at every 10 % while discharging.
    @Published var notify: Bool    { didSet { if notify  != oldValue { changed() } } }
    /// The station's Bluetooth MAC: how it is found again when DHCP moves it.
    var bleMac: String?            { didSet { if bleMac  != oldValue { changed() } } }

    var onChange: (() -> Void)?

    enum Keys {
        static let address = "prefs.address"
        static let cutoff  = "prefs.cutoff"
        static let bleMac  = "prefs.bleMac"
        static let notify  = "prefs.notify"
    }

    /// DoD 88 % in the Marstek app, the most it allows: discharge stops at 12 %.
    static let defaultCutoff = 12
    static let cutoffRange = 0...70

    /// The demo build shares the defaults domain with the installed copy and
    /// must not rewrite the real settings.
    private let persist: Bool

    init(persist: Bool = true) {
        self.persist = persist
        let d = UserDefaults.standard
        address = persist ? Self.clean(d.string(forKey: Keys.address) ?? "") : "192.168.0.46"
        let saved = d.object(forKey: Keys.cutoff) as? Int ?? Self.defaultCutoff
        cutoff = min(max(saved, Self.cutoffRange.lowerBound), Self.cutoffRange.upperBound)
        bleMac = persist ? d.string(forKey: Keys.bleMac) : nil
        notify = d.object(forKey: Keys.notify) as? Bool ?? true
    }

    /// Pasted text arrives with newlines as often as with spaces.
    static func clean(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func changed() {
        defer { onChange?() }
        guard persist else { return }
        let d = UserDefaults.standard
        d.set(Self.clean(address), forKey: Keys.address)
        d.set(cutoff, forKey: Keys.cutoff)
        d.set(notify, forKey: Keys.notify)
        if let bleMac { d.set(bleMac, forKey: Keys.bleMac) } else { d.removeObject(forKey: Keys.bleMac) }
    }
}
