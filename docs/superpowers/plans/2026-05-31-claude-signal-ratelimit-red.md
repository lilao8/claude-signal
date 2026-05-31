# claude-signal — Usage-Limit Red Light Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new trigger to the existing red light: when Claude Code hits a usage limit (`StopFailure`/`rate_limit`), show red until either the parsed reset time passes or normal Claude activity resumes.

**Architecture:** A standalone account-level `~/.claude-signal/ratelimit.json` (written by the hook, independent of per-session files and their 5-minute stale cleanup) carries a `reset_at` timestamp. A new pure `applyRateLimitOverride` function forces the aggregate to `.error` while the limit is active; a new `RateLimitStore` reads the file and self-cleans it once expired. The hook parses the reset time from the `StopFailure` payload's `last_assistant_message` and deletes the file on any normal activity. No new color — reuses the existing `.error` → red-flash rendering across both surfaces.

**Tech Stack:** Swift 6 + SwiftPM (full Xcode), AppKit, `jq` + macOS `date` (TZ-aware parsing) in the hook, XCTest. Spec: `docs/superpowers/specs/2026-05-31-claude-signal-ratelimit-red-design.md`. Verified payload data: `~/Project/claude-signal-touchbar-spike/RATELIMIT-FINDING.md`.

---

## Verified payload (basis for Tasks 4–5)

```json
{
  "hook_event_name": "StopFailure",
  "error": "rate_limit",
  "last_assistant_message": "You've hit your session limit · resets 1:10am (America/Toronto)"
}
```
- Trigger only when `error == "rate_limit"` (other errors ignored).
- Reset time: clock + IANA tz, NO date: `resets 1:10am (America/Toronto)`. Resolve to the **next** occurrence of that clock time in that tz.

---

## File Structure

```
New (core, pure, unit-tested):
  Sources/ClaudeSignalCore/RateLimitState.swift      # struct { resetAt: TimeInterval; raw: String? }
  Sources/ClaudeSignalCore/RateLimitOverride.swift   # applyRateLimitOverride(...) pure fn
  Sources/ClaudeSignalCore/RateLimitStore.swift      # read single file + expiry self-delete + tolerant
  Tests/ClaudeSignalCoreTests/RateLimitOverrideTests.swift
  Tests/ClaudeSignalCoreTests/RateLimitStoreTests.swift

Modified:
  Sources/ClaudeSignalCore/Coordinator.swift         # +rateLimitStore param, +1 pipeline line
  Sources/ClaudeSignal/AppController.swift            # construct + inject RateLimitStore
  hooks/on-event.sh                                   # StopFailure handling + delete-on-activity
  hooks/tests/test-on-event.sh                        # shell tests: hit / parse / extinguish / non-rate_limit
  hooks/install.sh                                    # add StopFailure to EVENTS
  README.md                                           # note usage-limit also triggers red
```

**Boundaries:** `RateLimitState`/`RateLimitOverride`/`RateLimitStore` mirror the existing `SessionState`/`applyNetworkOverride`/`StateStore` trio — pure logic, no AppKit, each one job. `Coordinator` gains exactly one collaborator and one pipeline line, symmetric with the existing `applyNetworkOverride` line. The hook is the only place that parses Claude's message text.

---

## Type contract (used verbatim across tasks)

```swift
// RateLimitState.swift
public struct RateLimitState: Codable, Equatable, Sendable {
    public let resetAt: TimeInterval   // unix seconds; .infinity for the no-parse fallback
    public let raw: String?
    enum CodingKeys: String, CodingKey { case resetAt = "reset_at"; case raw }
    public init(resetAt: TimeInterval, raw: String? = nil) { self.resetAt = resetAt; self.raw = raw }
}

// RateLimitOverride.swift
public func applyRateLimitOverride(_ aggregate: AggregateState,
                                   rateLimit: RateLimitState?,
                                   now: TimeInterval) -> AggregateState

// RateLimitStore.swift
public struct RateLimitStore: Sendable {
    public init(fileURL: URL)
    public func read(now: TimeInterval) -> RateLimitState?
}
```

