# claude-signal — Phase 2 (Touch Bar Control Strip) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second light surface — a persistent dot in the macOS Touch Bar Control Strip — that mirrors the menu-bar light, running alongside it on the existing core "brain".

**Architecture:** A new `TouchBarSurface` implements the existing `@MainActor SignalSurface` protocol (same as `MenuBarSurface`). It registers an `NSCustomTouchBarItem` into the always-visible Control Strip via a thin wrapper (`DFRControlStrip`) over the private `DFRFoundation` API — a recipe already verified on this exact machine (2019 MBP, macOS 14.6) by a spike. The animation math (breathe/flash alpha) is extracted from `MenuBarSurface` into a pure, unit-tested core helper (`LightAnimation`) and shared by both surfaces. `AppController` is refactored from a single surface to an array and renders to all of them.

**Tech Stack:** Swift 6 + SwiftPM, AppKit, the private `DFRFoundation` framework (loaded at runtime via `dlopen`/`dlsym` — no link-time dependency), XCTest. Requires full Xcode (already installed). Touch Bar hardware required to *see* the result, but the code compiles and degrades gracefully on machines without it.

---

## Verified spike recipe (the basis for Task 4)

From `/Users/xcalibur/Project/claude-signal-touchbar-spike/SPIKE-RESULT.md` — confirmed working on real hardware:

- `dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)` → succeeds.
- `dlsym(..., "DFRElementSetControlStripPresenceForIdentifier")` → non-nil; signature `@convention(c) (NSString, ObjCBool) -> Void`.
- `NSTouchBarItem.responds(to: NSSelectorFromString("addSystemTrayItem:"))` → true; call as a **class** method: `NSTouchBarItem.perform(sel, with: item)`.
- Registration sequence: build `NSCustomTouchBarItem(identifier:)` with a custom `view`, call `addSystemTrayItem:`, then `DFRElementSetControlStripPresenceForIdentifier(identifier.rawValue as NSString, true)`.
- App runs `.accessory` (no Dock icon), same as the menu-bar app.

---

## File Structure

```
Sources/
  ClaudeSignalCore/
    LightAnimation.swift          # NEW — pure: animation kind, period, alpha math (testable)
  ClaudeSignal/
    Surfaces/
      SignalSurface.swift         # MODIFY — drop Appearance.animation/Animation enum; keep Appearance.color
      MenuBarSurface.swift        # MODIFY — use LightAnimation instead of inline math
      DFRControlStrip.swift       # NEW — isolated wrapper over the private DFRFoundation API
      TouchBarLightView.swift     # NEW — NSView that draws the colored light dot
      TouchBarSurface.swift       # NEW — SignalSurface impl for the Control Strip
    AppController.swift           # MODIFY — hold [any SignalSurface], render to all
Tests/
  ClaudeSignalCoreTests/
    LightAnimationTests.swift     # NEW — unit tests for the pure animation helper
README.md                         # MODIFY — Phase 2 done; Touch Bar notes
docs/superpowers/specs/2026-05-30-claude-signal-design.md  # MODIFY — mark Phase 2 status
```

**Why extract `LightAnimation` to the core library:** the breathe/flash alpha computation currently lives inside `MenuBarSurface`'s GUI timer closure, where it can't be unit-tested, and Phase 2 would duplicate it. Moving the pure math (no AppKit) into `ClaudeSignalCore` makes it testable once and shared by both surfaces — the trickiest part of the visual layer gets real test coverage. `Appearance.color` (needs `NSColor`) stays in the executable.

---

## Type contract (used verbatim across tasks)

```swift
// LightAnimation.swift (ClaudeSignalCore) — pure, no AppKit
public enum LightAnimationKind: Equatable, Sendable { case steady, breathe, flash }

public enum LightAnimation {
    public static func kind(for state: DisplayState) -> LightAnimationKind
    public static func period(for state: DisplayState) -> TimeInterval?   // nil => steady
    public static func alpha(elapsed: TimeInterval, period: TimeInterval, ease: Bool) -> Double
}
```

`kind`: `.off`/`.done` → `.steady`; `.working` → `.breathe`; `.permission`/`.error` → `.flash`.
`period`: steady → `nil`; `.working` → `1.8`; `.permission` → `1.0`; `.error` → `0.6`.
`alpha`: `ease == true` (breathe) → `0.35 + 0.65*(0.5 - 0.5*cos(2π·phase))`; `ease == false` (flash) → `phase < 0.5 ? 1.0 : 0.15`, where `phase = (elapsed mod period)/period`.

