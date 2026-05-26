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
WEBHOOK_URL_MODE="keep"
WEBHOOK_URL_SIGN_OFF_MODE="keep"
POLL_SECONDS="15"
SHORTCUT_TRIGGERS="false"
CAMERA_ACTIVE_SHORTCUT="CameraWatch Camera Active"
CAMERA_INACTIVE_SHORTCUT="CameraWatch Camera Inactive"
SHORTCUT_TIMEOUT="20"
SHORTCUT_CONFIGURED="false"
SKIP_SHORTCUT_CHECK="false"
START_NOW="true"
INTERACTIVE_MODE="auto"
HAS_SETUP_OPTIONS="false"
POLL_CONFIGURED="false"
SHORTCUT_TRIGGERS_CONFIGURED="false"
CAMERA_ACTIVE_SHORTCUT_CONFIGURED="false"
CAMERA_INACTIVE_SHORTCUT_CONFIGURED="false"
SHORTCUT_TIMEOUT_CONFIGURED="false"
START_CONFIGURED="false"

usage() {
    cat <<EOF
Usage: ./macos/Install-CameraWatch.sh [options]

Options:
  --interactive                  Run guided setup for options not already supplied
  --non-interactive              Install using options/defaults without prompts
  --webhook-url URL              Webhook URL for camera active transitions
  --webhook-url-sign-off URL     Webhook URL for camera inactive transitions
  --poll SECONDS                 Poll interval in seconds (default: 15)
  --shortcut-triggers            Run Shortcuts on camera activity transitions
  --camera-active-shortcut NAME  Shortcut for camera active; enables shortcut triggers
  --camera-inactive-shortcut NAME
                                 Shortcut for camera inactive; enables shortcut triggers
  --shortcut-timeout SECONDS     Shortcut timeout in seconds (default: 20)
  --skip-shortcut-check          Do not validate Shortcuts during install
  --start                        Start immediately after install (default)
  --no-start                     Install without starting now
  --help                         Show this help
EOF
}

config_value() {
    local key="$1"
    local fallback="$2"
    /usr/bin/python3 - "$CONFIG_FILE" "$key" "$fallback" <<'PY'
import json
import os
import sys

path, key, fallback = sys.argv[1:]
try:
    with open(path, "r", encoding="utf-8") as handle:
        value = json.load(handle).get(key, fallback)
except Exception:
    value = fallback

if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
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
        --interactive)
            INTERACTIVE_MODE="true"
            shift
            ;;
        --non-interactive)
            INTERACTIVE_MODE="false"
            shift
            ;;
        --webhook-url)
            WEBHOOK_URL="$(require_value "$1" "${2:-}")"
            WEBHOOK_URL_MODE="set"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --webhook-url-sign-off)
            WEBHOOK_URL_SIGN_OFF="$(require_value "$1" "${2:-}")"
            WEBHOOK_URL_SIGN_OFF_MODE="set"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --poll)
            POLL_SECONDS="$(require_value "$1" "${2:-}")"
            POLL_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --shortcut-triggers|--focus-sync)
            SHORTCUT_TRIGGERS="true"
            SHORTCUT_TRIGGERS_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift
            ;;
        --camera-active-shortcut|--focus-on-shortcut)
            CAMERA_ACTIVE_SHORTCUT="$(require_value "$1" "${2:-}")"
            SHORTCUT_CONFIGURED="true"
            CAMERA_ACTIVE_SHORTCUT_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --camera-inactive-shortcut|--focus-off-shortcut)
            CAMERA_INACTIVE_SHORTCUT="$(require_value "$1" "${2:-}")"
            SHORTCUT_CONFIGURED="true"
            CAMERA_INACTIVE_SHORTCUT_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --shortcut-timeout|--focus-timeout)
            SHORTCUT_TIMEOUT="$(require_value "$1" "${2:-}")"
            SHORTCUT_TIMEOUT_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift 2
            ;;
        --skip-shortcut-check)
            SKIP_SHORTCUT_CHECK="true"
            HAS_SETUP_OPTIONS="true"
            shift
            ;;
        --start)
            START_NOW="true"
            START_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
            shift
            ;;
        --no-start)
            START_NOW="false"
            START_CONFIGURED="true"
            HAS_SETUP_OPTIONS="true"
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

if [[ "$SHORTCUT_CONFIGURED" == "true" ]]; then
    SHORTCUT_TRIGGERS="true"
    SHORTCUT_TRIGGERS_CONFIGURED="true"
fi