The hook writes `~/.claude-signal/ratelimit.json` as `{ "reset_at": <number>, "raw": "<string>" }`.
JSON note: `.infinity` cannot be encoded as JSON by the hook; the fallback (no parse) is written
as a very large sentinel `"reset_at": 99999999999` (year 5138) — far enough out to act as "until
activity clears it". `RateLimitState` decodes it as an ordinary large `TimeInterval`. (We do NOT
rely on Swift's `.infinity` on the wire.)

---

### Task 1: `RateLimitState` model (pure, TDD)

**Files:**
- Create: `Sources/ClaudeSignalCore/RateLimitState.swift`
- Test: `Tests/ClaudeSignalCoreTests/RateLimitStateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/RateLimitStateTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

final class RateLimitStateTests: XCTestCase {
    func testDecodesSnakeCaseJSON() throws {
        let json = #"{"reset_at":1780200000,"raw":"resets 1:10am (America/Toronto)"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 1780200000)
        XCTAssertEqual(s.raw, "resets 1:10am (America/Toronto)")
    }

    func testDecodesWithoutRaw() throws {
        let json = #"{"reset_at":1780200000}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 1780200000)
        XCTAssertNil(s.raw)
    }

    func testLargeSentinelDecodes() throws {
        let json = #"{"reset_at":99999999999}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(RateLimitState.self, from: json)
        XCTAssertEqual(s.resetAt, 99999999999)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/xcalibur/Project/claude-signal && swift test --filter RateLimitStateTests`
Expected: FAIL — `RateLimitState` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/RateLimitState.swift`:
```swift
import Foundation

/// Account-level usage-limit state. `resetAt` is unix seconds; the hook writes a very
/// large sentinel (~year 5138) when it can't parse a reset time, so the red stays on
/// until normal activity deletes the file.
public struct RateLimitState: Codable, Equatable, Sendable {
    public let resetAt: TimeInterval
    public let raw: String?

    enum CodingKeys: String, CodingKey {
        case resetAt = "reset_at"
        case raw
    }

    public init(resetAt: TimeInterval, raw: String? = nil) {
        self.resetAt = resetAt
        self.raw = raw
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RateLimitStateTests`
Expected: PASS (3 tests). Then `swift test` → all pass (was 37, now 40).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add RateLimitState model (account-level usage-limit state)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `applyRateLimitOverride` (pure, TDD)

**Files:**
- Create: `Sources/ClaudeSignalCore/RateLimitOverride.swift`
- Test: `Tests/ClaudeSignalCoreTests/RateLimitOverrideTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/RateLimitOverrideTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

final class RateLimitOverrideTests: XCTestCase {
    func testActiveLimitForcesError() {
        let rl = RateLimitState(resetAt: 2000)
        // now (1000) < resetAt (2000) → active → error, regardless of base aggregate
        XCTAssertEqual(applyRateLimitOverride(.idle, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.done, rateLimit: rl, now: 1000), .error)
        XCTAssertEqual(applyRateLimitOverride(.permission, rateLimit: rl, now: 1000), .error)
    }

    func testExpiredLimitPassesThrough() {
        let rl = RateLimitState(resetAt: 1000)
        // now (1000) >= resetAt (1000) → expired → pass through unchanged
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1000), .working)
        XCTAssertEqual(applyRateLimitOverride(.idle, rateLimit: rl, now: 1500), .idle)
    }

