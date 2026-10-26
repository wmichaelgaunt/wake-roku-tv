# ============================================================
# Wake-RokuTV.ps1
#
# Windows 11: wake a compatible Roku TV and select an HDMI
# input at startup or after system resume.
#
# Requires no third-party software.
# ============================================================

# ---------------- USER CONFIGURATION ------------------------

# Roku TV's current local IPv4 address.
$TV_IP        = "<FILL_IN_TV_IP_ADDRESS>"

# TV network-interface MAC address: 12 hex characters,
# with no colons or hyphens.
$TV_MAC       = "<FILL_IN_TV_MAC_12_HEX_CHARACTERS>"

# Broadcast address for the local subnet that reaches the TV.
$TV_BROADCAST = "<FILL_IN_LOCAL_BROADCAST_ADDRESS>"

# HDMI input connected to the PC: HDMI1, HDMI2, HDMI3, or HDMI4.
$TV_INPUT     = "HDMI1"

# Require Windows to detect an active HDMI display?
# $true  = Exit if no active HDMI display is detected.
# $false = Skip HDMI detection and continue.
$RequireHDMIDisplay = $true

# Timing, in seconds.
$NetworkTimeoutSeconds = 30
$TVWakeDelaySeconds    = 10

# ------------------------------------------------------------

$ErrorActionPreference = "Stop"

Write-Output "Wake-RokuTV starting."

# Validate required configuration.
if (
    $TV_IP -like "<FILL_IN_*" -or
    $TV_MAC -like "<FILL_IN_*" -or
    $TV_BROADCAST -like "<FILL_IN_*"
) {
    Write-Output "Configuration incomplete. Edit the script first."
    exit 1
}

$parsedIP = $null
if (-not [System.Net.IPAddress]::TryParse($TV_IP, [ref]$parsedIP) -or
    $parsedIP.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    Write-Output "TV_IP must be a valid IPv4 address."
    exit 1
}

$parsedBroadcast = $null
if (-not [System.Net.IPAddress]::TryParse($TV_BROADCAST, [ref]$parsedBroadcast) -or
    $parsedBroadcast.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    Write-Output "TV_BROADCAST must be a valid IPv4 address."
    exit 1
}

if ($TV_MAC -notmatch '^[0-9A-Fa-f]{12}$') {
    Write-Output "TV_MAC must contain exactly 12 hexadecimal characters."
    exit 1
}

if ($TV_INPUT -notin @("HDMI1", "HDMI2", "HDMI3", "HDMI4")) {
    Write-Output "TV_INPUT must be HDMI1, HDMI2, HDMI3, or HDMI4."
    exit 1
}

if ($NetworkTimeoutSeconds -lt 1 -or $TVWakeDelaySeconds -lt 0) {
    Write-Output "Timing values must be positive (wake delay may be zero)."
    exit 1
}

# ------------------------------------------------------------
# Wait for Windows to establish a route to the TV.
# This checks routing, not whether the TV itself is responding.
# ------------------------------------------------------------

Write-Output "Waiting for network route to TV..."

$networkReady = $false

for ($i = 0; $i -lt $NetworkTimeoutSeconds; $i++) {
    try {
        $route = Find-NetRoute -RemoteIPAddress $TV_IP -ErrorAction Stop
        if ($route) {
            $networkReady = $true
            break
        }
    }
    catch {
        # Network may still be initializing.
    }

    Start-Sleep -Seconds 1
}

if (-not $networkReady) {
    Write-Output "No usable route to the TV. Exiting."
    exit 1
}

Write-Output "Network route available."

# ------------------------------------------------------------
# Optionally check for an active HDMI-connected display.
# VideoOutputTechnology = 5 represents HDMI.
# This does not identify a particular physical GPU port.
# ------------------------------------------------------------

if ($RequireHDMIDisplay) {
    Write-Output "Checking active display connections..."

    try {
        $monitors = Get-CimInstance `
            -Namespace root\wmi `
            -ClassName WmiMonitorConnectionParams

        $hdmiMonitor = $monitors |
            Where-Object {
                $_.Active -eq $true -and
                $_.VideoOutputTechnology -eq 5
            } |
            Select-Object -First 1
    }
    catch {
        Write-Output "Could not query monitor connection information."
        Write-Output $_
        exit 1
    }

    if (-not $hdmiMonitor) {
        Write-Output "No active HDMI display detected. Nothing to do."
        exit 0
    }

    Write-Output "Active HDMI display detected."
}
else {
    Write-Output "HDMI detection disabled. Proceeding without display check."
}

# ------------------------------------------------------------
# Send Roku PowerOn command.
# ------------------------------------------------------------

Write-Output "Sending Roku PowerOn command..."

try {
    Invoke-WebRequest `
        -Uri "http://${TV_IP}:8060/keypress/PowerOn" `
        -Method Post `
        -UseBasicParsing `
        -TimeoutSec 5 |
        Out-Null

    Write-Output "PowerOn command sent."
}
catch {
    Write-Output "PowerOn request failed:"
    Write-Output $_
}

# ------------------------------------------------------------
# Send Wake-on-LAN magic packet.
# Packet: 6 bytes of FF followed by 16 copies of the TV MAC.
# This is best-effort and depends on TV/network support.
# ------------------------------------------------------------

Write-Output "Sending Wake-on-LAN packet..."

$udp = $null

try {
    [byte[]]$macBytes = for ($i = 0; $i -lt 12; $i += 2) {
        [Convert]::ToByte($TV_MAC.Substring($i, 2), 16)
    }

    [byte[]]$packet = New-Object byte[] 102

    for ($i = 0; $i -lt 6; $i++) {
        $packet[$i] = 0xFF
    }

    for ($i = 0; $i -lt 16; $i++) {
        for ($j = 0; $j -lt 6; $j++) {
            $packet[6 + ($i * 6) + $j] = $macBytes[$j]
        }
    }

    $udp = New-Object System.Net.Sockets.UdpClient
    $udp.EnableBroadcast = $true

    [void]$udp.Send(
        $packet,
        $packet.Length,
        $TV_BROADCAST,
        9
    )

    Write-Output "Wake-on-LAN packet sent."
}
catch {
    Write-Output "Wake-on-LAN failed:"
    Write-Output $_
}
finally {
    if ($null -ne $udp) {
        $udp.Dispose()
    }
}

# ------------------------------------------------------------
# Wait for the TV to wake, then select the configured input.
# ------------------------------------------------------------

Write-Output "Waiting $TVWakeDelaySeconds seconds..."
Start-Sleep -Seconds $TVWakeDelaySeconds

Write-Output "Selecting $TV_INPUT..."

try {
    Invoke-WebRequest `
        -Uri "http://${TV_IP}:8060/keypress/Input${TV_INPUT}" `
        -Method Post `
        -UseBasicParsing `
        -TimeoutSec 5 |
        Out-Null

    Write-Output "$TV_INPUT command sent."
}
catch {
    Write-Output "Input selection request failed:"
    Write-Output $_
}

Write-Output "Wake-RokuTV complete."
