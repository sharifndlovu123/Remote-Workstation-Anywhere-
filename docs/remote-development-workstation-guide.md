# Remote Development Workstation — Setup and Recovery Guide

**Last validated:** 25 October 2026  
**Status:** Operational; full-shutdown Wake-on-LAN, GNOME Remote Login, FreeRDP and automatic connection script tested successfully.

> This guide records the configuration that was tested. Commands assume you administer these devices and are running them on the device specified. Never commit passwords, private SSH keys, or Keychain exports to a repository.

## 1. Objective

Access the Ubuntu development desktop from a MacBook without leaving the desktop running continuously. The Raspberry Pi remains powered on and acts as a Tailscale subnet router and Wake-on-LAN sender. A single `home-desktop` command on macOS checks the RDP service, wakes the desktop if needed, waits for it to boot, retrieves the RDP password from macOS Keychain, and opens a fullscreen remote session.

### Working architecture

```text
MacBook (macOS)
  |  Tailscale client; SSH alias home-pi; FreeRDP; macOS Keychain
  |  Run: home-desktop
  v
Tailscale encrypted tunnel
  |
  v
Raspberry Pi 5 (always on)
  |  Ubuntu 26.04.1 LTS
  |  Ethernet: <GATEWAY_IP>
  |  Tailscale subnet router: <HOME_SUBNET>
  |  Sends WoL magic packet to <WOL_BROADCAST>
  v
Home LAN (<HOME_SUBNET>; router <ROUTER_IP>)
  |
  v
Ubuntu development desktop
  |  Ethernet: enp5s0
  |  Reserved LAN IP: <WORKSTATION_IP>
  |  Ethernet MAC: <WORKSTATION_MAC>
  |  GNOME / Wayland / GDM
  |  GNOME Remote Login RDP: TCP 3389
  v
Graphical development session
```

The Raspberry Pi is **not** an RD Gateway. In FreeRDP or Windows App, connect directly to `<WORKSTATION_IP>:3389`; do not configure the Pi as an RDP gateway. Tailscale routes packets for the home subnet through the Pi.

## 2. Device and network inventory

| Component | Confirmed configuration |
|---|---|
| Home subnet | `<HOME_SUBNET>` |
| Home router / gateway | `<ROUTER_IP>` |
| Raspberry Pi Ethernet | `eth0`, `<GATEWAY_IP>` |
| Raspberry Pi Wi-Fi | `wlan0`, `<GATEWAY_WIFI_IP>` (Ethernet preferred) |
| Raspberry Pi SSH | `ssh home-pi` from MacBook |
| Ubuntu desktop Ethernet | `enp5s0` |
| Ubuntu desktop IP | `<WORKSTATION_IP>` |
| Ubuntu desktop MAC | `<WORKSTATION_MAC>` |
| Ubuntu NetworkManager profile | `Wired connection 1` |
| Ubuntu display environment | `ubuntu:GNOME`, `ubuntu`, `wayland` |
| Ubuntu RDP service | System `gnome-remote-desktop.service` |
| Ubuntu RDP port | TCP `3389` |
| Ubuntu username | `<USERNAME>` |
| macOS Keychain service name | `<KEYCHAIN_SERVICE>` |
| macOS launcher | `~/bin/home-desktop` |
| RDP client | `sdl-freerdp` |

**IP address stability:** The router has DHCP reservations for the devices, including the desktop at `<WORKSTATION_IP>`. Do not independently assign a conflicting static address inside Ubuntu. If replacing the router or network, update reservations, the advertised subnet, and the script accordingly.

## 3. Tailscale and Raspberry Pi subnet routing

The Pi is always on and makes the home LAN accessible from the MacBook over Tailscale. This avoids exposing SSH or RDP to the public internet and does not require router port forwarding.

### 3.1 Check Tailscale

On the Raspberry Pi:

```bash
tailscale status
ip -4 addr show eth0
```

On the MacBook, ensure Tailscale is connected to the same tailnet. The Pi should be reachable through the configured `home-pi` SSH alias.

### 3.2 Persistent IP forwarding

IPv4 and IPv6 forwarding were enabled persistently on the Pi via `/etc/sysctl.d/99-tailscale.conf`. To inspect:

```bash
cat /etc/sysctl.d/99-tailscale.conf
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
```

