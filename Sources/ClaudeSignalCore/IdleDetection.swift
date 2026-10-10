import Foundation

/// Demotes a `working` session that finished a step and then went silent to `done`, so the
/// light turns off instead of staying stuck blue.
///
/// Why this is needed: the only hook path to `done` is the `Stop` event. If a session goes
/// idle WITHOUT firing Stop — e.g. `SubagentStop` is the final event, or an agent-mode
/// session parks — it would otherwise stay `working` (blue) until the StateStore's 300s
/// stale cleanup removes the file. That's the "nothing is running but the light won't turn
/// off" bug.
///
/// Only step-boundary events qualify (PostToolUse / SubagentStop / UserPromptSubmit): during
/// active work the agent fires its next PreToolUse within a second or two, so prolonged
/// silence after one of these means the turn effectively ended. A session stuck at
/// PreToolUse is the opposite signal (about to act / awaiting approval) and is handled by
/// PermissionDetection (→ yellow), so it is deliberately excluded here — the two event sets
/// are disjoint.
public enum IdleDetection {
    /// Default seconds a step-boundary `working` session may stay silent before we treat it
    /// as idle. Claude can think for well over 20s between tool calls without firing any
    /// hook, so a short threshold blinked the light off mid-turn; 60s keeps it blue through
    /// those gaps at the cost of clearing a truly-stuck session a little later.
    public static let defaultThreshold: TimeInterval = 60

    /// Events after which continued silence means the session went idle (not mid-tool).
    static let idleAfterEvents: Set<String> = ["PostToolUse", "SubagentStop", "UserPromptSubmit"]

    /// Returns `sessions` with any silent step-boundary `working` session demoted to `.done`.
    /// Pure; `now` and `threshold` are injected so it stays unit-testable.
    public static func demote(_ sessions: [SessionState],
                              now: TimeInterval,
                              threshold: TimeInterval = defaultThreshold) -> [SessionState] {
        sessions.map { session in
            guard session.status == .working,
                  let event = session.event, idleAfterEvents.contains(event),
                  now - session.updatedAt > threshold else { return session }
            var idle = session
            idle.status = .done
            return idle
        }
    }
}
