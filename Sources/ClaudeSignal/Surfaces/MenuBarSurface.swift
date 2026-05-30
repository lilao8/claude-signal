import AppKit
import ClaudeSignalCore

/// Renders the light as a colored dot in the macOS menu bar.
@MainActor
final class MenuBarSurface: SignalSurface {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var current: DisplayState?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "claude-signal", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        render(.off)
    }

    func render(_ state: DisplayState) {
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        switch Appearance.animation(for: state) {
        case .none:
            draw(alpha: state == .off ? 0 : 1, color: Appearance.color(for: state))
        case .breathe:
            startTimer(period: 1.8, color: Appearance.color(for: state), ease: true)
        case .flash:
            startTimer(period: state == .error ? 0.6 : 1.0,
                       color: Appearance.color(for: state), ease: false)
        }
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        // Use Timer(...) + a single explicit run-loop registration in .common mode
        // so the animation keeps running during menu tracking / window drags, and is
        // registered exactly once (scheduledTimer would add a second .default registration).
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let phase = (elapsed.truncatingRemainder(dividingBy: period)) / period  // 0..1
            let alpha: Double
            if ease {
                alpha = 0.35 + 0.65 * (0.5 - 0.5 * cos(2 * .pi * phase)) // smooth breathe
            } else {
                alpha = phase < 0.5 ? 1.0 : 0.15                         // square flash
            }
            // The timer fires on the main run loop, so we are already on the main actor.
            // assumeIsolated lets us call the @MainActor draw() without crossing a
            // Sendable boundary (avoids capturing non-Sendable NSColor across actors).
            MainActor.assumeIsolated {
                self?.draw(alpha: alpha, color: color)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func draw(alpha: Double, color: NSColor) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            if alpha <= 0 { return true }       // .off => empty image
            let inset = rect.insetBy(dx: 3, dy: 3)
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: inset).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }
}
