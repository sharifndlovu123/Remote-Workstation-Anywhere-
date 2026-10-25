# Ubuntu / GNOME workstation

**Verified:** Ubuntu 26.04, GNOME, Wayland, GNOME Remote Desktop in *Remote Login* mode (system-level RDP).

KDE, XRDP and Windows-hosted workstations are **not tested** and not covered here.

Wake-on-LAN, DHCP reservations and firmware are covered in [wake-on-lan.md](wake-on-lan.md) and [network-setup.md](network-setup.md).

## 1. Confirm the desktop session

```bash
echo "$XDG_CURRENT_DESKTOP"   # expect something like ubuntu:GNOME
echo "$XDG_SESSION_TYPE"      # expect wayland
```

Use **one** RDP server. GNOME Remote Desktop, XRDP and KDE's server all want TCP 3389 and will conflict. If you experimented with another one, disable it before continuing.

## 2. Remote Login versus Desktop Sharing

GNOME Remote Desktop offers two different modes.

| Mode | Purpose | Runs as | Notes |
|---|---|---|---|
| **Remote Login** | Connect to the machine as if at the login screen, including unattended and after a cold boot. | System service | What this repo uses. Credentials are set with `grdctl --system`. The remote session can be separate from the one on the physical screen. |
| **Desktop Sharing** | Share the already-running session of a logged-in user. | Per-user service | Different lock and session behaviour. Credentials are set with `grdctl` *without* `--system`. Not what this repo uses. |

Credentials for one mode do **not** apply to the other. Setting them in the wrong place is the cause of the most common failure (see [troubleshooting](troubleshooting.md#credentials-are-not-set)).

## 3. Enable Remote Login

Open **Settings → System → Remote Desktop**, switch to **Remote Login** and enable it. Menu names can differ between releases.

## 4. Set RDP credentials (system level)

```bash
sudo grdctl --system rdp set-credentials
```

On the tested version this prompts interactively for a username and password, so nothing secret lands in shell history or the process list. Check `grdctl --help` on your version to confirm. If yours requires the password as an argument, do not type it directly: avoid history (a leading space only helps if `HISTCONTROL` includes `ignorespace`; check with `echo $HISTCONTROL`) and remember arguments can be visible to other local users while the command runs.

The RDP username/password are specific to this service. Use a long, unique password.

Enable credential authentication:

```bash
sudo grdctl --system rdp set-auth-methods credentials
```

## 5. Restart the service

This step is easy to miss. In the verified setup the already-running daemon kept rejecting clients after credentials were stored, until it was restarted.

```bash
sudo systemctl daemon-reload
sudo systemctl restart gnome-remote-desktop.service
sudo systemctl status gnome-remote-desktop.service --no-pager
```

A log line such as `Init TPM credentials failed ... using GKeyFile as fallback` can appear. In the verified setup the service continued with its file-based fallback and worked, so it was not the blocking problem. Do not assume it is harmless on other hardware without testing.

## 6. Check status without exposing secrets

```bash
sudo grdctl --system status
```

Expected, in shape:

```text
Overall:
    Unit status: active
RDP:
    Status: enabled
    Port: 3389
    Authentication methods: credentials
    TLS certificate: <path>/rdp-tls.crt
    Username: (hidden)
    Password: (hidden)
```

Do **not** run it with the option that shows credentials in anything you log, screenshot or share.

## 7. Check that the port is listening

```bash
sudo ss -lntp '( sport = :3389 )'
```

You should see `gnome-remote-desktop` listening on `3389`.

## 8. Know the certificate fingerprint

Clients that use trust-on-first-use will show a fingerprint on first connect. Compare it with the real one before trusting it. Use the certificate path printed by `grdctl --system status`:

```bash
sudo openssl x509 -in /path/from/status/rdp-tls.crt -noout -fingerprint -sha256
```

More in [security.md](security.md#host-certificate-verification).

## 9. Firewall

If `ufw` or `nftables` is active on the workstation, allow TCP 3389 only from where it should come from. With default subnet routing that is the **gateway's LAN address**, not your laptop. See [security.md](security.md#how-subnet-routing-changes-the-source-ip).

```bash
sudo ufw status
sudo ufw allow from 192.168.1.2 to any port 3389 proto tcp
```

## 10. Diagnosing failures after a reboot

```bash
sudo systemctl status gnome-remote-desktop.service --no-pager
sudo journalctl -u gnome-remote-desktop.service -b --no-pager -l
sudo ss -lntp '( sport = :3389 )'
systemctl status gdm3.service --no-pager
sudo grdctl --system status
sudo ethtool eno1 | grep -i wake
```

If the port is not listening, the service is the problem. If the port is listening but login fails, look at credentials and logs. If the machine did not wake at all, it is a Wake-on-LAN problem, not an RDP one.

## Things to keep in mind

- Remote Login may start a session separate from the one on the physical screen. Save work before switching.
- Do not disable screen locking or authentication to make this more convenient.
- Keep Ubuntu, GNOME Remote Desktop and the kernel updated.
