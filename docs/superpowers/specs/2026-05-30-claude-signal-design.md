# claude-signal — Design

**Status:** Approved design (brainstorming complete) · **Date:** 2026-05-30
**Working name:** `claude-signal` (rename freely)

> **状态：** 已确认的设计（头脑风暴完成）· **日期：** 2026-05-30
> **暂用名：** `claude-signal`（可随意改名）

## 1. Purpose

Claude Code tasks often run for minutes. You don't want to babysit the terminal, but
you also don't want to miss the moment it finishes or gets stuck. `claude-signal` is a
"traffic light" for Claude Code's state, shown on **always-visible macOS system surfaces**
(menu bar, then Touch Bar, then the notch "island") so you can glance — not stare.

Inspired by [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light),
which drives a *physical* USB traffic light. This project replaces the physical light with
the Mac's own built-in surfaces.

> **目的：** Claude Code 的任务常常要跑好几分钟。你既不想一直盯着终端，又不想错过它完成
> 或卡住的那一刻。`claude-signal` 就是 Claude Code 状态的"红绿灯"，显示在 **macOS 上始终
> 可见的系统区域**（先是菜单栏，然后 Touch Bar，再到刘海"灵动岛"），让你只需瞥一眼，而不
> 用盯着看。灵感来自 [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light)，
> 那个项目驱动的是一盏*物理* USB 红绿灯；本项目用 Mac 自带的系统区域取代物理灯。

## 2. Scope