These names/values are referenced identically by `MenuBarSurface`, `TouchBarSurface`, and the tests.

---

### Task 1: Extract `LightAnimation` into the core library (pure, TDD)

**Files:**
- Create: `Sources/ClaudeSignalCore/LightAnimation.swift`
- Test: `Tests/ClaudeSignalCoreTests/LightAnimationTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/LightAnimationTests.swift`:
```swift
import XCTest
@testable import ClaudeSignalCore

final class LightAnimationTests: XCTestCase {
    func testKindForEachState() {
        XCTAssertEqual(LightAnimation.kind(for: .off), .steady)
        XCTAssertEqual(LightAnimation.kind(for: .done), .steady)
        XCTAssertEqual(LightAnimation.kind(for: .working), .breathe)
        XCTAssertEqual(LightAnimation.kind(for: .permission), .flash)
        XCTAssertEqual(LightAnimation.kind(for: .error), .flash)
    }

    func testPeriodForEachState() {
        XCTAssertNil(LightAnimation.period(for: .off))
        XCTAssertNil(LightAnimation.period(for: .done))
        XCTAssertEqual(LightAnimation.period(for: .working), 1.8)
        XCTAssertEqual(LightAnimation.period(for: .permission), 1.0)
        XCTAssertEqual(LightAnimation.period(for: .error), 0.6)
    }

    func testBreatheAlphaDimAtStartBrightAtHalf() {
        // ease=true: dim (0.35) at phase 0, full (1.0) at phase 0.5
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.0, period: 1.8, ease: true), 0.35, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.9, period: 1.8, ease: true), 1.0, accuracy: 0.0001)
        // wraps: a full period later is the same as phase 0
        XCTAssertEqual(LightAnimation.alpha(elapsed: 1.8, period: 1.8, ease: true), 0.35, accuracy: 0.0001)
    }

    func testFlashAlphaOnFirstHalfOffSecondHalf() {
        // ease=false: on (1.0) for first half of the period, dim (0.15) for the second
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.0, period: 1.0, ease: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.25, period: 1.0, ease: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.5, period: 1.0, ease: false), 0.15, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.75, period: 1.0, ease: false), 0.15, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/xcalibur/Project/claude-signal && swift test --filter LightAnimationTests`
Expected: FAIL — `LightAnimation` / `LightAnimationKind` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/LightAnimation.swift`:
```swift
import Foundation

/// How a light should animate for a given display state.
public enum LightAnimationKind: Equatable, Sendable {
    case steady   // no animation (off, or solid "done")
    case breathe  // smooth cosine pulse (working)
    case flash    // square on/off (permission, error)
}

/// Pure animation math, shared by every surface so the visual timing is identical
/// and the (otherwise GUI-buried) alpha computation is unit-testable.
public enum LightAnimation {
    public static func kind(for state: DisplayState) -> LightAnimationKind {
        switch state {
        case .off, .done:          return .steady
        case .working:             return .breathe
        case .permission, .error:  return .flash
        }
    }

    /// Animation period in seconds, or nil for steady states.
    public static func period(for state: DisplayState) -> TimeInterval? {
        switch state {
        case .off, .done:   return nil
        case .working:      return 1.8
        case .permission:   return 1.0
        case .error:        return 0.6
        }
    }

