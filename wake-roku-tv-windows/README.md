# Wake a Roku TV When Windows 11 Starts or Resumes

Automatically wake a compatible Roku TV and switch it to the HDMI input connected to your Windows PC when the PC starts or resumes from sleep.

This project is intended for home theater and console-style PC setups where HDMI-CEC is unavailable, unsupported, or unreliable. It uses Windows 11, PowerShell, Task Scheduler, and Roku's External Control Protocol (ECP). No third-party software is required.

## Features

- Runs automatically at Windows startup and after resuming from sleep.
- Sends a Roku power-on command and attempts a Wake-on-LAN wake.
- Selects a configurable HDMI input after a startup delay.
- Optionally requires Windows to detect an active HDMI-connected display before controlling the TV.
- Uses built-in Windows tools and PowerShell.
- Keeps hardware-specific settings in one configuration section.

## 1. Compatibility

### Tested configuration

The original implementation was tested with:

- **PC:** Windows 11 desktop with an NVIDIA GeForce RTX 4060.
- **TV:** Hisense Roku TV. The exact model and Roku OS version were not recorded.
- **Connection:** HDMI between the PC and TV, with both devices connected to the same local network.

This confirms the approach on one tested device family, not every Roku TV model or firmware version.

### Expected compatibility

| Device or feature | Compatibility |
|---|---|
| Windows 11 desktop | Target platform |
| Hisense Roku TV | Tested device family |
| Other Roku TVs | Expected to work if the required ECP commands are supported |
| Roku streaming players connected to a TV | Not the primary target; wake and input switching depend on the connected display |
| Hisense Google TV or VIDAA TV | Not supported by this script |
| Other PC graphics cards | Expected to work, subject to display-detection behavior |
| HDMI-CEC | Not required |
| Wake-on-LAN | Best-effort; TV and network support vary |

Roku's External Control Protocol uses HTTP on TCP port 8060. Some Roku OS versions require ECP control to be enabled in the TV settings.

Consult the [official Roku External Control API documentation](https://developer.roku.com/dev/docs/external-control-api) for current requirements and supported commands.

**Important:** This script cannot guarantee that every Roku TV will wake from a fully powered-off state. The TV must support the relevant network control behavior while in its current power state. Wake-on-LAN support is also device- and network-dependent.

## 2. How it works

When Windows starts or resumes from sleep:

1. Task Scheduler launches the PowerShell script.
2. The script waits for Windows to establish a usable network route to the TV.
3. If HDMI detection is enabled, the script checks whether Windows reports an active HDMI-connected display. If none is found, it exits.
4. The script sends a Roku `PowerOn` command to the TV.
5. It sends a Wake-on-LAN magic packet to the configured TV MAC address.
6. It waits for a configurable number of seconds.
7. It sends a command to select the configured HDMI input.

The script can skip step 3 entirely. This is useful when Windows does not report the TV as an active display during startup or resume.

### Limitations

The HDMI check identifies an active HDMI connection reported by Windows. It does not identify the exact physical HDMI port or guarantee that the connection belongs to a discrete graphics card.

The script also cannot verify that the selected HDMI input actually has a working video signal. It sends the input-selection command and reports whether the HTTP request succeeded.

## 3. Identify your device-specific settings

Before running the script, collect the following information.

| Setting | Example only | Purpose |
|---|---|---|
| TV IP address | `192.168.1.242` | Sends Roku ECP commands to the TV |
| TV MAC address | `38640746AF0A` | Destination address for the magic packet |
| Local broadcast address | `192.168.1.255` | Sends the magic packet to the local subnet |
| HDMI input | `HDMI1` | Selects the input connected to the PC |
| HDMI detection | `$true` | Determines whether an active HDMI display is required |

**Do not copy the example addresses.** Replace each placeholder with the values for your own hardware and network.

### 3.1 Find the TV IP address

On the TV, open its network settings and locate its IP address. Alternatively, identify the TV in your router's connected-device list.

You can test Roku ECP from a web browser by replacing the placeholder in this address:

`http://<TV_IP_ADDRESS>:8060/query/device-info`

If ECP is available, the TV should return device information. If the request fails, verify the IP address, network connectivity, and ECP settings before proceeding.

On supported Roku OS versions, check the TV's settings for an option similar to:

**Settings → System → Advanced system settings → Control by mobile apps**

Enable the relevant control permission if required. Menu names may vary by software version.

### 3.2 Find the TV MAC address

Find the MAC address for the network interface the TV uses, either in its network settings or in your router's device list.

A TV may have separate Wi-Fi and Ethernet MAC addresses. Use the address associated with its current network connection.

Enter the address as exactly 12 hexadecimal characters, without colons or hyphens.

For example:

- Displayed address: `AA:BB:CC:DD:EE:FF`
- Script format: `AABBCCDDEEFF`

A valid MAC address does not guarantee that Wake-on-LAN will work. Many TVs do not support magic-packet wake in every standby state, particularly over Wi-Fi.

### 3.3 Find the local broadcast address

Open PowerShell and run:

```powershell
Get-NetIPConfiguration
```

Identify the active network adapter that can reach your TV. Then run:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.AddressState -eq "Preferred" -and
        $_.IPAddress -notlike "169.254.*"
    } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength
