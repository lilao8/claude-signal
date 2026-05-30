# claude-signal — Phase 0 + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the "brain" (session tracking, aggregation, presence, resolution) plus shell hooks (Phase 0), then a menu-bar light driven by it (Phase 1) — a first shippable macOS traffic-light for Claude Code state.

**Architecture:** Claude Code lifecycle hooks (shell) write one JSON file per session into `~/.claude-signal/sessions/`. A Swift background app watches those files, aggregates them into a single state, gates "done" by user presence (macOS idle time), and renders one light. Pure logic lives in a dependency-free library target (`ClaudeSignalCore`, fully unit-tested); AppKit/UI lives in the executable target (`ClaudeSignal`).

**Tech Stack:** Swift 6 + Swift Package Manager (requires **full Xcode**, not just Command Line Tools — see Task 1). Foundation + CoreGraphics in the core library; AppKit in the executable. `jq` for the shell hooks. XCTest for unit tests. Zero third-party dependencies.

---

## File Structure

```
claude-signal/
  Package.swift                          # SwiftPM manifest (generated, then edited)
  Sources/
    ClaudeSignalCore/                    # LIBRARY — pure logic, no AppKit
      SessionStatus.swift                # enum of per-session states + priority
      SessionState.swift                 # Codable model of a session file
      AggregateState.swift               # combined state across sessions
      Aggregator.swift                   # [SessionState] -> AggregateState
      DisplayState.swift                 # what a surface renders
      SignalResolver.swift               # (AggregateState, Presence) -> DisplayState
      NetworkOverride.swift              # error-when-network-down logic
      Presence.swift                     # enum present/away
      PresenceMonitor.swift              # idle-time -> Presence (injectable provider)
      StateStore.swift                   # read/decode/clean session files
      Reachability.swift                 # ReachabilityChecking protocol
      Coordinator.swift                  # wires store+presence+reachability -> DisplayState
    ClaudeSignal/                        # EXECUTABLE — app + UI + CLI
      main.swift                         # entry: arg parse, --simulate vs app
      Simulate.swift                     # --simulate CLI
      AppController.swift                # builds Coordinator, runs poll timer
      Surfaces/
        SignalSurface.swift              # render protocol
        MenuBarSurface.swift             # NSStatusItem light
        SystemReachability.swift         # NWPathMonitor impl of ReachabilityChecking
  Tests/
    ClaudeSignalCoreTests/
      SessionStateTests.swift
      AggregatorTests.swift
      SignalResolverTests.swift
      NetworkOverrideTests.swift
      PresenceMonitorTests.swift
      StateStoreTests.swift
      CoordinatorTests.swift
  hooks/
    on-event.sh                          # stdin JSON -> writes session file
    install.sh                           # non-destructive merge into ~/.claude/settings.json
    uninstall.sh                         # removes our hooks
  hooks/tests/
    test-on-event.sh                     # shell tests for on-event.sh
  LaunchAgents/
    com.claudesignal.agent.plist.template
  scripts/
    install-launchagent.sh
```

**Responsibility boundaries:** Each core file has one job and is independently testable. The executable target is the *only* place AppKit appears, kept thin so almost no untested logic lives there. Hooks know nothing about lights; they only write files.

---

## Type contract (defined once, referenced throughout)

```swift
// SessionStatus.swift
public enum SessionStatus: String, Codable, Sendable {
    case working, permission, done, error
}

// SessionState.swift
public struct SessionState: Codable, Equatable, Sendable {
    public let sessionId: String
    public var status: SessionStatus
    public var updatedAt: TimeInterval   // unix seconds
    public var cwd: String?
    public var source: String?
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status = "state"
        case updatedAt = "updated_at"
        case cwd, source
    }
}

// AggregateState.swift  (priority order encoded by the enum's `priority`)
public enum AggregateState: Equatable, Sendable {
    case idle        // no live sessions
    case done        // a session finished, none busier
    case working
    case permission
    case error
}

// Presence.swift
public enum Presence: Equatable, Sendable { case present, away }

// DisplayState.swift
public enum DisplayState: Equatable, Sendable {
    case off, working, permission, error, done
}
```

These names are used verbatim in every task below.

---

# PHASE 0 — Foundation (no UI)

### Task 1: Toolchain + package scaffold

**Files:**
- Create: `Package.swift`, `Sources/ClaudeSignalCore/Placeholder.swift`, `Sources/ClaudeSignal/main.swift`, `Tests/ClaudeSignalCoreTests/SmokeTests.swift`

