# claude-signal

A tiny native macOS "traffic light" for **Claude Code** state — shown on the menu bar, around the camera notch (notch Macs), and in the Touch Bar Control Strip (Touch Bar Macs), so you can glance instead of babysitting the terminal.

一个小巧的原生 macOS **Claude Code** 状态"红绿灯"——显示在菜单栏、摄像头刘海周围（带刘海的 Mac），以及 Touch Bar 的 Control Strip（带 Touch Bar 的 Mac），让你瞥一眼就知道状态，而不用一直盯着终端。

> Claude Code tasks often run for minutes. You step away — and miss the moment it finishes, asks for permission, or gets stuck. claude-signal puts that state where your eyes already are.
>
> Claude Code 的任务常常要跑好几分钟。你切走去忙别的，就会错过它完成、要权限、或卡住的那一刻。claude-signal 把状态放在你余光所及之处。

<!--
  📸 SCREENSHOTS / 截图 — replace these placeholders with real captures.
  Suggested shots (put files under docs/images/ and update the paths below):
    1. demo.gif      — a short screen recording cycling through states:
                       blue breathing → yellow flashing → green steady → off.
                       Capture the menu-bar dot AND the Touch Bar together if possible.
                       (macOS: Cmd-Shift-5 to record a region; convert to GIF.)
    2. menubar.png   — close-up of the menu-bar dot in each color.
    3. touchbar.png  — the Touch Bar Control Strip dot (screenshot the Touch Bar via
                       `Cmd-Shift-6`, or photograph it).
    4. red-limit.png — the red light when a usage limit is hit.
-->

<p align="center">
  <img src="docs/images/demo.gif" alt="claude-signal cycling through states on the menu bar and Touch Bar" width="640">
  <br>
  <em>Demo placeholder — record a short GIF cycling blue → yellow → green → off. · 演示占位，录一段蓝→黄→绿→灭的短 GIF。</em>
</p>

---

## The light language · 灯语

