import AppKit
import ClaudeSignalCore

/// Renders the light as a persistent dot in the Touch Bar Control Strip.
/// Mirrors `MenuBarSurface`: draw once per state, animate via `LightLayerAnimator`.
/// On machines without the private Control-Strip API, registration is a no-op
/// and `render` simply updates a view nobody sees — no crash, menu bar unaffected.
@MainActor
final class TouchBarSurface: SignalSurface {
    /// Retained for the surface's lifetime to keep the Control Strip item alive.
    private let item: NSCustomTouchBarItem
    private let lightView = TouchBarLightView(frame: NSRect(x: 0, y: 0, width: 44, height: 30))
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
        lightView.setLight(color: Appearance.color(for: state), alpha: state == .off ? 0 : 1)
        LightLayerAnimator.apply(state, to: lightView.layer)
    }
}