    func testNilPassesThrough() {
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: nil, now: 1000), .working)
        XCTAssertEqual(applyRateLimitOverride(.done, rateLimit: nil, now: 1000), .done)
    }

    func testSentinelFallbackStaysActive() {
        let rl = RateLimitState(resetAt: 99999999999)  // no-parse fallback
        XCTAssertEqual(applyRateLimitOverride(.working, rateLimit: rl, now: 1780200000), .error)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RateLimitOverrideTests`
Expected: FAIL — `applyRateLimitOverride` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/RateLimitOverride.swift`:
```swift
import Foundation

/// While an account-level usage limit is active (now < resetAt), force the light to error
/// (red). Symmetric with `applyNetworkOverride`. Expired or absent limits pass through.
public func applyRateLimitOverride(_ aggregate: AggregateState,
                                   rateLimit: RateLimitState?,
                                   now: TimeInterval) -> AggregateState {
    if let rl = rateLimit, now < rl.resetAt { return .error }
    return aggregate
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RateLimitOverrideTests`
Expected: PASS (4 tests). Then `swift test` → all pass (43 total).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add applyRateLimitOverride (usage-limit -> red, symmetric with network override)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `RateLimitStore` (read + expiry self-delete + tolerant)

**Files:**
- Create: `Sources/ClaudeSignalCore/RateLimitStore.swift`
- Test: `Tests/ClaudeSignalCoreTests/RateLimitStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/RateLimitStoreTests.swift`:
```swift
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))  // not deleted while active
    }

    func testExpiredReturnsNilAndDeletesFile() throws {
        try write(resetAt: 1000)
        let store = RateLimitStore(fileURL: file)
        XCTAssertNil(store.read(now: 1000))   // now >= resetAt → expired
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))  // self-cleaned
    }

    func testCorruptFileReturnsNil() throws {
        try "not json".data(using: .utf8)!.write(to: file)
        let store = RateLimitStore(fileURL: file)
        XCTAssertNil(store.read(now: 1000))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RateLimitStoreTests`
Expected: FAIL — `RateLimitStore` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/RateLimitStore.swift`:
```swift
import Foundation

/// Reads the account-level rate-limit file. Returns the state while active; once
/// `now >= resetAt` it deletes the file (condition ① self-clean) and returns nil.
/// Missing or corrupt file → nil. Mirrors `StateStore`'s tolerant read pattern.
public struct RateLimitStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func read(now: TimeInterval) -> RateLimitState? {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(RateLimitState.self, from: data)
        else { return nil }

        if now >= state.resetAt {
            try? fm.removeItem(at: fileURL)   // expired: self-clean
            return nil
        }
        return state
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RateLimitStoreTests`
Expected: PASS (4 tests). Then `swift test` → all pass (47 total).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add RateLimitStore (read + expiry self-delete + corruption-tolerant)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire `RateLimitStore` into `Coordinator`

**Files:**
- Modify: `Sources/ClaudeSignalCore/Coordinator.swift`
- Test: `Tests/ClaudeSignalCoreTests/CoordinatorTests.swift` (existing file — add cases)

- [ ] **Step 1: Add failing tests to the existing CoordinatorTests**

First read `Tests/ClaudeSignalCoreTests/CoordinatorTests.swift` to match its existing helpers
(it builds a `Coordinator` with a temp session dir, fake idle provider, fake reachability).
The Coordinator initializer is changing to require a `rateLimitStore`, so the existing
`makeCoordinator` helper must be updated to pass one. Update the helper to accept an optional
rate-limit file and add new tests. Append/adjust so the file contains these new tests (keep all
existing tests, just thread the new parameter through the shared helper):

```swift
    // Add to CoordinatorTests:

    private func writeRateLimit(resetAt: TimeInterval) throws -> URL {
        let f = dir.appendingPathComponent("ratelimit.json")
        let data = try JSONEncoder().encode(RateLimitState(resetAt: resetAt))
        try data.write(to: f)
        return f
    }

    func testActiveRateLimitForcesErrorEvenWhenWorking() throws {
        try write("a", .working, 1000)                 // a session is working
        _ = try writeRateLimit(resetAt: 2000)          // but limit is active (now 1000 < 2000)
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .error)
    }

    func testExpiredRateLimitDoesNotForceError() throws {
        try write("a", .working, 1000)
        _ = try writeRateLimit(resetAt: 1000)          // expired (now 1000 >= 1000)
        let c = makeCoordinator(idle: 1, reachable: true)
        XCTAssertEqual(c.computeDisplayState(now: 1000), .working)
    }

    func testNoRateLimitFileBehavesAsBefore() throws {
        try write("a", .done, 1000)
        let c = makeCoordinator(idle: 99, reachable: true)   // away → done shows
        XCTAssertEqual(c.computeDisplayState(now: 1000), .done)
    }
```

And update the shared `makeCoordinator` helper so it always constructs a `RateLimitStore`
pointing at `dir/ratelimit.json` (which may or may not exist):
```swift
    private func makeCoordinator(idle: TimeInterval, reachable: Bool) -> Coordinator {
        Coordinator(
            store: StateStore(directory: dir, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: FakeIdle(seconds: idle)),
            reachability: FakeReachability(reachable: reachable),
            rateLimitStore: RateLimitStore(fileURL: dir.appendingPathComponent("ratelimit.json"))
        )
    }
```
(Match the exact names of the existing fakes/helpers in the file — `FakeIdle`/`FakeReachability`
may be named differently; read the file and reuse whatever it already defines. Only add the
`rateLimitStore:` argument.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CoordinatorTests`
Expected: FAIL — `Coordinator.init` has no `rateLimitStore:` parameter (compile error).

- [ ] **Step 3: Modify Coordinator**

Replace `Sources/ClaudeSignalCore/Coordinator.swift` with:
```swift
import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking
    let rateLimitStore: RateLimitStore

    public init(store: StateStore,
                presence: PresenceMonitor,
                reachability: ReachabilityChecking,
                rateLimitStore: RateLimitStore) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
        self.rateLimitStore = rateLimitStore
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        let sessions = store.loadLiveSessions(now: now)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        aggregate = applyRateLimitOverride(aggregate, rateLimit: rateLimitStore.read(now: now), now: now)
        return SignalResolver.resolve(aggregate, presence: presence.current())
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CoordinatorTests`
Expected: PASS (existing cases + 3 new). Then `swift test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire RateLimitStore into Coordinator pipeline

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Inject `RateLimitStore` in `AppController`

**Files:**
- Modify: `Sources/ClaudeSignal/AppController.swift`

No unit tests (composition root). Gate: `swift build` clean; `swift test` still passes.

- [ ] **Step 1: Read the current AppController and update the Coordinator construction**

Read `Sources/ClaudeSignal/AppController.swift`. In `init`, it builds the `Coordinator`. Add a
`RateLimitStore` pointing at `~/.claude-signal/ratelimit.json` and pass it. The session dir is
already derived as `base = ~/.claude-signal/sessions`; the ratelimit file is one level up at
`~/.claude-signal/ratelimit.json`. Update the coordinator construction to:
```swift
        let signalDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-signal")
        let sessionsDir = signalDir.appendingPathComponent("sessions")
        coordinator = Coordinator(
            store: StateStore(directory: sessionsDir, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: SystemIdleTimeProvider()),
            reachability: SystemReachability(),
            rateLimitStore: RateLimitStore(fileURL: signalDir.appendingPathComponent("ratelimit.json"))
        )
```
(Match the existing variable names in the file; the existing code computes the sessions path
inline — refactor it to the two-step `signalDir` / `sessionsDir` form above so both paths share
the base. Keep everything else in `init` and the class unchanged.)

- [ ] **Step 2: Build and test**

Run: `swift build && swift test`
Expected: build clean (0 warnings); all tests pass.
Run: `swift run ClaudeSignal --simulate working away`
Expected: `aggregate=working presence=away -> display=working` (CLI path unaffected).
(Do NOT run `swift run ClaudeSignal` with no args — it starts the GUI loop and hangs.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: inject RateLimitStore into AppController's coordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Hook — handle `StopFailure`, parse reset time, delete on activity

**Files:**
- Modify: `hooks/on-event.sh`
- Test: `hooks/tests/test-on-event.sh` (existing file — add cases)

- [ ] **Step 1: Add failing shell tests**

Read `hooks/tests/test-on-event.sh` to match its existing structure (it sets
`CLAUDE_SIGNAL_DIR` to a temp dir and pipes JSON into `on-event.sh`, asserting on the written
session file). Add these cases. The rate-limit file is at `$CLAUDE_SIGNAL_DIR/ratelimit.json`
(NOT under `sessions/`). Use a fixed `TZ` so the expected timestamp is deterministic:

```bash
# ---- usage-limit (StopFailure / rate_limit) ----

# rate_limit StopFailure writes ratelimit.json with a future reset_at
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"You'"'"'ve hit your session limit · resets 1:10am (America/Toronto)"}' | bash "$SCRIPT"
if [ -f "$CLAUDE_SIGNAL_DIR/ratelimit.json" ]; then
  reset_at=$(jq -r '.reset_at' "$CLAUDE_SIGNAL_DIR/ratelimit.json")
  raw=$(jq -r '.raw' "$CLAUDE_SIGNAL_DIR/ratelimit.json")
  # reset_at must be a number in the future relative to now
  now=$(date +%s)
  if [ "$reset_at" -gt "$now" ]; then echo "ok  - rate_limit writes future reset_at"; else echo "FAIL - reset_at not in future: $reset_at vs $now"; fail=1; fi
  case "$raw" in *"1:10am"*) echo "ok  - raw preserved" ;; *) echo "FAIL - raw not preserved: $raw"; fail=1 ;; esac
