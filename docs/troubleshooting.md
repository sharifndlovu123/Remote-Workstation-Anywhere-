# Troubleshooting

Work from the outside in: client → tailnet → gateway → workstation power → workstation service → client app. Examples use placeholder values.

Useful first commands

```bash
# on the client
remote-workstation --check
tailscale status
ssh gateway 'hostname'
nc -vz -G 5 192.168.1.50 3389          # macOS (use -w 5 instead of -G 5 on Linux)

# on the workstation
sudo grdctl --system status
sudo systemctl status gnome-remote-desktop.service --no-pager
sudo ss -lntp '( sport = :3389 )'
sudo journalctl -u gnome-remote-desktop.service --no-pager -l
```

## Quick table

| Symptom | Likely area | First check |
|---|---|---|
| `ssh gateway` fails | Tailscale, alias, keys | `tailscale status`; `ssh -v gateway`; gateway `authorized_keys` |
| Gateway reachable, workstation not | Power, route, address | WoL, DHCP reservation, `ping` from the gateway |
| Workstation will not wake | WoL, firmware, standby power | `sudo ethtool eno1`, NetworkManager profile |
| TCP 3389 refused | RDP service not running | `systemctl status gnome-remote-desktop.service` |
| TCP 3389 times out | Routing or firewall | Tailscale route, forwarding on gateway, workstation firewall |
| `Credentials are not set` | System-level credentials | `grdctl --system rdp set-credentials`, restart |
| Stalls while "securing connection" | Client or NLA incompatibility | Try FreeRDP, read the journal |
| Tiny remote display | HiDPI | `DISPLAY_SCALE`, `/dynamic-resolution` |
| `command not found` / `Permission denied` | Script install | See [script problems](#script-execution-problems) |

## RDP port reachable, but connection fails

A successful TCP test with `nc` proves only that something accepts connections on that port. It does **not** prove RDP authentication or session creation will work.

On the workstation:

```bash
sudo ss -lntp '( sport = :3389 )'
sudo systemctl status gnome-remote-desktop.service
sudo grdctl --system status
sudo journalctl -u gnome-remote-desktop.service --no-pager -l
```

How to read the results:

- Nothing listening on 3389: the service is stopped, disabled, or Remote Login is off. Enable Remote Login and restart the service.
- Listening, but `grdctl --system status` shows no credentials or no `credentials` auth method: see the next section.
- Listening and configured, but the journal shows transport or authentication errors: try a different client and compare. See [A Microsoft client fails but FreeRDP works](#a-microsoft-client-fails-but-freerdp-works).
- Run `journalctl -f -u gnome-remote-desktop.service` on the workstation while you connect to see errors as they happen.

## Credentials are not set

Observed in the journal:

```text
[RDP] Credentials are not set, denying client
```

Meaning: the service is listening but has no usable RDP credentials for the mode in use.

Fix (system-level Remote Login):

```bash
sudo grdctl --system rdp set-credentials          # interactive prompt
sudo grdctl --system rdp set-auth-methods credentials
sudo systemctl daemon-reload
sudo systemctl restart gnome-remote-desktop.service
sudo grdctl --system status
```

Notes:

- Use `--system`. Credentials set without it belong to the per-user Desktop Sharing service and do not apply to Remote Login.
- **Restart the service.** In the verified setup the running daemon kept rejecting clients after credentials were stored, until it was restarted.
- Interactive entry keeps the password out of shell history and the process list. If your `grdctl` version only accepts arguments, avoid putting the password on the command line where it can be seen or logged.
- Never share the output of status commands that reveal credentials.
- A warning like `Init TPM credentials failed ... using GKeyFile as fallback` was seen in the verified setup and did not block it.

## A Microsoft client fails but FreeRDP works

Observed with Microsoft's Windows App on macOS against GNOME Remote Desktop:

- Error `0x204`, then a stall at "Securing connection to remote PC".
- Workstation logs contained lines such as:

  ```text
  [transport_read_layer]: BIO_read retries exceeded
  [transport_accept_nla]: client authentication failure
  ```

- FreeRDP connected to the same server.

This is an **observed compatibility issue in one setup**. It is not proof that Windows App is universally incompatible with GNOME Remote Desktop, and those log lines alone do not identify the cause. Possible factors include certificate or NLA handling differences, versions, or settings. If you hit it, use FreeRDP, and if you investigate further please open an issue with versions and logs (with addresses and names removed).

Also: connect directly to the workstation's LAN address; leave "RD Gateway" empty. The gateway here is a Tailscale subnet router, not an RD Gateway.

## FreeRDP display too small

On a Retina/HiDPI screen the default FreeRDP window is small and the remote UI looks tiny.

Working combination on macOS: fullscreen, dynamic resolution and scaling.

```text
/f  /dynamic-resolution  /scale:180
```

In this repo set `DISPLAY_SCALE="180"`. FreeRDP accepts only `100`, `140` and `180`; the script rejects other values. Also check **Settings → Displays → Scale** on the workstation. If an update changes behaviour, compare against `sdl-freerdp /help`.

## Wake-on-LAN works from suspend but not from shutdown

Wake from suspend and from full power-off use different power states. Work down this list:

1. **Firmware.** Enable Wake on LAN / Power On By PCI-E in BIOS/UEFI. Disable ErP / EuP / deep-sleep style power saving, which can cut standby power to the NIC. Firmware updates and "load defaults" can reset these.
2. **Standby power.** PSU switch on, power cable connected, Ethernet cable connected. With the machine soft-off, the NIC's link light should normally still be on.
3. **OS setting at shutdown time.** Confirm after boot:

   ```bash
   sudo ethtool eno1 | grep -i wake      # expect: Wake-on: g
   nmcli -g 802-3-ethernet.wake-on-lan connection show 'Wired connection 1'   # expect: magic
   ```

   If it reads `d` after boot, NetworkManager is not applying the setting (wrong profile name or not the active profile).
4. **Driver behaviour.** Some NIC drivers reset the setting during shutdown. If `ethtool` is right before shutdown but wake fails, search for your NIC driver together with "wake on lan shutdown".
5. **Hardware.** Some boards and NICs only support wake from suspend. Check the motherboard manual and vendor forums.
6. **Packet path.** Verify the MAC and broadcast address; confirm the gateway is on the same LAN segment (wired preferred); watch for the packet with `tcpdump` on the workstation's LAN or the gateway.

   ```bash
   sudo tcpdump -i eth0 -n 'udp port 9 or udp port 7'    # on the gateway, while sending
   ```

7. **Sent is not received.** `wakeonlan` reports success when it has *sent* the packet, not when the machine woke.

## Script execution problems

**`Permission denied`**

```bash
ls -l "$(readlink ~/bin/remote-workstation || echo ~/bin/remote-workstation)"
chmod +x scripts/macos/connect.sh scripts/common/wake.sh scripts/linux/connect.sh
```

If you copied (not symlinked) the script, remember it needs `scripts/common/lib.sh` alongside it. Symlink instead of copying.

**`command not found: remote-workstation`**

- The symlink is missing or broken: `ls -l ~/bin/remote-workstation`.
- `~/bin` is not on PATH. Add `export PATH="$HOME/bin:$PATH"` to `~/.zshrc` (or `~/.bashrc`), then `source` it. Check with `command -v remote-workstation`.
- A new terminal may be needed.

**Incorrect file ownership**

Files created with `sudo` end up owned by root and unreadable or unwritable by you.

```bash
ls -l ~/.config/remote-workstation-anywhere/
sudo chown "$USER" ~/.config/remote-workstation-anywhere/config.env
chmod 600 ~/.config/remote-workstation-anywhere/config.env
```

**Missing PATH entries for tools**

`command not found: sdl-freerdp` or `nc`: install the tool and check `command -v sdl-freerdp`. On macOS with Homebrew, make sure the Homebrew prefix is on PATH in your shell startup file.

**Keychain lookup failures**

```bash
security find-generic-password -a youruser -s remote-workstation
```

- Not found: the account (`RDP_USERNAME`) or service (`KEYCHAIN_SERVICE`) does not match what you stored. Re-add with `security add-generic-password -U -a youruser -s remote-workstation -w`.
- Found, but the script still fails: a Keychain access prompt may have been denied or is waiting; unlock the login keychain and rerun from a normal terminal.
- Remote shell sessions (for example over SSH) may not be able to show the prompt.
- On Linux, `secret-tool lookup` needs a running secret service (GNOME Keyring or KWallet). Without it the script falls back to a prompt.

**SSH gateway connectivity failures**

```bash
ssh -v gateway 'hostname'
tailscale status
ping -c 3 192.168.1.2
```

- `Permission denied (publickey)`: the client's key is not in the gateway's `authorized_keys`, or `IdentityFile` is wrong.
- Timeout: Tailscale is down, the subnet route is not approved or accepted (Linux clients need `--accept-routes`), or the gateway is offline.
- `Host key verification failed`: the gateway was rebuilt; confirm that is why, then remove the old entry with `ssh-keygen -R`.
- `wakeonlan: command not found` on the gateway: install it there.

**Script says RDP did not become available**

The message lists likely causes. In practice: wake did not work (see above), the service is down, the route is missing, or `BOOT_TIMEOUT` is too short for a slow boot.

## Still stuck

Collect, with addresses, names and credentials removed: OS and FreeRDP versions, `remote-workstation --check` output, the relevant journal lines. Then open an issue.
