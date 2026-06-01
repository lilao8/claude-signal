# claude-signal — Phase 3 (Notch Outline Light) — Design

**Status:** Approved design (brainstorming complete) · **Date:** 2026-05-31
**Builds on:** the shipped menu-bar + Touch Bar + usage-limit-red app on `main`.

> **状态：** 已确认设计（头脑风暴完成）· **日期：** 2026-05-31
> **基于：** 已上线的菜单栏 + Touch Bar + 用量上限红灯（在 main 上）。

## 1. Purpose · 目的

Add a third display surface: a glowing **U-shaped outline around the camera notch** on notch-equipped Macs, breathing/flashing in the same color as the menu bar and Touch Bar lights. It's the most "Dynamic Island–like" surface, kept honest: macOS has no real interactive Dynamic Island, so this is a small click-through overlay window that traces the notch — not an expanding interactive island.

新增第三个显示区域：在带刘海的 Mac 上，沿摄像头刘海画一圈 **U 形发光描边**，随状态呼吸/闪烁，颜色与菜单栏和 Touch Bar 的灯一致。这是最接近"灵动岛"观感的区域，但说清楚：macOS 没有真正可交互的灵动岛，所以这是一个贴着刘海、可点击穿透的小覆盖窗口——不是会展开的交互岛。

## 2. Hardware reality · 硬件现实

The notch exists only on notch-equipped Macs (14"/16" MacBook Pro, recent Airs). The developer's own machine is a 2019 Intel MacBook Pro with **no notch**, so they cannot visually verify this surface — acceptance relies on a friend's M1 (notch) Mac via screenshots. This drives two design choices: (a) graceful no-op on non-notch Macs, and (b) extracting geometry math into a pure, unit-testable function so most correctness can be verified without a notch.

刘海只有带刘海的 Mac 才有。开发者本人是 2019 Intel MacBook Pro，**无刘海**，无法自己看效果——验收靠朋友的 M1（带刘海）截图。这驱动了两个设计决策：(a) 无刘海机器静默降级；(b) 把几何数学抽成可单测的纯函数，让大部分正确性无需刘海即可验证。

## 3. Form · 形态

A **U-shaped outline** (left edge + bottom edge with rounded corners + right edge; no top edge — the notch's top *is* the physical screen edge, so there's nothing to trace there). Color follows state (🔵blue/🟡yellow/🔴red/🟢green); breathe/flash animation is identical to the other surfaces (shared `LightAnimation`). Glow strength, border width, corner radius, and breathe period are **named constants** so a user can re-style it (thicker, brighter, faster) by editing one line — no need to understand the window logic.

**U 形描边**（左边 + 带圆角的下沿 + 右边；无顶边——刘海顶部就是屏幕物理上边缘，无可描）。颜色随状态变（蓝/黄/红/绿）；呼吸/闪烁动画与其它区域完全一致（共享 `LightAnimation`）。发光强度、边框粗细、圆角、呼吸周期都是**命名常量**，用户改一行就能换风格（更粗/更亮/更快），无需理解窗口逻辑。

## 4. Presence behavior · 在场行为

Same rules as the menu bar and Touch Bar (no special-casing): 🔴 red / 🟡 yellow / 🔵 blue are **always shown**; 🟢 green (done) is **presence-gated** (only when away). Rationale: consistency, and "blue breathing while working" is the tool's core value. If it's too bright in the visual field, that's a glow-constant tuning issue, not a state-logic change.

与菜单栏、Touch Bar 规则一致（不做特例）：🔴红 / 🟡黄 / 🔵蓝 **始终显示**；🟢绿（完成）**受在场判断控制**（仅离开时亮）。理由：一致性，且"工作中蓝色呼吸"是工具核心价值。若视野里太亮，那是调发光常量的事，不改状态逻辑。

## 5. Architecture · 架构

`NotchSurface` is a third `SignalSurface`, structurally identical to `TouchBarSurface` (render + animation timer driven by `LightAnimation`), added to `AppController.surfaces`. The brain (`ClaudeSignalCore`) is not touched.

`NotchSurface` 是第三个 `SignalSurface`，结构与 `TouchBarSurface` 完全相同（render + 由 `LightAnimation` 驱动的动画 timer），加进 `AppController.surfaces`。大脑（`ClaudeSignalCore`）不动。