else
  echo "FAIL - ratelimit.json not written"; fail=1
fi

# a NON-rate_limit StopFailure does NOT write ratelimit.json
rm -f "$CLAUDE_SIGNAL_DIR/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"max_output_tokens","last_assistant_message":"too long"}' | bash "$SCRIPT"
if [ -f "$CLAUDE_SIGNAL_DIR/ratelimit.json" ]; then echo "FAIL - non-rate_limit should not write ratelimit.json"; fail=1; else echo "ok  - non-rate_limit ignored"; fi

# a normal activity event deletes an existing ratelimit.json (extinguish condition ②)
echo '{"reset_at":99999999999,"raw":"x"}' > "$CLAUDE_SIGNAL_DIR/ratelimit.json"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"s1"}' | bash "$SCRIPT"
if [ -f "$CLAUDE_SIGNAL_DIR/ratelimit.json" ]; then echo "FAIL - normal activity should delete ratelimit.json"; fail=1; else echo "ok  - activity clears ratelimit"; fi

# fallback: rate_limit with an UNPARSEABLE message still writes a sentinel reset_at
rm -f "$CLAUDE_SIGNAL_DIR/ratelimit.json"
echo '{"hook_event_name":"StopFailure","session_id":"s1","error":"rate_limit","last_assistant_message":"limit reached, try later"}' | bash "$SCRIPT"
if [ -f "$CLAUDE_SIGNAL_DIR/ratelimit.json" ]; then
  reset_at=$(jq -r '.reset_at' "$CLAUDE_SIGNAL_DIR/ratelimit.json")
  if [ "$reset_at" -ge 99999999999 ]; then echo "ok  - unparseable rate_limit uses sentinel"; else echo "FAIL - expected sentinel, got $reset_at"; fail=1; fi
