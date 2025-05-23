<#  CameraWatch.ps1  — notify when the webcam starts or stops             #>
param(
    [string]$LogPath = "$env:LOCALAPPDATA\CameraWatch\CameraWatch.log"
)
$InformationPreference = 'Continue'
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
        Write-Information "DEBUG: Found $($active.Count) active camera process registry entries"
        $result = $currentActive | ForEach-Object { $_.PSPath -replace '.*webcam\\', '' } | Sort-Object -Unique
        Write-Information "DEBUG: Active camera process names: $($result -join ', ')"
    } catch {
        Write-Error "ERROR: Failed to retrieve camera processes: $_"
        $result = @() # Set empty array on failure
    }
    return $result
}

# Run as background job if not already running as a job

if ($MyInvocation.InvocationName -ne 'powershell') {
    # Relaunch as background job if not already running as a job
    $jobName = "CameraWatchBackgroundJob"
    # Check if job already exists
    if (-not (Get-Job -Name $jobName -ErrorAction SilentlyContinue)) {
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Job -Name $jobName -FilePath $scriptPath -ArgumentList @($LogPath) | Out-Null
        Write-Information "INFO: CameraWatch started as background job: $jobName"
        exit
    } else {
        Write-Information "INFO: CameraWatch background job already running."
        exit
    }
}

# Polling loop instead of WMI events
while ($true) {
    try {
        Start-Sleep -Seconds 15
        $now = Get-CameraProcesses
        Write-Information "DEBUG: Polled active processes: $($now -join ', ')"
        if (($now -join ',') -ne ($active -join ',')) {
            if ($now) {
                Write-Information "START   $($now -join ', ')"
                # Send POST request if there is an active camera process
                try {
                    $uri = "https://your-homeassistant-url/api/webhook/your-webhook-id"
                    # Ensure the URI is correct and accessible
                    $body = @{ user = $env:USERNAME; processes = ($now -join ',') }
                    Write-Information "DEBUG: Sending POST request to $uri with body: $($body | Out-String)"
                    Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop | Out-Null
                    Write-Information "DEBUG: POST request sent successfully"
                } catch {
                    Write-Error "ERROR: Failed to send POST request: $_"
                }
            } else {
                Write-Information "STOP"
                # Only send POST if previous poll found processes and current poll found none
                if ($active -and $active.Count -gt 0 -and (!$now -or $now.Count -eq 0)) {
                    try {
                        $uri = "https://your-homeassistant-url/api/webhook/your-webhook-id"
                        # Ensure the URI is correct and accessible
                        $body = @{ user = $env:USERNAME; processes = "" }
                        Write-Information "DEBUG: Sending POST request to $uri with body: $($body | Out-String)"
                        Invoke-RestMethod -Uri $uri -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop | Out-Null
                        Write-Information "DEBUG: POST request sent successfully"
                    } catch {
                        Write-Error "ERROR: Failed to send POST request: $_"
                    }
                }
            }
            $active = $now
        }
        Write-Information "INFO: Active camera processes after poll: $($active -join ', ')"
    } catch {
        Write-Error "ERROR: Failed during polling loop: $_"
    }
}