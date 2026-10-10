import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public let sessionId: String
    public var status: SessionStatus
    public var updatedAt: TimeInterval
    public var cwd: String?
    public var source: String?
    /// The hook lifecycle event that last wrote this state (e.g. "PreToolUse"). Used to
    /// detect a session blocked on an inline permission prompt — see PermissionDetection.
    public var event: String?
    /// PID of the Claude Code process that owns the session (written by the hook), so
    /// StateStore can drop the session exactly when that process exits. nil = unknown
    /// (older hook, or no claude ancestor found) → time-based staleness fallback.
    public var pid: Int32?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status = "state"
        case updatedAt = "updated_at"
        case cwd, source, event, pid
    }

    public init(sessionId: String, status: SessionStatus, updatedAt: TimeInterval,
                cwd: String? = nil, source: String? = nil, event: String? = nil,
                pid: Int32? = nil) {
        self.sessionId = sessionId
        self.status = status
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.source = source
        self.event = event
        self.pid = pid
    }
}