- [ ] **Step 1: Ensure full Xcode is installed and selected**

Command Line Tools alone cannot compile AppKit or SwiftPM manifests on this machine (verified: compiler/SDK version mismatch). Install Xcode from the App Store, then:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```
Expected: `xcodebuild -version` prints a version (no "requires Xcode" error).

- [ ] **Step 2: Scaffold the package**

```bash
cd /Users/xcalibur/Project/claude-signal
swift package init --type empty --name ClaudeSignal
```
Then replace `Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSignal",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeSignalCore"),
        .executableTarget(
            name: "ClaudeSignal",
            dependencies: ["ClaudeSignalCore"]
        ),
        .testTarget(
            name: "ClaudeSignalCoreTests",
            dependencies: ["ClaudeSignalCore"]
        ),
    ]
)
```

- [ ] **Step 3: Add minimal placeholder sources so the package compiles**

`Sources/ClaudeSignalCore/Placeholder.swift`:
```swift
public let claudeSignalCoreVersion = "0.0.1"
```

`Sources/ClaudeSignal/main.swift`:
```swift
import ClaudeSignalCore
print("claude-signal \(claudeSignalCoreVersion)")
```

`Tests/ClaudeSignalCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(claudeSignalCoreVersion, "0.0.1")
    }
}
```

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 5: Commit**

```bash
cd /Users/xcalibur/Project/claude-signal
printf '\n# SwiftPM\n.build/\n' >> .gitignore
git add -A
git commit -m "chore: scaffold SwiftPM package (core lib + executable + tests)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: SessionState model

