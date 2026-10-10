import Foundation

public struct StateStore: Sendable {
    public let directory: URL
    public let staleThreshold: TimeInterval
    public let liveness: ProcessLivenessChecking

    public init(directory: URL, staleThreshold: TimeInterval,
                liveness: ProcessLivenessChecking = SystemProcessLiveness()) {
        self.directory = directory
        self.staleThreshold = staleThreshold
        self.liveness = liveness
    }

    /// Reads all session files, deletes dead ones, returns the live set.
    ///
    /// A session that records its Claude Code process `pid` lives exactly as long as that
    /// process: kept however old it is (a finished or permission-waiting session must stay
    /// visible while you're away — the old blanket timeout dropped green/yellow after 5 min,
    /// exactly when you needed them), deleted the moment the process is gone. Sessions
    /// without a pid fall back to the `staleThreshold` timeout.
    public func loadLiveSessions(now: TimeInterval) -> [SessionState] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        var live: [SessionState] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(SessionState.self, from: data)
            else { continue }
            let dead: Bool
            if let pid = session.pid {
                dead = !liveness.isAlive(pid)
            } else {
                dead = now - session.updatedAt > staleThreshold
            }
            if dead {
                try? fm.removeItem(at: url)   // owner gone / stale: clean up
            } else {
                live.append(session)
            }
        }
        return live.sorted { $0.sessionId < $1.sessionId }
    }
}
