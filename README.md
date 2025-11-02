# CameraWatch

This is a PowerShell script that monitors webcam access on a Windows machine via changes in the Windows registry. You can trigger webhooks to trigger other functions. I use it to trigger my "I'm busy" sign for home office. To trigger the sign I use Home Assistant.

I tried it with events initially but didn't want to create background job handling for the event subscriptions. This might not be the most elegant solution but it works.

## Features

- Monitors webcam usage by checking Windows registry
- Sends webhook notifications when webcam starts/stops
- Runs automatically in the background
- Persists across reboots using Windows Task Scheduler
- Easy one-time installation

## Installation

1. **Download the repository** or clone it to your local machine

2. **Open PowerShell as Administrator** (recommended, but not required)

3. **Navigate to the CameraWatch directory**
   ```powershell
   cd path\to\CameraWatch
   ```

4. **Run the installation script**
   
   Without webhook URL (you can configure it later):
   ```powershell
   .\Install-CameraWatch.ps1
   ```
   
   With webhook URL (e.g., for Home Assistant):
   ```powershell
   .\Install-CameraWatch.ps1 -WebhookUrl "https://your-homeassistant-url/api/webhook/your-webhook-id"
   ```

5. **Choose to start immediately** when prompted, or the task will start automatically at next logon

The script will create a scheduled task that runs automatically when you log in and continues running in the background, even after reboots.

## Configuration

The webhook URL is stored in `%LOCALAPPDATA%\CameraWatch\config.json`. You can edit this file to change the webhook URL without reinstalling.

Example config.json:
```json
{
    "WebhookUrl": "https://your-homeassistant-url/api/webhook/your-webhook-id"
}
```

Logs are stored in `%LOCALAPPDATA%\CameraWatch\CameraWatch.log`

## Managing CameraWatch

### Check if CameraWatch is running
```powershell
Get-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\" | Get-ScheduledTaskInfo
```

### Start CameraWatch manually
```powershell
Start-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\"
```

### Stop CameraWatch
```powershell
Stop-ScheduledTask -TaskName "CameraWatch" -TaskPath "\CameraWatch\"
```

### View logs
```powershell
Get-Content "$env:LOCALAPPDATA\CameraWatch\CameraWatch.log" -Tail 50
```

## Uninstallation

To remove CameraWatch:

```powershell
.\Uninstall-CameraWatch.ps1
```

To also remove all configuration and log files:

```powershell
.\Uninstall-CameraWatch.ps1 -RemoveConfig
```

## How It Works

The script monitors the Windows registry key that tracks webcam usage:
- `HKEY_USERS\{SID}\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam`

It polls this registry location every 15 seconds to detect when applications start or stop using the webcam. When a state change is detected, it sends a POST request to your configured webhook URL with information about the active processes.

## Webhook Payload

When the webcam starts:
```json
{
    "user": "YourUsername",
    "processes": "process1,process2"
}
```

When the webcam stops:
```json
{
    "user": "YourUsername",
    "processes": ""
}
```

## Use Case: Home Assistant Integration

This script works great with Home Assistant to create automation based on webcam usage. For example:
1. Create a webhook trigger in Home Assistant
2. Configure CameraWatch with your webhook URL
3. Create automations to turn on/off a "busy" indicator light when webcam is in use

## Troubleshooting

### Task won't start
- Ensure the script path is correct in Task Scheduler
- Check that PowerShell execution policy allows script execution: `Get-ExecutionPolicy`
- If needed, set execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### Webhook not working
- Verify the webhook URL is correct in `%LOCALAPPDATA%\CameraWatch\config.json`
- Check logs at `%LOCALAPPDATA%\CameraWatch\CameraWatch.log`
- Test the webhook URL manually with a tool like curl or Postman

### Script not detecting webcam
- Ensure you have permission to access the registry key
- Check that your webcam is using the standard Windows camera APIs

## Requirements

- Windows 10 or later
- PowerShell 5.1 or later
- Permissions to create scheduled tasks (Administrator recommended but not required)

## License

This project is open source. Feel free to use and modify as needed.
