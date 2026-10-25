# Wake-on-LAN

Verified on an Ubuntu GNOME workstation: wake from suspend and from full shutdown. Whether your hardware can do the same is up to its firmware and NIC.

Examples use interface `eno1`, NetworkManager profile `Wired connection 1` and MAC `00:11:22:33:44:55`. Find yours:

```bash
ip -br link                       # interface names and MACs
nmcli -f NAME,DEVICE connection show --active
```

## 1. Firmware (BIOS/UEFI)

Settings vary by vendor. Look for options named like:

- Wake on LAN, Power On By PCI-E / PCIe devices, Resume by LAN
- ErP / EuP / "Deep sleep" or similar power-saving modes: these often **cut standby power to the NIC** and must be disabled for wake from full shutdown
- Restore on AC power loss (optional, separate feature)

Also: keep the machine plugged in, the PSU switch on, and the Ethernet cable connected. The NIC's link lights usually stay on while the machine is soft-off if standby power is working.

## 2. Check what the NIC supports

```bash
sudo ethtool eno1 | grep -i wake
```

Example output:

```text
Supports Wake-on: pumbg
Wake-on: d
```

`g` in the supported list means magic-packet wake is possible. `Wake-on: d` means it is currently **disabled**.

## 3. Enable it now

```bash
sudo ethtool -s eno1 wol g
sudo ethtool eno1 | grep -i wake      # expect: Wake-on: g
```

This does not survive a reboot on its own.

## 4. Persist it through NetworkManager

```bash
sudo nmcli connection modify 'Wired connection 1' 802-3-ethernet.wake-on-lan magic
nmcli -g 802-3-ethernet.wake-on-lan connection show 'Wired connection 1'    # expect: magic
```

Re-apply the connection (or reboot) and re-check `ethtool`. Expected final state: NetworkManager says `magic`, `ethtool` says `Wake-on: g`.

If your workstation does not use NetworkManager for Ethernet, use your network stack's equivalent (for example `wakeonlan: true` in netplan, or a systemd `.link` file). Those variants are untested here.

## 5. Send a magic packet from the gateway

```bash
ssh gateway 'wakeonlan -i 192.168.1.255 00:11:22:33:44:55'
```

The packet is a LAN broadcast sent by the gateway, which is why the gateway must be on the workstation's LAN. See [architecture.md](architecture.md#why-the-packet-is-sent-from-the-gateway).

Or use the repo script, which reads your config:

```bash
scripts/common/wake.sh
```

## 6. Test both power states

**Suspend**

```bash
# on the workstation
systemctl suspend
# then, from the client
scripts/common/wake.sh
```

**Full shutdown**

```bash
# on the workstation
sudo systemctl poweroff
# wait until it is fully off, then from the client
scripts/common/wake.sh
```

Allow the machine time to boot, then confirm the RDP port opens.

## DHCP and the MAC address

The magic packet targets the **MAC**, not the IP, so wake works regardless of lease state. Your DHCP reservation matters for the *connect* step. See [network-setup.md](network-setup.md).

## Diagnosing failures after reboot

| Observation | Likely cause |
|---|---|
| `Wake-on: d` after every boot | The NetworkManager profile does not have `magic`, or you modified a different profile than the one in use (check the active profile name). |
| `ethtool` says `g` but wake from shutdown fails | Firmware standby power or ErP/deep-sleep setting. |
| Works from suspend, not from shutdown | See [troubleshooting](troubleshooting.md#wake-on-lan-works-from-suspend-but-not-from-shutdown). |
| Nothing wakes it at all | Wrong MAC, wrong broadcast address, NIC lacks `g`, cable unplugged, gateway not on the same LAN segment. |
