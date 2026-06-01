# claude-signal

A tiny native macOS "traffic light" for **Claude Code** state — shown on the menu bar and (on Touch Bar Macs) the Touch Bar Control Strip, so you can glance instead of babysitting the terminal.

一个小巧的原生 macOS **Claude Code** 状态"红绿灯"——显示在菜单栏，以及（带 Touch Bar 的 Mac 上）Touch Bar 的 Control Strip，让你瞥一眼就知道状态，而不用一直盯着终端。

> Claude Code tasks often run for minutes. You step away — and miss the moment it finishes, asks for permission, or gets stuck. claude-signal puts that state where your eyes already are.
>
> Claude Code 的任务常常要跑好几分钟。你切走去忙别的，就会错过它完成、要权限、或卡住的那一刻。claude-signal 把状态放在你余光所及之处。

---

## The light language · 灯语

| Light · 灯 | Meaning | 含义 |
|---|---|---|
| 🔵 **Breathing blue** | Claude is working (thinking / running tools) — no action needed | Claude 正在工作（思考 / 跑工具）——无需你操作 |
| 🟡 **Flashing yellow** | Needs your permission (yes / allow once / always allow) | 需要你授权（yes / allow once / always allow） |
| 🔴 **Flashing red** | Something's wrong: network down while working, **or a usage limit was hit** | 出问题了：工作时断网，**或撞到用量上限** |
| 🟢 **Steady green** | Done — and you've stepped away (it stays dark while you're typing) | 做完了——而且你已离开（你打字时它保持熄灭） |
| ⚫️ **Off** | Your turn, or nothing happening | 轮到你了，或什么都没发生 |

**Priority when several sessions run at once · 多会话同时运行时的优先级:** 🔴 > 🟡 > 🔵 > 🟢 > ⚫️

The green "done" light is **presence-aware**: it only appears when you've actually stepped away (~30s idle), and goes dark the instant you touch the keyboard — so it never nags you while you work.

绿色"完成"灯是**感知在场**的：只有当你真正离开（约 30 秒无操作）时才亮，你一碰键盘它立刻熄灭——所以它绝不会在你工作时打扰你。

The same light shows on the menu bar **and** the Touch Bar Control Strip. On Macs without a Touch Bar, the Touch Bar surface is a silent no-op and the menu bar works as usual.

同一个灯同时显示在菜单栏**和** Touch Bar Control Strip 上。没有 Touch Bar 的 Mac 上，Touch Bar 部分静默跳过，菜单栏照常工作。

---

## How it works · 工作原理

Two halves: **sensing** lives inside Claude Code; **displaying** is one tiny always-on background app.

分两半：**感知**活在 Claude Code 内部；**显示**是一个极小的、常驻后台的 app。

```
Claude Code (Terminal CLI + VS Code extension)
        │  lifecycle hook events (JSON on stdin)
        ▼
hooks/on-event.sh   (installed into ~/.claude/settings.json)
        │  writes one small JSON file per session
        ▼
~/.claude-signal/sessions/<id>.json     +     ~/.claude-signal/ratelimit.json
        │  watched (polled ~1×/sec)
        ▼
Background app (Swift, no Dock icon, auto-starts at login)
   ├── StateStore        read / clean session files
   ├── Aggregator        many sessions → one state (pure)
   ├── PresenceMonitor   macOS idle time → present / away
   ├── RateLimitStore    read account-level limit, self-expire
   ├── SignalResolver    (state + presence) → display state (pure)
   └── Coordinator       wires it together
        │  one final light
        ▼
   Menu bar  +  Touch Bar Control Strip
```

**Key property · 关键特性:** the "brain" is pure logic with no UI, so it's fully unit-tested. Each display surface is an isolated plug-in — adding one never touches the brain.

"大脑"是纯逻辑、无 UI，因此可完整单元测试。每个显示区域都是独立插件——新增一个永远不碰大脑。

### Usage-limit detection · 用量上限检测

When Claude Code hits a usage limit, it fires a `StopFailure` hook with `error: "rate_limit"`. The hook parses the reset time from the message and writes an account-level `ratelimit.json`. The light goes red and stays red until **either** the reset time passes **or** you successfully use Claude again (which covers upgrading / buying credits). The parser understands three reset-time formats: relative ("in 45 mins"), absolute-with-timezone, and absolute-local.

