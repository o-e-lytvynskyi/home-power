import SwiftUI
import ServiceManagement

/// Login-item state, backed by `SMAppService` (macOS 13+). Nothing is stored in
/// UserDefaults — the registration itself is the source of truth, so the
/// checkbox cannot drift from what the system actually does.
///
/// Main thread only, like the other observable objects here.
final class LaunchAtLogin: ObservableObject {
    @Published var isEnabled: Bool
    @Published var errorText: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            errorText = "Approve HomePower in System Settings → General → Login Items."
        }
    }

    func apply(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        refresh()
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var launchAtLogin: LaunchAtLogin
    /// Broadcast discovery; the answer arrives on the main thread.
    let discover: (@escaping ([MarstekLink.Station]) -> Void) -> Void
    let onClose: () -> Void

    /// The field applies on Return or Find, not per keystroke: a half-typed
    /// address would send the poller off to a host that doesn't exist.
    @State private var draft = ""
    @State private var finding = false
    @State private var note: String?

    /// Reserved so a note of any length does not resize the window.
    private static let noteHeight: CGFloat = 28

    var body: some View {
        GlassCard(onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider().opacity(0.35)
                stationSection
                Divider().opacity(0.35)
                cutoffSection
                Divider().opacity(0.35)
                notifySection
                Divider().opacity(0.35)
                loginSection
                Divider().opacity(0.35)
                footer
            }
            .frame(width: 340, alignment: .leading)
        }
        .onAppear { draft = preferences.address }
    }

    // MARK: - Station

    private var stationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Station address")
                .font(.system(size: 12))
            HStack(spacing: 8) {
                TextField("Find automatically", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit(apply)
                Button(finding ? "Finding…" : "Find", action: find)
                    .disabled(finding)
                    .font(.system(size: 12))
            }
            Text(note ?? "IP address, optionally with :port. Local API must be on in the Marstek app (Settings → Local API).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: Self.noteHeight, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func apply() {
        let cleaned = Preferences.clean(draft)
        draft = cleaned
        guard cleaned != preferences.address else { return }
        preferences.address = cleaned
        note = cleaned.isEmpty ? "Looking for the station on the local networks." : "Polling \(cleaned)."
    }

    private func find() {
        finding = true
        note = "Asking the local networks…"
        discover { stations in
            finding = false
            guard let first = stations.first else {
                note = "Nothing answered on UDP \(MarstekLink.defaultPort). Is Local API on?"
                return
            }
            draft = first.ip
            preferences.address = first.ip
            let others = stations.count > 1 ? " (\(stations.count) answered, took the first)" : ""
            note = "Found \(first.device) at \(first.ip)\(others)."
        }
    }

    // MARK: - Cutoff

    private var cutoffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: $preferences.cutoff, in: Preferences.cutoffRange) {
                Text("Station stops discharging at \(preferences.cutoff)%")
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            Text("For the time-left estimate. Match the DoD set in the Marstek app: DoD 88% stops at 12%.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: Self.noteHeight, alignment: .topLeading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Notifications

    private var notifySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Notify every 10% while discharging", isOn: $preferences.notify)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Text("With the last hour's average draw and the time left. Silent down to 50%; below that with a sound and a warning.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: Self.noteHeight, alignment: .topLeading)
                .padding(.leading, 19)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Login item

    private var loginSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin.isEnabled },
                set: { launchAtLogin.apply($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            if let errorText = launchAtLogin.errorText {
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 19)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        Text("Local API over UDP · polls every \(Int(StationService.interval)) s")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}
