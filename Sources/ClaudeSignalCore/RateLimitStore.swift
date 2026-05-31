import Foundation

/// Reads the account-level rate-limit file. Returns the state while active; once
/// `now >= resetAt` it deletes the file (condition ① self-clean) and returns nil.
/// Missing or corrupt file → nil. Mirrors `StateStore`'s tolerant read pattern.
public struct RateLimitStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func read(now: TimeInterval) -> RateLimitState? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(RateLimitState.self, from: data)
        else { return nil }

        if now >= state.resetAt {
            try? fm.removeItem(at: fileURL)   // expired: self-clean
            return nil
        }
        return state
    }
}
