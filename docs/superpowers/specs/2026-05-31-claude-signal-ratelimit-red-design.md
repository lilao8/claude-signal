# claude-signal — Usage-Limit Red Light — Design

**Status:** Approved design (brainstorming complete) · **Date:** 2026-05-31
**Builds on:** the shipped menu-bar + Touch Bar app on `main`.

> **状态：** 已确认设计（头脑风暴完成）· **日期：** 2026-05-31
> **基于：** 已合并到 main 的菜单栏 + Touch Bar 成品。

## 1. Purpose

Add a new trigger for the existing **red light**: when Claude Code hits a usage limit
(e.g. the 5-hour session limit) and you can't use it, show red until you can again.
Red keeps its single, unified meaning — "a serious problem you need to deal with; Claude
is unusable" — and hitting a usage limit is simply another cause of it (alongside the
existing network-down-while-working trigger). No new color, no second red language.

> **目的：** 给现有**红灯**加一个新触发条件：当 Claude Code 撞到 usage limit（如 5 小时
> 会话限额）、你用不了时，亮红直到能用为止。红灯保持唯一统一的含义——"出了需要你处理的
> 严重问题，Claude 用不了"——撞限只是它的又一个触发原因（和现有的"工作中断网"并列）。
> 不新增颜色、不搞第二种红色语言。

## 2. Verified data (from the capture probe)

Captured live on the real account hitting a session limit (see
`~/Project/claude-signal-touchbar-spike/RATELIMIT-FINDING.md`):

```json
{
  "hook_event_name": "StopFailure",
  "error": "rate_limit",
  "last_assistant_message": "You've hit your session limit · resets 1:10am (America/Toronto)"
}
```

- **Limit-hit signal:** `hook_event_name == "StopFailure"` AND `error == "rate_limit"`.
  Other `error` values (`max_output_tokens`, `billing_error`, `server_error`, …) do NOT
  trigger the usage-limit red light.
- **Reset time:** in `last_assistant_message`, format `resets 1:10am (America/Toronto)`
  — a clock time + IANA timezone, **no date**.
- **Recovery (verified):** after the StopFailure, once the limit reset, a normal
  `UserPromptSubmit` fired again — confirming the "next normal activity = recovered"
  extinguish path is real and capturable.

> **已验证数据：** 撞限时 Claude Code 触发 `StopFailure`（`error="rate_limit"`），
> `last_assistant_message` 里含 "resets 1:10am (America/Toronto)"（钟点+IANA时区，无日期）。
> 恢复后会再次触发正常的 `UserPromptSubmit`。

## 3. Architecture — a parallel account-level channel

A new **account-level rate-limit channel** runs alongside the existing per-session channel
and merges into the red light during aggregation.

```
On limit hit:
  Claude Code ──StopFailure (error=rate_limit)──▶ on-event.sh
     parses "resets 1:10am (America/Toronto)" from last_assistant_message
                       ▼
     ~/.claude-signal/ratelimit.json   { "reset_at": <unix>, "raw": "<original text>" }

On recovery (either):
  ① wall clock passes reset_at      → daemon treats the file as expired (deletes it)
  ② any normal Claude activity      → on-event.sh deletes ratelimit.json

Daemon every tick:
  read session files (existing) + read ratelimit.json (new)
       ▼
  if rate-limit active (now < reset_at) → force aggregate = .error (red)
  else → existing aggregation
       ▼
  red (or other) → menu bar + Touch Bar
```

**Key points:**
- `ratelimit.json` is independent of session files — **not subject to the 5-minute stale
  cleanup**. It expires by `reset_at`, which may be hours away.