if [[ "$INTERACTIVE_MODE" == "auto" ]]; then
    if [[ "$HAS_SETUP_OPTIONS" == "false" && -t 0 ]]; then
        INTERACTIVE_MODE="true"
    elif [[ "$HAS_SETUP_OPTIONS" == "false" ]]; then
        echo "No setup options supplied and no interactive terminal is available." >&2
        echo "Run this installer in a terminal for guided setup, or pass --non-interactive with options." >&2
        exit 64
    else
        INTERACTIVE_MODE="false"
    fi
fi

if [[ "$INTERACTIVE_MODE" == "true" ]]; then
    echo "CameraWatch for macOS setup"
    echo

    current_webhook_url="$(config_value "WebhookUrl" "")"
    if [[ "$WEBHOOK_URL_MODE" == "keep" ]]; then
        if [[ -n "$current_webhook_url" ]]; then
            read -r -p "Camera active webhook URL [configured; Enter keeps it, '-' removes it]: " response
        else
            read -r -p "Camera active webhook URL [optional; Enter skips]: " response
        fi
        if [[ "$response" == "-" ]]; then
            WEBHOOK_URL_MODE="clear"
        elif [[ -n "$response" ]]; then
            WEBHOOK_URL="$response"
            WEBHOOK_URL_MODE="set"
        fi
    fi

    current_webhook_url_sign_off="$(config_value "WebhookUrlSignOff" "")"
    if [[ "$WEBHOOK_URL_SIGN_OFF_MODE" == "keep" ]]; then
        if [[ -n "$current_webhook_url_sign_off" ]]; then
            read -r -p "Camera inactive webhook URL [configured; Enter keeps it, '-' removes it]: " response
        else
            read -r -p "Camera inactive webhook URL [optional; Enter skips]: " response
        fi
        if [[ "$response" == "-" ]]; then
            WEBHOOK_URL_SIGN_OFF_MODE="clear"
        elif [[ -n "$response" ]]; then
            WEBHOOK_URL_SIGN_OFF="$response"
            WEBHOOK_URL_SIGN_OFF_MODE="set"
        fi
    fi

    if [[ "$POLL_CONFIGURED" == "false" ]]; then
        POLL_SECONDS="$(config_value "PollIntervalSeconds" "$POLL_SECONDS")"
        read -r -p "Poll interval in seconds [$POLL_SECONDS]: " response
        POLL_SECONDS="${response:-$POLL_SECONDS}"
    fi

    if [[ "$CAMERA_ACTIVE_SHORTCUT_CONFIGURED" == "false" ]]; then
        CAMERA_ACTIVE_SHORTCUT="$(config_value "CameraActiveShortcut" "$(config_value "FocusOnShortcut" "$CAMERA_ACTIVE_SHORTCUT")")"
    fi
    if [[ "$CAMERA_INACTIVE_SHORTCUT_CONFIGURED" == "false" ]]; then
        CAMERA_INACTIVE_SHORTCUT="$(config_value "CameraInactiveShortcut" "$(config_value "FocusOffShortcut" "$CAMERA_INACTIVE_SHORTCUT")")"
    fi
    if [[ "$SHORTCUT_TIMEOUT_CONFIGURED" == "false" ]]; then
        SHORTCUT_TIMEOUT="$(config_value "ShortcutTimeoutSeconds" "$(config_value "FocusShortcutTimeoutSeconds" "$SHORTCUT_TIMEOUT")")"
    fi

    if [[ "$SHORTCUT_TRIGGERS_CONFIGURED" == "false" ]]; then
        SHORTCUT_TRIGGERS="$(config_value "ShortcutTriggersEnabled" "$(config_value "FocusSyncEnabled" "$SHORTCUT_TRIGGERS")")"
        if [[ "$SHORTCUT_TRIGGERS" == "true" ]]; then
            read -r -p "Run Shortcuts when camera activity changes? [Y/n]: " response
            [[ "${response:-y}" =~ ^[Nn]$ ]] && SHORTCUT_TRIGGERS="false" || SHORTCUT_TRIGGERS="true"
        else
            read -r -p "Run Shortcuts when camera activity changes? [y/N]: " response
            [[ "${response:-n}" =~ ^[Yy]$ ]] && SHORTCUT_TRIGGERS="true" || SHORTCUT_TRIGGERS="false"
        fi
    fi

    if [[ "$SHORTCUT_TRIGGERS" == "true" ]]; then
        if [[ "$CAMERA_ACTIVE_SHORTCUT_CONFIGURED" == "false" ]]; then
            read -r -p "Shortcut to run when camera becomes active [$CAMERA_ACTIVE_SHORTCUT]: " response
            CAMERA_ACTIVE_SHORTCUT="${response:-$CAMERA_ACTIVE_SHORTCUT}"
        fi
        if [[ "$CAMERA_INACTIVE_SHORTCUT_CONFIGURED" == "false" ]]; then
            read -r -p "Shortcut to run when camera becomes inactive [$CAMERA_INACTIVE_SHORTCUT]: " response
            CAMERA_INACTIVE_SHORTCUT="${response:-$CAMERA_INACTIVE_SHORTCUT}"
        fi
        if [[ "$SHORTCUT_TIMEOUT_CONFIGURED" == "false" ]]; then
            read -r -p "Shortcut timeout in seconds [$SHORTCUT_TIMEOUT]: " response
            SHORTCUT_TIMEOUT="${response:-$SHORTCUT_TIMEOUT}"
        fi
    fi

    if [[ "$START_CONFIGURED" == "false" ]]; then
        read -r -p "Start CameraWatch now? [Y/n]: " response
        [[ "${response:-y}" =~ ^[Nn]$ ]] && START_NOW="false" || START_NOW="true"
    fi
    echo
