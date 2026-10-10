import Foundation

/// When a finished (`done`) or failed (`error`) session should stop showing.
///
/// Sessions now live as long as their Claude Code process (see StateStore), and the desktop
/// app keeps that process alive long after a turn ends. Without an "already seen" rule,
/// every finished session would re-light green each time you stepped away, and a failed
/// background session would stay red forever. So:
///
/// - `dropSeen`: keyboard/mouse input more than a grace period after the session finished
///   counts as having seen it; the session is dropped (→ off) and stays off when you leave
///   again. Grace for done = `doneGrace` (covers the flash below); for error = `errorGrace`,
///   so red is visible for a while even if you happen to be typing when it fails.
/// - `hasFreshDone`: a session that finished within the last `doneGrace` seconds flashes
///   green even while you're present, so you notice the turn is yours. Real `Stop` events
///   carry a fresh timestamp; idle-demoted sessions (IdleDetection) are older than its
///   threshold and never flash.
///
/// Both are stateless: "last input" is derived from the system idle time.
public enum Acknowledgment {
    public static let doneGrace: TimeInterval = 4
    public static let errorGrace: TimeInterval = 10

    public static func dropSeen(_ sessions: [SessionState],
                                lastInputAt: TimeInterval,
                                doneGrace: TimeInterval = doneGrace,
                                errorGrace: TimeInterval = errorGrace) -> [SessionState] {
        sessions.filter { s in
            switch s.status {
            case .done:  return !(lastInputAt > s.updatedAt + doneGrace)
            case .error: return !(lastInputAt > s.updatedAt + errorGrace)
            case .working, .permission: return true
            }
        }
    }

    public static func hasFreshDone(_ sessions: [SessionState],
                                    now: TimeInterval,
                                    window: TimeInterval = doneGrace) -> Bool {
        sessions.contains { s in
            let age = now - s.updatedAt
            return s.status == .done && age >= 0 && age < window
        }
    }
}
