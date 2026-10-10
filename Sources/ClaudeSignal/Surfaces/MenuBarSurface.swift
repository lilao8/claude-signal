import AppKit
import ClaudeSignalCore

/// Renders the light as a colored dot in the macOS menu bar.
@MainActor
final class MenuBarSurface: SignalSurface {
    private let statusItem: NSStatusItem
    private var current: DisplayState?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "claude-signal", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.wantsLayer = true   // opacity animated by LightLayerAnimator
        render(.off)
    }

    func render(_ state: DisplayState) {
        guard state != current else { return }
        current = state
        // Draw once at full brightness; breathe/flash runs as a Core Animation on the
        // button's layer (no per-frame redraw).
        draw(alpha: state == .off ? 0 : 1, color: Appearance.color(for: state))
        LightLayerAnimator.apply(state, to: statusItem.button?.layer)
    }

    private func draw(alpha: Double, color: NSColor) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 3, dy: 3)
            if alpha <= 0 {
                // .off => faint hollow ring rather than nothing, so "idle" is visibly
                // different from "app not running" (an empty slot looks the same as a
                // quit/crashed app). Drawn at render time, so it follows light/dark menu bar.
                let ring = NSBezierPath(ovalIn: inset.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                NSColor.tertiaryLabelColor.setStroke()
                ring.stroke()
                return true
            }
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: inset).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }
}
