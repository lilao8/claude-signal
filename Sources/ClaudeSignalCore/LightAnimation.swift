import Foundation

/// How a light should animate for a given display state.
public enum LightAnimationKind: Equatable, Sendable {
    case steady   // no animation (off, or solid "done")
    case breathe  // smooth cosine pulse (working)
    case flash    // square on/off (permission, error)
}

/// Pure animation math, shared by every surface so the visual timing is identical
/// and the (otherwise GUI-buried) alpha computation is unit-testable.
public enum LightAnimation {
    /// Breathe oscillates between this and 1.0; flash alternates 1.0 / `flashLow`.
    /// Shared with the Core Animation driver so the curve has one source of truth.
    public static let breatheMin: Double = 0.35
    public static let flashLow: Double = 0.15

    public static func kind(for state: DisplayState) -> LightAnimationKind {
        switch state {
        case .off, .done:          return .steady
        case .working:             return .breathe
        case .permission, .error:  return .flash
        }
    }

    /// Animation period in seconds, or nil for steady states.
    public static func period(for state: DisplayState) -> TimeInterval? {
        switch state {
        case .off, .done:   return nil
        case .working:      return 1.8
        case .permission:   return 1.0
        case .error:        return 0.6
        }
    }

    /// Combined animation config for a state: the period to animate over and whether
    /// to ease (breathe) vs. hard-switch (flash). Returns nil for steady states.
    /// Lets surfaces avoid duplicating the `period`+`kind` derivation.
    public static func config(for state: DisplayState) -> (period: TimeInterval, ease: Bool)? {
        guard let period = period(for: state) else { return nil }
        return (period, kind(for: state) == .breathe)
    }

    /// Alpha (0...1) at a given elapsed time.
    /// `ease == true` → smooth breathe; `ease == false` → square flash.
    public static func alpha(elapsed: TimeInterval, period: TimeInterval, ease: Bool) -> Double {
        let phase = (elapsed.truncatingRemainder(dividingBy: period)) / period  // 0..1
        if ease {
            return breatheMin + (1 - breatheMin) * (0.5 - 0.5 * cos(2 * .pi * phase))
        } else {
            return phase < 0.5 ? 1.0 : flashLow
        }
    }
}