当 Claude Code 撞到用量上限时，会触发 `StopFailure` hook（`error: "rate_limit"`）。hook 从消息里解析出重置时间，写一个账号级的 `ratelimit.json`。灯变红并保持，直到**重置时间到了**、**或**你重新成功使用 Claude（覆盖了升级 / 购买额度的情况）。解析器支持三种重置时间格式：相对（"in 45 mins"）、带时区的绝对时间、本地绝对时间。

---

## Install · 安装

Requires macOS 13+ and a full Xcode toolchain (not just Command Line Tools).

需要 macOS 13+ 和完整的 Xcode 工具链（不能只装 Command Line Tools）。

```bash
git clone <repo> && cd claude-signal
bash hooks/install.sh                 # register Claude Code hooks · 注册 Claude Code hooks
bash scripts/install-launchagent.sh   # build release + auto-start at login · 构建 release 并设开机自启
```

`hooks/install.sh` is non-destructive — it merges into your existing `~/.claude/settings.json` and won't clobber other hooks or settings.

`hooks/install.sh` 是非破坏性的——它会合并进你现有的 `~/.claude/settings.json`，不会覆盖其它 hooks 或设置。

---

## Develop · 开发

```bash
swift test                                          # core unit tests · 核心单元测试 (52)
bash hooks/tests/test-on-event.sh                   # hook script tests · hook 脚本测试 (19)
swift run ClaudeSignal --simulate working,done away # headless light-resolution check · 无界面解析检查
swift run ClaudeSignal                              # run the app in the foreground · 前台运行 app
```

`--simulate` resolves the final light from fake states without any UI or Claude — handy for testing the logic:

`--simulate` 不依赖任何 UI 或 Claude，从假状态解析出最终的灯——方便测逻辑：

```bash
$ swift run ClaudeSignal --simulate working away
aggregate=working presence=away -> display=working
```

---

## Tech notes · 技术说明

- **Swift 6 + SwiftPM, zero third-party dependencies.** Pure-logic core library (`ClaudeSignalCore`, fully TDD'd) + a thin AppKit executable.
  **Swift 6 + SwiftPM，零第三方依赖。** 纯逻辑核心库（`ClaudeSignalCore`，完整 TDD）+ 一个很薄的 AppKit 可执行程序。
- **Why native Swift, not JS/Python?** The menu bar, Touch Bar Control Strip, and notch are AppKit-only — there is no JS/Python API for them. The Touch Bar Control Strip in particular requires the private `DFRFoundation` framework (`dlopen`/`dlsym` at runtime), isolated in one file (`DFRControlStrip.swift`) and degrading gracefully to a no-op where unavailable.
  **为什么用原生 Swift 而非 JS/Python？** 菜单栏、Touch Bar Control Strip、刘海都是 AppKit 专属——没有对应的 JS/Python API。尤其 Touch Bar Control Strip 需要私有的 `DFRFoundation` 框架（运行时 `dlopen`/`dlsym`），全部隔离在一个文件里（`DFRControlStrip.swift`），在不支持时优雅降级为无操作。
- **Concurrency:** `@MainActor`-isolated UI, passes Swift 6 strict concurrency (0 warnings).
  **并发：** UI 全部 `@MainActor` 隔离，通过 Swift 6 严格并发检查（0 warning）。

---

## Uninstall · 卸载

```bash
bash hooks/uninstall.sh                                                  # remove hooks · 移除 hooks
launchctl unload "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
rm -f "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
rm -f "$HOME/.local/bin/claude-signal"
```

---

## Roadmap · 路线图

- ✅ **Phase 1** — menu bar · 菜单栏
- ✅ **Phase 2** — Touch Bar Control Strip · Touch Bar 控制条
- ✅ **Usage-limit red light** · 用量上限红灯
- ⏳ **Phase 3** — notch "Dynamic Island" overlay (for Macs with a notch) · 刘海"灵动岛"覆盖层（用于带刘海的 Mac）

Full design lives in `docs/superpowers/specs/`. Inspired by [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light), which drives a *physical* USB traffic light — this project replaces it with the Mac's own built-in surfaces.

完整设计见 `docs/superpowers/specs/`。灵感来自 [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light)，那个项目驱动的是一盏*物理* USB 红绿灯——本项目用 Mac 自带的系统区域取代它。
