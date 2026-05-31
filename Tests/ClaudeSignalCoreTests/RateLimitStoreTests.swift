import XCTest
@testable import ClaudeSignalCore

final class RateLimitStoreTests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cs-rl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("ratelimit.json")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(resetAt: TimeInterval, raw: String? = nil) throws {
        let data = try JSONEncoder().encode(RateLimitState(resetAt: resetAt, raw: raw))
        try data.write(to: file)
    }

    func testMissingFileReturnsNil() {
        let store = RateLimitStore(fileURL: file)
        XCTAssertNil(store.read(now: 1000))
    }

    func testActiveReturnsState() throws {
        try write(resetAt: 2000, raw: "resets 1:10am (America/Toronto)")
        let store = RateLimitStore(fileURL: file)
        let s = store.read(now: 1000)
        XCTAssertEqual(s?.resetAt, 2000)
        XCTAssertEqual(s?.raw, "resets 1:10am (America/Toronto)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testExpiredReturnsNilAndDeletesFile() throws {
        try write(resetAt: 1000)
        let store = RateLimitStore(fileURL: file)
        XCTAssertNil(store.read(now: 1000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCorruptFileReturnsNil() throws {
        try "not json".data(using: .utf8)!.write(to: file)
        let store = RateLimitStore(fileURL: file)
        XCTAssertNil(store.read(now: 1000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))  // corrupt file preserved, not deleted
    }
}
