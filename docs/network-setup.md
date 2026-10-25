# Network setup

Examples use `192.168.1.0/24`. Replace with your actual LAN.

| Role | Example address |
|---|---|
| Router | `192.168.1.1` |
| Gateway | `192.168.1.2` |
| Workstation | `192.168.1.50` |
| Broadcast | `192.168.1.255` |

## Find your values

On the workstation:

```bash
ip -br addr          # interface name and current address
ip route             # default gateway and subnet
ip -br link          # MAC address of each interface
```

The broadcast address for a `/24` is the last address in the subnet (`.255`). For other prefix lengths, `ip -4 addr show <interface>` prints it after `brd`.

## DHCP reservation versus static IP

The connect script targets the workstation by IP, so that address must not change.

| Approach | How | Pros | Cons |
|---|---|---|---|
| **DHCP reservation** (recommended) | In the router, bind the workstation's MAC to a fixed address. The workstation keeps using DHCP. | One place to manage. Nothing to misconfigure on the host. | Depends on the router's UI. |
| Static IP on the host | Configure the address in NetworkManager or netplan. | Works without router support. | Risk of conflicts with the DHCP pool. If you do this, pick an address outside the pool. |

Do not do both for the same address. A host-side static address that differs from the router's reservation causes confusing failures.

Reserve the gateway's address the same way.

## Use wired Ethernet

- Wake-on-LAN generally works only on wired Ethernet.
- A wired gateway avoids Wi-Fi power-saving and broadcast quirks.
- If the gateway has both Ethernet and Wi-Fi, make sure the subnet you advertise matches the interface you want, and prefer Ethernet.

## No port forwarding

Do **not** forward RDP (3389), SSH (22) or any other port from your router to these machines. All access goes through Tailscale.

## Subnet overlap

If you travel to a network that uses the same prefix as your home LAN (for example both use `192.168.1.0/24`), routes collide and traffic goes to the wrong place. Options:

- Use a less common home prefix (for example `192.168.77.0/24`).
- Reach the gateway by its Tailscale `100.x.y.z` address for SSH (set `GATEWAY_SSH_HOST` accordingly).
- Advertise only the single workstation address (a `/32`) instead of the whole subnet. See [tailscale-setup.md](tailscale-setup.md#narrowing-the-advertised-route). This is a hardening idea and has not been tested by the maintainers.

## Firewalls on the LAN

- The workstation's firewall (if enabled) must allow TCP 3389 from the gateway's LAN address. See [security.md](security.md#how-subnet-routing-changes-the-source-ip).
- Nothing needs to be opened for Wake-on-LAN on the workstation: the NIC listens for the magic packet while the OS is not running.
- The gateway only needs outbound access.