| Light · 灯 | Meaning | 含义 |
|---|---|---|
| 🔵 **Breathing blue** | Claude is working (thinking / running tools) — no action needed | Claude 正在工作（思考 / 跑工具）——无需你操作 |
| 🟡 **Flashing yellow** | Needs your permission (yes / allow once / always allow) — including inline prompts | 需要你授权（yes / allow once / always allow）——包括终端里的内联提示 |
| 🔴 **Flashing red** | Something's wrong: a turn failed (API error, overload…), network down while working, **or a usage limit was hit** | 出问题了：某轮失败（API 报错、过载…）、工作时断网，**或撞到用量上限** |
| 🟢 **Steady green** | Done and you haven't looked yet — shown while you're away; also a 4s flash the moment a turn finishes | 做完了且你还没看——你离开时显示；一轮刚结束时也会闪 4 秒 |
| ⚫️ **Off** | Your turn, or nothing happening (menu bar shows a faint hollow ring — no ring means the app isn't running) | 轮到你了，或什么都没发生（菜单栏显示淡灰空心圈——没有圈说明 app 没在跑） |

**Priority when several sessions run at once · 多会话同时运行时的优先级:** 🔴 > 🟡 > 🔵 > 🟢 > ⚫️

The green "done" light is **presence-aware**: it shows while you're away (~30s idle) and only for work you haven't seen yet — once you touch the keyboard or mouse after a session finished, that session counts as seen and won't re-light the next time you step away. It stays on for as long as you're gone (no timeout), so it's still there when you come back from lunch.

绿色"完成"灯是**感知在场**的：你离开时（约 30 秒无操作）才亮，而且只针对你还没看过的结果——会话完成后你只要碰过键盘或鼠标，就算看过了，下次离开不会再亮。你离开多久它就亮多久（没有超时），吃完饭回来它还在。

The same light shows on the menu bar, the Touch Bar Control Strip (no-op on Macs without a Touch Bar), and as a U-shaped glow around the camera notch (no-op on Macs without a notch).

同一个灯同时显示在菜单栏、Touch Bar Control Strip（无 Touch Bar 的机器自动跳过）、以及摄像头刘海周围的 U 形辉光（无刘海的机器自动跳过）上。

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
   ├── StateStore        read session files; drop a session when its claude process exits
   ├── PermissionDetection  stuck at PreToolUse → permission (yellow)
   ├── IdleDetection     silent after a step, no Stop → done
   ├── Acknowledgment    done/error you've already seen → dropped; just-finished → flash
   ├── Aggregator        many sessions → one state (pure)
   ├── PresenceMonitor   macOS idle time → present / away
   ├── RateLimitStore    read account-level limit, self-expire
   ├── SignalResolver    (state + presence) → display state (pure)
   └── Coordinator       wires it together
        │  one final light
        ▼
   Menu bar  +  Touch Bar Control Strip  +  Notch outline (notch Macs only)
```

**Key property · 关键特性:** the "brain" is pure logic with no UI, so it's fully unit-tested. Each display surface is an isolated plug-in — adding one never touches the brain.

"大脑"是纯逻辑、无 UI，因此可完整单元测试。每个显示区域都是独立插件——新增一个永远不碰大脑。

### Usage-limit detection · 用量上限检测

When Claude Code hits a usage limit, it fires a `StopFailure` hook with `error: "rate_limit"`. The hook parses the reset time from the message and writes an account-level `ratelimit.json`. The light goes red and stays red until **either** the reset time passes **or** you successfully use Claude again (which covers upgrading / buying credits). The parser understands three reset-time formats: relative ("in 45 mins"), absolute-with-timezone, and absolute-local.

当 Claude Code 撞到用量上限时，会触发 `StopFailure` hook（`error: "rate_limit"`）。hook 从消息里解析出重置时间，写一个账号级的 `ratelimit.json`。灯变红并保持，直到**重置时间到了**、**或**你重新成功使用 Claude（覆盖了升级 / 购买额度的情况）。解析器支持三种重置时间格式：相对（"in 45 mins"）、带时区的绝对时间、本地绝对时间。

### Light rules in detail · 亮灯规则细节

- **Session lifetime · 会话生命周期.** The hook records the pid of the Claude Code process that owns each session; the app keeps the session exactly as long as that process is alive. (Session files without a pid fall back to a 5-minute timeout.)
  hook 会记录每个会话所属 Claude Code 进程的 pid，app 让会话与该进程同生共死。（没有 pid 的旧文件按 5 分钟超时处理。）
- **Inline permission prompts → yellow · 内联授权提示 → 黄灯.** Inline "allow this tool?" prompts often fire no `Notification` hook. A session that has sat at `PreToolUse` for more than 12s without the tool completing is treated as waiting for permission. Trade-off: a single tool that runs longer than 12s also reads yellow until it finishes.
  终端里的"allow this tool?"内联提示常常不触发 `Notification` hook。会话停在 `PreToolUse` 超过 12 秒、工具还没完成，就视为在等授权。代价：单个工具运行超过 12 秒时，在它结束前也会显示黄灯。
- **Idle without `Stop` → done · 没发 `Stop` 的闲置 → 完成.** `Stop` is the only event that ends a turn. A session that finished a step (`PostToolUse` / `SubagentStop` / `UserPromptSubmit`) and then stayed silent for more than 20s is treated as done, so the light doesn't stay stuck on blue.
  `Stop` 是唯一表示一轮结束的事件。会话做完一步（`PostToolUse` / `SubagentStop` / `UserPromptSubmit`）后静默超过 20 秒，就视为完成，避免灯卡在蓝色。
- **Seen = input after it finished · 已读 = 完成后有过操作.** Keyboard/mouse input after a done session finished (4s grace) or an error session failed (10s grace) marks it as seen. A just-finished session flashes green for 4s even while you're at the keyboard.
  done 会话完成后（宽限 4 秒）、error 会话失败后（宽限 10 秒）你有过键盘或鼠标操作，就算已读。刚完成的会话即使你在场也会闪 4 秒绿灯。
- **Failures → red · 失败 → 红灯.** Any `StopFailure` other than a rate limit marks that session as error.
  限流以外的 `StopFailure` 会把该会话标为 error。
- **Notch · 刘海.** The outline sits just below the physical camera housing (anything drawn inside the notch band is hidden by hardware), targets whichever screen has a notch, and rebuilds when displays or scaling change.
  描边画在摄像头外壳正下方（画进刘海区域内的部分会被硬件挡住），自动选择带刘海的屏幕，并在显示器或缩放变化时重建。

All thresholds live in `ClaudeSignalCore` as named defaults (`PermissionDetection.defaultThreshold`, `IdleDetection.defaultThreshold`, `Acknowledgment.doneGrace` / `errorGrace`).

所有阈值都是 `ClaudeSignalCore` 里的具名默认值（`PermissionDetection.defaultThreshold`、`IdleDetection.defaultThreshold`、`Acknowledgment.doneGrace` / `errorGrace`）。

---

## Install (prebuilt — no Xcode) · 安装（预编译，无需 Xcode）

Download `claude-signal-macos.zip` from the [Releases](../../releases) page, unzip it, and from inside the unzipped folder run:

```bash
./install.sh
```

This installs a universal binary (Intel + Apple Silicon), registers the Claude Code hooks, and starts the app at login. **Keep the unzipped folder** — the hook scripts are referenced from there.

The binary is unsigned (no Apple Developer account). If macOS blocks it, right-click `~/.local/bin/claude-signal` in Finder → **Open** once to allow it.

从 [Releases](../../releases) 页面下载 `claude-signal-macos.zip`，解压后在解压目录里运行 `./install.sh`。它会安装一个 universal 二进制（Intel + Apple Silicon）、注册 Claude Code hooks、并设为开机自启。**请保留解压出来的文件夹**——hook 脚本是从那里引用的。二进制未签名（没有 Apple 开发者账号），若 macOS 拦截，在 Finder 里右键 `~/.local/bin/claude-signal` → **打开** 一次即可放行。

---

## Install (from source) · 安装（从源码）

Requires macOS 13+ and a Swift 6 toolchain — Command Line Tools are enough to build and install. (Running the XCTest suite needs full Xcode; see Develop.)

需要 macOS 13+ 和 Swift 6 工具链——只装 Command Line Tools 就能构建和安装。（运行 XCTest 测试需要完整 Xcode，见"开发"。）

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
swift test                                          # core unit tests · 核心单元测试 (76; needs full Xcode · 需完整 Xcode)
bash hooks/tests/test-on-event.sh                   # hook script tests · hook 脚本测试 (22)
swift run ClaudeSignal --simulate working,done away # headless light-resolution check · 无界面解析检查
swift run ClaudeSignal                              # run the app in the foreground · 前台运行 app
```

`--simulate` runs fake sessions through the app's real decision pipeline (permission and idle detection, seen rule, flash, network override) without any UI or Claude, so it prints exactly what the app would show. Each session is `state[@event][:age]` (age in seconds, default 60); presence is `present`, `away`, or `idle=<seconds since last input>`:

`--simulate` 不依赖任何 UI 或 Claude，把假会话送进 app 真实的判定流程（授权/闲置检测、已读规则、闪烁、断网覆盖），输出的就是 app 实际会显示的灯。每个会话写成 `state[@event][:age]`（age 单位秒，默认 60）；在场状态写 `present`、`away` 或 `idle=<距上次操作的秒数>`：

```bash
$ swift run ClaudeSignal --simulate working@PreToolUse:15 present
sessions=[working@PreToolUse:15s] idle=0s -> display=permission
$ swift run ClaudeSignal --simulate working@SubagentStop:30 idle=100
sessions=[working@SubagentStop:30s] idle=100s -> display=done
$ swift run ClaudeSignal --simulate done:2 present
sessions=[done:2s] idle=0s -> display=done
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
- ✅ **Phase 3** — notch outline light: a U-shaped glow around the camera notch on notch Macs (no-op on others) · 刘海描边灯：带刘海的 Mac 上沿摄像头刘海一圈 U 形辉光（无刘海机器自动跳过）
- ✅ **Smarter light rules** — yellow for inline prompts, no stuck blue, green/yellow persist until seen, failures go red, Core Animation (~0.4% CPU) · 更聪明的灯语：内联提示变黄、不再卡蓝、绿/黄灯保持到你看过、失败变红、Core Animation（约 0.4% CPU）

Full design lives in `docs/superpowers/specs/`. Inspired by [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light), which drives a *physical* USB traffic light — this project replaces it with the Mac's own built-in surfaces.

完整设计见 `docs/superpowers/specs/`。灵感来自 [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light)，那个项目驱动的是一盏*物理* USB 红绿灯——本项目用 Mac 自带的系统区域取代它。
