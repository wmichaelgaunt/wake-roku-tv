# Wake Roku TV

Automatically wake a Roku TV and switch it to a selected HDMI input when a PC starts or resumes, for setups where HDMI-CEC is unavailable or unreliable.

This repository provides separate guides and scripts for **Windows 11** and **Bazzite Linux**. The scripts use network commands supported by Roku TVs rather than requiring HDMI-CEC. They are intended as community starting points and may need adjustment for a specific PC, network, TV model, or operating system.

> **Testing note:** The author's only tested TV is a **Hisense Roku TV**. Other Roku TV models may behave differently depending on their firmware, network settings, and support for Roku's External Control Protocol (ECP). Compatibility with non-Roku TVs is not intended.

## Choose your operating system

- **Windows 11:** See [`wake-roku-tv-windows/`](wake-roku-tv-windows/README.md) for setup instructions, the PowerShell script, and Windows Task Scheduler configuration.
- **Bazzite Linux:** See [`wake-roku-tv-bazzite/`](wake-roku-tv-bazzite/README.md) for setup instructions, the shell script, and systemd resume/optional startup configuration.

Each subfolder contains its own README and MIT license. Follow the instructions for your operating system and fill in the hardware- and network-specific values in the script.

## How it works

The platform-specific script checks for an active HDMI display where supported, sends wake commands to the configured Roku TV over the local network, and requests a switch to the configured HDMI input. The scripts can use Roku's network control interface and Wake-on-LAN; exact behavior depends on the TV model, settings, and network.

This does **not** add HDMI-CEC support to the PC or TV. It is a software workaround that sends network commands when the relevant Windows task or Linux service or hook runs.

## Compatibility

| Platform | Status |
|---|---|
| Windows 11 | Instructions and script are provided in `wake-roku-tv-windows/`. |
| Bazzite Linux | Primary Linux target; instructions and script are provided in `wake-roku-tv-bazzite/`. |
| Other Linux distributions | Some systemd-based distributions may be adaptable, but they are not covered by the Bazzite guide and have not been independently verified. |

The Windows and Linux scripts are separate implementations. Do not assume that commands or setup steps from one folder apply to the other.

## Before you start

- The PC and TV must be able to communicate over the same local network, including any relevant router or VLAN rules.
- Find the TV's local IP address and MAC address, and identify the desired HDMI input.
- Check that network control and Wake-on-LAN behavior are supported and enabled as needed on your TV.
- Review the platform-specific README before running a script. Replace every clearly marked placeholder with values for your own network and hardware.
- HDMI detection may identify an active HDMI connector without distinguishing a particular physical port on a discrete GPU.

## Security and privacy

The scripts are intended for use on a trusted local network. Roku ECP commonly uses HTTP on the local network and may not provide authentication in the configurations described here. Do not expose the TV's control interface to the public internet. Use a trusted LAN and review the script before running it.

## Repository layout

```text
wake-roku-tv/
├── README.md
├── LICENSE
├── wake-roku-tv-windows/
│   ├── README.md
│   ├── Wake-RokuTV.ps1
│   └── .gitignore
└── wake-roku-tv-bazzite/
    ├── README.md
    ├── wake-roku-tv.sh
    └── .gitignore
```

## License

This project is released under the MIT License. See [`LICENSE`](LICENSE). The operating-system subfolders also include license files for convenience when their contents are shared separately.