```

Use the IPv4 address and prefix length of the relevant adapter.

For a common home network using `192.168.1.0/24`, the broadcast address is `192.168.1.255`. Your network may use a different subnet.

If you are unsure, consult your router's LAN configuration or calculate the broadcast address from the IPv4 address and subnet mask. The broadcast address must be appropriate for the TV's local subnet, and the network must permit the packet to reach it.

### 3.4 Identify the HDMI input

Determine which HDMI input on the TV is physically connected to the PC.

The script defaults to HDMI 1. If your PC is connected to HDMI 2, for example, set the input to `HDMI2`.

The script supports the input names `HDMI1`, `HDMI2`, `HDMI3`, and `HDMI4`. Availability depends on the TV model.

## 4. Test Roku control manually

Before automating the process, test whether the TV accepts ECP commands.

Open PowerShell and run the following, replacing the IP address with your TV's address:

```powershell
$TV_IP = "<FILL_IN_TV_IP_ADDRESS>"

Invoke-WebRequest `
    -Uri "http://${TV_IP}:8060/keypress/PowerOn" `
    -Method Post `
    -UseBasicParsing

Invoke-WebRequest `
    -Uri "http://${TV_IP}:8060/keypress/InputHDMI1" `
    -Method Post `
    -UseBasicParsing
```

These commands send a power-on request and select HDMI 1.

If they fail, resolve the network or ECP issue before configuring Task Scheduler. If the input command returns successfully but the TV does not switch inputs, confirm that the command is supported by your device and that the input name is correct.

## 5. Install the PowerShell script

Create this directory:

`C:\ProgramData\WakeRokuTV`

Save [`Wake-RokuTV.ps1`](Wake-RokuTV.ps1) in that directory:

`C:\ProgramData\WakeRokuTV\Wake-RokuTV.ps1`

Edit the user configuration section before running the script. All required hardware-specific values are marked with `FILL_IN`.

### Configure HDMI detection

The `$RequireHDMIDisplay` variable controls whether Windows must detect an active HDMI-connected display.

| Value | Behavior |
|---|---|
| `$true` | Requires an active HDMI display. The script exits without sending TV commands if none is detected. |
| `$false` | Skips display detection and attempts the wake and input-selection sequence. |

For a console-style PC that should wake the TV whenever the PC starts or resumes, regardless of Windows display detection, set:

```powershell
$RequireHDMIDisplay = $false
```

This setting does not bypass the network-route check. It also does not verify that the TV is physically connected to the PC.

## 6. Test the script

Open PowerShell and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File "C:\ProgramData\WakeRokuTV\Wake-RokuTV.ps1"
```

Run the test while logged into Windows so you can inspect the output.

Verify the following:

- With `$RequireHDMIDisplay = $true`, an active HDMI display allows the sequence to proceed.
- With `$RequireHDMIDisplay = $true` and no active HDMI display, the script exits without sending TV commands.
- With `$RequireHDMIDisplay = $false`, the script skips the display check.
- The TV responds to the power-on and input-selection commands.
- The configured delay is sufficient for the TV to accept the input command.

To inspect Windows' display reporting independently, run:

```powershell
Get-CimInstance `
    -Namespace root\wmi `
    -ClassName WmiMonitorConnectionParams |
    Select-Object Active, VideoOutputTechnology, InstanceName
```

An active HDMI display is expected to report `Active = True` and `VideoOutputTechnology = 5`. Graphics drivers, adapters, and display configurations may affect the results.

## 7. Configure Task Scheduler

Once the script works manually, configure Windows to run it automatically.

### 7.1 Create the task

