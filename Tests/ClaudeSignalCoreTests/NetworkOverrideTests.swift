import XCTest
@testable import ClaudeSignalCore

final class NetworkOverrideTests: XCTestCase {
    func testDownWhileWorkingBecomesError() {
        XCTAssertEqual(applyNetworkOverride(.working, networkDown: true), .error)
    }
    func testDownWhileIdleStaysIdle() {
        XCTAssertEqual(applyNetworkOverride(.idle, networkDown: true), .idle)
    }
    func testDownWhileDoneStaysDone() {
        XCTAssertEqual(applyNetworkOverride(.done, networkDown: true), .done)
    }
    func testUpNeverChanges() {
        XCTAssertEqual(applyNetworkOverride(.working, networkDown: false), .working)
        XCTAssertEqual(applyNetworkOverride(.permission, networkDown: false), .permission)
    }
}
