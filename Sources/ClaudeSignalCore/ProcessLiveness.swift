import Foundation

public protocol ProcessLivenessChecking: Sendable {
    func isAlive(_ pid: Int32) -> Bool
}

/// Real check: `kill(pid, 0)` sends no signal, only probes. EPERM means the process exists
/// but belongs to someone else — still alive.
public struct SystemProcessLiveness: ProcessLivenessChecking {
    public init() {}
    public func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