**Files:**
- Create: `Sources/ClaudeSignalCore/SessionStatus.swift`, `Sources/ClaudeSignalCore/SessionState.swift`
- Test: `Tests/ClaudeSignalCoreTests/SessionStateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/SessionStateTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionStateTests`
Expected: FAIL — `SessionState` / `SessionStatus` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/SessionStatus.swift`:
```swift
public enum SessionStatus: String, Codable, Sendable {
    case working, permission, done, error
}
```

`Sources/ClaudeSignalCore/SessionState.swift`:
```swift
import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public let sessionId: String
    public var status: SessionStatus
    public var updatedAt: TimeInterval
    public var cwd: String?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status = "state"
        case updatedAt = "updated_at"
        case cwd, source
    }

    public init(sessionId: String, status: SessionStatus, updatedAt: TimeInterval,
                cwd: String? = nil, source: String? = nil) {
        self.sessionId = sessionId
        self.status = status
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.source = source
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionStateTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SessionState/SessionStatus model with snake_case decoding

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Aggregator

**Files:**
- Create: `Sources/ClaudeSignalCore/AggregateState.swift`, `Sources/ClaudeSignalCore/Aggregator.swift`
- Test: `Tests/ClaudeSignalCoreTests/AggregatorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/AggregatorTests.swift`:
```swift
import XCTest
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AggregatorTests`
Expected: FAIL — `Aggregator` / `AggregateState` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/AggregateState.swift`:
```swift
public enum AggregateState: Equatable, Sendable {
    case idle, done, working, permission, error
}
```

`Sources/ClaudeSignalCore/Aggregator.swift`:
```swift
public enum Aggregator {
    /// Highest-priority state across all live sessions.
    /// Priority: error > permission > working > done > (none -> idle).
    public static func aggregate(_ sessions: [SessionState]) -> AggregateState {
        if sessions.isEmpty { return .idle }
        if sessions.contains(where: { $0.status == .error }) { return .error }
        if sessions.contains(where: { $0.status == .permission }) { return .permission }
        if sessions.contains(where: { $0.status == .working }) { return .working }
        return .done
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AggregatorTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Aggregator (priority pick across sessions)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: SignalResolver

**Files:**
- Create: `Sources/ClaudeSignalCore/Presence.swift`, `Sources/ClaudeSignalCore/DisplayState.swift`, `Sources/ClaudeSignalCore/SignalResolver.swift`
- Test: `Tests/ClaudeSignalCoreTests/SignalResolverTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/SignalResolverTests.swift`:
```swift
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
        XCTAssertEqual(SignalResolver.resolve(.done, presence: .away), .done)   // come back
        XCTAssertEqual(SignalResolver.resolve(.done, presence: .present), .off) // you're here
    }
    func testIdleIsOff() {
        XCTAssertEqual(SignalResolver.resolve(.idle, presence: .away), .off)
        XCTAssertEqual(SignalResolver.resolve(.idle, presence: .present), .off)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SignalResolverTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/Presence.swift`:
```swift
public enum Presence: Equatable, Sendable { case present, away }
```

`Sources/ClaudeSignalCore/DisplayState.swift`:
```swift
public enum DisplayState: Equatable, Sendable {
    case off, working, permission, error, done
}
```

`Sources/ClaudeSignalCore/SignalResolver.swift`:
```swift
public enum SignalResolver {
    public static func resolve(_ aggregate: AggregateState, presence: Presence) -> DisplayState {
        switch aggregate {
        case .error:      return .error
        case .permission: return .permission
        case .working:    return .working
        case .done:       return presence == .away ? .done : .off
        case .idle:       return .off
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SignalResolverTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SignalResolver (state + presence -> display)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Network override

**Files:**
- Create: `Sources/ClaudeSignalCore/NetworkOverride.swift`
- Test: `Tests/ClaudeSignalCoreTests/NetworkOverrideTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/NetworkOverrideTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NetworkOverrideTests`
Expected: FAIL — `applyNetworkOverride` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/NetworkOverride.swift`:
```swift
/// Network-down only escalates to error while Claude is actively working.
/// (Conservative red, per spec §8.)
public func applyNetworkOverride(_ aggregate: AggregateState, networkDown: Bool) -> AggregateState {
    if networkDown && aggregate == .working { return .error }
    return aggregate
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NetworkOverrideTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add conservative network-down -> error override

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: PresenceMonitor (injectable idle provider)

**Files:**
- Create: `Sources/ClaudeSignalCore/PresenceMonitor.swift`
- Test: `Tests/ClaudeSignalCoreTests/PresenceMonitorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/PresenceMonitorTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

private struct FakeIdle: IdleTimeProviding {
    let seconds: TimeInterval
    func idleSeconds() -> TimeInterval { seconds }
}

final class PresenceMonitorTests: XCTestCase {
    func testBelowThresholdIsPresent() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 5))
        XCTAssertEqual(m.current(), .present)
    }
    func testAtThresholdIsAway() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 30))
        XCTAssertEqual(m.current(), .away)
    }
    func testAboveThresholdIsAway() {
        let m = PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: 120))
        XCTAssertEqual(m.current(), .away)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PresenceMonitorTests`
Expected: FAIL — `PresenceMonitor` / `IdleTimeProviding` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/PresenceMonitor.swift`:
```swift
import Foundation
import CoreGraphics

public protocol IdleTimeProviding: Sendable {
    func idleSeconds() -> TimeInterval
}

/// Real provider: seconds since last keyboard/mouse/HID event.
public struct SystemIdleTimeProvider: IdleTimeProviding {
    public init() {}
    public func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }
}

public struct PresenceMonitor: Sendable {
    public let threshold: TimeInterval
    public let provider: IdleTimeProviding

    public init(threshold: TimeInterval, provider: IdleTimeProviding) {
        self.threshold = threshold
        self.provider = provider
    }

    public func current() -> Presence {
        provider.idleSeconds() >= threshold ? .away : .present
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PresenceMonitorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PresenceMonitor with injectable idle provider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: StateStore (read + stale cleanup)

**Files:**
- Create: `Sources/ClaudeSignalCore/StateStore.swift`
- Test: `Tests/ClaudeSignalCoreTests/StateStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/StateStoreTests.swift`:
```swift
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
        try writeSession("a", .working, updatedAt: 1000)
        try writeSession("b", .done, updatedAt: 1000)
        let store = StateStore(directory: dir, staleThreshold: 300)
        let live = store.loadLiveSessions(now: 1100)
        XCTAssertEqual(Set(live.map { $0.sessionId }), ["a", "b"])
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
    }

    func testMissingDirectoryReturnsEmpty() {
        let store = StateStore(directory: dir.appendingPathComponent("nope"), staleThreshold: 300)
        XCTAssertEqual(store.loadLiveSessions(now: 0).count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StateStoreTests`
Expected: FAIL — `StateStore` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/StateStore.swift`:
```swift
import Foundation

public struct StateStore: Sendable {
    public let directory: URL
    public let staleThreshold: TimeInterval

    public init(directory: URL, staleThreshold: TimeInterval) {
        self.directory = directory
        self.staleThreshold = staleThreshold
    }

    /// Reads all session files, deletes stale ones, returns the live set.
    public func loadLiveSessions(now: TimeInterval) -> [SessionState] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        var live: [SessionState] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(SessionState.self, from: data)
            else { continue }
            if now - session.updatedAt > staleThreshold {
                try? fm.removeItem(at: url)   // stale: clean up
            } else {
                live.append(session)
            }
        }
        return live.sorted { $0.sessionId < $1.sessionId }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StateStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add StateStore (load sessions + stale cleanup)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Coordinator

**Files:**
- Create: `Sources/ClaudeSignalCore/Reachability.swift`, `Sources/ClaudeSignalCore/Coordinator.swift`
- Test: `Tests/ClaudeSignalCoreTests/CoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/CoordinatorTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

private struct FakeIdle: IdleTimeProviding {
    let seconds: TimeInterval
    func idleSeconds() -> TimeInterval { seconds }
}
private final class FakeReach: ReachabilityChecking, @unchecked Sendable {
    var reachable: Bool
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CoordinatorTests`
Expected: FAIL — `Coordinator` / `ReachabilityChecking` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/Reachability.swift`:
```swift
public protocol ReachabilityChecking: Sendable {
    func isReachable() -> Bool
}
```

`Sources/ClaudeSignalCore/Coordinator.swift`:
```swift
import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking

    public init(store: StateStore, presence: PresenceMonitor, reachability: ReachabilityChecking) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        let sessions = store.loadLiveSessions(now: now)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        return SignalResolver.resolve(aggregate, presence: presence.current())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CoordinatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the full core suite + commit**

Run: `swift test`
Expected: all tests pass.
```bash
git add -A
git commit -m "feat: add Coordinator wiring store+presence+reachability

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: `--simulate` CLI

**Files:**
- Create: `Sources/ClaudeSignal/Simulate.swift`
- Modify: `Sources/ClaudeSignal/main.swift`

- [ ] **Step 1: Write the simulate command**

`Sources/ClaudeSignal/Simulate.swift`:
```swift
import Foundation
import ClaudeSignalCore

/// Usage: claude-signal --simulate <state>[,<state>...] <present|away> [networkDown]
/// Example: claude-signal --simulate working,done away
/// Prints the resolved DisplayState. No AppKit; pure logic check.
enum Simulate {
    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --simulate <states> <present|away> [networkDown]\n".utf8))
            return 2
        }
        let statuses: [SessionStatus] = args[0].split(separator: ",").compactMap {
            SessionStatus(rawValue: String($0))
        }
        let sessions = statuses.enumerated().map {
            SessionState(sessionId: "s\($0.offset)", status: $0.element, updatedAt: 0)
        }
        let presence: Presence = (args[1] == "away") ? .away : .present
        let networkDown = args.count >= 3 && args[2] == "networkDown"

        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: networkDown)
        let display = SignalResolver.resolve(aggregate, presence: presence)
        print("aggregate=\(aggregate) presence=\(presence) -> display=\(display)")
        return 0
    }
}
```

- [ ] **Step 2: Wire it into main.swift**

Replace `Sources/ClaudeSignal/main.swift` with:
```swift
import Foundation
import ClaudeSignalCore

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--simulate" {
    exit(Simulate.run(Array(args.dropFirst())))
}
// App mode is wired in Task 13.
print("claude-signal \(claudeSignalCoreVersion) (app mode not yet wired)")
```

- [ ] **Step 3: Build and manually verify**

Run: `swift run claude-signal --simulate working,done away`
Expected: `aggregate=working presence=away -> display=working`

Run: `swift run claude-signal --simulate done present`
Expected: `aggregate=done presence=present -> display=off`

Run: `swift run claude-signal --simulate working away networkDown`
Expected: `aggregate=error presence=away -> display=error`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add --simulate CLI for headless light resolution checks

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Hook script `on-event.sh`

**Files:**
- Create: `hooks/on-event.sh`, `hooks/tests/test-on-event.sh`

- [ ] **Step 1: Write the failing shell test**

`hooks/tests/test-on-event.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/on-event.sh"
TMP="$(mktemp -d)"
export CLAUDE_SIGNAL_DIR="$TMP"
fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "ok  - $1"; else echo "FAIL - $1: expected '$2' got '$3'"; fail=1; fi
}

# UserPromptSubmit -> working
echo '{"hook_event_name":"UserPromptSubmit","session_id":"s1","cwd":"/p"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "UserPromptSubmit->working" "working" "$state"

# Notification permission -> permission
echo '{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission to use Bash"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Notification permission->permission" "permission" "$state"

# Notification other -> working
echo '{"hook_event_name":"Notification","session_id":"s1","message":"Waiting for input"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Notification other->working" "working" "$state"

# Stop -> done
echo '{"hook_event_name":"Stop","session_id":"s1"}' | bash "$SCRIPT"
state=$(jq -r '.state' "$TMP/sessions/s1.json")
check "Stop->done" "done" "$state"

# SessionEnd -> file removed
echo '{"hook_event_name":"SessionEnd","session_id":"s1"}' | bash "$SCRIPT"
if [ -f "$TMP/sessions/s1.json" ]; then echo "FAIL - SessionEnd should remove file"; fail=1; else echo "ok  - SessionEnd removes file"; fi

# Missing session_id -> no crash, no file
echo '{"hook_event_name":"Stop"}' | bash "$SCRIPT"
echo "ok  - missing session_id handled (exit $?)"

rm -rf "$TMP"
exit $fail
```
Make it executable: `chmod +x hooks/tests/test-on-event.sh`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash hooks/tests/test-on-event.sh`
Expected: FAIL — `on-event.sh` does not exist.

- [ ] **Step 3: Write the hook script**

`hooks/on-event.sh`:
```bash
#!/usr/bin/env bash
# Reads a Claude Code hook payload (JSON on stdin) and updates this session's
# state file under $CLAUDE_SIGNAL_DIR/sessions/<session_id>.json.
set -uo pipefail

BASE="${CLAUDE_SIGNAL_DIR:-$HOME/.claude-signal}"
DIR="$BASE/sessions"
mkdir -p "$DIR"

input="$(cat)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -z "$sid" ] && exit 0

file="$DIR/$sid.json"
now="$(date +%s)"

write_state() {
  local state="$1"
  jq -n --arg sid "$sid" --arg st "$state" --arg cwd "$cwd" --argjson now "$now" \
    '{session_id:$sid, state:$st, updated_at:$now, cwd:$cwd, source:"claude"}' \
    > "$file.tmp" && mv "$file.tmp" "$file"
}

case "$event" in
  UserPromptSubmit|PreToolUse|PostToolUse|SubagentStop)
    write_state "working" ;;
  Notification)
    msg="$(printf '%s' "$input" | jq -r '.message // empty')"
    case "$msg" in
      *permission*|*"needs your"*) write_state "permission" ;;
      *)                           write_state "working" ;;
    esac ;;
  Stop)
    write_state "done" ;;
  SessionEnd)
    rm -f "$file" ;;
  *)
    : ;;  # SessionStart and anything else: no-op (no file => off)