else
  echo "FAIL - fallback should still write ratelimit.json"; fail=1
fi
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/xcalibur/Project/claude-signal && bash hooks/tests/test-on-event.sh`
Expected: FAIL — `on-event.sh` doesn't handle StopFailure yet (no ratelimit.json written; the
activity-delete also not implemented).

- [ ] **Step 3: Modify on-event.sh**

Read `hooks/on-event.sh`. Make these changes:

(a) Near the top, after `DIR="$BASE/sessions"` and `mkdir -p "$DIR"`, add a path for the
rate-limit file (a sibling of `sessions/`, directly under `$BASE`):
```bash
RATELIMIT_FILE="$BASE/ratelimit.json"
```

(b) Add a helper to parse the reset time and write the rate-limit file. Place it next to the
existing `write_state` function:
```bash
# Parse "resets 1:10am (America/Toronto)" from a StopFailure message and write
# ratelimit.json with a unix reset_at = the NEXT occurrence of that clock time in that tz.
# Falls back to a far-future sentinel if the time can't be parsed (red persists until activity).
SENTINEL=99999999999
write_ratelimit() {
  local msg="$1"
  local clock tz reset_at

  # Extract "1:10am" (hour:min + am/pm) and the parenthesized IANA timezone.
  clock="$(printf '%s' "$msg" | grep -oE '[0-9]{1,2}:[0-9]{2}[ap]m' | head -1)"
  tz="$(printf '%s' "$msg" | grep -oE '\([A-Za-z]+/[A-Za-z_]+\)' | head -1 | tr -d '()')"

  if [ -n "$clock" ] && [ -n "$tz" ]; then
    # Build "today HH:MM" in the target tz, in 12h format with am/pm.
    local today h m ampm hh24
    today="$(TZ="$tz" date '+%Y-%m-%d')"
    # split "1:10am"
    h="${clock%%:*}"
    m="$(printf '%s' "$clock" | sed -E 's/^[0-9]{1,2}:([0-9]{2})[ap]m/\1/')"
    ampm="$(printf '%s' "$clock" | grep -oE '[ap]m')"
    # convert to 24h
    hh24="$h"
    if [ "$ampm" = "pm" ] && [ "$h" != "12" ]; then hh24=$((h + 12)); fi
    if [ "$ampm" = "am" ] && [ "$h" = "12" ]; then hh24=0; fi
    # parse "YYYY-MM-DD HH:MM" in the target tz -> unix seconds
    reset_at="$(TZ="$tz" date -j -f '%Y-%m-%d %H:%M' "$today $(printf '%02d' "$hh24"):$m" '+%s' 2>/dev/null)"
    # if that instant is already past, roll to tomorrow
    if [ -n "$reset_at" ] && [ "$reset_at" -le "$(date +%s)" ]; then
      reset_at=$((reset_at + 86400))
    fi
  fi

  [ -z "${reset_at:-}" ] && reset_at="$SENTINEL"

  jq -n --argjson r "$reset_at" --arg raw "$msg" \
    '{reset_at:$r, raw:$raw}' > "$RATELIMIT_FILE.tmp" \
    && mv "$RATELIMIT_FILE.tmp" "$RATELIMIT_FILE" || rm -f "$RATELIMIT_FILE.tmp"
}
```

(c) In the `case "$event"` block: add a `StopFailure` branch, and make the normal-activity
branch ALSO delete the rate-limit file (extinguish condition ②). The existing normal-activity
branch is `UserPromptSubmit|PreToolUse|PostToolUse|SubagentStop) write_state "working" ;;` —
add `rm -f "$RATELIMIT_FILE"` to it, and also to the `Stop)` branch:
```bash
  UserPromptSubmit|PreToolUse|PostToolUse|SubagentStop)
    rm -f "$RATELIMIT_FILE"          # activity = recovered (extinguish ②)
    write_state "working" ;;
  Notification)
    msg="$(printf '%s' "$input" | jq -r '.message // empty')"
    case "$msg" in
      *permission*|*"needs your permission"*) write_state "permission" ;;
      *)                           write_state "working" ;;
    esac ;;
  Stop)
    rm -f "$RATELIMIT_FILE"          # activity = recovered (extinguish ②)
    write_state "done" ;;
  StopFailure)
    err="$(printf '%s' "$input" | jq -r '.error // empty')"
    if [ "$err" = "rate_limit" ]; then
      msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
      write_ratelimit "$msg"
    fi ;;
  SessionEnd)
    rm -f "$file" ;;
  *)
    : ;;
