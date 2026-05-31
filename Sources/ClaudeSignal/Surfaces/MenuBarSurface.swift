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

        let color = Appearance.color(for: state)
        // config == nil  <=>  steady state (off or done)
        guard let config = LightAnimation.config(for: state) else {
            draw(alpha: state == .off ? 0 : 1, color: color)
            return
        }
        startTimer(period: config.period, color: color, ease: config.ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        // Use Timer(...) + a single explicit RunLoop.main.add(forMode: .common) rather than
        // Timer.scheduledTimer: scheduledTimer would ALSO register in .default mode, giving a
        // duplicate registration. .common keeps the animation running during menu tracking too.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            // Timer fires on the main run loop; assumeIsolated avoids a Sendable crossing
            // for the non-Sendable NSColor capture.
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
