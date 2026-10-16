import SwiftUI

struct AboutView: View {
    let snapshot: PowerSnapshot
    let onClose: () -> Void

    var body: some View {
        GlassCard(onClose: onClose) {
            VStack(spacing: 0) {
                Image(systemName: "bolt.batteryblock.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .padding(.bottom, 12)

                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .semibold))
                Text("Version \(AppInfo.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Text("A Marstek Venus E home battery in the menu bar: charge, power and time left, read from the station's Local API on your network. No cloud account.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Divider()
                    .opacity(0.35)
                    .padding(.vertical, 14)

                Text(snapshot.state.hasReading ? "\(snapshot.reading?.soc ?? 0)% · \(snapshot.title)" : snapshot.title)
                    .font(.system(size: 12, weight: .medium))
                if let device = snapshot.reading?.device {
                    Text(device + (snapshot.reading?.firmware.map { " · firmware \($0)" } ?? ""))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 3)
                }

                // Verbatim: a localized key would print the port as "30 000".
                Text(verbatim: "Open API Rev 3.1 · UDP \(MarstekLink.defaultPort)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(width: 300)
        }
    }
}

enum AppInfo {
    static let name    = "HomePower"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
}