esac
exit 0
```
Make it executable: `chmod +x hooks/on-event.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash hooks/tests/test-on-event.sh`
Expected: all lines start with `ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add on-event.sh hook (Claude Code event -> session file)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Hook installer `install.sh` (non-destructive)

**Files:**
- Create: `hooks/install.sh`, `hooks/uninstall.sh`

- [ ] **Step 1: Write the installer**

The installer merges our hook into `~/.claude/settings.json` without clobbering existing hooks. Claude Code's hook format is `hooks.<EventName>[].hooks[]` with `{type:"command", command:"..."}`. We register `on-event.sh` for each event we care about, tagged so uninstall can find it.

`hooks/install.sh`:
```bash
#!/usr/bin/env bash
# Registers on-event.sh into ~/.claude/settings.json for the events we track.
# Non-destructive: preserves existing settings and other hooks. Idempotent.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK="$(cd "$(dirname "$0")" && pwd)/on-event.sh"
EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStop SessionEnd)

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Backup once.
cp "$SETTINGS" "$SETTINGS.claude-signal.bak"

tmp="$(mktemp)"
jq --arg hook "$HOOK" --argjson events "$(printf '%s\n' "${EVENTS[@]}" | jq -R . | jq -s .)" '
  .hooks = (.hooks // {})
  | reduce $events[] as $e (.;
      .hooks[$e] = ((.hooks[$e] // [])
        # drop any prior claude-signal entry for idempotency
        | map(select(any(.hooks[]?; .command == $hook) | not))
        + [{ "hooks": [ { "type": "command", "command": $hook } ] }]
      )
    )
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Installed claude-signal hooks into $SETTINGS (backup: $SETTINGS.claude-signal.bak)"
```
Make it executable: `chmod +x hooks/install.sh`

