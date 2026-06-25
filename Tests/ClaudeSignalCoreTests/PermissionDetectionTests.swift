import XCTest
@testable import ClaudeSignalCore

final class PermissionDetectionTests: XCTestCase {
    private func session(_ status: SessionStatus, event: String?, updatedAt: TimeInterval) -> SessionState {
        SessionState(sessionId: "s", status: status, updatedAt: updatedAt, event: event)
    }

    func testStuckPreToolUsePromotedToPermission() {
        let s = session(.working, event: "PreToolUse", updatedAt: 100)
        let out = PermissionDetection.promote([s], now: 120, threshold: 12)   // 20s > 12s
        XCTAssertEqual(out.first?.status, .permission)
    }

    func testRecentPreToolUseNotPromoted() {
        let s = session(.working, event: "PreToolUse", updatedAt: 100)
        let out = PermissionDetection.promote([s], now: 105, threshold: 12)   // 5s < 12s
        XCTAssertEqual(out.first?.status, .working)
    }

    func testPostToolUseNeverPromoted() {
        // A long-running tool advances to PostToolUse; only PreToolUse is the stuck signal.
        let s = session(.working, event: "PostToolUse", updatedAt: 100)
        let out = PermissionDetection.promote([s], now: 200, threshold: 12)
        XCTAssertEqual(out.first?.status, .working)
    }

    func testNonWorkingUntouched() {
        let done = session(.done, event: nil, updatedAt: 100)
        let out = PermissionDetection.promote([done], now: 200, threshold: 12)
        XCTAssertEqual(out.first?.status, .done)
    }

    func testThresholdIsExclusive() {
        // Exactly at the threshold should not promote (strictly greater).
        let s = session(.working, event: "PreToolUse", updatedAt: 100)
        let out = PermissionDetection.promote([s], now: 112, threshold: 12)
        XCTAssertEqual(out.first?.status, .working)
    }
}
