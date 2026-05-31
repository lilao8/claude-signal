import AppKit
import ClaudeSignalCore

/// Anything that can show the light. Phase 1 = menu bar; Phase 2 = Touch Bar; later = notch.
@MainActor
protocol SignalSurface: AnyObject {
    func render(_ state: DisplayState)
}

/// Color vocabulary for a DisplayState (shared by all surfaces).
/// Animation timing lives in `ClaudeSignalCore.LightAnimation`.
enum Appearance {
    static func color(for state: DisplayState) -> NSColor {
        switch state {
        case .off:        return .clear
        case .working:    return .systemBlue
        case .permission: return .systemYellow
        case .error:      return .systemRed
        case .done:       return .systemGreen
        }
    }
}