1. Open **Task Scheduler**.
2. Select **Create Task**, not **Create Basic Task**.
3. On the **General** tab:
   - Name: `Wake Roku TV`
   - Select **Run whether user is logged on or not**.
   - Select **Run with highest privileges**.
   - Choose the appropriate Windows version if a compatibility option is shown.
   - Running as `SYSTEM` is an option for this system-level script, but is not mandatory. If you use another account, ensure it has permission to execute the script.

### 7.2 Add the startup trigger

On the **Triggers** tab:

1. Select **New**.
2. Set **Begin the task** to **At startup**.
3. Enable the trigger.
4. Save it.

### 7.3 Add the resume trigger

Add a second trigger:

1. Select **New**.
2. Set **Begin the task** to **On an event**.
3. Select the **Custom** option, then create or select an event filter.
4. Configure the event filter for:
   - Log: `System`
   - Source: `Microsoft-Windows-Power-Troubleshooter` (displayed as `Power-Troubleshooter` on some systems)
   - Event ID: `1`
5. Save the trigger.

This event commonly records a return from a sleep state. Event availability and behavior can vary by system, so verify that your PC records the expected event after resuming.

### 7.4 Configure the action

On the **Actions** tab, select **New**.

**Program/script**

```text
powershell.exe
```

**Add arguments**

```text
-NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\WakeRokuTV\Wake-RokuTV.ps1"
```

**Start in**

```text
C:\ProgramData\WakeRokuTV
```

If you chose a different script path, update the arguments and working directory accordingly.

### 7.5 Review conditions and settings

On **Conditions**:

- Clear **Start the task only if the computer is on AC power** if you need this on a laptop running on battery.

On **Settings**:

- Allow the task to be run on demand.
- Choose a suitable policy for what happens if the task is already running.
- Consider enabling a short delay after startup if your network is consistently slow to initialize.

Save the task. Windows may request credentials depending on the selected account.

### 7.6 Verify automation

Test the task manually from Task Scheduler first. Then test both a normal startup and a resume from sleep.

Check **History** and **Last Run Result** if the TV does not respond. If the task works manually but not automatically, verify the triggers, account permissions, script path, and network initialization timing.

## 8. Troubleshooting

### TV does not wake

- Confirm the TV IP address and that it is reachable on the local network.
- Verify that the manual Roku ECP power-on command works.
- Check whether the TV supports network wake from its current standby state.
- Remember that successful transmission of a magic packet does not confirm that the TV received or acted on it.

### TV wakes but does not change input

- Verify that ECP control is enabled if required.
- Test the input-selection command manually.
- Increase `$TVWakeDelaySeconds` if the TV needs more time to initialize.
- Confirm that `$TV_INPUT` matches an available input.

### Script exits without doing anything

- Check that all three network configuration placeholders have been replaced.
- Verify that Windows can establish a route to the TV.
- If HDMI detection is enabled, inspect the reported monitor connection information.
- Set `$RequireHDMIDisplay = $false` if you do not want monitor detection to block the wake sequence.

### Script works manually but not at startup or resume

- Verify both Task Scheduler triggers.
- Confirm the action points to the correct PowerShell script.
- Ensure the selected account can read and execute the script.
- Check whether the task runs before the network becomes available.
- Review Task Scheduler history and the task's last run result.

### A DisplayPort monitor is connected instead

With HDMI detection enabled, the script should exit if Windows does not report an active HDMI display. With HDMI detection disabled, the script proceeds without distinguishing HDMI from DisplayPort.

The detection logic does not verify that the active HDMI connection belongs to a particular GPU or physical port.

## 9. Security and privacy

The script sends unauthenticated HTTP commands to the TV over the local network. Devices that can access the TV's ECP service may be able to control it.

Use this on a trusted home network. Do not expose TCP port 8060 directly to the internet.

The script does not intentionally transmit personal information or send commands to an external service. It uses the configured local TV address and broadcast address.

## References

- [Roku External Control API](https://developer.roku.com/dev/docs/external-control-api)
- [Microsoft: WmiMonitorConnectionParams](https://learn.microsoft.com/en-us/windows/win32/wmicoreprov/wmimonitorconnectionparams)
- [Microsoft: Display output technology enumeration](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ne-wingdi-displayconfig_video_output_technology)
- [Microsoft: Task Scheduler](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)

## License

This project is licensed under the MIT License. See [LICENSE](../LICENSE).