<p align="center">
<img src="https://raw.githubusercontent.com/ivoronin/TomatoBar/main/TomatoBar/Assets.xcassets/AppIcon.appiconset/icon_128x128%402x.png" width="128" height="128"/>
</p>

<h1 align="center">TomatoBar — personal fork</h1>

macOS menu-bar Pomodoro timer with **project tracking**, **focus analytics**, and **per-session notes**.

Forked from [AuroraWright/TomatoBar](https://github.com/AuroraWright/TomatoBar), which in turn forks the original [ivoronin/TomatoBar](https://github.com/ivoronin/TomatoBar). All upstream behavior (Pomodoro cycles, sounds, DND, hotkeys, presets, `tomatobar://` URL scheme) is preserved unchanged.

## What this fork adds

### Project / area tagging
Pick a project — and optionally a sub-area — from the menu-bar popover before each Pomodoro. Both layers support create / rename / archive / complete / delete.

### Persistent session log
Every work and rest interval is stored as a structured record (project, area, planned vs. actual duration, completed flag, notes) in `~/Library/Containers/<bundle-id>/Data/Documents/tracking.json`. A `.bak` snapshot is taken on each launch.

### Session notes prompt
When a Pomodoro ends, a full-screen overlay asks **"刚刚完成了什么？" / "What did you just accomplish?"** and stores the answer on the session. Press <kbd>↵</kbd> to save — the mask auto-dismisses while the rest period continues counting down. Single-click the mask to dismiss without saving; double-click to skip the rest entirely.

### Dashboard ( <kbd>⌘D</kbd> )
- Today / week / month summary cards
- Weekly daily-focus bar chart, monthly per-project stacked chart
- GitHub-style 12-month focus heatmap
- Per-project (or per-area when filtered) breakdown
- Chronological session log with notes shown as titles

### Project retrospective
Projects marked completed open a detail view: area-distribution pie chart, hour-of-day session histogram, cumulative-focus curve.

## Build

Requires Xcode 15+, macOS 14+.

```bash
xcodebuild -project TomatoBar.xcodeproj -scheme TomatoBar -configuration Debug build
```

For free / Personal Team signing (self-use only, provisioning profile expires after 7 days), see [CLAUDE.md](CLAUDE.md) — it documents Bundle ID rename, sandbox container path, and the entitlements needed for the macOS Focus / Do-Not-Disturb integration.

## Credits

- Direct upstream: [AuroraWright/TomatoBar](https://github.com/AuroraWright/TomatoBar)
- Original: [ivoronin/TomatoBar](https://github.com/ivoronin/TomatoBar)
- Timer sounds: buddhabeats (licensed)
- `macos-focus-mode.shortcut` from [arodik/macos-focus-mode](https://github.com/arodik/macos-focus-mode) — MIT
