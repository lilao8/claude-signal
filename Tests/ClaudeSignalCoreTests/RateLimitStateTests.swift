import XCTest
@testable import ClaudeSignalCore

final class RateLimitStateTests: XCTestCase {
    func testDecodesSnakeCaseJSON() throws {
        let json = #"{"reset_at":1780200000,"raw":"resets 1:10am (America/Toronto)"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 1780200000)
        XCTAssertEqual(s.raw, "resets 1:10am (America/Toronto)")
    }

    func testDecodesWithoutRaw() throws {
        let json = #"{"reset_at":1780200000}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 1780200000)
        XCTAssertNil(s.raw)
    }

    func testLargeSentinelDecodes() throws {
        let json = #"{"reset_at":99999999999}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 99999999999)
    }
}
