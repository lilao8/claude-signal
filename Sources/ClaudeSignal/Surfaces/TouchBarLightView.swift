import AppKit

/// A small Touch Bar view that draws a single rounded "light" in a color + alpha.
/// `setLight` updates the appearance and triggers a redraw; the surface drives it
/// from an animation timer (mirroring the menu-bar dot).
@MainActor
final class TouchBarLightView: NSView {
    private var fillColor: NSColor = .clear
    private var fillAlpha: Double = 0

    func setLight(color: NSColor, alpha: Double) {
        fillColor = color
        fillAlpha = alpha
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard fillAlpha > 0 else { return }   // off => draw nothing
        let inset = bounds.insetBy(dx: 6, dy: 6)
        let radius = inset.height / 2
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        fillColor.withAlphaComponent(fillAlpha).setFill()
        path.fill()
    }
}