```
AppController.surfaces = [MenuBarSurface(), TouchBarSurface(), NotchSurface()]
                                                                │ render(state)
                                                                ▼
NotchSurface  (@MainActor, : SignalSurface)
   ├── NotchGeometry         pure: NSScreen insets → outline window frame (UNIT-TESTED)
   ├── borderless click-through overlay NSWindow (transparent, top level)
   ├── NotchOutlineView      draws the U-shaped glowing border at color+alpha
   └── animation timer       reuses LightAnimation.config/alpha (same as other surfaces)
```

**Reuse:** color from existing `Appearance.color`, timing from existing `LightAnimation` — so the notch light is automatically the same color and rhythm as the other surfaces.

**复用：** 颜色来自现有 `Appearance.color`，时序来自现有 `LightAnimation`——所以刘海灯自动与其它区域同色同节奏。

## 6. Notch geometry · 刘海几何

macOS 12+ exposes notch geometry on `NSScreen`:
- `safeAreaInsets.top > 0` → this screen has a notch (value = notch height). **`== 0` → no notch → `NotchSurface` is a complete no-op** (this is the degradation check).
- `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` → the menu-bar rectangles flanking the notch. The notch's left/right bounds (and width) are derived from the inner edges of these two rects.
- All values read live from the API — no hard-coded per-model numbers.

macOS 12+ 在 `NSScreen` 上暴露刘海几何：`safeAreaInsets.top > 0` 表示有刘海（值=刘海高度），`== 0` 则 `NotchSurface` 完全无操作（降级判断）；`auxiliaryTopLeftArea`/`auxiliaryTopRightArea` 是刘海两侧的菜单栏矩形，由它们的内边缘反推刘海的左右边界和宽度；全部实时读取，不写死任何机型数字。

## 7. Overlay window · 覆盖窗口

A `NSWindow` with:
- `styleMask = .borderless`
- `level = .statusBar` (or higher — floats above the menu bar around the notch)
- `backgroundColor = .clear`, `isOpaque = false` (window invisible; only the outline shows)
- `ignoresMouseEvents = true` (**click-through** — never blocks clicks on the menu bar / anything near the notch)
- `collectionBehavior = [.canJoinAllSpaces, .stationary]` (stays put across Space switches / full-screen)
- positioned over the small region just below + beside the notch, width = notch width + small margin.

（窗口属性见上：无边框、置顶、透明、点击穿透、跨桌面常驻、贴在刘海下方+两侧。）

## 8. Drawing · 绘制

`NotchOutlineView` (custom NSView) draws a **U-shaped path** (left vertical + rounded bottom + right vertical, no top) stroked in the current color at the current alpha, with a glow (`shadow`/glow radius). Tunable named constants: `borderWidth`, `cornerRadius`, `glowRadius`, `breathePeriod`. The animation timer is identical to `TouchBarSurface` (1/30s, `LightAnimation.alpha`, `MainActor.assumeIsolated`, `[weak self]`, single `.common` run-loop registration).

`NotchOutlineView`（自定义 NSView）画 U 形路径（左竖+圆角下沿+右竖，无顶），用当前颜色+alpha 描边并加发光。可调命名常量：`borderWidth`/`cornerRadius`/`glowRadius`/`breathePeriod`。动画 timer 与 `TouchBarSurface` 完全相同。

## 9. Graceful degradation · 优雅降级

