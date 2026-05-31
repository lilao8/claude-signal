import XCTest
@testable import ClaudeSignalCore

final class RateLimitOverrideTests: XCTestCase {
    func testActiveLimitForcesError() {
        let rl = RateLimitState(resetAt: 2000)
        XCTAssertEqual(applyRateLimitOverride(.idle, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.done, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.permission, rateLimit: rl, now: 1000), .error)
    }

    func testExpiredLimitPassesThrough() {
        let rl = RateLimitState(resetAt: 1000)
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1000), .working)
        XCTAssertEqual(applyRateLimitOverride(.idle, rateLimit: rl, now: 1500), .idle)
    }

    func testNilPassesThrough() {
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: nil, now: 1000), .working)
        XCTAssertEqual(applyRateLimitOverride(.done, rateLimit: nil, now: 1000), .done)
    }

    func testSentinelFallbackStaysActive() {
        let rl = RateLimitState(resetAt: 99999999999)
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1780200000), .error)
    }
}