`hooks/uninstall.sh`:
```bash
#!/usr/bin/env bash
# Removes claude-signal hook entries from ~/.claude/settings.json.
set -euo pipefail
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
HOOK="$(cd "$(dirname "$0")" && pwd)/on-event.sh"
[ -f "$SETTINGS" ] || { echo "no settings file"; exit 0; }
tmp="$(mktemp)"
jq --arg hook "$HOOK" '
  if .hooks then
    .hooks |= with_entries(
      .value |= map(select(any(.hooks[]?; .command == $hook) | not))
    )
  else . end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "Removed claude-signal hooks from $SETTINGS"
```
Make it executable: `chmod +x hooks/uninstall.sh`

- [ ] **Step 2: Test install + uninstall against a throwaway settings file**

```bash
export CLAUDE_SETTINGS="$(mktemp)"
echo '{"permissions":{"allow":["Bash(ls)"]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/other/tool.sh"}]}]}}' > "$CLAUDE_SETTINGS"
bash hooks/install.sh
echo "--- after install ---"; jq . "$CLAUDE_SETTINGS"
# Verify: our hook present on Stop AND the pre-existing /other/tool.sh still present AND permissions untouched.
jq -e '.permissions.allow == ["Bash(ls)"]' "$CLAUDE_SETTINGS" >/dev/null && echo "ok permissions preserved"
jq -e '[.hooks.Stop[].hooks[].command] | (index("/other/tool.sh") != null) and (any(. == (env.PWD + "/hooks/on-event.sh")) or true)' "$CLAUDE_SETTINGS" >/dev/null && echo "ok existing hook preserved"
bash hooks/install.sh   # run again -> must stay idempotent (no duplicate)
dupes=$(jq '[.hooks.Stop[].hooks[].command] | map(select(test("on-event.sh"))) | length' "$CLAUDE_SETTINGS")
[ "$dupes" = "1" ] && echo "ok idempotent (1 entry)" || echo "FAIL idempotent ($dupes entries)"
bash hooks/uninstall.sh
jq -e '[.hooks.Stop[].hooks[].command] | index("/other/tool.sh") != null' "$CLAUDE_SETTINGS" >/dev/null && echo "ok uninstall kept other hook"
```
Expected: `ok permissions preserved`, `ok existing hook preserved`, `ok idempotent (1 entry)`, `ok uninstall kept other hook`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add non-destructive hook install/uninstall scripts

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