If rebuilding the Pi, enable forwarding as appropriate and configure Tailscale to advertise the home subnet:

```bash
sudo tailscale set --advertise-routes=<HOME_SUBNET>
```

Approve the advertised subnet route in the Tailscale admin console. The MacBook must accept/use the route. The working configuration already has the route approved; no further changes are needed for normal use.

### 3.3 MacBook SSH alias

The MacBook's `~/.ssh/config` includes an alias equivalent to:

```sshconfig
Host home-pi
    HostName <GATEWAY_IP>
    User <USERNAME>
    IdentityFile ~/.ssh/<SSH_KEY_FILE>
    IdentitiesOnly yes
```

The `IdentityFile` must match the actual MacBook private key path. An alternative is the Pi's Tailscale `100.x.x.x` address, which avoids possible overlap with other networks using `<HOME_SUBNET>`.

Test:

```bash
ssh home-pi 'hostname && ip -4 addr show eth0'
```

The Pi's `~/.ssh/authorized_keys` must contain the MacBook's corresponding public key. A separate Ubuntu-to-Pi SSH key was also authorized during setup; keys from different machines must be enrolled independently.

## 4. Wake-on-LAN on Ubuntu

### 4.1 Hardware and interface

The development desktop uses a Gigabyte B650 EAGLE AX motherboard, with wired Ethernet interface `enp5s0` and MAC `<WORKSTATION_MAC>`. Wake-on-LAN requires Ethernet and standby power to the network interface.

Check capability:

```bash
sudo ethtool enp5s0 | grep -i wake
```

The initial state supported magic packets but was disabled:

```text
Supports Wake-on: pumbg
Wake-on: d
```

### 4.2 Enable magic-packet wake

```bash
sudo ethtool -s enp5s0 wol g
```

Persist the setting through NetworkManager:

```bash
sudo nmcli connection modify 'Wired connection 1' \
  802-3-ethernet.wake-on-lan magic
```

Verify:

```bash
nmcli -g 802-3-ethernet.wake-on-lan connection show 'Wired connection 1'
sudo ethtool enp5s0 | grep -i wake
```

`magic` in NetworkManager and `Wake-on: g` in `ethtool` are the expected settings.

### 4.3 Send a magic packet from the Pi

The Pi has `wakeonlan` installed. From the MacBook:

```bash
ssh home-pi 'wakeonlan -i <WOL_BROADCAST> <WORKSTATION_MAC>'
```

The directed broadcast `<WOL_BROADCAST>` is on the Pi's local LAN. Sending the packet *from the Pi* avoids depending on broadcast forwarding through Tailscale.

### 4.4 Verified power states

- **Suspend:** Ubuntu woke successfully after `systemctl suspend`.
- **Full shutdown:** Ubuntu also woke successfully after `sudo systemctl poweroff`.

For full-shutdown wake, keep the desktop plugged in, PSU switched on, and Ethernet connected. BIOS/UEFI power-management settings may affect WoL if firmware settings are reset. The motherboard and current settings were verified to support this workflow.

## 5. Ubuntu graphical remote login

### 5.1 Correct desktop environment

Although KDE's `krdp` package was explored during troubleshooting, the active Ubuntu session was confirmed to be **GNOME on Wayland**:

```bash
echo "$XDG_CURRENT_DESKTOP"  # ubuntu:GNOME
echo "$DESKTOP_SESSION"       # ubuntu
echo "$XDG_SESSION_TYPE"      # wayland
```

The missing `plasmashell` executable was expected for this GNOME session. The working server is **GNOME Remote Desktop**, not KDE KRDP and not XRDP. Do not install or enable additional RDP servers without a reason; they can conflict on port 3389.

### 5.2 Enable Remote Login

In Ubuntu's graphical settings, open **Settings → System → Remote Desktop → Remote Login** and enable Remote Login. This differs from **Desktop Sharing**:

- **Remote Login:** Intended for connecting to a login session remotely, including unattended access.
- **Desktop Sharing:** Shares an existing desktop session and has different lock/session behavior.

GNOME Remote Login may start a separate session rather than reconnecting to an existing local desktop session.

### 5.3 Configure system-level RDP credentials

The service was listening on port 3389 but initially rejected clients with:

```text
[RDP] Credentials are not set, denying client
```

