import AppKit
import ClaudeSignalCore

/// Anything that can show the light. Phase 1 = menu bar; later = Touch Bar, notch.
@MainActor
protocol SignalSurface: AnyObject {
    func render(_ state: DisplayState)
}

/// Visual vocabulary for a DisplayState (shared by all surfaces).
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
    enum Animation { case none, breathe, flash }
    static func animation(for state: DisplayState) -> Animation {
        switch state {
        case .off, .done:        return .none      // done = steady
        case .working:           return .breathe
        case .permission, .error:return .flash
        }
    }
}
