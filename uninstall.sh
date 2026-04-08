#!/bin/bash

PLIST_NAME="com.aaroncave.screenshot-to-terminal"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo "==> Stopping screenshot-to-terminal..."
launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

if [ -f "$PLIST_PATH" ]; then
    rm "$PLIST_PATH"
    echo "==> Removed LaunchAgent plist"
fi

echo "==> Done. You can also delete ~/projects/screenshot-to-terminal/ to remove the binary."