We fixed this by setting credentials for the **system** Remote Login service (not the per-user Desktop Sharing service):

```bash
sudo grdctl --system rdp set-credentials
```

This interactively prompts for an RDP username and password. The configured username is `<USERNAME>`; the password is **not documented here**.

Enable username/password authentication:

```bash
sudo grdctl --system rdp set-auth-methods credentials
```

Inspect the resulting configuration without revealing secrets:

```bash
sudo grdctl --system status
```

The working output showed:

```text
Overall:
    Unit status: active
RDP:
    Status: enabled
    Port: 3389
    Authentication methods: credentials
    TLS certificate: /var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/certificates/rdp-tls.crt
    Username: (hidden)
    Password: (hidden)
```

**Do not use** `sudo grdctl --system status --show-credentials` in logs or shared documentation.

### 5.4 Restart the service after credential changes

This was a key recovery step: although `grdctl` reported stored credentials, the already-running daemon continued rejecting connections until it was restarted.

```bash
sudo systemctl daemon-reload
sudo systemctl restart gnome-remote-desktop.service
sudo systemctl status gnome-remote-desktop.service --no-pager
```

The restart resolved the `Credentials are not set` problem.

A warning about TPM credential initialization appeared:

```text
Init TPM credentials failed ... using GKeyFile as fallback
```

The service continued using its file-based fallback and ultimately worked. This warning was not the blocking issue in the verified setup.

### 5.5 Verify port and reachability

On Ubuntu:

```bash
sudo ss -lntp '( sport = :3389 )'
```

The listener should be `gnome-remote-desktop` on TCP 3389.

On the MacBook:

```bash
nc -vz -G 5 <WORKSTATION_IP> 3389
```

A successful TCP connection confirms network reachability only; it does not prove RDP authentication or session creation is working.

## 6. macOS RDP client and credentials

### 6.1 Why FreeRDP

Microsoft's Windows App on macOS initially returned error `0x204`, then stalled at **“Securing connection to remote PC.”** Server logs showed FreeRDP transport/NLA errors during those attempts:

```text
[transport_read_layer]: BIO_read retries exceeded
[transport_accept_nla]: client authentication failure
```

Those errors alone did not prove the exact cause. **FreeRDP connected successfully** with the same GNOME server, so it became the chosen client. Windows App is not required for the working configuration.

Install with Homebrew:

```bash
brew install freerdp
command -v sdl-freerdp
```

A manual test (prompts for credentials):

```bash
sdl-freerdp /v:<WORKSTATION_IP>:3389 /u:<USERNAME> /cert:tofu
```

`/cert:tofu` means *trust on first use*. On first connection, compare the presented certificate fingerprint with the value from `sudo grdctl --system status` on Ubuntu before trusting it. Re-check unexpected certificate changes.

### 6.2 Store password in macOS Keychain

The Keychain **service name** is `<KEYCHAIN_SERVICE>` and account is `<USERNAME>`.

To add or replace the entry interactively:

```bash
security add-generic-password -U -a <USERNAME> -s <KEYCHAIN_SERVICE> -w
```

To verify that an entry exists without displaying the password:

```bash
security find-generic-password -a <USERNAME> -s <KEYCHAIN_SERVICE>
```

The launcher reads it using `security find-generic-password ... -w`. Do not hard-code the password into the script or include it in FreeRDP's `/p:` command-line argument.

## 7. Final one-command MacBook launcher

**File:** `~/bin/home-desktop` on the MacBook.

The script below checks TCP 3389, sends a magic packet through the Pi if RDP is unavailable, waits up to 120 seconds, retrieves the Keychain password, and starts FreeRDP. It retains the working fullscreen, dynamic resolution and **180% scaling** options.

