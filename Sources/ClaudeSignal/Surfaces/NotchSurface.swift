import AppKit
import ClaudeSignalCore

/// Renders the light as a U-shaped glow around the camera notch.
/// Mirrors TouchBarSurface's render/animation logic, sharing LightAnimation.
/// On screens without a notch, builds no window and render() is a no-op — no crash,
/// menu bar unaffected. Acceptance is via a notch Mac (developer has none).
@MainActor
final class NotchSurface: SignalSurface {
    private let window: NSWindow?
    private let outlineView: NotchOutlineView?
    private var timer: Timer?
    private var current: DisplayState?

    init() {
        if let screen = NSScreen.main,
           let frame = NotchGeometry.outlineFrame(NotchSurface.input(for: screen)) {
            let win = NSWindow(contentRect: frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .statusBar
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.hasShadow = false
            let view = NotchOutlineView(frame: NSRect(origin: .zero, size: frame.size))
            win.contentView = view
            win.orderFrontRegardless()
            self.window = win
            self.outlineView = view
        } else {
            self.window = nil
            self.outlineView = nil
            FileHandle.standardError.write(Data(
                "claude-signal: no notch on main screen; notch surface disabled.\n".utf8))
        }
        render(.off)
    }

    /// Capture NSScreen notch values into the pure geometry input.
    private static func input(for screen: NSScreen) -> NotchInsetInput {
        NotchInsetInput(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea
        )
    }

    func render(_ state: DisplayState) {
        guard let outlineView else { return }   // no-op on non-notch Macs
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        let color = Appearance.color(for: state)
        guard let config = LightAnimation.config(for: state) else {
            outlineView.setLight(color: color, alpha: state == .off ? 0 : 1)
            return
        }
        startTimer(period: config.period, color: color, ease: config.ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        guard let outlineView else { return }
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            MainActor.assumeIsolated {
                outlineView.setLight(color: color, alpha: alpha)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
