import XCTest
@testable import ClaudeSignalCore

private struct FakeIdle: IdleTimeProviding {
    let seconds: TimeInterval
    func idleSeconds() -> TimeInterval { seconds }
}

final class PresenceMonitorTests: XCTestCase {
    func testBelowThresholdIsPresent() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 5))
        XCTAssertEqual(m.current(), .present)
    }
    func testAtThresholdIsAway() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 30))
        XCTAssertEqual(m.current(), .away)
    }
    func testAboveThresholdIsAway() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 120))
        XCTAssertEqual(m.current(), .away)
    }
}
