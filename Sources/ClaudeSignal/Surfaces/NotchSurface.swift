import AppKit
import ClaudeSignalCore

/// Renders the light as a U-shaped glow around the camera notch.
/// Mirrors TouchBarSurface's render/animation logic, sharing LightAnimation.
///
/// Targets whichever screen actually HAS a notch (not `NSScreen.main`, which is the screen
/// with the key window — an external display at launch used to disable the notch surface
/// for the whole process). Rebuilds on display changes (plug/unplug a monitor, clamshell,
/// switching scaled resolution), since the notch's point geometry changes with them. With
/// no notched screen, holds no window and render() just remembers the state.
@MainActor
final class NotchSurface: SignalSurface {
    private var window: NSWindow?
    private var outlineView: NotchOutlineView?
    private var timer: Timer?
    private var current: DisplayState?
    private var screenObserver: NSObjectProtocol?

    init() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        render(.off)
    }

    /// (Re)create the overlay window on the notched screen, then replay the current state.
    private func rebuild() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil)
        window = nil
        outlineView = nil

        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let frame = NotchGeometry.outlineFrame(NotchSurface.input(for: screen)) else {
            FileHandle.standardError.write(Data(
                "claude-signal: no notched screen; notch surface idle.\n".utf8))
            return
        }
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
        window = win
        outlineView = view

        if let state = current {   // replay onto the fresh view
            current = nil
            render(state)
        }
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
        guard state != current else { return }
        current = state                          // remembered for replay after a rebuild
        timer?.invalidate(); timer = nil
        guard let outlineView else { return }    // no notched screen right now

        let color = Appearance.color(for: state)
        guard let config = LightAnimation.config(for: state) else {
            outlineView.setLight(color: color, alpha: state == .off ? 0 : 1)
            return
        }
        startTimer(period: config.period, color: color, ease: config.ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        guard outlineView != nil else { return }   // no-op on non-notch Macs
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            // Timer fires on the main run loop; assumeIsolated avoids a Sendable crossing
            // for the non-Sendable NSColor capture. Drive the view through self so a
            // torn-down surface stops updating (parity with TouchBarSurface).
            MainActor.assumeIsolated {
                self?.outlineView?.setLight(color: color, alpha: alpha)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
