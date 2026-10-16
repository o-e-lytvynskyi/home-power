import AppKit
import SwiftUI

/// `--render`: every demo state as PNGs — the menu header on a menu-coloured
/// card, and the menu-bar face (percentage + glyph) on a light and a dark
/// strip. Checks the layout without Screen Recording; the real menu still
/// gets one screenshot at the end.
enum Render {

    static func all(into dir: String) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("can't create \(dir): \(error)"); return false
        }
        var ok = true
        for name in PowerSnapshot.demoStates {
            let snapshot = PowerSnapshot.demo(name)
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .dark ? "dark" : "light"
                ok = write(menu(snapshot, scheme: scheme), to: "\(dir)/menu-\(name)-\(suffix).png") && ok
            }
            ok = write(face(snapshot), to: "\(dir)/face-\(name).png") && ok
        }
        let history = PowerHistory(fileURL: nil)
        history.seed(HistorySeries.demoSamples(now: Date()))
        for range in [HistoryRange.day, .week] {
            for scheme in [ColorScheme.light, .dark] {
                let suffix = scheme == .dark ? "dark" : "light"
                let flag = range == .day ? "24h" : "7d"
                ok = write(historyWindow(history, range: range, scheme: scheme),
                           to: "\(dir)/history-\(flag)-\(suffix).png") && ok
                // The crosshair over yesterday evening's discharge.
                let evening = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-3.5 * 3600)
                ok = write(historyWindow(history, range: range, scheme: scheme, hover: evening),
                           to: "\(dir)/history-\(flag)-\(suffix)-hover.png") && ok
            }
        }
        print(dir)
        return ok
    }

    private static func menu(_ snapshot: PowerSnapshot, scheme: ColorScheme) -> Data? {
        MainActor.assumeIsolated {
            let view = PowerView(snapshot: snapshot, cutoff: Preferences.defaultCutoff, now: Date())
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
    }

    private static func historyWindow(_ history: PowerHistory, range: HistoryRange, scheme: ColorScheme,
                                      hover: Date? = nil) -> Data? {
        MainActor.assumeIsolated {
            let model = HistoryModel(history: history, range: range, ratedWh: { 5120 })
            let view = HistoryContent(model: model, hover: hover)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
    }

    /// The menu-bar face at 4×, on light above and dark below. A template
    /// glyph is tinted as the menu bar would tint it.
    private static func face(_ snapshot: PowerSnapshot) -> Data? {
        let scale: CGFloat = 4
        let size = NSSize(width: 70, height: 22)
        let pixels = NSSize(width: size.width * scale, height: size.height * 2 * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width),
                                         pixelsHigh: Int(pixels.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size.width, height: size.height * 2)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (index, dark) in [true, false].enumerated() {
            let strip = NSRect(x: 0, y: CGFloat(index) * size.height, width: size.width, height: size.height)
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            appearance.performAsCurrentDrawingAppearance {
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                strip.fill()
                let ink: NSColor = dark ? .white : .black

                let title = NSMutableAttributedString(attributedString: StatusIcon.title(for: snapshot))
                title.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: title.length))
                let titleSize = title.size()
                title.draw(at: NSPoint(x: strip.minX + 6, y: strip.midY - titleSize.height / 2))

                let icon = StatusIcon.image(for: snapshot)
                let iconRect = NSRect(x: strip.minX + 10 + titleSize.width, y: strip.midY - icon.size.height / 2,
                                      width: icon.size.width, height: icon.size.height)
                if icon.isTemplate {
                    let tinted = NSImage(size: icon.size, flipped: false) { rect in
                        icon.draw(in: rect)
                        ink.set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: iconRect)
                } else {
                    icon.draw(in: iconRect)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(_ data: Data?, to path: String) -> Bool {
        guard let data else { print("render failed: \(path)"); return false }
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { print("\(error)"); return false }
        return true
    }
}
