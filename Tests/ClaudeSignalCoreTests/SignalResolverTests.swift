import XCTest
@testable import ClaudeSignalCore

final class SignalResolverTests: XCTestCase {
    func testErrorAlwaysShown() {
        XCTAssertEqual(SignalResolver.resolve(.error, presence: .present), .error)
        XCTAssertEqual(SignalResolver.resolve(.error, presence: .away), .error)
    }
    func testPermissionAlwaysShown() {
        XCTAssertEqual(SignalResolver.resolve(.permission, presence: .present), .permission)
        XCTAssertEqual(SignalResolver.resolve(.permission, presence: .away), .permission)
    }
    func testWorkingAlwaysShown() {
        XCTAssertEqual(SignalResolver.resolve(.working, presence: .present), .working)
        XCTAssertEqual(SignalResolver.resolve(.working, presence: .away), .working)
    }
    func testDoneGatedByPresence() {
        XCTAssertEqual(SignalResolver.resolve(.done, presence: .away), .done)
        XCTAssertEqual(SignalResolver.resolve(.done, presence: .present), .off)
    }
    func testIdleIsOff() {
        XCTAssertEqual(SignalResolver.resolve(.idle, presence: .away), .off)
        XCTAssertEqual(SignalResolver.resolve(.idle, presence: .present), .off)
    }
}