```bash
#!/bin/bash
set -euo pipefail

# Ubuntu desktop
HOST="<WORKSTATION_IP>"
PORT="3389"
USERNAME="<USERNAME>"

# Raspberry Pi and Wake-on-LAN
PI_HOST="home-pi"
DESKTOP_MAC="<WORKSTATION_MAC>"
BROADCAST="<WOL_BROADCAST>"
TIMEOUT=120

rdp_ready() {
    nc -z -G 3 "$HOST" "$PORT" >/dev/null 2>&1
}

echo "Checking Ubuntu desktop..."

if rdp_ready; then
    echo "Ubuntu RDP is already available."
else
    echo "RDP unavailable. Sending Wake-on-LAN packet..."

    ssh -o ConnectTimeout=10 "$PI_HOST" \
        "wakeonlan -i $BROADCAST $DESKTOP_MAC"

    echo "Waiting for Ubuntu RDP (up to ${TIMEOUT}s)..."
    START=$SECONDS

    until rdp_ready; do
        if (( SECONDS - START >= TIMEOUT )); then
            echo "Error: RDP did not become available within ${TIMEOUT}s."
            echo "Check Ubuntu power, Tailscale routing and the RDP service."
            exit 1
        fi
        sleep 3
    done
    echo "Ubuntu RDP is available."
fi

echo "Retrieving credentials from macOS Keychain..."
PASSWORD=$(security find-generic-password \
    -a "$USERNAME" \
    -s "<KEYCHAIN_SERVICE>" \
    -w)

echo "Launching FreeRDP..."
printf '%s\n' "$PASSWORD" | sdl-freerdp \
    /v:"$HOST:$PORT" \
    /u:"$USERNAME" \
    /from-stdin \
    /f \
    /dynamic-resolution \
    /scale:180 \
    /cert:tofu

unset PASSWORD
```

**Note:** `/from-stdin` is supported by the installed, tested FreeRDP build. It avoids placing the password in the command-line arguments, although the password still exists briefly in the script's memory. The script assumes the macOS `security` utility and the `sdl-freerdp` executable are available.

### 7.1 Install and verify the launcher

```bash
mkdir -p ~/bin
nano ~/bin/home-desktop
chmod 700 ~/bin/home-desktop
bash -n ~/bin/home-desktop
```

The executable permission was important: an initial `Permission denied` error was fixed with `chmod u+x ~/bin/home-desktop`.

### 7.2 Add `~/bin` to Zsh PATH

If not already configured, add this line to `~/.zshrc`:

```bash
export PATH="$HOME/bin:$PATH"
```

Then:

```bash
source ~/.zshrc
command -v home-desktop
```

Expected result is a path ending in `/bin/home-desktop`.

**Normal use:**

```bash
home-desktop
```

### 7.3 Display configuration

FreeRDP initially opened a small window. Adding `/f` and `/dynamic-resolution` provided fullscreen and dynamic sizing. The Retina display then made Ubuntu's internal UI appear too small. The tested setting was:

```text
/scale:180
```

This provided a comfortable result. If display behavior changes after an update, review FreeRDP's `/help` and GNOME's **Settings → Displays → Scale** options.

## 8. End-to-end validation

The following components were individually verified:

1. MacBook reaches the Raspberry Pi over Tailscale.
2. Raspberry Pi advertises the `<HOME_SUBNET>` home subnet.
3. MacBook can reach `<WORKSTATION_IP>:3389`.
4. Pi wakes Ubuntu from **suspend**.
5. Pi wakes Ubuntu from **full shutdown**.
6. GNOME Remote Login accepts configured system RDP credentials after service restart.
7. FreeRDP connects and supports actual development work.
8. `home-desktop` executes from PATH, retrieves the `<KEYCHAIN_SERVICE>` Keychain credential and uses fullscreen with `/scale:180`.
9. The combined script was reported working well.

To re-run the full power-off test:

```bash
# On Ubuntu
sudo systemctl poweroff
```

Wait until it shuts down. On the MacBook, with Tailscale connected:

```bash
home-desktop
```

Expected: check RDP → send WoL if unavailable → wait for port 3389 → open FreeRDP.

## 9. Troubleshooting reference

