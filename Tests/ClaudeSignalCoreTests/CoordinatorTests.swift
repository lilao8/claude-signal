import XCTest
@testable import ClaudeSignalCore

private struct FakeIdle: IdleTimeProviding {
    let seconds: TimeInterval
    func idleSeconds() -> TimeInterval { seconds }
}
private struct AlwaysAlive: ProcessLivenessChecking {
    func isAlive(_ pid: Int32) -> Bool { true }
}
private struct FakeReach: ReachabilityChecking {
    let reachable: Bool
    init(_ r: Bool) { reachable = r }
    func isReachable() -> Bool { reachable }
}

final class CoordinatorTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("cs-co-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(_ id: String, _ status: SessionStatus, _ at: TimeInterval) throws {
        let data = try JSONEncoder().encode(SessionState(sessionId: id, status: status, updatedAt: at))
        try data.write(to: dir.appendingPathComponent("\(id).json"))
    }

    private func writeWithPid(_ id: String, _ status: SessionStatus, _ at: TimeInterval, pid: Int32) throws {
        let data = try JSONEncoder().encode(SessionState(sessionId: id, status: status, updatedAt: at, pid: pid))
        try data.write(to: dir.appendingPathComponent("\(id).json"))
    }

    private func makeCoordinator(idle: TimeInterval, reachable: Bool) -> Coordinator {
        Coordinator(
            store: StateStore(directory: dir, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: idle)),
            reachability: FakeReach(reachable),
            rateLimitStore: RateLimitStore(fileURL: dir.appendingPathComponent("ratelimit.json"))
        )
    }

    private func writeRateLimit(resetAt: TimeInterval) throws {
        let f = dir.appendingPathComponent("ratelimit.json")
        let data = try JSONEncoder().encode(RateLimitState(resetAt: resetAt))
        try data.write(to: f)
    }

    func testWorkingPresentShowsWorking() throws {
        try write("a", .working, 1000)
        let c = makeCoordinator(idle: 5, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .working)
    }
    func testDoneAwayShowsDone() throws {
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 99, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .done)
    }
    func testDonePresentShowsOff() throws {
        // Past the fresh-done flash window, present (and input since it finished) → off.
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1010), .off)
    }
    func testJustFinishedFlashesGreenWhilePresent() throws {
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 0, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1002), .done)
    }
    func testSeenDoneStaysOffWhenYouLeaveAgain() throws {
        // Finished at 1000; you typed at 1050 (seen); now away since then → still off.
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 60, reachable: true)   // last input = 1110 - 60 = 1050
        XCTAssertEqual(c.computeDisplayState(now: 1110), .off)
    }
    func testUnseenDoneStaysGreenLongAfter() throws {
        // Finished at 1000, no input since (away 2h): still green — no 5-minute expiry.
        let c = Coordinator(
            store: StateStore(directory: dir, staleThreshold: 300, liveness: AlwaysAlive()),
            presence: PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 7300)),
            reachability: FakeReach(true),
            rateLimitStore: RateLimitStore(fileURL: dir.appendingPathComponent("ratelimit.json"))
        )
        try writeWithPid("a", .done, 1000, pid: 42)
        XCTAssertEqual(c.computeDisplayState(now: 8200), .done)
    }
    func testNetworkDownWhileWorkingShowsError() throws {
        try write("a", .working, 1000)
        let c = makeCoordinator(idle: 1, reachable: false)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .error)
    }
    func testNoSessionsShowsOff() {
        let c = makeCoordinator(idle: 1, reachable: false)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .off)
    }
    func testPermissionShownEvenWhenNetworkDown() throws {
        try write("a", .permission, 1000)
        let c = makeCoordinator(idle: 1, reachable: false) // network down, but permission != working
        XCTAssertEqual(c.computeDisplayState(now: 1000), .permission)
    }

    func testActiveRateLimitForcesErrorEvenWhenWorking() throws {
        try write("a", .working, 1000)
        try writeRateLimit(resetAt: 2000)              // active: now 1000 < 2000
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .error)
    }

    func testActiveRateLimitForcesErrorEvenWhenPermission() throws {
        try write("a", .permission, 1000)
        try writeRateLimit(resetAt: 2000)
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .error)
    }

    func testExpiredRateLimitDoesNotForceError() throws {
        try write("a", .working, 1000)
        try writeRateLimit(resetAt: 1000)              // expired: now 1000 >= 1000
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .working)
    }

    func testNoRateLimitFileBehavesAsBefore() throws {
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 99, reachable: true)   // away → done shows
        XCTAssertEqual(c.computeDisplayState(now: 1000), .done)
    }
}
