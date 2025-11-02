<#
.SYNOPSIS
    Installs CameraWatch as a scheduled task that runs at user logon.

.DESCRIPTION
    This script creates a Windows Task Scheduler task that automatically starts
    CameraWatch when the user logs in. The task will run in the background and
    persist across reboots.

.PARAMETER WebhookUrl
    The webhook URL to send notifications to (e.g., Home Assistant webhook)

.EXAMPLE
    .\Install-CameraWatch.ps1 -WebhookUrl "https://your-homeassistant-url/api/webhook/your-webhook-id"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$WebhookUrl = ""
)

$ErrorActionPreference = "Stop"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "This script should be run as Administrator for best results."
    Write-Host "Attempting to install for current user only..." -ForegroundColor Yellow
}

# Get the directory where this script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$MainScriptPath = Join-Path $ScriptDir "Camerawatch.ps1"

# Verify the main script exists
if (-not (Test-Path $MainScriptPath)) {
    Write-Error "Cannot find Camerawatch.ps1 in $ScriptDir"
    exit 1
}

# Create config directory
$ConfigDir = "$env:LOCALAPPDATA\CameraWatch"
$ConfigFile = Join-Path $ConfigDir "config.json"

try {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Write-Host "Created configuration directory: $ConfigDir" -ForegroundColor Green
} catch {
    Write-Error "Failed to create configuration directory: $_"
    exit 1
}

# Save webhook URL to config if provided
if ($WebhookUrl) {
    $config = @{
        WebhookUrl = $WebhookUrl
    }
    $config | ConvertTo-Json | Set-Content $ConfigFile
    Write-Host "Saved webhook URL to configuration" -ForegroundColor Green
}

# Task Scheduler configuration
$TaskName = "CameraWatch"
$TaskDescription = "Monitors webcam access and sends notifications"
$TaskPath = "\CameraWatch\"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "CameraWatch task already exists. Removing old task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
}

# Create the scheduled task action
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$MainScriptPath`""

# Create the trigger (at logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn

# Create settings for the task
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -DontStopOnIdleEnd `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Get current user principal
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Register the scheduled task
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -Principal $Principal `
        -Description $TaskDescription `
        -Force | Out-Null
    
    Write-Host "`nCameraWatch has been successfully installed!" -ForegroundColor Green
    Write-Host "The task will start automatically at next logon." -ForegroundColor Green
    Write-Host "`nTo start the task now, run:" -ForegroundColor Cyan
    Write-Host "  Start-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskPath'" -ForegroundColor White
    Write-Host "`nTo check task status, run:" -ForegroundColor Cyan
    Write-Host "  Get-ScheduledTask -TaskName '$TaskName' -TaskPath '$TaskPath' | Get-ScheduledTaskInfo" -ForegroundColor White
    Write-Host "`nTo uninstall, run:" -ForegroundColor Cyan
    Write-Host "  .\Uninstall-CameraWatch.ps1" -ForegroundColor White
    
    # Prompt to start now
    $response = Read-Host "`nDo you want to start CameraWatch now? (Y/N)"
    if ($response -eq 'Y' -or $response -eq 'y') {
        Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
        Write-Host "CameraWatch started successfully!" -ForegroundColor Green
        
        # Wait a moment and check if it's running
        Start-Sleep -Seconds 2
        $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
        Write-Host "Task Status: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
    }
    
} catch {
    Write-Error "Failed to register scheduled task: $_"
    exit 1
}