### In scope (v1)
- Monitor **Claude Code**: Terminal CLI **and** the VS Code extension (both share `~/.claude/settings.json` hooks).
- Surfaces, built in phases: **menu bar → Touch Bar → notch island**.
- Presence-aware behavior (don't nag while the user is actively at the keyboard).

### Out of scope (deferred)
- The **Claude desktop chat / Cowork app** — it exposes no hooks/automation API. Reflecting
  its state would require fragile Accessibility/screen-scraping. Possible future stretch goal.
- **In-editor indicators** (e.g., a VS Code status-bar dot). Explicitly rejected: the value of
  the light is that it's visible *when you've tabbed away from the editor*.
- Other agents (Codex, etc.), config GUI, sound — possible later.

> **范围：**
> **v1 包含：** 监控 **Claude Code**——终端 CLI **和** VS Code 插件（两者共用
> `~/.claude/settings.json` 里的 hooks）；分阶段实现的显示区域：**菜单栏 → Touch Bar →
> 刘海灵动岛**；感知"人在不在"的行为（你正在键盘前操作时不打扰你）。
> **暂不包含（搁置）：** **Claude 桌面聊天 / Cowork app**——它没有 hook / 自动化 API，要反映
> 它的状态只能靠脆弱的辅助功能(Accessibility)或截图识别，列为未来可能的拓展目标；**编辑器内
> 的指示器**（比如 VS Code 状态栏小点）——明确否决，因为这个灯的价值恰恰在于你*切走离开编辑
> 器*时还能看到；其它 agent（如 Codex）、配置图形界面、声音提示——以后再说。

## 3. State language

| Light | Meaning | Notes |
|---|---|---|
| 🔵 **Breathing blue** | Claude is working | thinking / running tools / editing. No action needed. |
| 🟡 **Flashing yellow** | Needs permission | a permission/confirmation prompt (yes / allow once / always allow). Claude is **blocked** on you. |
| 🔴 **Flashing red** | Error | e.g. network down or other serious failure. Rare by design — rarely seeing red means things are healthy. |
| 🟢 **Steady green** | Done, waiting for you | Claude finished its turn. Only meaningful when you've **stepped away** (see presence). |
| ⚫️ **Off** | Your turn / idle | You're actively at the keyboard, or nothing is happening. The light stays dark while you type. |

**Priority (when multiple sessions run at once):** 🔴 > 🟡 > 🔵 > 🟢 > ⚫️.

Rationale for the split (differs from the reference project, intentionally): the reference
lumps permission+blocked+failed into red and uses yellow for "done, come look." We instead
distinguish three *different* non-working situations by their meaning — done (green),
blocked-on-permission (yellow), error (red) — which is clearer to reason about.

> **状态语言：**
> 🔵 **呼吸蓝** = Claude 正在工作（思考 / 跑工具 / 改文件），无需你操作。
> 🟡 **闪烁黄** = 需要权限（yes / allow once / always allow 这类确认），Claude **被卡住**等你。
> 🔴 **闪烁红** = 出错（如断网或其它严重故障）。设计上很少出现——很少见到红灯说明一切正常。
> 🟢 **常亮绿** = 做完了，在等你。Claude 结束了这一轮，只有当你**已经离开**时才有意义（见"感知"）。
> ⚫️ **灭灯** = 轮到你了 / 空闲。你正在键盘前操作，或什么都没发生；你打字时灯保持熄灭。
> **优先级（多个会话同时跑时取最高）：** 🔴 > 🟡 > 🔵 > 🟢 > ⚫️。
> 这样划分的理由（有意区别于参考项目）：参考项目把"权限+阻塞+失败"都归为红灯，用黄灯表示
> "做完了来看看"；我们则按含义区分三种*不同*的非工作情况——做完(绿)、卡在权限(黄)、出错
> (红)——更好理解。

## 4. Architecture

Two halves: **sensing** lives inside Claude Code; **displaying** is one tiny background app.

```
Claude Code (Terminal CLI + VS Code extension)
        │  event JSON on stdin
        ▼
Hook scripts  (shell, installed into ~/.claude/settings.json)
        │  writes one JSON file per session
        ▼
~/.claude-signal/sessions/<session_id>.json
        │  watched
        ▼
Core daemon (Swift, always-on background app, no Dock icon)
   ├── StateStore      read / watch / clean session files
   ├── Aggregator      [SessionState] → AggregateState   (pure)
   ├── PresenceMonitor macOS idle-time → present / away
   ├── SignalResolver  (Aggregate, Presence) → DisplayState  (pure)
   └── Coordinator     wires it together
        │  final display state
        ▼
Surfaces (behind a shared SignalSurface interface)
   ├── MenuBarSurface   Phase 1
   ├── TouchBarSurface  Phase 2
   └── NotchSurface     Phase 3
```

**Key property:** the brain is pure logic with no UI → fully unit-testable. Each surface is
an isolated plug-in; adding one never touches the brain.

> **架构：** 分两半——**感知**活在 Claude Code 内部；**显示**是一个极小的后台常驻 app。
> 数据流向（见上图）：Claude Code（终端 + VS Code 插件）通过 stdin 发出事件 JSON → Hook 脚本
> （shell，装进 `~/.claude/settings.json`）为每个会话写一个 JSON 文件 →
> `~/.claude-signal/sessions/<会话id>.json` → 核心后台进程（Swift，常驻、无 Dock 图标）监听
> 这些文件，内含 StateStore（读/监听/清理会话文件）、Aggregator（多会话聚合，纯逻辑）、
> PresenceMonitor（系统空闲时间 → 在场/离开）、SignalResolver（聚合状态+在场 → 最终显示状态，
> 纯逻辑）、Coordinator（把它们串起来）→ 最终显示状态送到各个显示区域（菜单栏 P1 / Touch Bar
> P2 / 刘海 P3，背后共用一个 SignalSurface 接口）。
> **关键特性：** "大脑"是纯逻辑、无 UI，因此可完整单元测试；每个显示区域都是独立插件，新增一个
> 永远不碰大脑。

## 5. Session state file

One file per session at `~/.claude-signal/sessions/<session_id>.json`:

```json
{
  "session_id": "abc123",
  "state": "working | permission | done | error",
  "updated_at": 1780150000,
  "cwd": "/path/to/project",
  "source": "terminal | vscode"
}
```

Hook scripts only ever write these files. The daemon only ever reads/cleans them.

> **会话状态文件：** 每个会话一个文件，位于 `~/.claude-signal/sessions/<会话id>.json`（结构见
> 上）。Hook 脚本只负责*写*这些文件，后台进程只负责*读/清理*这些文件——职责严格分开。

## 6. Event → session-state mapping

Claude Code hook event → the state written for that session:

| Hook event | State written | Light (pre-presence) |
|---|---|---|
| `SessionStart` | registered, no work | ⚫️ off |
| `UserPromptSubmit` | working | 🔵 |
| `PreToolUse` / `PostToolUse` | working (keepalive) | 🔵 |
| `Notification` (permission-type message) | permission | 🟡 |
| `Stop` | done | 🟢 (presence-gated) |
| `SubagentStop` | working (main agent continues) | 🔵 |
| `SessionEnd` | delete the file | ⚫️ off |

The `Notification` hook fires both for permission requests and for "waiting for input."
The script branches on the message content; only permission-type messages map to 🟡.

> **事件 → 会话状态 的映射：** 见上表（Claude Code 的 hook 事件 → 为该会话写入的状态 → 应用
> 在场判断前对应的灯）。注意：`Notification` 这个 hook 在"请求权限"和"等待输入"两种情况下都
> 会触发，脚本会根据消息内容分支判断，**只有权限类消息才映射为 🟡**。

## 7. Resolver logic

1. **Aggregate**: highest-priority state across all live sessions — 🔴 error > 🟡 permission > 🔵 working > 🟢 done.
2. **Apply presence**:
   - 🔴 / 🟡 / 🔵 → **always shown** (Claude needs you, or is busy — never suppressed).
   - 🟢 done → **presence-gated**: user *away* (no input for ~30s) → 🟢; user *present* → ⚫️ off.
   - no live sessions → ⚫️ off.

**Presence** = macOS system idle time (seconds since last keyboard/mouse/HID event), via
`CGEventSource.secondsSinceLastEventType`. Threshold default ~30s, configurable. Returning
to the keyboard flips 🟢 → ⚫️ within ~1s.

**Example:** terminal A working 🔵, VS Code B done 🟢, terminal C on permission 🟡 →
aggregate = 🟡 → light is yellow (the most useful thing to surface is "something's blocked on you").

> **解析逻辑（Resolver）：**
> ① **聚合**：取所有存活会话中优先级最高的状态——🔴 出错 > 🟡 权限 > 🔵 工作 > 🟢 完成。
> ② **应用在场判断**：🔴 / 🟡 / 🔵 → **始终显示**（Claude 需要你、或正忙，绝不抑制）；🟢 完成
> → **受在场判断控制**：你*离开*（约 30 秒无输入）→ 显示 🟢；你*在场*→ ⚫️ 灭灯；没有存活会话
> → ⚫️ 灭灯。
> **在场判断** = macOS 系统空闲时间（距上次键鼠/HID 事件的秒数），通过
> `CGEventSource.secondsSinceLastEventType` 获取；默认阈值约 30 秒，可配置；你一回到键盘，
> 🟢 会在约 1 秒内变 ⚫️。
> **例子：** 终端 A 工作中 🔵、VS Code B 已完成 🟢、终端 C 在等权限 🟡 → 聚合结果 = 🟡 → 灯显示
> 黄色（因为最该提醒你的是"有东西卡着等你"）。

## 8. Red (error) detection — deliberately conservative

Claude Code has **no clean error hook**, so:
- **v1 trigger:** the daemon watches general network reachability via `NWPathMonitor`. If there is no satisfied network path *while a session is working* → 🔴. (More conservative than per-host checks: a captive portal or dead-internet-but-connected-Wi-Fi case won't trigger red.)
- Generic tool/command failures (a bash command exiting non-zero) are **intentionally not red** —
  they're common and usually benign.
- Richer hook-based failure signals are a future enhancement. Rarely seeing red is the goal.

> **红灯（出错）检测——有意保守：** Claude Code **没有干净的"出错"hook**，所以：
> **v1 触发条件**——后台进程通过 `NWPathMonitor` 监听整体网络可达性；若在*有会话正在工作时*没有任何可用网络路径 → 🔴。（比按主机探测更保守：连着 Wi-Fi 但无网/门户认证的情况不会触发红灯。）普通的工具/命令失败（某个 bash 命令返回
> 非零）**有意不算红灯**——它们很常见且通常无害；更丰富的基于 hook 的失败信号留作未来增强。
> 目标就是：很少见到红灯。

## 9. Crash safety

If a session file goes stale (no update for ~5 min and no `SessionEnd`) — e.g. terminal killed
mid-run — the daemon treats it as dead and cleans it up, so the light never gets stuck on blue.

> **崩溃安全：** 如果某个会话文件变"陈旧"（约 5 分钟无更新且没有收到 `SessionEnd`）——比如终端
> 在运行中途被杀掉——后台进程会判定它已死并清理掉，这样灯永远不会卡在蓝色上。

## 10. Surfaces & feasibility notes

- **Menu bar** — `NSStatusItem` colored dot. Trivial, universal (works on every Mac). The baseline.
- **Touch Bar** — persistent item in the system **Control Strip** (the always-present region).
  Uses the semi-documented `NSTouchBar` Control-Strip registration approach that apps like
  **Pock** use. Feasible; expect to spend time on the registration details.
- **Notch island** — borderless, always-on-top, non-activating `NSWindow` positioned over the
  camera notch (the technique apps like **Boring Notch** / NotchNook use).

All three conform to a single `SignalSurface` protocol: `func render(_ state: DisplayState)`.

> **显示区域与可行性说明：**
> **菜单栏**——`NSStatusItem` 彩色小圆点，简单、通用（每台 Mac 都能用），是基准方案。
> **Touch Bar**——常驻在系统 **Control Strip**（始终显示的那块区域）的一个项目，采用 **Pock**
> 这类 app 走的、半官方文档的 `NSTouchBar` Control-Strip 注册方式；可行，但注册细节要花点时间踩坑。
> **刘海灵动岛**——一个无边框、置顶、不抢焦点的 `NSWindow`，定位在摄像头刘海处（**Boring Notch**
> / NotchNook 这类 app 用的技术）。
> 这三者都实现同一个 `SignalSurface` 协议：`func render(_ state: DisplayState)`。

## 11. Tech stack & project structure

- **Swift + AppKit.** Background agent (`LSUIElement` — no Dock icon). Auto-start at login via
  `SMAppService`. **Zero third-party dependencies** (Foundation/AppKit only). File watching via
  `DispatchSource`.
- **Why Swift, not Python/JS:** the menu bar / Touch Bar Control Strip / notch overlay are AppKit
  objects with no Python or JS API. Any non-native stack would still require Swift for the
  surfaces *plus* a second runtime (and Electron's ~150MB Chromium contradicts the "small"
  requirement). The logic that *could* be Python/JS is ~150 trivial lines, and the sensing half
  is already shell scripts — so Swift is only imposed where it's genuinely required.

```
claude-signal/
  hooks/
    on-event.sh        # maps a Claude Code event → writes session JSON
    install.sh         # merges hooks into ~/.claude/settings.json (non-destructive)
  ClaudeSignal/
    Core/
      SessionState.swift
      StateStore.swift
      Aggregator.swift
      PresenceMonitor.swift
      SignalResolver.swift
      Coordinator.swift
    Surfaces/
      SignalSurface.swift
      MenuBarSurface.swift
      TouchBarSurface.swift
      NotchSurface.swift
    App/AppDelegate.swift
  Tests/
  docs/superpowers/specs/
```

> **技术栈与项目结构：**
> **Swift + AppKit。** 后台代理（`LSUIElement`——无 Dock 图标），通过 `SMAppService` 开机自启，
> **零第三方依赖**（仅 Foundation/AppKit），文件监听用 `DispatchSource`。
> **为什么用 Swift 而非 Python/JS：** 菜单栏 / Touch Bar Control Strip / 刘海覆盖层都是 AppKit
> 对象，没有 Python 或 JS 的 API。任何非原生方案最终都得为这些显示区域写 Swift，*外加*再装一个
> 运行时（而 Electron 那 ~150MB 的 Chromium 与"小巧"的要求相悖）。那部分*能*用 Python/JS 写的
> 逻辑只有约 150 行琐碎代码，而感知那一半本来就是 shell 脚本——所以 Swift 只用在真正必需的地方。
> 项目结构见上。

## 12. Build phases (each ships a usable tool)

- **Phase 0 — Foundation (no UI):** session schema, hook scripts + installer, `StateStore`,
  `Aggregator`, `PresenceMonitor`, `SignalResolver`, plus a `--simulate` CLI that injects fake
  states and prints the resolved light. The whole brain built and TDD'd with zero AppKit.
- **Phase 1 — Menu bar (MVP):** `NSStatusItem` dot with animations (breathing blue, flashing
  yellow/red, steady green), wired to the Coordinator, auto-start at login. **First shippable;
  works on both current and next Mac.**
- **Phase 2 — Touch Bar:** persistent Control Strip item. Current Mac.
- **Phase 3 — Notch island:** notch overlay window. Next Mac.
- **Later/optional:** config UI (threshold, colors), sound ping, other agents (Codex), richer red.

> **构建阶段（每个阶段都能交付一个可用的工具）：**
> **阶段 0 — 基础（无 UI）：** 会话数据结构、hook 脚本 + 安装器、`StateStore`、`Aggregator`、
> `PresenceMonitor`、`SignalResolver`，外加一个 `--simulate` CLI（注入假状态并打印解析出的灯）。
> 整个"大脑"在完全不碰 AppKit 的情况下用 TDD 建好。
> **阶段 1 — 菜单栏（MVP）：** `NSStatusItem` 小圆点 + 动画（呼吸蓝、闪黄/闪红、常亮绿），接到
> Coordinator，开机自启。**第一个可交付版本；当前和未来的 Mac 都能用。**
> **阶段 2 — Touch Bar：** 常驻 Control Strip 项目。用于当前 Mac。
> **阶段 3 — 刘海灵动岛：** 刘海覆盖窗口。用于新 Mac。
> **以后/可选：** 配置界面（阈值、颜色）、声音提示、其它 agent（Codex）、更丰富的红灯逻辑。

## 13. Testing strategy (TDD)

- `Aggregator` + `SignalResolver` → table-driven XCTest covering every state×presence combo.
  This is where correctness lives; needs no UI.
- `StateStore` → tests against a temp dir simulating file writes + stale cleanup.
- Hook scripts → shell tests: pipe sample event JSON to stdin, assert the file written.
- `--simulate` CLI → manual visual QA of each surface without running Claude.
- Surfaces stay thin, so little untested logic lives in AppKit.

> **测试策略（TDD）：**
> `Aggregator` + `SignalResolver` → 表驱动的 XCTest，覆盖每一种"状态×在场"的组合——正确性就
> 集中在这里，且不需要 UI；`StateStore` → 在临时目录里模拟文件写入 + 陈旧清理来测试；hook 脚本
> → shell 测试：把样例事件 JSON 通过 stdin 喂进去，断言写出的文件；`--simulate` CLI → 不运行
> Claude 也能对每个显示区域做人工视觉验收；显示区域保持很薄，所以 AppKit 里几乎没有未被测试的逻辑。

## 14. Open questions / future

- Exact Touch Bar Control-Strip registration approach (validate against current macOS).
- Whether to expose presence threshold / colors in a small config file from day one.
- Notch overlay sizing across different Mac notch geometries.

> **待定问题 / 未来事项：**
> Touch Bar Control-Strip 的确切注册方式（需在当前 macOS 上验证）；是否从第一天起就把在场阈值 /
> 颜色暴露到一个小配置文件里；刘海覆盖层在不同 Mac 刘海几何尺寸下的大小适配。
