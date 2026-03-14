#!/bin/bash
# Uninstall ColmiSync background service

PLIST_NAME="com.colmisync.sync"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    echo "✅ Service uninstalled"
else
    echo "ℹ️  Service not installed"
fi
