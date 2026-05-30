import Foundation

public struct StateStore: Sendable {
    public let directory: URL
    public let staleThreshold: TimeInterval

    public init(directory: URL, staleThreshold: TimeInterval) {
        self.directory = directory
        self.staleThreshold = staleThreshold
    }

    /// Reads all session files, deletes stale ones, returns the live set.
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
            if now - session.updatedAt > staleThreshold {
                try? fm.removeItem(at: url)   // stale: clean up
            } else {
                live.append(session)
            }
        }
        return live.sorted { $0.sessionId < $1.sessionId }
    }
}
