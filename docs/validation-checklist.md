# Validation checklist

Use this after setting everything up, and again after major upgrades. Tick what you tested; leave unchecked what you did not.

## Workstation

- [ ] `sudo grdctl --system status` shows RDP enabled, port 3389, authentication `credentials`
- [ ] `sudo ss -lntp '( sport = :3389 )'` shows `gnome-remote-desktop`
- [ ] Service restarted after the last credential change
- [ ] `sudo ethtool <interface> | grep -i wake` shows `Wake-on: g`
- [ ] `nmcli -g 802-3-ethernet.wake-on-lan connection show '<profile>'` shows `magic`
- [ ] Setting survives a reboot
- [ ] DHCP reservation in place, address matches `WORKSTATION_IP`
- [ ] Firmware Wake-on-LAN enabled; deep power-saving modes reviewed

## Gateway

- [ ] `tailscale status` online
- [ ] IP forwarding enabled persistently (`sysctl net.ipv4.ip_forward`)
- [ ] Subnet route advertised **and approved**
- [ ] SSH key authentication works from the client; password login disabled
- [ ] `wakeonlan` installed
- [ ] Can reach the workstation from the gateway (`ping`, `nc -vz <ip> 3389`)

## Client

- [ ] Tailscale connected; route to the LAN works (Linux: `--accept-routes`)
- [ ] `ssh <gateway-alias> hostname` works without prompts
- [ ] Credential stored (Keychain or libsecret)
- [ ] Config file exists, mode `600`, values correct
- [ ] `remote-workstation --check` reports client, credential and reachability sensibly
- [ ] Command on PATH (`command -v remote-workstation`)

## End-to-end

- [ ] Workstation awake: command connects without sending Wake-on-LAN
- [ ] Workstation suspended: command wakes and connects
- [ ] Workstation fully shut down: command wakes and connects
- [ ] Display fullscreen, resizes, scaling comfortable
- [ ] Certificate fingerprint verified on first connection
- [ ] Closing the session returns cleanly

## Failure behaviour

- [ ] Gateway unreachable: clear SSH error, no hang
- [ ] Wrong MAC or WoL broken: clear timeout message listing causes
- [ ] Missing Keychain entry: clear error naming account and service

## Repository hygiene (contributors)

- [ ] `bash -n` passes on every script
- [ ] `shellcheck` passes on every script
- [ ] Scripts executable (`ls -l scripts/*/*.sh`; `lib.sh` is sourced, not executed)
- [ ] Relative links in the docs resolve
- [ ] `grep` of the tree finds no personal addresses, MACs, hostnames, usernames or credentials
- [ ] Support matrix in README matches reality

## What the maintainers have **not** verified in this repository's automated checks

- FreeRDP behaviour on Linux and Windows
- Wake-on-LAN on hardware other than the reference workstation
- Narrowed `/32` subnet routes and Tailscale policy examples
- Non-GNOME workstations
