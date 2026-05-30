import XCTest
@testable import ClaudeSignalCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(claudeSignalCoreVersion, "0.0.1")
    }
}