On any screen without a notch (the developer's Intel Mac, external displays, older models): `safeAreaInsets.top == 0` → `NotchSurface` creates no window, draws nothing, never crashes; the menu bar (and Touch Bar where present) work as usual. **The developer can self-verify this no-op path on their own machine** (`swift run`, confirm nothing breaks and no notch window appears). Unlike Touch Bar's private `DFRFoundation`, the notch APIs are **public**, so there's no "system update breaks it" hazard.

无刘海的任何屏幕（开发者 Intel Mac、外接显示器、旧机型）：`safeAreaInsets.top == 0` → 不建窗口、不画、不崩；菜单栏（及有 Touch Bar 的机器）照常。**开发者可在自己机器上自验这条 no-op 路径**。与 Touch Bar 的私有 `DFRFoundation` 不同，刘海 API 是**公开的**，无"系统更新就崩"隐患。

## 10. File structure · 文件结构

```
New (executable target):
  Sources/ClaudeSignal/Surfaces/NotchGeometry.swift     # pure: insets → outline frame (UNIT-TESTED)
  Sources/ClaudeSignal/Surfaces/NotchOutlineView.swift  # U-shaped glow NSView
  Sources/ClaudeSignal/Surfaces/NotchSurface.swift       # SignalSurface: window + animation
  Tests/ClaudeSignalCoreTests/... → see testing note     # geometry tests (see §11)

Modified:
  Sources/ClaudeSignal/AppController.swift               # surfaces += NotchSurface()
  README.md                                              # mark Phase 3 done
```

Note on test placement: `NotchGeometry` lives in the executable target, but to unit-test it, either (a) move the pure geometry struct into `ClaudeSignalCore` (preferred — pure logic belongs in the testable core), or (b) add an executable-target test target. **Decision: put `NotchGeometry` in `ClaudeSignalCore`** (it's pure math, no AppKit beyond `CGRect`/`CGFloat`), so it sits with the other pure logic and is covered by the existing `ClaudeSignalCoreTests`.

测试放置：把纯几何 `NotchGeometry` 放进 `ClaudeSignalCore`（纯数学，除 `CGRect`/`CGFloat` 外不碰 AppKit），与其它纯逻辑同处，由现有 `ClaudeSignalCoreTests` 覆盖。

## 11. Testing strategy · 测试策略

- **`NotchGeometry` (pure, the highest-risk + only auto-testable part):** XCTest fed with real per-model values (e.g. a 16" MacBook Pro's `safeAreaInsets.top` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`), asserting the computed outline window frame. Also test the **no-notch case** (`safeAreaInsets.top == 0` → returns nil / "no notch").
  **`NotchGeometry`（纯逻辑，风险最高且唯一可自动测）：** 用真实机型数值喂 XCTest，断言算出的描边窗口 frame；并测**无刘海**情形。
- **`NotchOutlineView` / `NotchSurface`:** no automated tests (GUI + real hardware); verified by the friend's M1 via screenshots.
  **`NotchOutlineView` / `NotchSurface`：** 无自动测（GUI+真硬件），靠朋友 M1 截图验收。
- **No-op self-check:** developer runs the app on their Intel Mac and confirms the notch surface does nothing and nothing breaks.
  **降级自检：** 开发者在 Intel Mac 上跑，确认刘海区域无动作、不崩。
- Existing 52 unit + 19 hook tests remain unaffected.

## 12. Acceptance via friend's M1 · 通过朋友 M1 验收

Because the developer can't see a notch, implementation ships with a short **M1 acceptance checklist**: how to run it, what to look for (U-shaped colored glow around the notch, breathing while Claude works, flashing yellow on permission, red on error/limit, off when idle-and-present), and how to screenshot for feedback. Expect 1–N rounds of geometry tuning (border placement / corner radius / fit) over screenshots — the pure `NotchGeometry` tests reduce, but don't eliminate, this.

因开发者看不到刘海，实现会附一份简短的 **M1 验收清单**：怎么跑、该看到什么（刘海周围 U 形彩色辉光，工作时呼吸，权限时闪黄，错误/限额时红，空闲且在场时灭）、怎么截图反馈。预期会有若干轮隔截图的几何微调；纯 `NotchGeometry` 测试能减少但无法消除这一点。

## 13. Scope (YAGNI) · 范围

- ✅ In: U-shaped notch outline, color/animation synced via shared LightAnimation, presence rules identical to other surfaces, public NSScreen geometry, pure testable geometry, graceful no-op, tunable constants.
  包含：U 形刘海描边、共享动画同步、与其它区域一致的在场规则、公开几何 API、可测纯几何、优雅降级、可调常量。
- ❌ Out: interactive/expanding Dynamic Island, top-edge tracing (impossible), per-user GUI for restyling (constants only), multi-display notch on more than the main screen (main screen only for v1).
  不包含：可交互/会展开的灵动岛、顶边描边（做不到）、改风格的图形界面（只给常量）、多显示器刘海（v1 仅主屏）。
