# FAQ

**Do I need a Raspberry Pi?**
No. Any always-on Linux device on the workstation's LAN that can run Tailscale (with IP forwarding), SSH and a Wake-on-LAN utility works in principle. A Pi 5 is what was verified.

**Why not just forward port 3389 on my router?**
Because exposed RDP is attacked constantly. Tailscale gives you private, authenticated, encrypted access with no inbound ports. See [security.md](security.md).

**Why does the packet have to come from the gateway?**
Magic packets are LAN broadcasts and do not cross a Tailscale subnet route. See [architecture.md](architecture.md#why-the-packet-is-sent-from-the-gateway).

**Is the gateway an "RD Gateway"?**
No. It is a Tailscale subnet router. Leave any RD Gateway setting empty and connect directly to the workstation's LAN address.

**Can I use my workstation's Tailscale address instead of the subnet route?**
Possibly: install Tailscale on the workstation and connect to its `100.x.y.z` address. But it cannot receive Wake-on-LAN while off, and the gateway is still needed for waking, so this setup standardizes on the subnet route. Mixing both is untested here.

**Do I need DNS or MagicDNS?**
No. Everything uses IP addresses.

**The RDP port is open. Why can't I log in?**
An open TCP port says nothing about authentication. See [troubleshooting](troubleshooting.md#rdp-port-reachable-but-connection-fails).

**Why FreeRDP instead of Microsoft's client on macOS?**
In our test, Microsoft's Windows App failed against GNOME Remote Desktop while FreeRDP worked. That is an observation about one setup, not a general verdict. See [troubleshooting](troubleshooting.md#a-microsoft-client-fails-but-freerdp-works).

**Does it work with KDE, XRDP or a Windows workstation?**
Untested, and not covered by these docs. See [prerequisites.md](prerequisites.md).

**Does it work from Windows or Linux clients?**
Linux: experimental script, not verified. Windows: manual procedure, untested.

**Will I see the same screen as the one on my physical monitor?**
Not necessarily. GNOME Remote Login can create a separate session. Save work before switching.

**What if I leave the workstation running? Do I still need the gateway?**
For the SSH/RDP path you still need a way into the LAN. The gateway also provides that. If you run Tailscale directly on the always-on workstation you could skip it, but that is a different, unverified setup.

**What does the script do if the desktop is already on but RDP is broken?**
It tries a ping first. If the host answers, it skips the Wake-on-LAN packet (it would not help), waits for RDP up to `BOOT_TIMEOUT`, then explains the likely causes.

**Where are my settings stored?**
In `~/.config/remote-workstation-anywhere/config.env` (mode `600`), outside the repository. Passwords are not stored there.

**Can I put the password in the config file?**
No, by design. Use the Keychain or libsecret.

**Is the config file executed?**
No. It is parsed line by line against a fixed list of keys. Quotes are stripped, nothing is expanded.

**Can I use a different config location?**
Yes: `RWA_CONFIG=/path/to/config.env remote-workstation`.

**How do I use more than one workstation?**
Keep one config file per machine and select with `RWA_CONFIG`. Use a different `KEYCHAIN_SERVICE` if the passwords differ.

**Why only 100, 140 and 180 for scaling?**
Those are the values FreeRDP's `/scale` option accepts. The script validates against them.
