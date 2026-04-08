# screenshot-to-terminal

A macOS utility that watches for new screenshots and automatically pastes the file path where your cursor is.

## How it works

- **Cmd+Shift+4** (region select) — takes a screenshot and auto-pastes the file path into the active app
- **Cmd+Shift+3** (full screen) — normal screenshot, no paste

Supports VS Code, Claude Desktop, Discord, Terminal, iTerm2, and Warp.

## Requirements

- macOS 13+
- Swift compiler (included with Xcode or Command Line Tools)
- Accessibility permission for the binary

## Install

```bash
./install.sh
```

This compiles the Swift source and installs a LaunchAgent that runs automatically on login.

After first install, grant Accessibility permission:

**System Settings → Privacy & Security → Accessibility** → add the `screenshot-to-terminal` binary.

## Uninstall

```bash
./uninstall.sh
```

## Configuration

Screenshots are watched in `~/Documents/Screenshots`. To change this, update `screenshotDir` in `main.swift` and reinstall.

## Logs

```bash
tail -f ~/Library/Logs/screenshot-to-terminal.log
```
