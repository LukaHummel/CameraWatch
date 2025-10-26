<#  CameraWatch.ps1  — notify when the webcam starts or stops             #>
param(
    [string]$LogPath = "$env:LOCALAPPDATA\CameraWatch\CameraWatch.log",
    [string]$WebhookUrl = ""
)
$InformationPreference = 'Continue'

# Load configuration if available
$ConfigFile = "$env:LOCALAPPDATA\CameraWatch\config.json"
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        if (-not $WebhookUrl -and $config.WebhookUrl) {
            $WebhookUrl = $config.WebhookUrl
        }
    } catch {
        Write-Warning "Failed to load configuration: $_"
    }
}

# Debug: Log script start
Write-Information "DEBUG: Script started"

# Get current user SID
try {
    $UserSID = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Write-Information "DEBUG: User SID: $UserSID"
} catch {
    Write-Error "ERROR: Failed to retrieve user SID: $_"
    exit 1
}

$KeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\webcam"
$RootHKCU = "Registry::HKEY_USERS\$UserSID\$KeyPath"
Write-Information "DEBUG: RootHKCU: $RootHKCU"

try {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
} catch {
    Write-Error "ERROR: Failed to create log directory: $_"
    exit 1
}

function Get-CameraProcesses {
    Write-Information "DEBUG: Checking active camera processes"
    $result = @()
    try {
        $items = Get-ChildItem $RootHKCU -Recurse -ErrorAction SilentlyContinue
        Write-Information "DEBUG: Found $($items.Count) registry items under webcam key"
        $props = $items | Get-ItemProperty -Name LastUsedTimeStop -ErrorAction SilentlyContinue
        Write-Information "DEBUG: Found $($props.Count) items with LastUsedTimeStop property"
        $currentActive = $props | Where-Object { $_.LastUsedTimeStop -eq 0 }
        Write-Information "DEBUG: Found $($currentActive.Count) active camera process registry entries"
        $result = $currentActive | ForEach-Object { $_.PSPath -replace '.*webcam\\', '' } | Sort-Object -Unique
        Write-Information "DEBUG: Active camera process names: $($result -join ', ')"
    } catch {
        Write-Error "ERROR: Failed to retrieve camera processes: $_"
        $result = @() # Set empty array on failure
    }
    return $result
}

function Send-WebhookNotification {
    param(
        [string]$Processes
    )
    
    if (-not $WebhookUrl) {
        Write-Information "DEBUG: No webhook URL configured, skipping notification"
        return
    }
    
    try {
        $body = @{ 
            user = $env:USERNAME
            processes = $Processes
        }
        Write-Information "DEBUG: Sending POST request to $WebhookUrl"
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Information "DEBUG: POST request sent successfully"
    } catch {
        Write-Error "ERROR: Failed to send POST request: $_"
    }
}

# Main monitoring loop
Write-Information "INFO: Starting CameraWatch monitoring loop"
$active = @()

while ($true) {
    try {
        Start-Sleep -Seconds 15
        $now = Get-CameraProcesses
        Write-Information "DEBUG: Polled active processes: $($now -join ', ')"
        
        if (($now -join ',') -ne ($active -join ',')) {
            if ($now -and $now.Count -gt 0) {
                Write-Information "START   $($now -join ', ')"
                Send-WebhookNotification -Processes ($now -join ',')
            } else {
                Write-Information "STOP"
                # Only send notification if there were previously active processes
                if ($active -and $active.Count -gt 0) {
                    Send-WebhookNotification -Processes ""
                }
            }
            $active = $now
        }
        Write-Information "INFO: Active camera processes after poll: $($active -join ', ')"
    } catch {
        Write-Error "ERROR: Failed during polling loop: $_"
    }
}