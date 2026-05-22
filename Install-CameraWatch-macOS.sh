#!/bin/bash
set -euo pipefail

LABEL="com.camerawatch.agent"
APP_SUPPORT_DIR="$HOME/Library/Application Support/CameraWatch"
LOG_DIR="$HOME/Library/Logs/CameraWatch"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
CONFIG_FILE="$APP_SUPPORT_DIR/config.json"
WATCHER_BIN="$APP_SUPPORT_DIR/camerawatch"
PLIST_FILE="$LAUNCH_AGENT_DIR/$LABEL.plist"

WEBHOOK_URL=""
WEBHOOK_URL_SIGN_OFF=""
POLL_SECONDS="15"
FOCUS_SYNC="false"
FOCUS_ON_SHORTCUT="CameraWatch Focus On"
FOCUS_OFF_SHORTCUT="CameraWatch Focus Off"
FOCUS_TIMEOUT="20"
SKIP_SHORTCUT_CHECK="false"
START_NOW="true"

usage() {
    cat <<EOF
Usage: ./Install-CameraWatch-macOS.sh [options]

Options:
  --webhook-url URL              Webhook URL for camera active transitions
  --webhook-url-sign-off URL     Webhook URL for camera inactive transitions
  --poll SECONDS                 Poll interval in seconds (default: 15)
  --focus-sync                   Enable camera-to-Focus sync through Shortcuts
  --focus-on-shortcut NAME       Shortcut name or identifier for camera active
  --focus-off-shortcut NAME      Shortcut name or identifier for camera inactive
  --focus-timeout SECONDS        Shortcut timeout in seconds (default: 20)
  --skip-shortcut-check          Do not validate Shortcuts during install
  --start                        Start immediately after install (default)
  --no-start                     Install without starting now
  --help                         Show this help
EOF
}

require_value() {
    local name="$1"
    local value="${2:-}"
    if [[ -z "$value" ]]; then
        echo "Missing value for $name" >&2
        exit 64
    fi
    printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --webhook-url)
            WEBHOOK_URL="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --webhook-url-sign-off)
            WEBHOOK_URL_SIGN_OFF="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --poll)
            POLL_SECONDS="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --focus-sync)
            FOCUS_SYNC="true"
            shift
            ;;
        --focus-on-shortcut)
            FOCUS_ON_SHORTCUT="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --focus-off-shortcut)
            FOCUS_OFF_SHORTCUT="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --focus-timeout)
            FOCUS_TIMEOUT="$(require_value "$1" "${2:-}")"
            shift 2
            ;;
        --skip-shortcut-check)
            SKIP_SHORTCUT_CHECK="true"
            shift
            ;;
        --start)
            START_NOW="true"
            shift
            ;;
        --no-start)
            START_NOW="false"
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

for value_name in POLL_SECONDS FOCUS_TIMEOUT; do
    value="${!value_name}"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
        echo "$value_name must be a positive integer" >&2
        exit 64
    fi
done

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$MACOS_MAJOR" -lt 12 ]]; then
    echo "CameraWatch for macOS requires macOS 12 or later." >&2
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1 || ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Apple Command Line Tools are required. Install them with: xcode-select --install" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/macos/CameraWatch.swift"
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Cannot find macos/CameraWatch.swift next to the installer." >&2
    exit 1
fi

if [[ "$FOCUS_SYNC" == "true" && "$SKIP_SHORTCUT_CHECK" != "true" ]]; then
    if ! command -v shortcuts >/dev/null 2>&1; then
        echo "Cannot find the macOS shortcuts command." >&2
        exit 1
    fi

    SHORTCUTS_LIST="$(shortcuts list --show-identifiers || true)"
    shortcut_exists() {
        local shortcut="$1"
        awk -v shortcut="$shortcut" '
            $0 == shortcut { found = 1 }
            index($0, shortcut " (") == 1 { found = 1 }
            index($0, "(" shortcut ")") > 0 { found = 1 }
            END { exit found ? 0 : 1 }
        ' <<<"$SHORTCUTS_LIST"
    }

    if ! shortcut_exists "$FOCUS_ON_SHORTCUT"; then
        echo "Focus on Shortcut not found: $FOCUS_ON_SHORTCUT" >&2
        echo "Create it in Shortcuts or pass --skip-shortcut-check." >&2
        exit 1
    fi
    if ! shortcut_exists "$FOCUS_OFF_SHORTCUT"; then
        echo "Focus off Shortcut not found: $FOCUS_OFF_SHORTCUT" >&2
        echo "Create it in Shortcuts or pass --skip-shortcut-check." >&2
        exit 1
    fi
fi

mkdir -p "$APP_SUPPORT_DIR" "$LOG_DIR" "$LAUNCH_AGENT_DIR"

echo "Compiling CameraWatch for macOS..."
xcrun swiftc "$SOURCE_FILE" -o "$WATCHER_BIN"
chmod 755 "$WATCHER_BIN"

echo "Writing configuration: $CONFIG_FILE"
/usr/bin/python3 - "$CONFIG_FILE" "$WEBHOOK_URL" "$WEBHOOK_URL_SIGN_OFF" "$POLL_SECONDS" "$FOCUS_SYNC" "$FOCUS_ON_SHORTCUT" "$FOCUS_OFF_SHORTCUT" "$FOCUS_TIMEOUT" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
webhook_url = sys.argv[2]
webhook_url_sign_off = sys.argv[3]
poll_seconds = int(sys.argv[4])
focus_sync = sys.argv[5].lower() == "true"
focus_on = sys.argv[6]
focus_off = sys.argv[7]
focus_timeout = int(sys.argv[8])

config = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            config = json.load(handle)
    except Exception:
        config = {}

if webhook_url:
    config["WebhookUrl"] = webhook_url
if webhook_url_sign_off:
    config["WebhookUrlSignOff"] = webhook_url_sign_off
config["PollIntervalSeconds"] = poll_seconds
config["FocusSyncEnabled"] = focus_sync
config["FocusOnShortcut"] = focus_on
config["FocusOffShortcut"] = focus_off
config["FocusShortcutTimeoutSeconds"] = focus_timeout

with open(config_path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
PY

if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    echo "Stopping existing LaunchAgent..."
    launchctl bootout "gui/$UID" "$PLIST_FILE" >/dev/null 2>&1 || true
fi

cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WATCHER_BIN</string>
        <string>--config</string>
        <string>$CONFIG_FILE</string>
        <string>--log</string>
        <string>$LOG_DIR/CameraWatch.log</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/CameraWatch.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/CameraWatch.stderr.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST_FILE" >/dev/null

if [[ "$START_NOW" == "true" ]]; then
    echo "Loading LaunchAgent: $PLIST_FILE"
    launchctl bootstrap "gui/$UID" "$PLIST_FILE"
    launchctl kickstart -k "gui/$UID/$LABEL"
    echo "CameraWatch started."
else
    echo "CameraWatch installed and will load at next login."
fi

echo
echo "Config: $CONFIG_FILE"
echo "Log: $LOG_DIR/CameraWatch.log"
echo "Status after start: launchctl print gui/$UID/$LABEL"