- The usage-limit red **ignores presence** (consistent with the existing red — red always
  shows regardless of whether you're at the keyboard).
- It uses the existing highest-priority `.error` state, so it outranks
  working/done/permission and renders as the same red flash. Rationale: the limit is
  **account-level**, not tied to any one session, so it does not belong in a per-session file.

> **架构：** 新增一条账号级限额通道，与现有 per-session 通道并行，在聚合时汇入红灯。
> `ratelimit.json` 独立存储、不受 5 分钟陈旧清理影响、靠 reset_at 判过期；撞限红灯无视
> presence（红灯永远显示）；复用现有最高优先级 `.error`，渲染为同样的红色闪烁。

## 4. Hook script changes (`on-event.sh`)

**New handling for `StopFailure`:**
1. Read `error`. Only proceed if `error == "rate_limit"`.
2. Regex `last_assistant_message` to extract the clock time (`1:10am`) and IANA timezone
   (`America/Toronto`).
3. Resolve the clock time to a unix timestamp: take that clock time **in that timezone**;
   if "today's 1:10am" is already `<= now`, use **tomorrow's** 1:10am (i.e. the next
   occurrence — at limit-hit time the reset is always in the future).
4. Write `~/.claude-signal/ratelimit.json`: `{ "reset_at": <unix>, "raw": "<original>" }`.

**Extinguish (either condition):**
- **① time reached:** no hook action — the daemon compares `now >= reset_at` each tick.
- **② next activity:** on ANY normal activity event (`UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `Stop`, `SubagentStop`), delete `ratelimit.json`. Being able to act
  normally means you can use Claude again (covers upgrade / buy-credit instant recovery).

**Technical notes (solvable, flagged for implementation):**
- **Timezone parsing in bash:** macOS `date` can resolve a clock time in a named TZ via
  `TZ=<zone> date ...`; this is the fiddly part and the implementation must get it right
  (and test it with a fixed TZ for deterministic expected values).
- **Regex robustness / fallback:** if `StopFailure`/`rate_limit` arrives but the time can't
  be parsed (wording changed), still light red — but write a rate-limit marker **without a
  `reset_at`**, so red persists and is extinguished only by condition ② (next activity).
  The "we hit a limit" fact is never dropped; only the precise countdown is lost.

> **Hook 改动：** 处理 StopFailure（仅 error==rate_limit）→ 解析 reset 时间 → 写
> ratelimit.json；正常活动事件时删除该文件（条件②）；时间到由后台进程判（条件①）。
> bash 时区解析要小心；正则解析失败时降级为"无时限红灯，仅靠下次活动熄灭"。

## 5. Daemon (Swift) changes — pure, testable

New pure function, symmetric with the existing `applyNetworkOverride`:

```swift
// RateLimitOverride.swift
func applyRateLimitOverride(_ aggregate: AggregateState,
                            rateLimit: RateLimitState?,
                            now: TimeInterval) -> AggregateState {
    if let rl = rateLimit, now < rl.resetAt { return .error }
    return aggregate
}
```
(Fallback marker with no `reset_at` is modeled as `resetAt = .infinity` so `now < resetAt`
is always true until the file is deleted by condition ②.)

New single-file reader, parallel to `StateStore`:

```swift
// RateLimitStore.swift
struct RateLimitState: Equatable, Sendable { let resetAt: TimeInterval; let raw: String? }

func read(now: TimeInterval) -> RateLimitState?
//  file missing        -> nil
//  now >= resetAt      -> delete file, return nil   (self-clean, condition ①)
//  otherwise           -> RateLimitState(...)
//  corrupt JSON        -> nil   (tolerant, like StateStore)
```

Coordinator wires the new channel into the existing pipeline (one added line):

```swift
func computeDisplayState(now: TimeInterval) -> DisplayState {
    let sessions = sessionStore.loadLiveSessions(now: now)
    var aggregate = Aggregator.aggregate(sessions)
    aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())   // existing
    aggregate = applyRateLimitOverride(aggregate, rateLimit: rateLimitStore.read(now: now), now: now)  // new
    return SignalResolver.resolve(aggregate, presence: presence.current())
}
```

**Unchanged:** `SignalResolver`, `Aggregator`, `SessionState`, all surfaces. The usage-limit
red reuses the existing `.error` → red-flash rendering. Adding a trigger does not touch the
downstream.

> **Swift 侧：** 新增纯函数 `applyRateLimitOverride`（对称于 applyNetworkOverride）+
> 单文件读取器 `RateLimitStore`（读取/过期自删/容错）+ Coordinator 管线加一行。
> 降级标记用 resetAt=∞ 建模。SignalResolver/Aggregator/各 surface 一行不改。

## 6. File structure

```
New (core, pure, testable):
  Sources/ClaudeSignalCore/RateLimitState.swift
  Sources/ClaudeSignalCore/RateLimitOverride.swift
  Sources/ClaudeSignalCore/RateLimitStore.swift
  Tests/ClaudeSignalCoreTests/RateLimitOverrideTests.swift
  Tests/ClaudeSignalCoreTests/RateLimitStoreTests.swift

