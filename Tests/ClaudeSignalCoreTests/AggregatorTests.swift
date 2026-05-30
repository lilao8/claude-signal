import XCTest
import Foundation
@testable import ClaudeSignalCore

final class AggregatorTests: XCTestCase {
    private func session(_ status: SessionStatus) -> SessionState {
        SessionState(sessionId: UUID().uuidString, status: status, updatedAt: 0)
    }

    func testEmptyIsIdle() {
        XCTAssertEqual(Aggregator.aggregate([]), .idle)
    }
    func testSingleWorking() {
        XCTAssertEqual(Aggregator.aggregate([session(.working)]), .working)
    }
    func testSingleDone() {
        XCTAssertEqual(Aggregator.aggregate([session(.done)]), .done)
    }
    func testErrorBeatsEverything() {
        let r = Aggregator.aggregate([session(.done), session(.working), session(.permission), session(.error)])
        XCTAssertEqual(r, .error)
    }
    func testPermissionBeatsWorkingAndDone() {
        XCTAssertEqual(Aggregator.aggregate([session(.done), session(.working), session(.permission)]), .permission)
    }
    func testWorkingBeatsDone() {
        XCTAssertEqual(Aggregator.aggregate([session(.done), session(.working)]), .working)
    }
}
