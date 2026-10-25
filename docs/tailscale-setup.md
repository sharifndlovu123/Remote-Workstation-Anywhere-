# Tailscale and gateway setup

Verified with a Raspberry Pi 5 running Ubuntu Server on Ethernet. Any always-on Linux device should work the same way. A Raspberry Pi is **optional**.

Examples use `192.168.1.0/24`.

## 1. Install Tailscale on the gateway

Follow the current instructions at <https://tailscale.com/download/linux> for your distribution. Do not paste install one-liners you have not read.

## 2. Enable IP forwarding (persistent)

A subnet router must forward packets.

```bash
sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding
```

## 3. Advertise your LAN

First time:

```bash
sudo tailscale up --advertise-routes=192.168.1.0/24
```

Already connected:

```bash
sudo tailscale set --advertise-routes=192.168.1.0/24
```

## 4. Approve the route

In the Tailscale admin console, open the gateway machine, review its **Subnet routes** and approve `192.168.1.0/24`. An advertised route does nothing until approved.

Also consider **disabling key expiry** for the gateway so it does not drop off the tailnet unattended. Weigh that against your threat model and protect the device physically.

## 5. Accept routes on clients

macOS and Windows clients use approved subnet routes automatically. On **Linux** clients, enable it explicitly:

```bash
sudo tailscale set --accept-routes=true
```

Check from the client:

```bash
tailscale status
ping -c 3 192.168.1.2          # gateway LAN address, reached via the route
```

## 6. SSH public-key authentication to the gateway

On the client:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_gateway -C "client-to-gateway"
ssh-copy-id -i ~/.ssh/id_ed25519_gateway.pub youruser@192.168.1.2
```

Add an alias to `~/.ssh/config`:

```sshconfig
Host gateway
    HostName 192.168.1.2
    User youruser
    IdentityFile ~/.ssh/id_ed25519_gateway
    IdentitiesOnly yes
```

`HostName` can also be the gateway's Tailscale `100.x.y.z` address, which is useful if a foreign network overlaps your LAN prefix.

Test:

```bash
ssh gateway 'hostname && ip -br addr'
```

Set `GATEWAY_SSH_HOST=gateway` in your config. The scripts run SSH in `BatchMode`, so a password prompt means key auth is not working.

Once key login works, consider disabling password authentication on the gateway (`PasswordAuthentication no` in `sshd_config`). Keep a second session open while you test so you cannot lock yourself out.

Every client machine needs its own key authorised on the gateway. Keys are not shared between machines.

## 7. Install a Wake-on-LAN utility

```bash
sudo apt install wakeonlan
```

Test it locally on the gateway (workstation off or asleep, WoL already enabled on it):

```bash
wakeonlan -i 192.168.1.255 00:11:22:33:44:55
```

`-i` sets the broadcast address on the gateway's own LAN. Use your real MAC and broadcast.

## 8. Test LAN connectivity from the gateway

```bash
ping -c 3 192.168.1.1        # router
ping -c 3 192.168.1.50       # workstation (while awake)
nc -vz 192.168.1.50 3389     # RDP port (while awake and configured)
```

## Narrowing the advertised route

Advertising the whole subnet lets any authorised tailnet device reach every host on your LAN (printers, IoT, other computers). You can reduce exposure by:

1. Using Tailscale access policies to allow only the workstation's address and ports. See [security.md](security.md#tailscale-access-policies).
2. Advertising only the workstation's address, for example `--advertise-routes=192.168.1.50/32`. Wake-on-LAN still works because the gateway sends the broadcast locally. This has **not** been tested by the maintainers; try it before relying on it.
