import SwiftUI

/// The top of the menu: charge, what the battery is doing, and the station's
/// details. Built from plain values on each menu open — nothing in it updates
/// while the menu is up.
struct PowerView: View {
    let snapshot: PowerSnapshot
    let cutoff: Int
    let now: Date

    static let width: CGFloat = 300

    struct Row: Hashable {
        let label: String
        let value: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOME BATTERY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            if snapshot.state.hasReading, let reading = snapshot.reading {
                charge(reading)
                details(reading)
            } else {
                problem
            }

            Text(footer)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.top, 12)
        }
        // Lines up with the menu items' titles.
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .frame(width: Self.width, alignment: .leading)
    }

    // MARK: - Charge

    private func charge(_ r: StationReading) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(r.soc)%")
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                Spacer(minLength: 8)
                if let energy = Self.energy(r) {
                    Text(energy)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Bar(share: Double(r.soc) / 100, colour: Self.tint(r.soc))
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                if let estimate = Self.estimate(r, cutoff: cutoff) {
                    Text(estimate)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    private func details(_ r: StationReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Self.rows(r, cutoff: cutoff), id: \.self) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                .font(.system(size: 12))
            }
        }
        .padding(.top, 14)
    }

    // MARK: - Problems

    private var problem: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.title)
                .font(.system(size: 13, weight: .medium))
            if let hint = snapshot.hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reading = snapshot.reading, let at = snapshot.updatedAt {
                Text("Last reading \(Format.ago(at, now: now)): \(reading.soc)%"
                     + (reading.flow == .idle ? "" : ", \(reading.flow == .charging ? "charging" : "discharging")"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var footer: String {
        var parts: [String] = []
        if let at = snapshot.updatedAt, snapshot.state.hasReading { parts.append("Updated \(Format.ago(at, now: now))") }
        if !snapshot.host.isEmpty { parts.append(snapshot.host) }
        if snapshot.state.hasReading, let failure = snapshot.failure { parts.append("last poll: \(failure.text)") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    // MARK: - Text, shared with the debug flags

    static func energy(_ r: StationReading) -> String? {
        guard let remaining = r.remainingWh else { return nil }
        guard let rated = r.ratedWh else { return "\(Format.kWh(remaining)) kWh" }
        return "\(Format.kWh(remaining)) of \(Format.kWh(rated)) kWh"
    }

    static func estimate(_ r: StationReading, cutoff: Int) -> String? {
        if let left = r.hoursLeft(cutoffPercent: cutoff) {
            return left == 0 ? "at the \(cutoff)% cutoff" : "\(Format.hours(left)) to \(cutoff)%"
        }
        if let full = r.hoursToFull() { return "full in \(Format.hours(full))" }
        return nil
    }

    static func rows(_ r: StationReading, cutoff: Int) -> [Row] {
        var rows: [Row] = []
        if let w = r.backupW { rows.append(Row(label: "BACKUP socket", value: Format.watts(w))) }
        if let w = r.gridW {
            let value = w == 0 ? "0 W" : (w < 0 ? "drawing \(Format.watts(-w))" : "feeding \(Format.watts(w))")
            rows.append(Row(label: "Grid port", value: value))
        }
        if let t = r.batteryTempC { rows.append(Row(label: "Battery temperature", value: String(format: "%.0f °C", t))) }
        if let mode = r.mode { rows.append(Row(label: "Mode", value: mode)) }
        if let rssi = r.rssi {
            rows.append(Row(label: "Wi-Fi", value: "\(rssi < 0 ? "−\(-rssi)" : "\(rssi)") dBm" + (r.ssid.map { " · \($0)" } ?? "")))
        }
        if let device = r.device {
            rows.append(Row(label: "Station", value: device + (r.firmware.map { " · fw \($0)" } ?? "")))
        }
        return rows
    }

    static func tint(_ soc: Int) -> Color {
        Color(nsColor: soc <= PowerSnapshot.lowPercent ? .systemRed : (soc <= 35 ? .systemOrange : .systemGreen))
    }
}

private struct Bar: View {
    let share: Double
    let colour: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(colour)
                    .frame(width: max(geo.size.width * min(max(share, 0), 1), 6))
            }
        }
        .frame(height: 6)
    }
}
