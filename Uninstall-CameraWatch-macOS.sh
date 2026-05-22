#!/bin/bash
set -euo pipefail

LABEL="com.camerawatch.agent"
APP_SUPPORT_DIR="$HOME/Library/Application Support/CameraWatch"
LOG_DIR="$HOME/Library/Logs/CameraWatch"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"
WATCHER_BIN="$APP_SUPPORT_DIR/camerawatch"
REMOVE_CONFIG="false"

usage() {
    cat <<EOF
Usage: ./Uninstall-CameraWatch-macOS.sh [options]

Options:
  --remove-config    Also remove configuration and log files
  --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove-config)
            REMOVE_CONFIG="true"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 64
            ;;
    esac
done

if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    echo "Stopping LaunchAgent..."
    launchctl bootout "gui/$UID" "$PLIST_FILE" >/dev/null 2>&1 || true
fi

if [[ -f "$PLIST_FILE" ]]; then
    rm -f "$PLIST_FILE"
    echo "Removed LaunchAgent: $PLIST_FILE"
else
    echo "LaunchAgent not found: $PLIST_FILE"
fi

if [[ -f "$WATCHER_BIN" ]]; then
    rm -f "$WATCHER_BIN"
    echo "Removed watcher binary: $WATCHER_BIN"
fi

if [[ "$REMOVE_CONFIG" == "true" ]]; then
    rm -rf "$APP_SUPPORT_DIR" "$LOG_DIR"
    echo "Removed configuration and logs."
else
    echo "Kept configuration and logs:"
    echo "  $APP_SUPPORT_DIR"
    echo "  $LOG_DIR"
fi

echo "CameraWatch for macOS has been uninstalled."
