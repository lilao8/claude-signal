import AppKit
import ClaudeSignalCore

/// Renders the light as a persistent dot in the Touch Bar Control Strip.
/// Mirrors `MenuBarSurface`'s render/animation logic, sharing `LightAnimation`.
/// On machines without the private Control-Strip API, registration is a no-op
/// and `render` simply updates a view nobody sees — no crash, menu bar unaffected.
@MainActor
final class TouchBarSurface: SignalSurface {
    /// Retained for the surface's lifetime to keep the Control Strip item alive.
    private let item: NSCustomTouchBarItem
    private let lightView = TouchBarLightView(frame: NSRect(x: 0, y: 0, width: 44, height: 30))
    private var timer: Timer?
    private var current: DisplayState?

    init() {
        item = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.claudesignal.touchbar.light"))
        item.view = lightView
        DFRControlStrip.add(item)   // graceful no-op if the private API is unavailable
        if !DFRControlStrip.isAvailable {
            FileHandle.standardError.write(Data(
                "claude-signal: Touch Bar Control Strip API unavailable; menu bar only.\n".utf8))
        }
        render(.off)
    }

    func render(_ state: DisplayState) {
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        let color = Appearance.color(for: state)
        // config == nil  <=>  steady state (off or done)
        guard let config = LightAnimation.config(for: state) else {
            lightView.setLight(color: color, alpha: state == .off ? 0 : 1)
            return
        }
        startTimer(period: config.period, color: color, ease: config.ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            // Timer fires on the main run loop; assumeIsolated avoids a Sendable crossing
            // for the non-Sendable NSColor capture.
            MainActor.assumeIsolated {
                self?.lightView.setLight(color: color, alpha: alpha)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