```
Note: `StopFailure` payloads may have no `session_id` in some cases, but `write_ratelimit`
doesn't use `$sid` or `$file` — it writes the account-level `$RATELIMIT_FILE`. The early
`[ -z "$sid" ] && exit 0` guard near the top of the script would, however, exit before we reach
the StopFailure branch if session_id is empty. The captured real payload DOES include
`session_id`, so this is fine in practice; but to be safe, move the StopFailure handling
BEFORE that guard, OR relax the guard. Simplest: right after computing `event`, add an early
StopFailure handler before the `[ -z "$sid" ]` guard:
```bash
# StopFailure is account-level (rate limit) — handle before the session_id guard,
# since it doesn't need a session id.
if [ "$event" = "StopFailure" ]; then
  err="$(printf '%s' "$input" | jq -r '.error // empty')"
  if [ "$err" = "rate_limit" ]; then
    msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"
    write_ratelimit "$msg"
  fi
  exit 0
fi
```
If you use this early-handler form, do NOT also add a `StopFailure)` case in the `case` block
(avoid double handling). Pick ONE placement — the early handler is recommended because it
sidesteps the session_id guard cleanly. Keep `write_ratelimit` defined above the handler.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash hooks/tests/test-on-event.sh`
Expected: all lines `ok`, exit 0. Includes the original session tests plus the 4 new
rate-limit cases.

