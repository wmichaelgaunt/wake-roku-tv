# Wake a Roku TV When Linux Starts or Resumes

Automatically wake a compatible Roku TV and switch it to the HDMI input connected to your Linux PC when the PC resumes from suspend. An optional systemd startup service can also run the same script at boot.

This project is intended for home-theater and console-style PC setups where HDMI-CEC is unavailable, unsupported, or unreliable. It uses Bash, systemd, Linux DRM display status, `curl`, and Python 3 for the Wake-on-LAN packet. No third-party TV-control application is required.

## Features

- Runs after system resume using a systemd sleep hook.
- Can also be configured to run at boot.
- Checks whether a connected HDMI display is reported by Linux before controlling the TV.
- Waits for a usable route to the TV before sending network commands.
- Sends a Roku power-on command and attempts a Wake-on-LAN broadcast.
- Selects a configurable HDMI input after a delay.
- Keeps hardware- and network-specific values in one configuration section.
- Uses generic Roku TV naming; the tested TV was a Hisense Roku TV.

## 1. Compatibility

### Tested configuration

The original implementation was tested with:

- **PC:** Desktop running Bazzite Linux (Fedora Atomic/Kinoite-based).
- **TV:** Hisense Roku TV. The exact model and Roku OS version were not recorded.
- **Connection:** HDMI between the PC and TV, with both devices connected to the same local network.
- **Network:** Ethernet on the PC; TV reachable by its local IP address.

This confirms the approach on one tested device family, not every Roku TV model or firmware version.

### Linux distributions

| Distribution | Expected compatibility | Notes |
|---|---|---|
| Bazzite | Primary target; tested | Uses systemd and the Linux DRM sysfs interface. |
| Fedora Silverblue / Kinoite | Expected | Similar Fedora Atomic architecture and SELinux defaults. |
| Fedora Workstation / Server | Expected | Uses systemd; package and SELinux setup may vary. |
| Ubuntu / Debian | Expected | Uses systemd on standard installations; install `curl` and Python 3 if missing. |
| Arch Linux | Expected | Uses systemd on standard installations; install `curl` and Python 3 if missing. |
| Other systemd-based distributions | Possible | Must provide `/etc/systemd/system-sleep/`, systemd, Python 3, `curl`, and DRM connector status files. |
| Non-systemd distributions | Not covered by this guide | The script may work, but the resume integration must be adapted. |

These are compatibility expectations based on the interfaces used, not independently tested distributions.

### TV compatibility

Roku's External Control Protocol (ECP) uses HTTP on TCP port 8060. This project sends Roku commands such as `PowerOn` and `InputHDMI1`.

- **Hisense Roku TV:** Tested device family.
- **Other Roku TVs:** Expected to work if their firmware exposes the required ECP commands and allows network control; unverified.
- **Roku streaming players connected to a TV:** Not the primary target. Waking the player does not necessarily wake the display or switch its input.
- **Hisense Google TV, VIDAA TVs, and non-Roku TVs:** Not supported by this script.

