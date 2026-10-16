import Combine
import Foundation

/// One good poll, as kept on disk. Optional fields are what the station did
/// not report that time.
struct HistorySample: Equatable {
    let time: Date
    let soc: Double
    let wh: Double?
    /// Positive while discharging, like `StationReading.batteryW`.
    let batteryW: Double?
    let backupW: Double?
    let gridW: Double?

    init(time: Date, soc: Double, wh: Double? = nil, batteryW: Double? = nil,
         backupW: Double? = nil, gridW: Double? = nil) {
        self.time = time
        self.soc = soc
        self.wh = wh
        self.batteryW = batteryW
        self.backupW = backupW
        self.gridW = gridW
    }

    init(_ reading: StationReading, at time: Date) {
        self.init(time: time, soc: Double(reading.soc), wh: reading.remainingWh,
                  batteryW: reading.batteryW.map(Double.init), backupW: reading.backupW.map(Double.init),
                  gridW: reading.gridW.map(Double.init))
    }

    /// `epoch,soc,wh,batteryW,backupW,gridW`; an empty field is nil.
    var line: String {
        func f(_ v: Double?) -> String {
            guard let v else { return "" }
            return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        }
        return [String(Int(time.timeIntervalSince1970)), f(soc), f(wh), f(batteryW), f(backupW), f(gridW)]
            .joined(separator: ",")
    }

    init?(line: Substring) {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 2, let epoch = Double(fields[0]), let soc = Double(fields[1]) else { return nil }
        func f(_ i: Int) -> Double? { i < fields.count ? Double(fields[i]) : nil }
        self.init(time: Date(timeIntervalSince1970: epoch), soc: soc, wh: f(2), batteryW: f(3),
                  backupW: f(4), gridW: f(5))
    }
}

/// Every good poll of the last 30 days, in memory and appended to a CSV file.
///
/// A poll every 30 s is ~2,900 lines and ~100 KB a day, so a month loads in
/// tens of milliseconds. Nothing is written for a failed poll: a missing
/// stretch is how a gap is recognised later, and `HistorySeries` fills it.
final class PowerHistory: ObservableObject {

    static let retention: TimeInterval = 30 * 86_400

    @Published private(set) var samples: [HistorySample] = []

    /// Nil keeps everything in memory (the demo).
    let fileURL: URL?

    /// Where the installed app keeps it. Spelled out rather than taken from the
    /// bundle, so debug flags run from a scratch build read the same file.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HomePower", isDirectory: true).appendingPathComponent("history.csv")
    }

    init(fileURL: URL?, now: Date = Date()) {
        self.fileURL = fileURL
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let cutoff = now.addingTimeInterval(-Self.retention)
        var loaded: [HistorySample] = []
        var dropped = 0
        for line in text.split(separator: "\n") {
            // A torn last line from a crash or a power cut is skipped, not fatal.
            guard let sample = HistorySample(line: line) else { dropped += 1; continue }
            guard sample.time >= cutoff else { dropped += 1; continue }
            if let last = loaded.last, sample.time <= last.time { dropped += 1; continue }
            loaded.append(sample)
        }
        samples = loaded
        if dropped > 0 { rewrite() }
    }

    /// Appends a reading taken at `time`. Readings out of order are ignored.
    func record(_ sample: HistorySample) {
        if let last = samples.last, sample.time <= last.time { return }
        samples.append(sample)
        append(sample.line + "\n")

        // Pruned about once an hour rather than on every poll.
        if let first = samples.first, sample.time.timeIntervalSince(first.time) > Self.retention + 3600 {
            let cutoff = sample.time.addingTimeInterval(-Self.retention)
            samples.removeAll { $0.time < cutoff }
            rewrite()
        }
    }

    /// Replaces everything, for the demo.
    func seed(_ samples: [HistorySample]) {
        self.samples = samples
    }

    // MARK: - File

    private func append(_ text: String) {
        guard let fileURL else { return }
        let data = Data(text.utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: fileURL)
        }
    }

    private func rewrite() {
        guard let fileURL else { return }
        let text = samples.map(\.line).joined(separator: "\n") + (samples.isEmpty ? "" : "\n")
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}