Then a manual deterministic spot-check of the parser (uses a fixed tz):
```bash
export CLAUDE_SIGNAL_DIR="$(mktemp -d)"
echo '{"hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"You'"'"'ve hit your session limit · resets 1:10am (America/Toronto)"}' | bash hooks/on-event.sh
echo "written:"; jq . "$CLAUDE_SIGNAL_DIR/ratelimit.json"
echo "reset_at as local time:"; date -r "$(jq -r .reset_at "$CLAUDE_SIGNAL_DIR/ratelimit.json")"
rm -rf "$CLAUDE_SIGNAL_DIR"
```
Expected: `reset_at` prints as the next 1:10 AM Toronto time, converted to your local clock.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: on-event.sh handles StopFailure/rate_limit (parse reset, clear on activity)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Register `StopFailure` in `install.sh`

**Files:**
- Modify: `hooks/install.sh`

- [ ] **Step 1: Add StopFailure to the EVENTS array**

In `hooks/install.sh`, the events line is:
```bash
EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop SubagentStop SessionEnd)
```
Change it to include `StopFailure`:
```bash
EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop StopFailure SubagentStop SessionEnd)
```

- [ ] **Step 2: Verify the installer still works against a throwaway settings file**

⚠️ Use a TEMP settings file — never the real `~/.claude/settings.json`.
```bash
export CLAUDE_SETTINGS="$(mktemp)"
echo '{}' > "$CLAUDE_SETTINGS"
bash hooks/install.sh
jq -e '.hooks.StopFailure[0].hooks[0].command | endswith("on-event.sh")' "$CLAUDE_SETTINGS" >/dev/null && echo "ok StopFailure registered" || echo "FAIL"
# idempotent re-run
bash hooks/install.sh
dupes=$(jq '[.hooks.StopFailure[].hooks[].command] | length' "$CLAUDE_SETTINGS")
[ "$dupes" = "1" ] && echo "ok idempotent" || echo "FAIL dupes=$dupes"
rm -f "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.claude-signal.bak"
```
Expected: `ok StopFailure registered`, `ok idempotent`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: register StopFailure hook in install.sh

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Docs + full verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full automated suite**

Run: `swift test && bash hooks/tests/test-on-event.sh && swift build -c release`
Expected: all unit tests pass; all hook tests `ok`; release build succeeds.

- [ ] **Step 2: Update README red-light description**

