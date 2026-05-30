import XCTest
@testable import ClaudeSignalCore

final class StateStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cs-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeSession(_ id: String, _ status: SessionStatus, updatedAt: TimeInterval) throws {
        let s = SessionState(sessionId: id, status: status, updatedAt: updatedAt)
        let data = try JSONEncoder().encode(s)
        try data.write(to: dir.appendingPathComponent("\(id).json"))
    }

    func testLoadsLiveSessions() throws {
        // write out of order to prove the result is sorted by sessionId
        try writeSession("b", .done, updatedAt: 1000)
        try writeSession("a", .working, updatedAt: 1000)
        let store = StateStore(directory: dir, staleThreshold: 300)
        let live = store.loadLiveSessions(now: 1100)
        XCTAssertEqual(live.map { $0.sessionId }, ["a", "b"])
    }

    func testDropsAndDeletesStale() throws {
        try writeSession("old", .working, updatedAt: 1000)
        try writeSession("fresh", .working, updatedAt: 1400)
        let store = StateStore(directory: dir, staleThreshold: 300)
        let live = store.loadLiveSessions(now: 1500) // old is 500s stale > 300
        XCTAssertEqual(live.map { $0.sessionId }, ["fresh"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("old.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("fresh.json").path))
    }

    func testSkipsCorruptFiles() throws {
        try "not json".data(using: .utf8)!.write(to: dir.appendingPathComponent("junk.json"))
        try writeSession("ok", .working, updatedAt: 1000)
        let store = StateStore(directory: dir, staleThreshold: 300)
        let live = store.loadLiveSessions(now: 1000)
        XCTAssertEqual(live.map { $0.sessionId }, ["ok"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("junk.json").path))
    }

    func testMissingDirectoryReturnsEmpty() {
        let store = StateStore(directory: dir.appendingPathComponent("nope"), staleThreshold: 300)
        XCTAssertEqual(store.loadLiveSessions(now: 0).count, 0)
    }
}
