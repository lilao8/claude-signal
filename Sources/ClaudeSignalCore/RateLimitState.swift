import Foundation

/// Account-level usage-limit state. `resetAt` is unix seconds; the hook writes a very
/// large sentinel (~year 5138) when it can't parse a reset time, so the red stays on
/// until normal activity deletes the file.
public struct RateLimitState: Codable, Equatable, Sendable {
    public let resetAt: TimeInterval
    public let raw: String?

    enum CodingKeys: String, CodingKey {
        case resetAt = "reset_at"
        case raw
    }

    public init(resetAt: TimeInterval, raw: String? = nil) {
        self.resetAt = resetAt
        self.raw = raw
    }
}
