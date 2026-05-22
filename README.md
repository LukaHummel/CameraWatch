# CameraWatch

CameraWatch monitors webcam activity and sends webhook notifications when the camera starts or stops. It is designed for Home Assistant automations such as turning a home-office busy light on and off.

The repository includes:

- Windows support through PowerShell and Task Scheduler
- macOS support through a Swift watcher and a per-user LaunchAgent
- Optional macOS Focus mode sync through Shortcuts

## Webhook Payload

CameraWatch sends JSON payloads with the same shape on both platforms:

Camera active:
```json
{
  "user": "YourUsername",
  "processes": "process1,process2"
}
```

Camera inactive:
```json
{
  "user": "YourUsername",
  "processes": ""
}
```

On Windows, `processes` contains active webcam registry entries. On macOS, supported public APIs expose camera device usage, not owning app processes, so `processes` contains comma-separated active camera device names such as `MacBook Pro Camera`.

## macOS

### Requirements

- macOS 12 or later
- Apple Command Line Tools
- Optional: Shortcuts configured for Focus sync

Install Command Line Tools if needed:

```bash
xcode-select --install
```

### How It Works

The macOS watcher uses AVFoundation to discover video devices and checks whether a camera is in use by another app. It polls every 15 seconds by default. On state changes, it sends direct webhooks to Home Assistant.

Focus sync is optional. When enabled, CameraWatch runs one Shortcut when the camera becomes active and another Shortcut when the camera becomes inactive:

```text
Camera activity -> Swift watcher -> Home Assistant webhook
                          |
                          -> optional Shortcuts Focus sync
```

Direct webhooks are the primary path because camera activity remains the source of truth. Focus is a side effect, not an intermediate trigger.

### Installation

Without Focus sync:

```bash
./Install-CameraWatch-macOS.sh \
  --webhook-url "https://your-homeassistant-url/api/webhook/on-id" \
  --webhook-url-sign-off "https://your-homeassistant-url/api/webhook/off-id"
```

With Focus sync:

```bash
./Install-CameraWatch-macOS.sh \
  --webhook-url "https://your-homeassistant-url/api/webhook/on-id" \
  --webhook-url-sign-off "https://your-homeassistant-url/api/webhook/off-id" \
  --focus-sync \
  --focus-on-shortcut "CameraWatch Focus On" \
  --focus-off-shortcut "CameraWatch Focus Off"
```

To use existing Shortcuts, pass their names or identifiers:

```bash
./Install-CameraWatch-macOS.sh \
  --webhook-url "https://your-homeassistant-url/api/webhook/on-id" \
  --webhook-url-sign-off "https://your-homeassistant-url/api/webhook/off-id" \
  --focus-sync \
  --focus-on-shortcut "FocusOn" \
  --focus-off-shortcut "FocusOff"
```

The installer compiles the Swift watcher, writes configuration, creates a LaunchAgent, and starts CameraWatch immediately by default.

### Focus Shortcut Setup

Create two Shortcuts in the Shortcuts app:

- `CameraWatch Focus On`: use the "Set Focus" action to turn your chosen Focus on until turned off.
- `CameraWatch Focus Off`: use the "Set Focus" action to turn the same Focus off.

When `--focus-sync` is enabled, the installer validates that both Shortcuts exist. Use `--skip-shortcut-check` if you want to install first and create the Shortcuts later.

### macOS Configuration

Config is stored at:

```text
~/Library/Application Support/CameraWatch/config.json
```

Example:

```json
{
  "WebhookUrl": "https://your-homeassistant-url/api/webhook/on-id",
  "WebhookUrlSignOff": "https://your-homeassistant-url/api/webhook/off-id",
  "PollIntervalSeconds": 15,
  "FocusSyncEnabled": false,
  "FocusOnShortcut": "CameraWatch Focus On",
  "FocusOffShortcut": "CameraWatch Focus Off",
  "FocusShortcutTimeoutSeconds": 20
}
```

Logs are stored at:

```text
~/Library/Logs/CameraWatch/CameraWatch.log
```

### Managing macOS CameraWatch

Check status:

```bash
launchctl print gui/$UID/com.camerawatch.agent
```

Restart:

```bash
launchctl kickstart -k gui/$UID/com.camerawatch.agent
```

Stop and unload:

```bash
launchctl bootout gui/$UID ~/Library/LaunchAgents/com.camerawatch.agent.plist
```

View logs:

```bash
tail -f ~/Library/Logs/CameraWatch/CameraWatch.log
```

Run one dry check manually:

```bash
"$HOME/Library/Application Support/CameraWatch/camerawatch" --once --dry-run
```

Test webhooks or Focus sync:

```bash
"$HOME/Library/Application Support/CameraWatch/camerawatch" --test-notification on --dry-run
"$HOME/Library/Application Support/CameraWatch/camerawatch" --test-notification off --dry-run
"$HOME/Library/Application Support/CameraWatch/camerawatch" --test-focus on --dry-run
"$HOME/Library/Application Support/CameraWatch/camerawatch" --test-focus off --dry-run
```

### macOS Uninstallation

Remove the LaunchAgent and installed watcher binary:

```bash
./Uninstall-CameraWatch-macOS.sh
```

Also remove configuration and logs:

```bash
./Uninstall-CameraWatch-macOS.sh --remove-config
```

## Windows

### Requirements

- Windows 10 or later
- PowerShell 5.1 or later
- Permissions to create scheduled tasks; Administrator is recommended but not required

### How It Works

The Windows script monitors the registry key that tracks webcam usage:

```text
HKEY_USERS\{SID}\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam
```

It polls this registry location every 15 seconds. When a state change is detected, it sends a POST request to the configured webhook URL.

### Installation

Open PowerShell, navigate to the repository, and run:

```powershell
.\Install-CameraWatch.ps1
```

With webhook URLs:

```powershell
.\Install-CameraWatch.ps1 `
  -WebhookUrl "https://your-homeassistant-url/api/webhook/on-id" `
  -WebhookUrlSignOff "https://your-homeassistant-url/api/webhook/off-id"
```

The script creates a scheduled task that runs automatically when you log in.

### Windows Configuration

Config is stored at:

```text
%LOCALAPPDATA%\CameraWatch\config.json
```

Example:

```json
{
  "WebhookUrl": "https://your-homeassistant-url/api/webhook/on-id",
  "WebhookUrlSignOff": "https://your-homeassistant-url/api/webhook/off-id"
}
```

Logs are stored at:

```text
%LOCALAPPDATA%\CameraWatch\CameraWatch.log
```

### Managing Windows CameraWatch

Check status:

```powershell
Get-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\" | Get-ScheduledTaskInfo
```

Start:

```powershell
Start-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\"
```

Stop:

```powershell
Stop-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\"
```

View logs:

```powershell
Get-Content "$env:LOCALAPPDATA\CameraWatch\CameraWatch.log" -Tail 50
```

### Windows Uninstallation

```powershell
.\Uninstall-CameraWatch.ps1
```

Also remove configuration and logs:

```powershell
.\Uninstall-CameraWatch.ps1 -RemoveConfig
```

## Home Assistant Integration

1. Create one webhook trigger for camera active and one webhook trigger for camera inactive.
2. Configure CameraWatch with both webhook URLs.
3. Use the active webhook to turn on a busy indicator.
4. Use the inactive webhook to turn it off.

## Troubleshooting

### macOS: CameraWatch does not start

- Check the LaunchAgent status with `launchctl print gui/$UID/com.camerawatch.agent`.
- Check `~/Library/Logs/CameraWatch/CameraWatch.log`.
- Re-run the installer after installing Command Line Tools.

### macOS: Focus sync does not work

- Confirm both Shortcuts exist with `shortcuts list --show-identifiers`.
- Run the test commands with `--test-focus on` and `--test-focus off`.
- macOS may ask for permission the first time a LaunchAgent runs Shortcuts.

### Webhook not working

- Verify the webhook URLs in the config file.
- Check logs for redacted webhook attempts and HTTP errors.
- Test the webhook URL manually with `curl` or Postman.

### Camera not detected

- On Windows, confirm the webcam uses the standard Windows camera APIs.
- On macOS, confirm the app is using an AVFoundation-visible camera device.

## License

This project is open source. Feel free to use and modify as needed.
