<#  CameraWatch.ps1  — notify when the webcam starts or stops             #>
param(
    [string]$LogPath = "$env:LOCALAPPDATA\CameraWatch\CameraWatch.log",
    [string]$WebhookUrl = ""
)

# Load configuration if available
$ConfigFile = "$env:LOCALAPPDATA\CameraWatch\config.json"
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        if (-not $WebhookUrl -and $config.WebhookUrl) {
            $WebhookUrl = $config.WebhookUrl
        }
    } catch {
        # Silently continue if config fails to load
    }
}

# Create log directory if it doesn't exist
try {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
} catch {
    # Exit if we can't create log directory
    exit 1
}

# Logging function that writes to both file and console
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry
}

# Debug: Log script start
Write-Log "DEBUG: Script started"

# Get current user SID
try {
    $UserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Write-Log "DEBUG: User SID: $UserSID"
} catch {
    Write-Log "ERROR: Failed to retrieve user SID: $_"
    exit 1
}

$KeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
$RootHKCU = "Registry::HKEY_USERS\$UserSID\$KeyPath"
Write-Log "DEBUG: RootHKCU: $RootHKCU"

function Get-CameraProcesses {
    Write-Log "DEBUG: Checking active camera processes"
    $result = @()
    try {
        $items = Get-ChildItem $RootHKCU -Recurse -ErrorAction SilentlyContinue
        Write-Log "DEBUG: Found $($items.Count) registry items under webcam key"
        $props = $items | Get-ItemProperty -Name LastUsedTimeStop -ErrorAction SilentlyContinue
        Write-Log "DEBUG: Found $($props.Count) items with LastUsedTimeStop property"
        $currentActive = $props | Where-Object { $_.LastUsedTimeStop -eq 0 }
        Write-Log "DEBUG: Found $($currentActive.Count) active camera process registry entries"
        $result = $currentActive | ForEach-Object { $_.PSPath -replace '.*webcam\\', '' } | Sort-Object -Unique
        Write-Log "DEBUG: Active camera process names: $($result -join ', ')"
    } catch {
        Write-Log "ERROR: Failed to retrieve camera processes: $_"
        $result = @() # Set empty array on failure
    }
    return $result
}

function Send-WebhookNotification {
    param(
        [string]$Processes
    )
    
    if (-not $WebhookUrl) {
        Write-Log "DEBUG: No webhook URL configured, skipping notification"
        return
    }
    
    try {
        $body = @{ 
            user = $env:USERNAME
            processes = $Processes
        }
        Write-Log "DEBUG: Sending POST request to $WebhookUrl"
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Log "DEBUG: POST request sent successfully"
    } catch {
        Write-Log "ERROR: Failed to send POST request: $_"
    }
}

# Main monitoring loop
Write-Log "INFO: Starting CameraWatch monitoring loop"
$active = @()

while ($true) {
    try {
        Start-Sleep -Seconds 15
        $now = Get-CameraProcesses
        Write-Log "DEBUG: Polled active processes: $($now -join ', ')"
        
        if (($now -join ',') -ne ($active -join ',')) {
            if ($now -and $now.Count -gt 0) {
                Write-Log "START   $($now -join ', ')"
                Send-WebhookNotification -Processes ($now -join ',')
            } else {
                Write-Log "STOP"
                # Only send notification if there were previously active processes
                if ($active -and $active.Count -gt 0) {
                    Send-WebhookNotification -Processes ""
                }
            }
            $active = $now
        }
        Write-Log "INFO: Active camera processes after poll: $($active -join ', ')"
    } catch {
        Write-Log "ERROR: Failed during polling loop: $_"
    }
}