In `README.md`, the red bullet currently reads:
```
- 🔴 flashing red — error (e.g. network down while working)
```
Replace it with:
```
- 🔴 flashing red — error: network down while working, OR you've hit a usage limit (stays red until the limit resets or you use Claude again)
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: README notes usage-limit as a red-light trigger

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 4: Hand off the probe-removal + manual QA to the user**

The automated gates can't trigger a real rate limit. Tell the user these manual steps (do NOT
run them automatically — they touch the real `~/.claude/settings.json` and need the user):

1. **Remove the temporary capture probe** from the real settings, then install the real hooks
   (now including StopFailure):
   ```bash
   # restore the pre-probe settings, then install the real hooks
   cp ~/.claude/settings.json.pre-capture-probe.bak ~/.claude/settings.json   # if present
   cd ~/Project/claude-signal && bash hooks/install.sh
   ```
   (If the user already removed the probe, just run `install.sh`.)
2. **Manual QA** — simulate a rate-limit without waiting to actually hit one:
   ```bash
   # fake an active limit 2 minutes out, with the app running
   python3 - <<'PY'
   import json, time, os
   p = os.path.expanduser("~/.claude-signal/ratelimit.json")
   json.dump({"reset_at": int(time.time())+120, "raw": "manual test"}, open(p,"w"))
   print("wrote", p)
   PY
   ```
   With `swift run ClaudeSignal` running, the menu bar + Touch Bar should go RED within ~1s and
   stay red (ignoring presence). Then either wait 2 min (auto-off via expiry) or send any normal
   Claude activity / delete the file to confirm it clears.

---

## Self-Review

**Spec coverage** (against `2026-05-31-claude-signal-ratelimit-red-design.md`):
- §1 unified red, usage-limit as another trigger → reuses `.error`; no new color (Tasks 2,4). ✓
- §3 standalone account-level `ratelimit.json`, not subject to stale cleanup → separate file +
  `RateLimitStore` (Tasks 3,6); never read by StateStore. ✓
- §3 ignores presence → `applyRateLimitOverride` returns `.error` which `SignalResolver` always
  shows (error is never presence-gated) (Task 2). ✓
- §4 hook: StopFailure + only rate_limit + parse next-occurrence reset + delete on activity →
  Task 6 (early handler, TZ-aware `date`, sentinel fallback). ✓
- §5 pure `applyRateLimitOverride` + `RateLimitStore` + Coordinator one line → Tasks 2,3,4. ✓
- §5 unchanged SignalResolver/Aggregator/SessionState/surfaces → confirmed: only Coordinator +
  AppController touched on the Swift side. ✓
- §6 file structure → matches Tasks 1–8. ✓
- §7 edge cases: working+limit→red (Task4 test); multi-session→one global file (by design, one
  file); expired-while-idle→self-clean (Task3 test); upgrade→activity deletes (Task6 test);
  restart→file persists on disk (inherent); regex fail→sentinel (Task6 test). ✓
- §8 testing: override table tests, store temp-dir tests, hook shell tests → Tasks 2,3,6. ✓
- §9 YAGNI: no countdown digits, only rate_limit, no upgrade detection → none added. ✓
- §10 remove probe first → Task 8 Step 4 (explicit, user-run). ✓

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `RateLimitState(resetAt:raw:)` with CodingKeys `reset_at`/`raw`;
`applyRateLimitOverride(_:rateLimit:now:)`; `RateLimitStore(fileURL:)` + `.read(now:)`;
`Coordinator.init(store:presence:reachability:rateLimitStore:)`. The hook writes
`{reset_at, raw}` and the sentinel `99999999999` consistently in Tasks 1, 3, 6. `.error` is the
existing `AggregateState`/`DisplayState` case. ✓

**Known fragilities (flagged, accepted by user):** the bash TZ parser depends on macOS
`date -j -f` and the message wording; if wording changes, the sentinel-fallback path keeps red
on (extinguished by activity). The user accepted handling wording changes later.
