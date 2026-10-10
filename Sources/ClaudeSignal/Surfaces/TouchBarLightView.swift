import AppKit

/// A small Touch Bar view that draws a single rounded "light" in a color + alpha.
/// `setLight` redraws once per state change; brightness animation runs on the
/// layer via LightLayerAnimator.
@MainActor
final class TouchBarLightView: NSView {
    private var fillColor: NSColor = .clear
    private var fillAlpha: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true   // layer-backed: LightLayerAnimator animates its opacity
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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
