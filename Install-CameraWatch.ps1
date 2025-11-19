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
    [string]$WebhookUrl = "",
    [Parameter(Mandatory=$false)]
    [string]$WebhookUrlSignOff = ""
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
$VBSLauncherPath = Join-Path $ScriptDir "Start-CameraWatch.vbs"

# Verify the main script exists
if (-not (Test-Path $MainScriptPath)) {
    Write-Error "Cannot find Camerawatch.ps1 in $ScriptDir"
    exit 1
}

# Verify the VBS launcher exists
if (-not (Test-Path $VBSLauncherPath)) {
    Write-Error "Cannot find Start-CameraWatch.vbs in $ScriptDir"
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

# Save webhook URLs to config if provided
$config = @{}
if ($WebhookUrl) {
    $config.WebhookUrl = $WebhookUrl
}
if ($WebhookUrlSignOff) {
    $config.WebhookUrlSignOff = $WebhookUrlSignOff
}
if ($config.Keys.Count -gt 0) {
    $config | ConvertTo-Json | Set-Content $ConfigFile
    Write-Host "Saved webhook URL(s) to configuration" -ForegroundColor Green
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

# Create the scheduled task action using VBScript launcher for truly hidden execution
$Action = New-ScheduledTaskAction -Execute "wscript.exe" `
    -Argument "`"$VBSLauncherPath`""

# Create the trigger (at logon with a small delay to ensure registry is ready)
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Trigger.Delay = "PT30S"  # 30 second delay after logon

# Create settings for the task
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -DontStopOnIdleEnd `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)  # No time limit - run indefinitely

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
        try {
            Start-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath
            Write-Host "CameraWatch task has been triggered..." -ForegroundColor Green
            
            # Wait for the task to start
            Start-Sleep -Seconds 3
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath
            $taskState = (Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath).State
            
            Write-Host "`nTask State: $taskState" -ForegroundColor Cyan
            Write-Host "Last Run Time: $($taskInfo.LastRunTime)" -ForegroundColor Cyan
            Write-Host "Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
            
            if ($taskState -eq "Running") {
                Write-Host "`nTask is running! Check the log file:" -ForegroundColor Green
                Write-Host "  Get-Content `"$ConfigDir\CameraWatch.log`" -Tail 20" -ForegroundColor White
            } else {
                Write-Warning "Task may have exited. Checking log for errors..."
                $logFile = Join-Path $ConfigDir "CameraWatch.log"
                if (Test-Path $logFile) {
                    Write-Host "`nRecent log entries:" -ForegroundColor Yellow
                    Get-Content $logFile -Tail 10 | ForEach-Object { Write-Host "  $_" }
                } else {
                    Write-Warning "Log file not found. The script may have failed to start."
                    Write-Host "`nTry running the script manually to see errors:" -ForegroundColor Cyan
                    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$MainScriptPath`"" -ForegroundColor White
                }
            }
        } catch {
            Write-Error "Failed to start task: $_"
        }
    }
    
} catch {
    Write-Error "Failed to register scheduled task: $_"
    exit 1
}
