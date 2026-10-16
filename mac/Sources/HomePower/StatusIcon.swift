import AppKit

/// A battery drawn to scale, like the system's own: the fill is the state of
/// charge. The state reads by shape — a bolt while charging, a dashed outline
/// with no fill while there is no live reading — and colour joins in only for
/// a low battery, so the glyph stays a template in the menu bar's own colour
/// the rest of the time.
enum StatusIcon {
    static let size = NSSize(width: 27, height: 14)

    static func image(for snapshot: PowerSnapshot) -> NSImage {
        let state = snapshot.state
        let fill = state.hasReading ? Double(snapshot.reading?.soc ?? 0) / 100 : nil
        let low = snapshot.isLow
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, fill: fill, charging: state == .charging, low: low)
            return true
        }
        image.isTemplate = !low
        image.accessibilityDescription = snapshot.title
        return image
    }

    private static func draw(in rect: NSRect, fill: Double?, charging: Bool, low: Bool) {
        // Drawn at draw time, so labelColor resolves against the menu bar.
        let ink: NSColor = low ? .labelColor : .black
        let body = NSRect(x: 1, y: 2, width: 22, height: 10)

        let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.6, dy: 0.6), xRadius: 3, yRadius: 3)
        outline.lineWidth = 1.2
        if fill == nil { outline.setLineDash([2.2, 1.6], count: 2, phase: 0) }
        ink.withAlphaComponent(fill == nil ? 0.75 : 0.55).setStroke()
        outline.stroke()

        let nub = NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.8, y: 5, width: 1.8, height: 4),
                               xRadius: 0.9, yRadius: 0.9)
        ink.withAlphaComponent(fill == nil ? 0.75 : 0.55).setFill()
        nub.fill()

        guard let fill else { return }
        let inner = body.insetBy(dx: 2, dy: 2)
        // A sliver even at 1 %, so an almost empty battery still shows ink.
        let width = fill > 0 ? max(inner.width * min(fill, 1), 1.5) : 0
        (low ? NSColor.systemRed : ink).setFill()
        NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height),
                     xRadius: 1.4, yRadius: 1.4).fill()

        if charging { bolt(in: body, ink: ink) }
    }

    /// A bolt over the middle, with a cleared halo so it reads on any fill.
    private static func bolt(in body: NSRect, ink: NSColor) {
        let c = NSPoint(x: body.midX, y: body.midY)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x + 1.4, y: c.y + 5.6))
        path.line(to: NSPoint(x: c.x - 3.0, y: c.y - 0.6))
        path.line(to: NSPoint(x: c.x - 0.1, y: c.y - 0.6))
        path.line(to: NSPoint(x: c.x - 1.4, y: c.y - 5.6))
        path.line(to: NSPoint(x: c.x + 3.0, y: c.y + 0.6))
        path.line(to: NSPoint(x: c.x + 0.1, y: c.y + 0.6))
        path.close()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        path.lineWidth = 2.4
        path.lineJoinStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
        ink.setFill()
        path.fill()
    }

    /// The percentage next to the glyph; nothing while there is no live reading.
    static func title(for snapshot: PowerSnapshot) -> NSAttributedString {
        guard snapshot.state.hasReading, let soc = snapshot.reading?.soc else { return NSAttributedString() }
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSAttributedString(string: "\(soc)%",
                                  attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)])
    }
}
