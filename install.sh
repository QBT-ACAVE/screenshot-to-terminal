#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/screenshot-to-terminal"
PLIST_NAME="com.aaroncave.screenshot-to-terminal"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "==> Compiling Swift..."
swiftc "$SCRIPT_DIR/main.swift" -o "$BINARY" -O

echo "==> Installing LaunchAgent..."

# Stop existing agent if running
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/screenshot-to-terminal.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/screenshot-to-terminal.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "==> Done! screenshot-to-terminal is now running."
echo "    Logs: ~/Library/Logs/screenshot-to-terminal.log"
echo "    Take a screenshot (Cmd+Shift+3 or 4) while a terminal is focused."