fi

for value_name in POLL_SECONDS SHORTCUT_TIMEOUT; do
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
SOURCE_FILE="$SCRIPT_DIR/CameraWatch.swift"
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Cannot find macos/CameraWatch.swift." >&2
    exit 1
fi

if [[ "$SHORTCUT_TRIGGERS" == "true" && "$SKIP_SHORTCUT_CHECK" != "true" ]]; then
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

    if ! shortcut_exists "$CAMERA_ACTIVE_SHORTCUT"; then
        echo "Camera active Shortcut not found: $CAMERA_ACTIVE_SHORTCUT" >&2
        echo "Create it in Shortcuts or pass --skip-shortcut-check." >&2
        exit 1
    fi
    if ! shortcut_exists "$CAMERA_INACTIVE_SHORTCUT"; then
        echo "Camera inactive Shortcut not found: $CAMERA_INACTIVE_SHORTCUT" >&2
        echo "Create it in Shortcuts or pass --skip-shortcut-check." >&2
        exit 1
    fi
fi

mkdir -p "$APP_SUPPORT_DIR" "$LOG_DIR" "$LAUNCH_AGENT_DIR"

echo "Compiling CameraWatch for macOS..."
xcrun swiftc "$SOURCE_FILE" -o "$WATCHER_BIN"
chmod 755 "$WATCHER_BIN"

echo "Writing configuration: $CONFIG_FILE"
/usr/bin/python3 - "$CONFIG_FILE" "$WEBHOOK_URL_MODE" "$WEBHOOK_URL" "$WEBHOOK_URL_SIGN_OFF_MODE" "$WEBHOOK_URL_SIGN_OFF" "$POLL_SECONDS" "$SHORTCUT_TRIGGERS" "$CAMERA_ACTIVE_SHORTCUT" "$CAMERA_INACTIVE_SHORTCUT" "$SHORTCUT_TIMEOUT" <<'PY'
import json
import os
import sys

config_path = sys.argv[1]
webhook_url_mode = sys.argv[2]
webhook_url = sys.argv[3]
webhook_url_sign_off_mode = sys.argv[4]
webhook_url_sign_off = sys.argv[5]
poll_seconds = int(sys.argv[6])
shortcut_triggers = sys.argv[7].lower() == "true"
camera_active_shortcut = sys.argv[8]
camera_inactive_shortcut = sys.argv[9]
shortcut_timeout = int(sys.argv[10])

config = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as handle:
            config = json.load(handle)
    except Exception:
        config = {}

if webhook_url_mode == "set":
    config["WebhookUrl"] = webhook_url
elif webhook_url_mode == "clear":
    config.pop("WebhookUrl", None)
if webhook_url_sign_off_mode == "set":
    config["WebhookUrlSignOff"] = webhook_url_sign_off
elif webhook_url_sign_off_mode == "clear":
    config.pop("WebhookUrlSignOff", None)
config["PollIntervalSeconds"] = poll_seconds
config["ShortcutTriggersEnabled"] = shortcut_triggers
config["CameraActiveShortcut"] = camera_active_shortcut
config["CameraInactiveShortcut"] = camera_inactive_shortcut
config["ShortcutTimeoutSeconds"] = shortcut_timeout
for legacy_key in ("FocusSyncEnabled", "FocusOnShortcut", "FocusOffShortcut", "FocusShortcutTimeoutSeconds"):
    config.pop(legacy_key, None)

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