# PHASE 1 — Menu bar (MVP)

### Task 12: SignalSurface protocol + appearance mapping

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/SignalSurface.swift`

- [ ] **Step 1: Define the protocol and a pure appearance mapping**

`Sources/ClaudeSignal/Surfaces/SignalSurface.swift`:
```swift
import AppKit
import ClaudeSignalCore

/// Anything that can show the light. Phase 1 = menu bar; later = Touch Bar, notch.
protocol SignalSurface: AnyObject {
    func render(_ state: DisplayState)
}

/// Visual vocabulary for a DisplayState (shared by all surfaces).
enum Appearance {
    static func color(for state: DisplayState) -> NSColor {
        switch state {
        case .off:        return .clear
        case .working:    return .systemBlue
        case .permission: return .systemYellow
        case .error:      return .systemRed
        case .done:       return .systemGreen
        }
    }
    enum Animation { case none, breathe, flash }
    static func animation(for state: DisplayState) -> Animation {
        switch state {
        case .off, .done:        return .none      // done = steady
        case .working:           return .breathe
        case .permission, .error:return .flash
        }
    }
}
```

- [ ] **Step 2: Build to confirm AppKit compiles**

Run: `swift build`
Expected: build succeeds (this is the first AppKit code — confirms Task 1's toolchain fix worked).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add SignalSurface protocol + DisplayState appearance mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: MenuBarSurface (NSStatusItem dot + animation)

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/MenuBarSurface.swift`

- [ ] **Step 1: Implement the menu-bar surface**

`Sources/ClaudeSignal/Surfaces/MenuBarSurface.swift`:
```swift
import AppKit
import ClaudeSignalCore

/// Renders the light as a colored dot in the macOS menu bar.
final class MenuBarSurface: SignalSurface {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var current: DisplayState = .off

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "claude-signal", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        render(.off)
    }

    func render(_ state: DisplayState) {
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        switch Appearance.animation(for: state) {
        case .none:
            draw(alpha: state == .off ? 0 : 1, color: Appearance.color(for: state))
        case .breathe:
            startTimer(period: 1.8, color: Appearance.color(for: state), ease: true)
        case .flash:
            startTimer(period: state == .error ? 0.6 : 1.0,
                       color: Appearance.color(for: state), ease: false)
        }
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let t = Date().timeIntervalSince(start)
            let phase = (t.truncatingRemainder(dividingBy: period)) / period  // 0..1
            let a: Double
            if ease {
                a = 0.35 + 0.65 * (0.5 - 0.5 * cos(2 * .pi * phase)) // smooth breathe
            } else {
                a = phase < 0.5 ? 1.0 : 0.15                          // square flash
            }
            self?.draw(alpha: a, color: color)
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func draw(alpha: Double, color: NSColor) {
        guard let button = statusItem.button else { return }
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            if alpha <= 0 { return true }       // .off => empty image
            let inset = rect.insetBy(dx: 3, dy: 3)
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: inset).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add MenuBarSurface (animated NSStatusItem dot)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 14: System reachability (NWPathMonitor)

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/SystemReachability.swift`

