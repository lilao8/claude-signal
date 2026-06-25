import AppKit

/// Draws a U-shaped glowing outline (left + rounded bottom + right; no top) inside its
/// bounds. `setLight(color:alpha:)` updates appearance; the surface drives it from an
/// animation timer (mirrors TouchBarLightView). Tunable style constants are here so a
/// user can re-style by editing one line.
@MainActor
final class NotchOutlineView: NSView {
    // --- tunable style constants ---
    private let borderWidth: CGFloat = 3
    private let cornerRadius: CGFloat = 10
    private let glowRadius: CGFloat = 7
    // --------------------------------

    private var strokeColor: NSColor = .clear
    private var strokeAlpha: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true   // layer-backed: cheaper redraws for the ~30fps animation
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setLight(color: NSColor, alpha: Double) {
        strokeColor = color
        strokeAlpha = alpha
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard strokeAlpha > 0 else { return }   // off => draw nothing

        let inset = borderWidth / 2 + glowRadius
        let r = bounds.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return }

        // U-shape: top-left → down left → rounded bottom-left → across bottom →
        // rounded bottom-right → up right → top-right. No top edge.
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.maxY))
        path.line(to: NSPoint(x: r.minX, y: r.minY + cornerRadius))
        path.appendArc(withCenter: NSPoint(x: r.minX + cornerRadius, y: r.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: r.maxX - cornerRadius, y: r.minY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - cornerRadius, y: r.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))
        path.lineWidth = borderWidth
        path.lineCapStyle = .round

        let c = strokeColor.withAlphaComponent(strokeAlpha)
        c.setStroke()

        // Two-pass glow: a wide soft halo first, then a tighter brighter core on top.
        // Stacking the shadows reads as a real emissive glow even at the breathe low
        // (alpha ~0.35), without touching the shared LightAnimation timing.
        let halo = NSShadow()
        halo.shadowColor = c
        halo.shadowBlurRadius = glowRadius
        halo.shadowOffset = .zero
        halo.set()
        path.stroke()

        let core = NSShadow()
        core.shadowColor = c
        core.shadowBlurRadius = glowRadius / 2
        core.shadowOffset = .zero
        core.set()
        path.stroke()
    }
}
