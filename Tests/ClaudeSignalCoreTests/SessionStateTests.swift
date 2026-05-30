import XCTest
@testable import ClaudeSignalCore

final class SessionStateTests: XCTestCase {
    func testDecodesSnakeCaseJSON() throws {
        let json = #"""
        {"session_id":"abc123","state":"working","updated_at":1780150000,"cwd":"/p","source":"claude"}
        """#.data(using: .utf8)!
        let s = try JSONDecoder().decode(SessionState.self, from: json)
        XCTAssertEqual(s.sessionId, "abc123")
        XCTAssertEqual(s.status, .working)
        XCTAssertEqual(s.updatedAt, 1780150000)
        XCTAssertEqual(s.cwd, "/p")
        XCTAssertEqual(s.source, "claude")
    }

    func testDecodesWithoutOptionalFields() throws {
        let json = #"{"session_id":"x","state":"done","updated_at":1}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(SessionState.self, from: json)
        XCTAssertEqual(s.status, .done)
        XCTAssertNil(s.cwd)
    }

    func testUnknownStateFailsToDecode() {
        let json = #"{"session_id":"x","state":"bogus","updated_at":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(SessionState.self, from: json))
    }
}