See the [official Roku External Control API documentation](https://developer.roku.com/dev/docs/external-control-api). ECP availability and power behavior vary by model, firmware, and settings. The TV must be able to receive network commands in its current power state. Wake-on-LAN is best-effort and is not supported by every TV/network combination.

## 2. How it works

After resume, systemd calls scripts in `/etc/systemd/system-sleep/` with `post` as the first argument. The sleep hook starts the TV script in the background after a short delay so it does not hold up the resume path.

The TV script then:

1. Waits for a usable route to the TV's IP address.
2. Checks Linux DRM connector status files for a connected HDMI connector.
3. Exits without controlling the TV if no connected HDMI connector is found.
4. Sends the Roku `PowerOn` command.
5. Sends a Wake-on-LAN magic packet to the configured TV MAC address.
6. Waits for a configurable delay.
7. Sends the command to select the configured HDMI input.

### HDMI detection limitation

The script checks whether **any** Linux DRM connector whose name starts with `HDMI` reports `connected`. It does not conclusively identify a particular physical port on a specific graphics card, and connector names vary by driver. Some drivers may report the TV as `HDMI-A-1`; others may use different names. Inspect `/sys/class/drm/` on your system before relying on this condition.

If the TV is not reported as connected during resume, the script exits without sending commands. This is intentional for setups where the TV should only be woken when an HDMI display is connected. You can disable this check in the script if that behavior is not appropriate for your setup.

## 3. Requirements

- A systemd-based Linux distribution.
- Bash.
- `curl`.
- Python 3.
- A Roku TV reachable on the local network.
- The TV's local IP address and network-interface MAC address.
- An active HDMI connector reported through `/sys/class/drm/`.

On Bazzite, Fedora, and many other distributions these tools are usually available. On Debian/Ubuntu, install missing packages with:

```bash
sudo apt update
sudo apt install curl python3
```

On Fedora:

```bash
sudo dnf install curl python3
```

On Arch Linux:

```bash
sudo pacman -S curl python
```

Bazzite is an image-based/Atomic system; do not use `rpm-ostree` layering for tools already provided by the base image. If a required utility is missing, follow the current Bazzite documentation for installing it.

## 4. Find your TV's settings

### TV IP address

Find the TV's IPv4 address in the TV's network settings or in your router's connected-device list. Prefer a DHCP reservation in your router so the address does not change.

Test Roku ECP from a browser or terminal, replacing the placeholder:

```bash
curl --max-time 5 "http://<TV_IP_ADDRESS>:8060/query/device-info"
```

If ECP is available, the TV should return XML device information. If it fails, check the IP address, network isolation, and the TV's network-control settings.

### TV MAC address

Find the MAC address for the TV's active network interface in the TV network settings or router. Wi-Fi and Ethernet can have different MAC addresses; use the interface the TV actually uses.

The script expects 12 hexadecimal characters without colons or hyphens, for example `AABBCCDDEEFF`.

### Broadcast address

Find the PC's IPv4 address and subnet prefix:

```bash
ip -4 addr
ip route
ip route get <TV_IP_ADDRESS>
```

For a typical `192.168.1.0/24` network, the broadcast address is `192.168.1.255`. Do not assume this example applies to your network. Set the broadcast address to match the TV's subnet. The route lookup also helps identify the interface used to reach the TV.

### HDMI connector name

List DRM connectors and their status:

```bash
for status in /sys/class/drm/card*-*/status; do
    [ -e "$status" ] || continue
    printf '%s: ' "$status"
    cat "$status"
done
```

Look for a connector with a name such as `card1-HDMI-A-1` whose status is `connected`. The script checks for any connected connector whose name contains `HDMI`. If your driver uses a different connector name, adjust the HDMI-detection section in the script.

## 5. Install the TV-control script

Create the script in `/usr/local/bin`, not in a user's home directory. This avoids common systemd/SELinux execution-context issues.

```bash
sudo install -d -m 755 /usr/local/bin
sudo nano /usr/local/bin/wake-roku-tv.sh
```

Copy the contents of [`wake-roku-tv.sh`](wake-roku-tv.sh) into that file, then edit the configuration section at the top.

All required hardware-specific values are marked with `FILL_IN`.

After editing, set permissions and ownership:

```bash
sudo chown root:root /usr/local/bin/wake-roku-tv.sh
sudo chmod 755 /usr/local/bin/wake-roku-tv.sh
```

On SELinux-enabled systems such as Bazzite and Fedora, restore the expected file context:

```bash
sudo restorecon -v /usr/local/bin/wake-roku-tv.sh
```

If `restorecon` is unavailable on your distribution, skip that command. On SELinux systems, verify the context with:

```bash
ls -lZ /usr/local/bin/wake-roku-tv.sh
matchpathcon /usr/local/bin/wake-roku-tv.sh
```

The expected type for `/usr/local/bin` is commonly `bin_t`. Do not disable SELinux to work around a file-context issue.

## 6. Test the script manually

Run:

```bash
sudo /usr/local/bin/wake-roku-tv.sh
```

When a connected HDMI connector is detected, the script should log the sequence and attempt to wake the TV and select the configured input. If no HDMI connector is reported as connected, it should exit without sending TV commands.

If a TV is connected but Linux reports `disconnected`, inspect the DRM connector status and driver behavior before proceeding.

## 7. Run the script after resume

Create a systemd sleep hook:

```bash
sudo nano /etc/systemd/system-sleep/wake-roku-tv
```

Paste:

```bash
#!/bin/bash

# systemd passes:
#   $1 = pre or post
#   $2 = suspend, hibernate, hybrid-sleep, etc.

if [ "$1" = "post" ]; then
    (
        # Give the network and display stack time to recover.
        sleep 5
        /usr/local/bin/wake-roku-tv.sh
    ) >> /var/log/wake-roku-tv.log 2>&1 &
fi

exit 0
```

Save the file and make it executable:

```bash
sudo chown root:root /etc/systemd/system-sleep/wake-roku-tv
sudo chmod 755 /etc/systemd/system-sleep/wake-roku-tv
sudo restorecon -v /etc/systemd/system-sleep/wake-roku-tv
```

The `restorecon` command is relevant to SELinux-enabled distributions. If unavailable, skip it.

The hook starts the script in the background so network waiting and TV startup delays do not block the resume hook. The script's output is appended to `/var/log/wake-roku-tv.log`.

> Note: On some distributions, systemd sleep hooks run in a constrained environment. If the log is not created or the script does not run, check the system journal and SELinux audit log. You may need to adjust logging for your distribution.

## 8. Optional: run at boot

The resume hook does not run at ordinary boot. To also run the script at boot, create a separate oneshot service:

```bash
sudo nano /etc/systemd/system/wake-roku-tv-boot.service
```

Paste:

```ini
[Unit]
Description=Wake Roku TV at system boot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 5
ExecStart=/usr/local/bin/wake-roku-tv.sh

[Install]
WantedBy=multi-user.target
```

Confirm that `/usr/bin/sleep` exists on your distribution. If it does not, change the path to the result of `command -v sleep`.

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable wake-roku-tv-boot.service
```

To test it without rebooting:

```bash
sudo systemctl start wake-roku-tv-boot.service
sudo systemctl status wake-roku-tv-boot.service
```

If your system does not use `multi-user.target` in the expected way, or does not have `network-online.target` configured by its network manager, adjust the unit to match that distribution.

## 9. Troubleshooting

### Script works manually but not after resume

Check the log:

```bash
sudo tail -100 /var/log/wake-roku-tv.log
```

Inspect systemd sleep messages:

```bash
journalctl -b --no-pager | grep -Ei 'systemd-sleep|wake-roku-tv'
```

### Network is unavailable after resume

Check the route to the TV:

```bash
ip route get <TV_IP_ADDRESS>
```

The script retries the route check for a configurable number of seconds. Increase the timeout if your network takes longer to recover.

### Roku commands fail

Test the device-info endpoint:

```bash
curl --max-time 5 "http://<TV_IP_ADDRESS>:8060/query/device-info"
```

Then test the power and input commands manually:

```bash
curl --max-time 5 -X POST "http://<TV_IP_ADDRESS>:8060/keypress/PowerOn"
curl --max-time 5 -X POST "http://<TV_IP_ADDRESS>:8060/keypress/InputHDMI1"
```

Use the input command that matches the configured TV input. Check the TV's ECP settings and whether the TV accepts network commands in its current power state.

### Wake-on-LAN fails

Verify the MAC address and broadcast address. The script's WoL packet is sent as a UDP broadcast on port 9. Broadcast filtering, Wi-Fi behavior, router isolation, or TV hardware limitations may prevent it from waking the TV. The Roku `PowerOn` command and WoL packet are separate attempts; one may work when the other does not.

### SELinux denies execution

Check for AVC denials:

```bash
sudo ausearch -m AVC -ts recent
```

Restore expected labels:

```bash
sudo restorecon -v /usr/local/bin/wake-roku-tv.sh
sudo restorecon -v /etc/systemd/system-sleep/wake-roku-tv
```

Do not disable SELinux as a general fix.

### No HDMI connector detected

Inspect `/sys/class/drm/*/status` and confirm that the expected connector reports `connected`. Display drivers can report connector state differently, especially during resume. You can disable HDMI gating in the script if you prefer it to attempt TV control regardless of connector state.

## 10. Uninstall

Remove the optional boot service if you enabled it:

```bash
sudo systemctl disable --now wake-roku-tv-boot.service
sudo rm -f /etc/systemd/system/wake-roku-tv-boot.service
sudo systemctl daemon-reload
```

Remove the resume hook and script:

```bash
sudo rm -f /etc/systemd/system-sleep/wake-roku-tv
sudo rm -f /usr/local/bin/wake-roku-tv.sh
```

Remove the log if desired:

```bash
sudo rm -f /var/log/wake-roku-tv.log
```

## Security and privacy

The script sends unauthenticated HTTP commands to a Roku device on the local network. Use it only on a trusted LAN. Do not expose the TV's ECP port directly to the internet.

## References

- [Roku External Control API documentation](https://developer.roku.com/dev/docs/external-control-api)
- [systemd sleep hooks](https://www.freedesktop.org/software/systemd/man/latest/systemd-sleep.html)
- [Linux DRM connector status](https://docs.kernel.org/gpu/drm-kms.html)

## License

This project is licensed under the MIT License. See [LICENSE](../LICENSE).