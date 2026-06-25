import Foundation

/// Detects sessions blocked on an inline permission prompt and promotes them to
/// `.permission` so the light goes yellow.
///
/// Why this is needed: Claude Code's inline "allow this tool? (yes/no)" prompts often do
/// NOT fire the `Notification` hook (or only after a long idle delay), so on its own the
/// hook just leaves the session at `working`/PreToolUse (blue) — the user never sees yellow
/// while a prompt waits. The hook tags each working state with its lifecycle event, which
/// lets us spot a session that has been sitting at `PreToolUse` without advancing.
///
/// The ambiguity: a genuinely slow tool (a long build/test) also sits at PreToolUse until
/// PostToolUse fires, and is indistinguishable from a waiting prompt in a single snapshot.
/// Hence the time threshold — long enough that ordinary fast tools never trip it. A slow
/// tool that exceeds it will briefly read yellow, but self-clears once it finishes, whereas
/// a real prompt stays yellow until answered.
public enum PermissionDetection {
    /// Default seconds a session may sit at PreToolUse before we treat it as a permission
    /// prompt. Tunable: larger = fewer false yellows on slow tools, but slower to surface a
    /// real prompt.
    public static let defaultThreshold: TimeInterval = 12

    /// Returns `sessions` with any stuck-at-PreToolUse working session promoted to
    /// `.permission`. Pure; `now` and `threshold` are injected so it stays unit-testable.
    public static func promote(_ sessions: [SessionState],
                               now: TimeInterval,
                               threshold: TimeInterval = defaultThreshold) -> [SessionState] {
        sessions.map { session in
            guard session.status == .working,
                  session.event == "PreToolUse",
                  now - session.updatedAt > threshold else { return session }
            var promoted = session
            promoted.status = .permission
            return promoted
        }
    }
}