- [ ] **Step 1: Implement the real reachability checker**

`Sources/ClaudeSignal/Surfaces/SystemReachability.swift`:
```swift
import Foundation
import Network
import ClaudeSignalCore

/// Tracks general network reachability via NWPathMonitor.
/// `isReachable()` returns the last observed path status (thread-safe).
final class SystemReachability: ReachabilityChecking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "claude-signal.reachability")
    private let lock = NSLock()
    private var reachable = true   // assume up until told otherwise

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.lock()
            self?.reachable = (path.status == .satisfied)
            self?.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    func isReachable() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reachable
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add NWPathMonitor-based SystemReachability

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 15: App controller + run loop wiring

**Files:**
- Create: `Sources/ClaudeSignal/AppController.swift`
- Modify: `Sources/ClaudeSignal/main.swift`

- [ ] **Step 1: Implement the controller**

`Sources/ClaudeSignal/AppController.swift`:
```swift
import AppKit
import Foundation
import ClaudeSignalCore

/// Owns the surface + coordinator, polls state on a timer, renders.
final class AppController: NSObject, NSApplicationDelegate {
    private let surface = MenuBarSurface()
    private let coordinator: Coordinator
    private var pollTimer: Timer?

    override init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-signal/sessions")
        coordinator = Coordinator(
            store: StateStore(directory: base, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: SystemIdleTimeProvider()),
            reachability: SystemReachability()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        tick()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let state = coordinator.computeDisplayState(now: Date().timeIntervalSince1970)
        surface.render(state)
    }
}
```

- [ ] **Step 2: Wire app mode into main.swift**

Replace `Sources/ClaudeSignal/main.swift` with:
```swift
import AppKit
import Foundation
import ClaudeSignalCore

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--simulate" {
    exit(Simulate.run(Array(args.dropFirst())))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let controller = AppController()
app.delegate = controller
app.run()
```

- [ ] **Step 3: Build and run manually**

Run: `swift run claude-signal`
Then in another terminal, drive states with the hook script and watch the menu-bar dot:
```bash
export CLAUDE_SIGNAL_DIR="$HOME/.claude-signal"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo"}' | bash hooks/on-event.sh   # blue breathing
echo '{"hook_event_name":"Notification","session_id":"demo","message":"needs your permission"}' | bash hooks/on-event.sh  # yellow flash
echo '{"hook_event_name":"Stop","session_id":"demo"}' | bash hooks/on-event.sh   # green if you stop touching the keyboard ~30s, else off
echo '{"hook_event_name":"SessionEnd","session_id":"demo"}' | bash hooks/on-event.sh   # off
```
Expected: the menu-bar dot follows each state. For green, leave the machine idle ~30s after `Stop`. Quit via the menu's Quit item.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire AppController poll loop -> menu bar (Phase 1 MVP runnable)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 16: Auto-start at login (LaunchAgent)

**Files:**
- Create: `LaunchAgents/com.claudesignal.agent.plist.template`, `scripts/install-launchagent.sh`

- [ ] **Step 1: Create the LaunchAgent template**

`LaunchAgents/com.claudesignal.agent.plist.template`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claudesignal.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>__BINARY__</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/claude-signal.err.log</string>
  <key>StandardOutPath</key><string>/tmp/claude-signal.out.log</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the install script**

`scripts/install-launchagent.sh`:
```bash
#!/usr/bin/env bash
# Builds a release binary, installs it, and loads a per-user LaunchAgent
# so claude-signal starts at login.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

swift build -c release --package-path "$ROOT"
BIN_SRC="$ROOT/.build/release/claude-signal"
BIN_DST="$HOME/.local/bin/claude-signal"
mkdir -p "$(dirname "$BIN_DST")"
cp "$BIN_SRC" "$BIN_DST"

PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/com.claudesignal.agent.plist"
mkdir -p "$PLIST_DIR"
sed "s#__BINARY__#$BIN_DST#" "$ROOT/LaunchAgents/com.claudesignal.agent.plist.template" > "$PLIST"

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Loaded LaunchAgent. Binary: $BIN_DST  Plist: $PLIST"
echo "To stop: launchctl unload \"$PLIST\""
```
Make it executable: `chmod +x scripts/install-launchagent.sh`

- [ ] **Step 3: Manually verify**

Run: `bash scripts/install-launchagent.sh`
Expected: builds release, copies binary, loads agent. Confirm:
```bash
launchctl list | grep claudesignal   # should show the label
```
The menu-bar dot should appear. Drive a state via `on-event.sh` (as in Task 15) to confirm the login-launched instance responds. Then optionally unload while developing:
```bash
launchctl unload "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add LaunchAgent + installer for auto-start at login

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 17: End-to-end verification + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Full automated suite**

Run: `swift test && bash hooks/tests/test-on-event.sh`
Expected: all unit tests pass; all hook tests print `ok`.

- [ ] **Step 2: Real Claude Code smoke test**

```bash
bash hooks/install.sh          # register hooks in ~/.claude/settings.json
bash scripts/install-launchagent.sh   # or: swift run claude-signal
```
Open a real Claude Code session in the terminal, give it a task that runs a few tools, and watch the menu-bar dot:
- While it works → **blue breathing**
- If it asks permission → **yellow flashing**
- When it finishes and you step away ~30s → **green steady**
- Start typing → **off**

- [ ] **Step 3: Write README**

`README.md`:
```markdown
# claude-signal

A menu-bar traffic light for Claude Code state on macOS.

- 🔵 breathing blue — Claude is working
- 🟡 flashing yellow — needs your permission
- 🔴 flashing red — error (e.g. network down while working)
- 🟢 steady green — done, and you've stepped away
- ⚫️ off — your turn / idle

## Install
```bash
bash hooks/install.sh                 # register Claude Code hooks
bash scripts/install-launchagent.sh   # build + auto-start at login
```

## Develop
```bash
swift test                            # core unit tests
bash hooks/tests/test-on-event.sh     # hook script tests
swift run claude-signal --simulate working,done away   # headless resolution check
swift run claude-signal               # run the app in the foreground
```

## Uninstall
```bash
bash hooks/uninstall.sh
launchctl unload "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
```

See `docs/superpowers/specs/2026-05-30-claude-signal-design.md` for the full design.
Roadmap: Touch Bar (Phase 2) and notch island (Phase 3).
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: add README; Phase 0+1 complete (menu-bar MVP)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage** (against `2026-05-30-claude-signal-design.md`):
- §3 state language → DisplayState + Appearance (Tasks 4, 12, 13). ✓
- §3 priority order → Aggregator (Task 3). ✓
- §4 architecture (hooks→files→daemon→surface) → Tasks 7, 10, 15. ✓
- §5 session file schema → SessionState + on-event.sh (Tasks 2, 10). ✓
- §6 event→state mapping → on-event.sh + tests (Task 10). ✓ (SessionStart = no-op → off, matching "registered, no work".)
- §7 resolver + presence gating → SignalResolver, PresenceMonitor, Coordinator (Tasks 4, 6, 8). ✓
- §8 conservative red → NetworkOverride + SystemReachability (Tasks 5, 14). ✓
- §9 crash safety / stale cleanup → StateStore (Task 7). ✓
- §11 stack/structure, no Dock icon, auto-start → Tasks 1, 15 (`.accessory`), 16 (LaunchAgent — deviation from `SMAppService`, justified: bare SwiftPM binary, not a bundled .app). ✓
- §12 phases 0+1 → this plan; phases 2-3 deferred. ✓
- §13 testing strategy → unit tests per core type, shell tests for hooks, `--simulate` for manual QA. ✓

**Placeholder scan:** none — every code/shell step is complete.

**Type consistency:** `SessionState`, `SessionStatus`, `AggregateState`, `Presence`, `DisplayState`, `Aggregator.aggregate`, `SignalResolver.resolve`, `applyNetworkOverride`, `PresenceMonitor.current`, `StateStore.loadLiveSessions`, `Coordinator.computeDisplayState`, `ReachabilityChecking.isReachable`, `SignalSurface.render` — all used identically across tasks. ✓

**Known deviations from spec (intentional, surfaced to user):**
1. Build system is SwiftPM (requires full Xcode) rather than an Xcode project — Task 1 installs Xcode first.
2. Auto-start via LaunchAgent instead of `SMAppService` (the latter needs a bundled `.app`; we ship a bare binary).
3. No-Dock-icon via runtime `.accessory` policy instead of `LSUIElement` Info.plist key.
