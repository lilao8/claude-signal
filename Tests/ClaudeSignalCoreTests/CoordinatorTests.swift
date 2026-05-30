import XCTest
@testable import ClaudeSignalCore

private struct FakeIdle: IdleTimeProviding {
    let seconds: TimeInterval
    func idleSeconds() -> TimeInterval { seconds }
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

    private func makeCoordinator(idle: TimeInterval, reachable: Bool) -> Coordinator {
        Coordinator(
            store: StateStore(directory: dir, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: idle)),
            reachability: FakeReach(reachable)
        )
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
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .off)
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
}
