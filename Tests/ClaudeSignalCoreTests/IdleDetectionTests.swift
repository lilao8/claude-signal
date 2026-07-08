import XCTest
@testable import ClaudeSignalCore

final class IdleDetectionTests: XCTestCase {
    private func session(_ status: SessionStatus, event: String?, updatedAt: TimeInterval) -> SessionState {
        SessionState(sessionId: "s", status: status, updatedAt: updatedAt, event: event)
    }

    func testSilentSubagentStopDemotedToDone() {
        // The reported bug: stuck at SubagentStop, nothing after, light won't turn off.
        let s = session(.working, event: "SubagentStop", updatedAt: 100)
        let out = IdleDetection.demote([s], now: 130, threshold: 20)   // 30s > 20s
        XCTAssertEqual(out.first?.status, .done)
    }

    func testSilentPostToolUseDemoted() {
        let s = session(.working, event: "PostToolUse", updatedAt: 100)
        let out = IdleDetection.demote([s], now: 130, threshold: 20)
        XCTAssertEqual(out.first?.status, .done)
    }

    func testRecentPostToolUseNotDemoted() {
        // Normal active work: next PreToolUse comes fast, so short silence stays working.
        let s = session(.working, event: "PostToolUse", updatedAt: 100)
        let out = IdleDetection.demote([s], now: 108, threshold: 20)   // 8s < 20s
        XCTAssertEqual(out.first?.status, .working)
    }

    func testPreToolUseNeverDemoted() {
        // PreToolUse is the permission/long-tool signal — excluded here.
        let s = session(.working, event: "PreToolUse", updatedAt: 100)
        let out = IdleDetection.demote([s], now: 200, threshold: 20)
        XCTAssertEqual(out.first?.status, .working)
    }

    func testDoneUntouched() {
        let s = session(.done, event: nil, updatedAt: 100)
        let out = IdleDetection.demote([s], now: 200, threshold: 20)
        XCTAssertEqual(out.first?.status, .done)
    }
}
