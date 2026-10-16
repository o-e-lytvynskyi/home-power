import SwiftUI
import AppKit

// MARK: - Glass surface

/// Liquid Glass on macOS 26, `NSVisualEffectView` everywhere older.
/// Every surface in this app uses this one view — there is no second style.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            VisualEffectBackground(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = .behindWindow
        v.state        = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

/// Wraps content in the standard card: glass fill, hairline edge, close button.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(GlassBackground(cornerRadius: cornerRadius))
            .overlay(alignment: .topTrailing) {
                CloseButton(action: onClose).padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Close")
    }
}

// MARK: - Panel

/// Borderless, exactly content-sized panel.
///
/// A `.titled` window would draw its own frame at the system corner radius on
/// top of the glass card's radius — that is where the doubled outline and the
/// stray traffic light come from. Borderless keeps one shape on screen.
final class GlassPanel: NSPanel {

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel   = true
        // The panel is held in a strong reference and reopened by rebuilding;
        // letting AppKit release it on close would leave that reference dangling.
        isReleasedWhenClosed = false
        backgroundColor   = .clear
        isOpaque          = false
        hasShadow         = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.layout()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting
        setContentSize(size)
        center()
        invalidateShadow()
    }

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Called after any close — ✕, Esc or code all pass through `close()`;
    /// SwiftUI's `.onDisappear` doesn't fire reliably for a closed panel.
    var onClosed: (() -> Void)?

    override func close() {
        super.close()
        onClosed?()
        onClosed = nil
    }

    /// Esc closes, like every other transient macOS surface.
    override func cancelOperation(_ sender: Any?) { close() }
}
