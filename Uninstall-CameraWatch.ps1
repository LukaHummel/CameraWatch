<#
.SYNOPSIS
    Uninstalls CameraWatch scheduled task.

.DESCRIPTION
    This script removes the CameraWatch scheduled task from Windows Task Scheduler
    and optionally removes configuration files.

.PARAMETER RemoveConfig
    If specified, also removes the configuration directory and log files.

.EXAMPLE
    .\Uninstall-CameraWatch.ps1
    
.EXAMPLE
    .\Uninstall-CameraWatch.ps1 -RemoveConfig
#>

param(
    [switch]$RemoveConfig
)

$ErrorActionPreference = "Stop"

# Task Scheduler configuration
$TaskName = "CameraWatch"
$TaskPath = "\CameraWatch\"

# Check if task exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue

if ($existingTask) {
    try {
        # Stop the task if it's running
        Stop-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        
        # Unregister the task
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        Write-Host "CameraWatch scheduled task has been removed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to remove scheduled task: $_"
        exit 1
    }
} else {
    Write-Host "CameraWatch scheduled task not found." -ForegroundColor Yellow
}

# Remove configuration if requested
if ($RemoveConfig) {
    $ConfigDir = "$env:LOCALAPPDATA\CameraWatch"
    
    if (Test-Path $ConfigDir) {
        try {
            Remove-Item -Path $ConfigDir -Recurse -Force
            Write-Host "Configuration directory removed: $ConfigDir" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to remove configuration directory: $_"
        }
    } else {
        Write-Host "Configuration directory not found." -ForegroundColor Yellow
    }
}

Write-Host "`nCameraWatch has been uninstalled." -ForegroundColor Green
