import Foundation
import Network
import ClaudeSignalCore

/// Tracks general network reachability via NWPathMonitor.
/// `isReachable()` returns the last observed path status (thread-safe).
final class SystemReachability: ReachabilityChecking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "claude-signal.reachability")
    private let lock = NSLock()
    private var reachable = true   // assume up until told otherwise

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.lock()
            self?.reachable = (path.status == .satisfied)
            self?.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    func isReachable() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reachable
    }
}
