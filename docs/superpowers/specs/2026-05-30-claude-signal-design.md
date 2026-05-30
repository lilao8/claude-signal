# claude-signal — Design

**Status:** Approved design (brainstorming complete) · **Date:** 2026-05-30
**Working name:** `claude-signal` (rename freely)

## 1. Purpose

Claude Code tasks often run for minutes. You don't want to babysit the terminal, but
you also don't want to miss the moment it finishes or gets stuck. `claude-signal` is a
"traffic light" for Claude Code's state, shown on **always-visible macOS system surfaces**
(menu bar, then Touch Bar, then the notch "island") so you can glance — not stare.

Inspired by [starlight36/vibecoding-signal-light](https://github.com/starlight36/vibecoding-signal-light),
which drives a *physical* USB traffic light. This project replaces the physical light with
the Mac's own built-in surfaces.

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

## 8. Red (error) detection — deliberately conservative

Claude Code has **no clean error hook**, so:
- **v1 trigger:** the daemon does a light periodic reachability check (e.g. `api.anthropic.com`).
  Unreachable *while a session is working* → 🔴. Covers the "断网 / network down" case.
- Generic tool/command failures (a bash command exiting non-zero) are **intentionally not red** —
  they're common and usually benign.
- Richer hook-based failure signals are a future enhancement. Rarely seeing red is the goal.

## 9. Crash safety

If a session file goes stale (no update for ~5 min and no `SessionEnd`) — e.g. terminal killed
mid-run — the daemon treats it as dead and cleans it up, so the light never gets stuck on blue.

## 10. Surfaces & feasibility notes

- **Menu bar** — `NSStatusItem` colored dot. Trivial, universal (works on every Mac). The baseline.
- **Touch Bar** — persistent item in the system **Control Strip** (the always-present region).
  Uses the semi-documented `NSTouchBar` Control-Strip registration approach that apps like
  **Pock** use. Feasible; expect to spend time on the registration details.
- **Notch island** — borderless, always-on-top, non-activating `NSWindow` positioned over the
  camera notch (the technique apps like **Boring Notch** / NotchNook use).

All three conform to a single `SignalSurface` protocol: `func render(_ state: DisplayState)`.

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

## 13. Testing strategy (TDD)

- `Aggregator` + `SignalResolver` → table-driven XCTest covering every state×presence combo.
  This is where correctness lives; needs no UI.
- `StateStore` → tests against a temp dir simulating file writes + stale cleanup.
- Hook scripts → shell tests: pipe sample event JSON to stdin, assert the file written.
- `--simulate` CLI → manual visual QA of each surface without running Claude.
- Surfaces stay thin, so little untested logic lives in AppKit.

## 14. Open questions / future

- Exact Touch Bar Control-Strip registration approach (validate against current macOS).
- Whether to expose presence threshold / colors in a small config file from day one.
- Notch overlay sizing across different Mac notch geometries.
