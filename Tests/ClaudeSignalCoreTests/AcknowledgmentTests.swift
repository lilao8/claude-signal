import XCTest
@testable import ClaudeSignalCore

final class AcknowledgmentTests: XCTestCase {
    private func s(_ status: SessionStatus, _ at: TimeInterval) -> SessionState {
        SessionState(sessionId: "s", status: status, updatedAt: at)
    }

    func testDoneDroppedOnceInputAfterGrace() {
        XCTAssertTrue(Acknowledgment.dropSeen([s(.done, 100)], lastInputAt: 110).isEmpty)
    }
    func testDoneKeptWithoutInputSince() {
        XCTAssertEqual(Acknowledgment.dropSeen([s(.done, 100)], lastInputAt: 90).count, 1)
    }
    func testErrorHasLongerGrace() {
        XCTAssertEqual(Acknowledgment.dropSeen([s(.error, 100)], lastInputAt: 105).count, 1)
        XCTAssertTrue(Acknowledgment.dropSeen([s(.error, 100)], lastInputAt: 111).isEmpty)
    }
    func testWorkingAndPermissionNeverDropped() {
        XCTAssertEqual(Acknowledgment.dropSeen([s(.working, 100), s(.permission, 100)],
                                               lastInputAt: 999).count, 2)
    }
    func testFreshDoneWindow() {
        XCTAssertTrue(Acknowledgment.hasFreshDone([s(.done, 100)], now: 103))
        XCTAssertFalse(Acknowledgment.hasFreshDone([s(.done, 100)], now: 105))
        XCTAssertFalse(Acknowledgment.hasFreshDone([s(.working, 100)], now: 101))
    }
}
