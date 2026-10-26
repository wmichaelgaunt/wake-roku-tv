#!/usr/bin/env bash
# ============================================================
# wake-roku-tv.sh
#
# Wake a compatible Roku TV and select an HDMI input.
# Designed for systemd-based Linux distributions.
# ============================================================

# ---------------- USER CONFIGURATION ------------------------

# TV's current local IPv4 address.
TV_IP="<FILL_IN_TV_IP_ADDRESS>"

# TV's MAC address as 12 hex characters, without separators.
TV_MAC="<FILL_IN_TV_MAC_12_HEX_CHARACTERS>"

# Broadcast address for the subnet containing the TV.
TV_BROADCAST="<FILL_IN_LOCAL_BROADCAST_ADDRESS>"

# HDMI input connected to the PC: HDMI1, HDMI2, HDMI3, or HDMI4.
TV_INPUT="HDMI1"

# Require Linux to report a connected HDMI connector?
# true  = exit if no connected HDMI connector is detected.
# false = skip HDMI detection and attempt TV control.
REQUIRE_HDMI="true"

# Seconds to wait for a usable route to the TV.
NETWORK_TIMEOUT_SECONDS=30

# Seconds to wait between wake commands and input selection.
TV_WAKE_DELAY_SECONDS=10

# ------------------------------------------------------------

set -u

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

fail() {
    log "ERROR: $*"
    exit 1
}

# Validate configuration.
case "$TV_IP" in
    "<FILL_IN_"*|"") fail "Set TV_IP in the configuration section." ;;
esac
case "$TV_MAC" in
    "<FILL_IN_"*|"") fail "Set TV_MAC in the configuration section." ;;
esac
case "$TV_BROADCAST" in
    "<FILL_IN_"*|"") fail "Set TV_BROADCAST in the configuration section." ;;
esac

[[ "$TV_MAC" =~ ^[[:xdigit:]]{12}$ ]] ||
    fail "TV_MAC must contain exactly 12 hexadecimal characters."

[[ "$TV_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
    fail "TV_IP must be an IPv4 address."

[[ "$TV_BROADCAST" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
    fail "TV_BROADCAST must be an IPv4 address."

case "$TV_INPUT" in
    HDMI1|HDMI2|HDMI3|HDMI4) ;;
    *) fail "TV_INPUT must be HDMI1, HDMI2, HDMI3, or HDMI4." ;;
esac

[[ "$NETWORK_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] &&
    (( NETWORK_TIMEOUT_SECONDS >= 1 )) ||
    fail "NETWORK_TIMEOUT_SECONDS must be a positive integer."

[[ "$TV_WAKE_DELAY_SECONDS" =~ ^[0-9]+$ ]] ||
    fail "TV_WAKE_DELAY_SECONDS must be a non-negative integer."

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."
[[ -d /sys/class/drm ]] || fail "/sys/class/drm is unavailable."

log "Wake-Roku-TV starting."

# Wait for an actual route to the TV, rather than relying only on
# a fixed delay after resume.
log "Waiting for a usable network route to $TV_IP..."
network_ready=false

for ((i=0; i<NETWORK_TIMEOUT_SECONDS; i++)); do
    if ip route get "$TV_IP" >/dev/null 2>&1; then
        network_ready=true
        break
    fi
    sleep 1
done

[[ "$network_ready" == true ]] ||
    fail "No usable route to $TV_IP after ${NETWORK_TIMEOUT_SECONDS}s."

log "Network route is available."

# Detect a connected HDMI DRM connector. Connector status files
# are commonly /sys/class/drm/card*-HDMI-A-*/status.
hdmi_connected=false

if [[ "$REQUIRE_HDMI" == "true" ]]; then
    for status_file in /sys/class/drm/card*-*/status; do
        [[ -r "$status_file" ]] || continue
        connector="$(basename "$(dirname "$status_file")")"

        if [[ "$connector" == *HDMI* ]] &&
           [[ "$(cat "$status_file" 2>/dev/null)" == "connected" ]]; then
            log "Connected HDMI connector detected: $connector"
            hdmi_connected=true
            break
        fi
    done

    if [[ "$hdmi_connected" != true ]]; then
        log "No connected HDMI connector detected. Nothing to do."
        exit 0
    fi
else
    log "HDMI detection is disabled; continuing without connector check."
fi

# Send Roku ECP power-on command. This may fail if the TV is asleep
# in a state that does not accept network commands.
log "Sending Roku PowerOn command..."
if curl --silent --show-error --max-time 5 \
    -X POST "http://${TV_IP}:8060/keypress/PowerOn" >/dev/null; then
    log "PowerOn request sent."
else
    log "PowerOn request failed; continuing with Wake-on-LAN attempt."
fi

# Send Wake-on-LAN magic packet: six FF bytes followed by 16 copies
# of the TV MAC. Python's UDP socket enables broadcast explicitly.
log "Sending Wake-on-LAN packet to $TV_BROADCAST:9..."
if ! TV_MAC="$TV_MAC" TV_BROADCAST="$TV_BROADCAST" python3 - <<'PY'
import os
import socket

mac_text = os.environ["TV_MAC"]
broadcast = os.environ["TV_BROADCAST"]
mac = bytes.fromhex(mac_text)
if len(mac) != 6:
    raise SystemExit("TV_MAC must decode to exactly 6 bytes")

packet = b"\xff" * 6 + mac * 16

with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.sendto(packet, (broadcast, 9))
PY
then
    log "Wake-on-LAN send failed; continuing to input selection."
else
    log "Wake-on-LAN packet sent."
fi

log "Waiting ${TV_WAKE_DELAY_SECONDS}s for the TV..."
sleep "$TV_WAKE_DELAY_SECONDS"

log "Selecting $TV_INPUT..."
if curl --silent --show-error --max-time 5 \
    -X POST "http://${TV_IP}:8060/keypress/Input${TV_INPUT}" >/dev/null; then
    log "$TV_INPUT request sent."
else
    log "$TV_INPUT request failed."
    exit 1
fi

log "Wake-Roku-TV complete."