Modified:
  hooks/on-event.sh                 # StopFailure handling + delete on normal activity
  hooks/tests/test-on-event.sh      # shell tests for hit / parse / extinguish
  hooks/install.sh                  # add StopFailure to the registered events
  Sources/ClaudeSignal/AppController.swift   # inject RateLimitStore into Coordinator
  Sources/ClaudeSignalCore/Coordinator.swift # +1 line: applyRateLimitOverride
  docs/.../design.md + README       # note that usage-limit also triggers red
```

## 7. Edge cases

1. **Limit hit while also working** → red (error is top priority). Correct — you can't use it.
2. **Multiple sessions, one hits the limit** → limit is account-level; one global
   `ratelimit.json` → red. Correct.
3. **Reset time passed but you've been idle** → daemon's `RateLimitStore.read` self-cleans on
   tick → red goes off. No user action needed.
4. **Upgrade / buy credit then use immediately** → next activity event deletes the file → red
   goes off at once.
5. **App restart** (relogin / reopen) → `ratelimit.json` persists on disk → red restored after
   restart. State not lost.
6. **Regex fails to parse time (wording changed)** → fallback: write a marker with no
   `reset_at` (modeled `resetAt = .infinity`); red shows, extinguished only by condition ②.
   Precise countdown lost, but the limit is never under-reported.

## 8. Testing strategy

- `applyRateLimitOverride`: table-driven XCTest — active-not-expired→error; expired→pass-through;
  nil→pass-through; across all aggregate values; the `.infinity` fallback case.
- `RateLimitStore`: temp-dir tests — read, expiry self-delete, corrupt-file tolerance
  (mirrors `StateStoreTests`).
- Hook time parsing: shell tests — feed sample StopFailure JSON, assert the written `reset_at`
  using a fixed timezone for deterministic expected values; assert normal-activity events
  delete the file; assert non-`rate_limit` errors do nothing.

## 9. Scope (YAGNI)

- ✅ In: usage-limit → red; both extinguish conditions; standalone limit file; pure-function
  override; tests.
- ❌ Out: countdown digits on the light ("X min left"); other error types (only `rate_limit`);
  actively detecting the upgrade action (confirmed not possible — no hook for it).

## 10. Implementation note — remove the capture probe first

The user's real `~/.claude/settings.json` currently has the **temporary capture probe**
registered (events: Notification/Stop/StopFailure/SubagentStop/UserPromptSubmit/SessionStart →
`capture-probe.sh`, now moved to the spike dir). Backup at
`~/.claude/settings.json.pre-capture-probe.bak`. Wiring the real `StopFailure` hook requires
registering it via `install.sh`; the probe must be removed/replaced first. This is an explicit
step in the implementation plan, not a silent assumption.

> **实现前提醒：** 用户真实 settings.json 里还挂着临时探针；正式注册 StopFailure hook 前
> 必须先清掉探针（备份在 .pre-capture-probe.bak）。这是实现计划里的明确一步。