    /// Alpha (0...1) at a given elapsed time.
    /// `ease == true` → smooth breathe; `ease == false` → square flash.
    public static func alpha(elapsed: TimeInterval, period: TimeInterval, ease: Bool) -> Double {
        let phase = (elapsed.truncatingRemainder(dividingBy: period)) / period  // 0..1
        if ease {
            return 0.35 + 0.65 * (0.5 - 0.5 * cos(2 * .pi * phase))
        } else {
            return phase < 0.5 ? 1.0 : 0.15
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LightAnimationTests`
Expected: PASS (4 tests). Then `swift test` → all pass (was 32, now 36).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: extract pure LightAnimation helper into core (testable breathe/flash math)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Refactor `MenuBarSurface` to use `LightAnimation`; slim `Appearance`

**Files:**
- Modify: `Sources/ClaudeSignal/Surfaces/SignalSurface.swift`
- Modify: `Sources/ClaudeSignal/Surfaces/MenuBarSurface.swift`

No new unit tests (behavior-preserving refactor; covered by Task 1's tests + build). Gate: `swift build` clean and all 36 tests still pass.

- [ ] **Step 1: Remove the animation mapping from `Appearance` (it now lives in `LightAnimation`)**

Replace the entire contents of `Sources/ClaudeSignal/Surfaces/SignalSurface.swift` with:
```swift
import AppKit
import ClaudeSignalCore

/// Anything that can show the light. Phase 1 = menu bar; Phase 2 = Touch Bar; later = notch.
@MainActor
protocol SignalSurface: AnyObject {
    func render(_ state: DisplayState)
}

/// Color vocabulary for a DisplayState (shared by all surfaces).
/// Animation timing lives in `ClaudeSignalCore.LightAnimation`.
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
}
```

- [ ] **Step 2: Refactor `MenuBarSurface.render` to use `LightAnimation`**

Replace the entire contents of `Sources/ClaudeSignal/Surfaces/MenuBarSurface.swift` with:
```swift
import AppKit
import ClaudeSignalCore

/// Renders the light as a colored dot in the macOS menu bar.
@MainActor
final class MenuBarSurface: SignalSurface {
    private let statusItem: NSStatusItem
    private var timer: Timer?
    private var current: DisplayState?

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

        let color = Appearance.color(for: state)
        // period == nil  <=>  steady state (off or done)
        guard let period = LightAnimation.period(for: state) else {
            draw(alpha: state == .off ? 0 : 1, color: color)
            return
        }
        let ease = LightAnimation.kind(for: state) == .breathe
        startTimer(period: period, color: color, ease: ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        // Timer(...) + a single .common registration so the animation keeps running
        // during menu tracking, and is registered exactly once.
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            // Timer fires on the main run loop; assumeIsolated avoids a Sendable crossing
            // for the non-Sendable NSColor capture.
            MainActor.assumeIsolated {
                self?.draw(alpha: alpha, color: color)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: build clean (0 warnings); all 36 tests pass. The menu-bar behavior is unchanged (same numbers, now sourced from `LightAnimation`).

Also confirm the CLI path still works (no regression):
Run: `swift run ClaudeSignal --simulate working,done away`
Expected: `aggregate=working presence=away -> display=working`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: MenuBarSurface uses shared LightAnimation; slim Appearance to color only

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `DFRControlStrip` — isolated wrapper over the private API

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/DFRControlStrip.swift`

No unit tests (private OS API + GUI; verified by the spike). Gate: `swift build` clean.

- [ ] **Step 1: Implement the wrapper**

`Sources/ClaudeSignal/Surfaces/DFRControlStrip.swift`:
```swift
import AppKit
import Foundation

/// Thin wrapper over the private `DFRFoundation` Control-Strip API.
///
/// Verified working on macOS 14.6 (2019 MacBook Pro) by a spike. Uses runtime
/// `dlopen`/`dlsym` so there is no link-time dependency on a private framework,
/// and degrades gracefully (every call becomes a no-op) on machines where the
/// symbols are absent — e.g. Apple Silicon Macs without a Touch Bar. This keeps
/// all the private-API surface in one isolated, well-labeled place.
enum DFRControlStrip {
    private typealias SetPresenceFn = @convention(c) (NSString, ObjCBool) -> Void

    /// Resolved once. nil if the private framework/symbol isn't available here.
    private static let setPresence: SetPresenceFn? = {
        let path = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(path, RTLD_NOW),
              let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
        else { return nil }
        return unsafeBitCast(sym, to: SetPresenceFn.self)
    }()

    private static let addSystemTraySel = NSSelectorFromString("addSystemTrayItem:")

    /// Whether the persistent Control-Strip API is usable on this machine.
    static var isAvailable: Bool {
        setPresence != nil && NSTouchBarItem.responds(to: addSystemTraySel)
    }

    /// Register `item` as a persistent Control-Strip item (always visible,
    /// independent of the focused app). No-op if the private API is unavailable.
    static func add(_ item: NSTouchBarItem) {
        guard isAvailable else { return }
        NSTouchBarItem.perform(addSystemTraySel, with: item)
        setPresence?(item.identifier.rawValue as NSString, true)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build clean. (No behavior yet — nothing calls it until Task 5.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add DFRControlStrip wrapper over private Touch Bar Control-Strip API

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `TouchBarLightView` — the colored dot view

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/TouchBarLightView.swift`

No unit tests (custom NSView drawing). Gate: `swift build` clean.

- [ ] **Step 1: Implement the view**

`Sources/ClaudeSignal/Surfaces/TouchBarLightView.swift`:
```swift
import AppKit

/// A small Touch Bar view that draws a single rounded "light" in a color + alpha.
/// `setLight` updates the appearance and triggers a redraw; the surface drives it
/// from an animation timer (mirroring the menu-bar dot).
@MainActor
final class TouchBarLightView: NSView {
    private var fillColor: NSColor = .clear
    private var fillAlpha: Double = 0

    func setLight(color: NSColor, alpha: Double) {
        fillColor = color
        fillAlpha = alpha
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard fillAlpha > 0 else { return }   // off => draw nothing
        let inset = bounds.insetBy(dx: 6, dy: 6)
        let radius = inset.height / 2
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        fillColor.withAlphaComponent(fillAlpha).setFill()
        path.fill()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build clean.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add TouchBarLightView (colored dot rendered in the Control Strip item)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `TouchBarSurface` — the Control Strip light

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/TouchBarSurface.swift`

No unit tests (GUI + private API; visual QA is the user's, in Task 7). Gate: `swift build` clean.

- [ ] **Step 1: Implement the surface**

`Sources/ClaudeSignal/Surfaces/TouchBarSurface.swift`:
```swift
import AppKit
import ClaudeSignalCore

/// Renders the light as a persistent dot in the Touch Bar Control Strip.
/// Mirrors `MenuBarSurface`'s render/animation logic, sharing `LightAnimation`.
/// On machines without the private Control-Strip API, registration is a no-op
/// and `render` simply updates a view nobody sees — no crash, menu bar unaffected.
@MainActor
final class TouchBarSurface: SignalSurface {
    private let identifier = NSTouchBarItem.Identifier("com.claudesignal.touchbar.light")
    private let item: NSCustomTouchBarItem
    private let lightView = TouchBarLightView(frame: NSRect(x: 0, y: 0, width: 44, height: 30))
    private var timer: Timer?
    private var current: DisplayState?

    init() {
        item = NSCustomTouchBarItem(identifier: identifier)
        item.view = lightView
        DFRControlStrip.add(item)   // graceful no-op if the private API is unavailable
        if !DFRControlStrip.isAvailable {
            FileHandle.standardError.write(Data(
                "claude-signal: Touch Bar Control Strip API unavailable; menu bar only.\n".utf8))
        }
        render(.off)
    }

    func render(_ state: DisplayState) {
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        let color = Appearance.color(for: state)
        // period == nil  <=>  steady state (off or done)
        guard let period = LightAnimation.period(for: state) else {
            lightView.setLight(color: color, alpha: state == .off ? 0 : 1)
            return
        }
        let ease = LightAnimation.kind(for: state) == .breathe
        startTimer(period: period, color: color, ease: ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            MainActor.assumeIsolated {
                self?.lightView.setLight(color: color, alpha: alpha)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build clean.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add TouchBarSurface (Control Strip light, shares LightAnimation)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Wire `TouchBarSurface` into `AppController` (multi-surface)

**Files:**
- Modify: `Sources/ClaudeSignal/AppController.swift`

No unit tests. Gate: `swift build` clean; `--simulate` still works.

- [ ] **Step 1: Refactor `AppController` to render to multiple surfaces**

Replace the entire contents of `Sources/ClaudeSignal/AppController.swift` with:
```swift
import AppKit
import Foundation
import ClaudeSignalCore

/// Owns the surfaces + coordinator, polls state on a timer, renders to every surface.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let surfaces: [any SignalSurface]
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
        // Menu bar (universal) + Touch Bar (no-ops gracefully if unavailable).
        surfaces = [MenuBarSurface(), TouchBarSurface()]
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Render the initial state immediately rather than waiting one full interval.
        tick()
        // pollTimer runs for the whole process lifetime and is intentionally never
        // invalidated; the OS reclaims it at exit. [weak self] keeps it a safe no-op
        // if the controller is ever torn down early.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so we are already on the main actor.
            // assumeIsolated lets us call the @MainActor tick() without a Sendable crossing.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        let state = coordinator.computeDisplayState(now: Date().timeIntervalSince1970)
        for surface in surfaces {
            surface.render(state)
        }
    }
}
```

- [ ] **Step 2: Build, test, and confirm the CLI path**

Run: `swift build && swift test`
Expected: build clean; 36 tests pass.

Run: `swift run ClaudeSignal --simulate working away` and `swift run ClaudeSignal --simulate done present`
Expected: `aggregate=working presence=away -> display=working` and `aggregate=done presence=present -> display=off`.

(Do NOT run `swift run ClaudeSignal` with no args here — it launches the GUI event loop and blocks. That's the user's manual QA in Task 7.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: render to both menu bar and Touch Bar surfaces (Phase 2 wired)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Verification + docs

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-05-30-claude-signal-design.md`

- [ ] **Step 1: Full automated suite**

Run: `swift test && bash hooks/tests/test-on-event.sh && swift build -c release`
Expected: 36 unit tests pass; all hook tests print `ok`; release build succeeds.

- [ ] **Step 2: Update the README's roadmap line**

In `README.md`, find the line:
```
Roadmap: Touch Bar (Phase 2) and notch island (Phase 3).
```
Replace it with:
```
Roadmap: ✅ Touch Bar (Phase 2, Control Strip) — done. Next: notch island (Phase 3).
```
And under the state-language bullet list, add a note after it:
```
The same light shows in both the menu bar and (on Touch Bar Macs) the Control Strip.
On Macs without a Touch Bar, the Touch Bar surface is a silent no-op and the menu bar works as usual.
```

- [ ] **Step 3: Mark Phase 2 status in the spec**

In `docs/superpowers/specs/2026-05-30-claude-signal-design.md`, in section 12 (build phases), find the Phase 2 bullet:
```
- **Phase 2 — Touch Bar:** persistent Control Strip item. Current Mac.
```
Replace it with:
```
- **Phase 2 — Touch Bar:** ✅ DONE. Persistent Control Strip item via the private DFRFoundation
  API (dlopen/dlsym + `addSystemTrayItem:` + `DFRElementSetControlStripPresenceForIdentifier`),
  verified on macOS 14.6 / 2019 MBP. Shares `LightAnimation` with the menu bar; degrades to a
  no-op on Macs without a Touch Bar.
```
(Also update the Chinese mirror of that bullet in the same section if present, to match: mark 已完成 and note the DFRFoundation 私有 API approach + graceful no-op.)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: mark Phase 2 (Touch Bar) done in README and spec

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Hand the manual visual QA to the user**

The automated gates can't see a physical Touch Bar. Tell the user to run:
```bash
cd ~/Project/claude-signal
swift run ClaudeSignal
# then in another terminal, drive states and watch BOTH the menu bar and the Touch Bar:
export CLAUDE_SIGNAL_DIR="$HOME/.claude-signal"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo"}' | bash hooks/on-event.sh   # blue breathing
echo '{"hook_event_name":"Notification","session_id":"demo","message":"Claude needs your permission to use Bash"}' | bash hooks/on-event.sh  # yellow flashing
echo '{"hook_event_name":"Stop","session_id":"demo"}' | bash hooks/on-event.sh   # green steady (after ~30s away)
echo '{"hook_event_name":"SessionEnd","session_id":"demo"}' | bash hooks/on-event.sh   # off
```
Expected: a dot in the Touch Bar Control Strip mirrors the menu-bar dot's color/animation, and stays present when switching apps.

---

## Self-Review

**Spec coverage** (against the design spec):
- §10 "Touch Bar — persistent item in the Control Strip … the semi-documented approach apps like Pock use" → Tasks 3 (`DFRControlStrip`), 4 (`TouchBarLightView`), 5 (`TouchBarSurface`). ✓
- §10 "All three conform to a single `SignalSurface` protocol" → `TouchBarSurface: SignalSurface`, wired in Task 6. ✓
- §3 state language (colors + breathe/flash/steady) → `Appearance.color` + `LightAnimation`, shared by both surfaces. ✓ (Touch Bar shows the identical light as the menu bar.)
- §11 "adding a surface never touches the brain" → confirmed: Tasks 3–6 touch only the executable's Surfaces + AppController; `ClaudeSignalCore` only *gains* the pure `LightAnimation` helper (no brain logic changed). ✓
- §12 Phase 2 → this plan; marked done in Task 7. ✓
- "works on both your current and next Mac" → `DFRControlStrip.isAvailable` guard makes the Touch Bar surface a graceful no-op on the notch Mac; menu bar still works. ✓

**Placeholder scan:** none — every code/command step is complete and concrete.

**Type consistency:** `SignalSurface.render(_:)`, `DisplayState`, `Appearance.color(for:)`, `LightAnimation.kind/period/alpha`, `LightAnimationKind`, `DFRControlStrip.add/isAvailable`, `TouchBarLightView.setLight(color:alpha:)`, `NSTouchBarItem.Identifier`, `NSCustomTouchBarItem` — all used identically across Tasks 1–6. The `period == nil ⇔ steady` contract and `ease = (kind == .breathe)` derivation are identical in both `MenuBarSurface` (Task 2) and `TouchBarSurface` (Task 5). ✓

**Risk note (carried from the spike):** the Control-Strip mechanism relies on a private framework. It is isolated in `DFRControlStrip` and fully optional at runtime (`isAvailable` guard), so a future macOS change degrades the app to menu-bar-only rather than crashing. Acceptable for a personal/portfolio tool.
