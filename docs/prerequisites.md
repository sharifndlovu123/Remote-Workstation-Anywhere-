# Prerequisites and support matrix

## What you need

| Item | Requirement |
|---|---|
| Workstation | Wired Ethernet. Firmware and NIC that support Wake-on-LAN (magic packet). Stays plugged in with the PSU switch on. |
| Gateway | Always-on Linux device on the same LAN, ideally wired. Any suitable device works; a Raspberry Pi is optional. Needs `sudo`, SSH server, Tailscale and a Wake-on-LAN utility. |
| Client | Tailscale plus an RDP client. FreeRDP 3 is the tested choice. |
| Network | A router that can reserve a DHCP address for the workstation. No port forwarding needed. |
| Accounts | A Tailscale account (the free tier is enough for personal use). |
| Skills | Comfortable with a terminal, SSH keys and `sudo`. |

## Support matrix

"Verified" means someone ran the whole workflow end to end, including remote power-on from full shutdown. Everything else is labelled honestly.

### Workstation

| Platform | Status | Notes |
|---|---|---|
| Ubuntu 26.04, GNOME, Wayland, GNOME Remote Desktop (Remote Login, system RDP) | **Verified** | Wake from suspend and from full shutdown both tested. |
| Other GNOME distributions | Untested | Should be similar if `grdctl --system` exists. Package names and menus may differ. |
| KDE Plasma (KRDP) | Untested | Different server and tooling. Not documented here. |
| XRDP | Untested | Different server. Do not run it alongside GNOME Remote Desktop on port 3389. |
| Windows host | Untested | Needs a different Wake-on-LAN and RDP setup. |

### Gateway

| Platform | Status |
|---|---|
| Raspberry Pi 5, Ubuntu Server, Ethernet | **Verified** |
| Other always-on Linux devices (mini PC, NAS, router with Tailscale) | Untested, expected to work |
| Gateway on Wi-Fi only | Not recommended: broadcast and latency behaviour vary |

### Client

| Platform | RDP client | Status |
|---|---|---|
| macOS | FreeRDP 3 (`sdl-freerdp`, Homebrew) | **Verified** |
| macOS | Microsoft "Windows App" | Observed to fail against GNOME Remote Desktop (see [troubleshooting](troubleshooting.md#a-microsoft-client-fails-but-freerdp-works)). Not a universal verdict. |
| Linux | FreeRDP 3 | Experimental: script provided, not exercised on real hardware |
| Windows | Built-in Remote Desktop Connection (`mstsc`) | Untested |
| Mobile (iOS, Android) | Various | Untested |

## Limitations to understand up front

- The workstation must support Wake-on-LAN. Many boards and NICs do, some only from suspend, some not at all.
- Remote wake needs an always-on device on the workstation's LAN, unless you have another mechanism (for example a smart plug plus a BIOS "power on after AC loss" setting, which is outside this repo).
- The client needs network access and a compatible RDP client.
- Performance depends on latency and bandwidth. Expect lag on poor links.
- GNOME Remote Login may create a session separate from the local one on the monitor. Save work before switching.
- Remote access does not guarantee identical behaviour for GPU-accelerated or latency-sensitive applications (games, 3D tools, audio/video editing).
- A reachable RDP port only proves TCP connectivity, not that login works.

## Tools used by the scripts

| Tool | Where | Why |
|---|---|---|
| `bash` (3.2 or newer) | client | scripts are bash 3.2 compatible |
| `ssh` | client | reach the gateway |
| `nc` (netcat) | client | TCP port probe |
| `ping` | client | informational host check |
| `security` | macOS | Keychain access (built in) |
| `secret-tool` (libsecret) | Linux, optional | credential store; falls back to a prompt |
| FreeRDP 3 | client | RDP client |
| `wakeonlan` | gateway | send the magic packet |
| `ethtool`, `nmcli` | workstation | configure Wake-on-LAN |
| `grdctl` | workstation | configure GNOME Remote Desktop |