| Symptom | Likely area | Check or recovery |
|---|---|---|
| `ssh home-pi` fails | Tailscale, SSH alias, keys | `tailscale status`; `ssh -v home-pi`; inspect `~/.ssh/config` and Pi's `authorized_keys` |
| Pi reachable but desktop not reachable | Power, subnet route, LAN IP | Check WoL, router reservation, `ping <WORKSTATION_IP>` |
| Desktop won't wake | Ethernet WoL, firmware, standby power | `sudo ethtool enp5s0`; `nmcli` WoL profile; PSU and Ethernet cable |
| TCP 3389 refused | GNOME RDP service | `sudo systemctl status gnome-remote-desktop.service`; `sudo ss -lntp '( sport = :3389 )'` |
| TCP 3389 times out | Routing/firewall | Tailscale route, Pi forwarding, Ubuntu firewall, correct address |
| `[RDP] Credentials are not set` | System-level RDP credentials | `sudo grdctl --system rdp set-credentials`, then restart service |
| RDP stalls during securing/authentication | Client/NLA/session | Inspect journal; retry known-working FreeRDP instead of Windows App |
| GNOME service logs TPM fallback | TPM unavailable for credential storage | Not necessarily fatal; service worked with GKeyFile fallback |
| `home-desktop: command not found` | Zsh PATH | Add `~/bin` to `~/.zshrc`, reload shell |
| `Permission denied` running script | Executable bit or ownership | `ls -l ~/bin/home-desktop`; `chmod 700 ~/bin/home-desktop` |
| Keychain lookup fails | Wrong service/account or access control | Check service `<KEYCHAIN_SERVICE>`, account `<USERNAME>`, macOS Keychain permission prompt |
| Remote desktop looks tiny | HiDPI scaling | Keep `/f`, `/dynamic-resolution`, `/scale:180` |
| Wake succeeds but RDP never opens | RDP service not ready or broken | Check Ubuntu's `gnome-remote-desktop.service` and `journalctl` |

Useful diagnostic commands on Ubuntu:

```bash
sudo grdctl --system status
sudo systemctl status gnome-remote-desktop.service --no-pager
sudo journalctl -u gnome-remote-desktop.service --since '5 minutes ago' --no-pager -l
sudo ss -lntp '( sport = :3389 )'
systemctl status gdm3.service --no-pager
sudo ethtool enp5s0 | grep -i wake
```

Useful checks on MacBook:

```bash
tailscale status
ssh home-pi 'hostname'
nc -vz -G 5 <WORKSTATION_IP> 3389
command -v sdl-freerdp
command -v home-desktop
security find-generic-password -a <USERNAME> -s <KEYCHAIN_SERVICE>
```

## 10. Security and operational notes

- **Do not port-forward TCP 3389** or SSH from the public internet. Keep access via Tailscale and the private LAN.
- The **RDP Gateway** field in Microsoft clients is unrelated to Tailscale subnet routing. Leave it unset.
- A Tailscale subnet route enables network reachability; it does **not** by itself restrict which devices already on the home LAN can reach RDP. Review Ubuntu firewall rules and LAN trust as needed.
- Protect the MacBook with disk encryption and a strong login password, since it holds the SSH private key and Keychain RDP secret.
- Keep the Pi, Ubuntu, Tailscale, FreeRDP and macOS updated.
- Do not publish passwords, private keys, full Keychain output, or RDP certificates' private keys.
- If the Pi or router changes, update the SSH alias, Tailscale subnet route and WoL broadcast as necessary.
- If Ubuntu's Ethernet adapter changes, update the WoL MAC and interface/profile names.
- If the desktop's DHCP reservation changes, update `HOST` in the launcher.
- The launcher treats an unavailable RDP port as a possible power-off state and sends one WoL packet. If the desktop is already running but RDP is broken, the wake packet won't repair the service; use SSH or local access to troubleshoot.
- The `nc` readiness check proves only that TCP 3389 is accepting connections, not that RDP login is guaranteed.
- When using a remote GNOME login, an existing local graphical session may be separate from the remote session. Save work before switching sessions or shutting down.

## 11. Quick-reference commands

**From MacBook — normal remote development:**

```bash
home-desktop
```

**From MacBook — manually wake Ubuntu:**

```bash
ssh home-pi 'wakeonlan -i <WOL_BROADCAST> <WORKSTATION_MAC>'
```

**From MacBook — check RDP port:**

```bash
nc -vz -G 5 <WORKSTATION_IP> 3389
```

**From Ubuntu — restart Remote Login after credential changes:**

```bash
sudo systemctl restart gnome-remote-desktop.service
```

**From Ubuntu — verify RDP settings:**

```bash
sudo grdctl --system status
```

**From Ubuntu — verify Wake-on-LAN:**

```bash
sudo ethtool enp5s0 | grep -i wake
```

---

**Result:** The MacBook can remotely power on the Ubuntu desktop from a full shutdown and access a usable GNOME development session over Tailscale using a single `home-desktop` command.
