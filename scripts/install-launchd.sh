#!/bin/bash
# Install ColmiSync as a background service using launchd
# Runs sync every hour to keep health data updated

set -e

PLIST_NAME="com.colmisync.sync"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
BINARY_PATH="$(cd "$(dirname "$0")/../macos/ColmiSync" && pwd)/.build/release/ColmiSync"
LOG_PATH="$HOME/.colmisync/sync.log"

# Check if binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "Building ColmiSync in release mode..."
    cd "$(dirname "$0")/../macos/ColmiSync"
    swift build -c release
fi

# Create log directory
mkdir -p "$HOME/.colmisync"

# Create plist
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY_PATH}</string>
        <string>--cli</string>
        <string>--scan-time</string>
        <string>30</string>
        <string>--retries</string>
        <string>3</string>
    </array>
    
    <!-- Run every hour -->
    <key>StartInterval</key>
    <integer>3600</integer>
    
    <!-- Also run at load -->
    <key>RunAtLoad</key>
    <false/>
    
    <key>StandardOutPath</key>
    <string>${LOG_PATH}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_PATH}</string>
    
    <!-- Keep trying if it fails -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
    <!-- Timeout after 2 minutes -->
    <key>TimeOut</key>
    <integer>120</integer>
    
    <!-- Nice name for Activity Monitor -->
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

echo "✅ Created plist at: $PLIST_PATH"

# Load the service
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "✅ Service loaded and will run every hour"
echo ""
echo "Commands:"
echo "  Run now:     launchctl start $PLIST_NAME"
echo "  Check logs:  tail -f $LOG_PATH"
echo "  Stop:        launchctl unload $PLIST_PATH"
echo "  Status:      launchctl list | grep colmisync"
