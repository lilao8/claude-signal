# claude-signal — Phase 3 (Notch Outline Light) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a U-shaped glowing outline around the camera notch on notch-equipped Macs, synced in color and animation to the existing menu-bar and Touch Bar lights.

**Architecture:** A pure, unit-tested `NotchGeometry` (in `ClaudeSignalCore`) turns `NSScreen` notch insets into an overlay-window frame. `NotchSurface` (a third `SignalSurface`, structurally identical to `TouchBarSurface`) owns a borderless, click-through, top-level overlay `NSWindow` containing a `NotchOutlineView` that draws the U-shaped glow, driven by the shared `LightAnimation`. On screens with no notch it is a complete no-op. The brain (`ClaudeSignalCore` aggregation/resolve) is untouched.

**Tech Stack:** Swift 6 + SwiftPM (full Xcode), AppKit, public `NSScreen` notch APIs (`safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, macOS 12+), XCTest. Spec: `docs/superpowers/specs/2026-05-31-claude-signal-phase3-notch-design.md`.

**Acceptance note:** the developer's Mac has no notch — they can only verify the *no-op* path locally. Visual acceptance of the outline itself is done by a friend on an M1 (notch) Mac via screenshots. The pure `NotchGeometry` tests are the main automated safety net.

---

## File Structure

```
New:
  Sources/ClaudeSignalCore/NotchGeometry.swift          # pure: notch insets -> outline frame (UNIT-TESTED)
  Tests/ClaudeSignalCoreTests/NotchGeometryTests.swift
  Sources/ClaudeSignal/Surfaces/NotchOutlineView.swift  # NSView: draws the U-shaped glow
  Sources/ClaudeSignal/Surfaces/NotchSurface.swift      # SignalSurface: overlay window + animation

Modified:
  Sources/ClaudeSignal/AppController.swift              # surfaces += NotchSurface()
  README.md                                             # mark Phase 3 done
```

**Boundary rationale:** geometry math is pure (only `CGRect`/`CGFloat`), so it lives in the testable core and carries the highest-risk logic under test. The window + drawing (real-hardware-only) stay thin in the executable, mirroring how `TouchBarSurface` + `TouchBarLightView` are split.

---

## Type contract (used verbatim across tasks)

```swift
// NotchGeometry.swift  (ClaudeSignalCore) — pure, no AppKit beyond CoreGraphics types
import CoreGraphics

public struct NotchInsetInput: Equatable, Sendable {
    public let screenFrame: CGRect          // full screen frame (points)
    public let safeAreaTop: CGFloat         // NSScreen.safeAreaInsets.top (0 == no notch)
    public let auxLeft: CGRect?             // NSScreen.auxiliaryTopLeftArea  (nil if unavailable)
    public let auxRight: CGRect?            // NSScreen.auxiliaryTopRightArea (nil if unavailable)
    public init(screenFrame: CGRect, safeAreaTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?)
}

public enum NotchGeometry {
    /// The frame (in screen points, bottom-left origin like AppKit) for the overlay window
    /// that traces the notch's bottom + sides. Returns nil when there is no notch.
    public static func outlineFrame(_ input: NotchInsetInput, margin: CGFloat = 2) -> CGRect?
}
```

Geometry definition (AppKit coords: origin bottom-left, y grows upward):
- No notch ⇔ `safeAreaTop <= 0` OR either aux rect is nil ⇒ return `nil`.
- Notch horizontal span: from `auxLeft.maxX` (inner right edge of the left menu-bar area) to `auxRight.minX` (inner left edge of the right area). `notchWidth = auxRight.minX - auxLeft.maxX`.
- Notch vertical span: the top `safeAreaTop` points of the screen. Top edge = `screenFrame.maxY`; bottom edge = `screenFrame.maxY - safeAreaTop`.
- Outline window frame = that notch rectangle, expanded by `margin` on left/right/bottom (not top — top is the physical screen edge):
  - `x = auxLeft.maxX - margin`
  - `width = notchWidth + 2*margin`
  - `y = screenFrame.maxY - safeAreaTop - margin`
  - `height = safeAreaTop + margin`  (covers notch height + bottom margin; top flush with screen edge)
- Guard: if `notchWidth <= 0` (degenerate / bad aux rects) ⇒ return `nil`.

---

### Task 1: `NotchGeometry` — pure geometry (TDD)

**Files:**
- Create: `Sources/ClaudeSignalCore/NotchGeometry.swift`
- Test: `Tests/ClaudeSignalCoreTests/NotchGeometryTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeSignalCoreTests/NotchGeometryTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import ClaudeSignalCore

final class NotchGeometryTests: XCTestCase {
    // Realistic-ish 16" MacBook Pro: 3456×2234 @2x => 1728×1117 points, notch ~32pt tall,
    // notch ~200pt wide centered. auxLeft/right are the menu-bar areas flanking it.
    private func sixteenInch() -> NotchInsetInput {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let notchWidth: CGFloat = 200
        let notchLeftX = (1728 - notchWidth) / 2      // 764
        let notchRightX = notchLeftX + notchWidth     // 964
        let menuTop = 1117 - 32                        // aux areas occupy the top 32pt band
        let auxLeft = CGRect(x: 0, y: menuTop, width: notchLeftX, height: 32)
        let auxRight = CGRect(x: notchRightX, y: menuTop, width: 1728 - notchRightX, height: 32)
        return NotchInsetInput(screenFrame: screen, safeAreaTop: 32, auxLeft: auxLeft, auxRight: auxRight)
    }

    func testNoNotchWhenSafeAreaZero() {
        let input = NotchInsetInput(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testNoNotchWhenAuxMissing() {
        let input = NotchInsetInput(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                    safeAreaTop: 32, auxLeft: nil, auxRight: nil)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testOutlineFrameForSixteenInch() {
        let frame = NotchGeometry.outlineFrame(sixteenInch(), margin: 2)
        let f = try! XCTUnwrap(frame)
        // x = auxLeft.maxX - margin = 764 - 2 = 762
        XCTAssertEqual(f.minX, 762, accuracy: 0.001)
        // width = notchWidth + 2*margin = 200 + 4 = 204
        XCTAssertEqual(f.width, 204, accuracy: 0.001)
        // y = screen.maxY - safeAreaTop - margin = 1117 - 32 - 2 = 1083
        XCTAssertEqual(f.minY, 1083, accuracy: 0.001)
        // height = safeAreaTop + margin = 32 + 2 = 34
        XCTAssertEqual(f.height, 34, accuracy: 0.001)
        // top edge flush with screen top: y + height = 1117
        XCTAssertEqual(f.maxY, 1117, accuracy: 0.001)
    }

    func testDegenerateWidthReturnsNil() {
        // aux rects overlapping (notchWidth <= 0)
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let auxLeft = CGRect(x: 0, y: 1085, width: 900, height: 32)   // maxX 900
        let auxRight = CGRect(x: 850, y: 1085, width: 878, height: 32) // minX 850 < 900
        let input = NotchInsetInput(screenFrame: screen, safeAreaTop: 32, auxLeft: auxLeft, auxRight: auxRight)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testMarginZero() {
        let frame = NotchGeometry.outlineFrame(sixteenInch(), margin: 0)
        let f = try! XCTUnwrap(frame)
        XCTAssertEqual(f.minX, 764, accuracy: 0.001)
        XCTAssertEqual(f.width, 200, accuracy: 0.001)
        XCTAssertEqual(f.height, 32, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/xcalibur/Project/claude-signal && swift test --filter NotchGeometryTests`
Expected: FAIL — `NotchGeometry` / `NotchInsetInput` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeSignalCore/NotchGeometry.swift`:
```swift
import CoreGraphics

/// Inputs needed to locate the notch, captured from NSScreen at the call site so this
/// stays pure and unit-testable without real hardware.
public struct NotchInsetInput: Equatable, Sendable {
    public let screenFrame: CGRect
    public let safeAreaTop: CGFloat
    public let auxLeft: CGRect?
    public let auxRight: CGRect?

    public init(screenFrame: CGRect, safeAreaTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?) {
        self.screenFrame = screenFrame
        self.safeAreaTop = safeAreaTop
        self.auxLeft = auxLeft
        self.auxRight = auxRight
    }
}

/// Pure geometry: NSScreen notch insets -> the overlay-window frame that traces the
/// notch's bottom + left + right (no top — that's the physical screen edge).
/// Returns nil when there is no usable notch. AppKit coords (origin bottom-left).
public enum NotchGeometry {
    public static func outlineFrame(_ input: NotchInsetInput, margin: CGFloat = 2) -> CGRect? {
        guard input.safeAreaTop > 0,
              let auxLeft = input.auxLeft,
              let auxRight = input.auxRight else { return nil }

        let notchLeftX = auxLeft.maxX
        let notchRightX = auxRight.minX
        let notchWidth = notchRightX - notchLeftX
        guard notchWidth > 0 else { return nil }

        let topY = input.screenFrame.maxY
        return CGRect(
            x: notchLeftX - margin,
            y: topY - input.safeAreaTop - margin,
            width: notchWidth + 2 * margin,
            height: input.safeAreaTop + margin
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS (5 tests). Then `swift test` → all pass (was 52, now 57).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add pure NotchGeometry (notch insets -> outline window frame)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `NotchOutlineView` — the U-shaped glow

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/NotchOutlineView.swift`

No unit tests (custom NSView drawing; visual QA on the friend's M1). Gate: `swift build` clean.

- [ ] **Step 1: Implement the view**

`Sources/ClaudeSignal/Surfaces/NotchOutlineView.swift`:
```swift
import AppKit

/// Draws a U-shaped glowing outline (left + rounded bottom + right; no top) inside its
/// bounds. `setLight(color:alpha:)` updates appearance; the surface drives it from an
/// animation timer (mirrors TouchBarLightView). Tunable style constants are here so a
/// user can re-style by editing one line.
@MainActor
final class NotchOutlineView: NSView {
    // --- tunable style constants ---
    private let borderWidth: CGFloat = 1.5
    private let cornerRadius: CGFloat = 10
    private let glowRadius: CGFloat = 6
    // --------------------------------

    private var strokeColor: NSColor = .clear
    private var strokeAlpha: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true   // layer-backed: cheaper redraws for the ~30fps animation
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setLight(color: NSColor, alpha: Double) {
        strokeColor = color
        strokeAlpha = alpha
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard strokeAlpha > 0 else { return }   // off => draw nothing

        let inset = borderWidth / 2 + glowRadius
        let r = bounds.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return }

        // U-shape: start top-left, down to bottom (rounded) across to right, up to top-right.
        // (No top edge — the notch top is the screen edge.)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.maxY))                       // top-left
        path.line(to: NSPoint(x: r.minX, y: r.minY + cornerRadius))        // down left side
        path.appendArc(withCenter: NSPoint(x: r.minX + cornerRadius, y: r.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 180, endAngle: 270)  // bottom-left corner
        path.line(to: NSPoint(x: r.maxX - cornerRadius, y: r.minY))        // across bottom
        path.appendArc(withCenter: NSPoint(x: r.maxX - cornerRadius, y: r.minY + cornerRadius),
                       radius: cornerRadius, startAngle: 270, endAngle: 360) // bottom-right corner
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))                       // up right side
        path.lineWidth = borderWidth
        path.lineCapStyle = .round

        let c = strokeColor.withAlphaComponent(strokeAlpha)
        let shadow = NSShadow()
        shadow.shadowColor = c
        shadow.shadowBlurRadius = glowRadius
        shadow.shadowOffset = .zero
        shadow.set()
        c.setStroke()
        path.stroke()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds (0 warnings).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add NotchOutlineView (U-shaped glowing notch border)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `NotchSurface` — overlay window + animation

**Files:**
- Create: `Sources/ClaudeSignal/Surfaces/NotchSurface.swift`

No unit tests (window + real hardware; visual QA on friend's M1). Gate: `swift build` clean.

- [ ] **Step 1: Implement the surface**

`Sources/ClaudeSignal/Surfaces/NotchSurface.swift`:
```swift
import AppKit
import ClaudeSignalCore

/// Renders the light as a U-shaped glow around the camera notch.
/// Mirrors TouchBarSurface's render/animation logic, sharing LightAnimation.
/// On screens without a notch, builds no window and render() is a no-op — no crash,
/// menu bar unaffected. Acceptance is via a notch Mac (developer has none).
@MainActor
final class NotchSurface: SignalSurface {
    private let window: NSWindow?
    private let outlineView: NotchOutlineView?
    private var timer: Timer?
    private var current: DisplayState?

    init() {
        // Use the main screen's notch geometry (v1: main screen only).
        if let screen = NSScreen.main,
           let frame = NotchGeometry.outlineFrame(NotchSurface.input(for: screen)) {
            let win = NSWindow(contentRect: frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .statusBar
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.hasShadow = false
            let view = NotchOutlineView(frame: NSRect(origin: .zero, size: frame.size))
            win.contentView = view
            win.orderFrontRegardless()
            self.window = win
            self.outlineView = view
        } else {
            // No notch on this Mac → complete no-op.
            self.window = nil
            self.outlineView = nil
            FileHandle.standardError.write(Data(
                "claude-signal: no notch on main screen; notch surface disabled.\n".utf8))
        }
        render(.off)
    }

    /// Capture NSScreen notch values into the pure geometry input.
    private static func input(for screen: NSScreen) -> NotchInsetInput {
        NotchInsetInput(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxLeft: screen.auxiliaryTopLeftArea,
            auxRight: screen.auxiliaryTopRightArea
        )
    }

    func render(_ state: DisplayState) {
        guard let outlineView else { return }   // no-op on non-notch Macs
        guard state != current else { return }
        current = state
        timer?.invalidate(); timer = nil

        let color = Appearance.color(for: state)
        guard let config = LightAnimation.config(for: state) else {
            outlineView.setLight(color: color, alpha: state == .off ? 0 : 1)
            return
        }
        startTimer(period: config.period, color: color, ease: config.ease)
    }

    private func startTimer(period: TimeInterval, color: NSColor, ease: Bool) {
        guard let outlineView else { return }
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard self != nil else { return }
            let elapsed = Date().timeIntervalSince(start)
            let alpha = LightAnimation.alpha(elapsed: elapsed, period: period, ease: ease)
            MainActor.assumeIsolated {
                outlineView.setLight(color: color, alpha: alpha)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds (0 warnings). If Swift 6 flags the `outlineView` capture in the timer closure, the `guard let outlineView` at the top of `startTimer` captures it as a local constant (non-optional) used inside `assumeIsolated`; that is the intended pattern. If a concurrency error remains, report the exact message.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add NotchSurface (click-through notch overlay, shares LightAnimation)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Wire `NotchSurface` into `AppController`

**Files:**
- Modify: `Sources/ClaudeSignal/AppController.swift`

No unit tests. Gate: `swift build` clean; `--simulate` still works; no-op self-check on the dev's non-notch Mac.

- [ ] **Step 1: Add NotchSurface to the surfaces array**

Read `Sources/ClaudeSignal/AppController.swift`. Find the line:
```swift
        surfaces = [MenuBarSurface(), TouchBarSurface()]
```
Change it to:
```swift
        surfaces = [MenuBarSurface(), TouchBarSurface(), NotchSurface()]
```
Leave everything else unchanged.

- [ ] **Step 2: Build, test, confirm CLI path**

Run: `swift build && swift test`
Expected: build clean; all 57 tests pass (52 prior + 5 NotchGeometry).

Run: `swift run ClaudeSignal --simulate working away`
Expected: `aggregate=working presence=away -> display=working`.
(Do NOT run `swift run ClaudeSignal` with no args here — it starts the GUI loop and blocks.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: render to the notch surface too (Phase 3 wired)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Docs + verification + M1 acceptance checklist

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full automated suite**

Run: `swift test && bash hooks/tests/test-on-event.sh && swift build -c release`
Expected: 57 unit tests pass; 19 hook checks ok; release build succeeds.

- [ ] **Step 2: No-op self-check (developer's non-notch Mac)**

This is the ONE visual thing the developer can verify themselves. With a release build:
```bash
swift run ClaudeSignal &        # starts in background; on a non-notch Mac it must NOT crash
sleep 3
# Expect on stderr: "claude-signal: no notch on main screen; notch surface disabled."
# Menu bar dot should still appear and work. Then quit:
kill %1 2>/dev/null || true
```
Confirm: app launches, prints the "no notch" line, menu bar still works, no crash. (Do this once, then stop the background instance.)

- [ ] **Step 3: Update README roadmap**

In `README.md`, find the roadmap line for Phase 3, currently:
```
- ⏳ **Phase 3** — notch "Dynamic Island" overlay (for Macs with a notch) · 刘海"灵动岛"覆盖层（用于带刘海的 Mac）
```
Replace it with:
```
- ✅ **Phase 3** — notch outline light: a U-shaped glow around the camera notch on notch Macs (no-op on others) · 刘海描边灯：带刘海的 Mac 上沿摄像头刘海一圈 U 形辉光（无刘海机器自动跳过）
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: mark Phase 3 (notch outline light) done in README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Produce the M1 acceptance checklist (report to controller, do not execute)**

The developer can't see a notch. Hand off this checklist for the friend's M1 (notch) Mac:

1. Build & run on the M1:
   ```bash
   git clone <repo> && cd claude-signal
   swift run ClaudeSignal       # or build release + run the binary
   ```
2. Look at the notch: a **U-shaped colored glow** should trace the bottom + sides of the notch.
3. Drive the states from another terminal and watch the notch glow change (it should match the menu-bar dot's color/animation):
   ```bash
   H=hooks/on-event.sh
   echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo"}' | bash $H   # blue breathing
   echo '{"hook_event_name":"Notification","session_id":"demo","message":"needs your permission"}' | bash $H  # yellow flash
   echo '{"reset_at":'"$(($(date +%s)+120))"',"raw":"t"}' > ~/.claude-signal/ratelimit.json  # red (usage limit)
   rm ~/.claude-signal/ratelimit.json                                            # back to normal
   echo '{"hook_event_name":"Stop","session_id":"demo"}' | bash $H               # green when idle ~30s
   echo '{"hook_event_name":"SessionEnd","session_id":"demo"}' | bash $H         # off
   ```
4. Screenshot the notch in (at least) the blue and red states and send back, noting: does the glow **fit** the notch (not floating off / clipping in)? corner radius look right? too bright / too dim? Report findings for geometry/constant tuning (`margin` in NotchGeometry, `borderWidth`/`cornerRadius`/`glowRadius` in NotchOutlineView).

---

## Self-Review

**Spec coverage** (against `2026-05-31-claude-signal-phase3-notch-design.md`):
- §3 U-shape, no top edge → NotchOutlineView path (Task 2). ✓
- §3 tunable named constants → `borderWidth`/`cornerRadius`/`glowRadius` in NotchOutlineView (Task 2). ✓
- §4 presence rules identical → NotchSurface reuses LightAnimation.config + `.error`/etc never presence-gated by reusing the same render shape as TouchBarSurface; Coordinator/SignalResolver unchanged. ✓
- §5 third SignalSurface, brain untouched → Task 3 + Task 4 (only AppController + executable touched; core gains only pure NotchGeometry). ✓
- §6 NSScreen geometry (safeAreaInsets/auxiliary areas), no-notch ⇒ no-op → NotchGeometry + NotchSurface.input (Tasks 1, 3). ✓
- §7 borderless / .statusBar / clear / ignoresMouseEvents / canJoinAllSpaces+stationary → NotchSurface window setup (Task 3). ✓
- §8 drawing + animation identical to TouchBarSurface → NotchOutlineView + NotchSurface.startTimer (Tasks 2, 3). ✓
- §9 graceful no-op + public APIs → NotchSurface else-branch + Task 5 Step 2 self-check. ✓
- §10 NotchGeometry in ClaudeSignalCore → Task 1. ✓
- §11 geometry unit-tested with realistic per-model values + no-notch case → NotchGeometryTests (Task 1). ✓
- §12 M1 acceptance checklist → Task 5 Step 5. ✓
- §13 scope: main screen only, no interactive island, constants-only restyle → reflected; no extra tasks added. ✓

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `NotchInsetInput(screenFrame:safeAreaTop:auxLeft:auxRight:)`, `NotchGeometry.outlineFrame(_:margin:)`, `NotchOutlineView.setLight(color:alpha:)`, `NotchSurface: SignalSurface` with `render(_:)`, `LightAnimation.config(for:)`/`.alpha(elapsed:period:ease:)`, `Appearance.color(for:)` — all consistent with the existing codebase and across tasks. ✓

**Known fragilities (accepted):** the geometry→window placement may need screenshot-driven tuning on the friend's M1 (the pure tests verify the math, not the on-screen fit). `margin`/style constants are the tuning knobs. Documented in Task 5 Step 5.
