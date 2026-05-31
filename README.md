# claude-signal

A menu-bar traffic light for Claude Code state on macOS.

- 🔵 breathing blue — Claude is working
- 🟡 flashing yellow — needs your permission
- 🔴 flashing red — error (e.g. network down while working)
- 🟢 steady green — done, and you've stepped away
- ⚫️ off — your turn / idle

The same light shows in both the menu bar and (on Touch Bar Macs) the Control Strip.
On Macs without a Touch Bar, the Touch Bar surface is a silent no-op and the menu bar works as usual.

## Install
```bash
bash hooks/install.sh                 # register Claude Code hooks
bash scripts/install-launchagent.sh   # build + auto-start at login
```

## Develop
```bash
swift test                            # core unit tests
bash hooks/tests/test-on-event.sh     # hook script tests
swift run ClaudeSignal --simulate working,done away   # headless resolution check
swift run ClaudeSignal                # run the app in the foreground
```

## Uninstall
```bash
bash hooks/uninstall.sh
launchctl unload "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
rm -f "$HOME/Library/LaunchAgents/com.claudesignal.agent.plist"
rm -f "$HOME/.local/bin/claude-signal"
```

See `docs/superpowers/specs/2026-05-30-claude-signal-design.md` for the full design.
Roadmap: ✅ Touch Bar (Phase 2, Control Strip) — done. Next: notch island (Phase 3).
