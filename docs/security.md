# Security

Remote access to a powerful machine is valuable to an attacker too. Read this whole page and complete the [checklist](#security-checklist) after installation.

## Threat model in one paragraph

You want only your own devices to reach the workstation's RDP service and the gateway's SSH service, from anywhere, without exposing anything to the public internet. The design relies on Tailscale for device identity and encrypted transport, on SSH keys for the gateway, and on a strong password plus certificate checking for RDP. A stolen or compromised client, a weak RDP password, or an over-broad Tailscale policy can each defeat it.

## Never port-forward RDP (or SSH)

Public RDP is scanned and attacked continuously. Do not forward TCP 3389 or SSH from your router. This design needs **no** inbound router rules. If you ever find yourself adding one "just to test", remove it.

## Private network access is not authentication

Being on the tailnet means a device is allowed to send packets. It does **not** mean the person is allowed to log in. Keep both layers:

| Layer | Controls | Where |
|---|---|---|
| Network | Which devices can reach which addresses and ports | Tailscale access policies, workstation firewall |
| Application | Who can log in | RDP credentials, SSH keys, OS accounts |

Restricting SSH to the gateway does **not** automatically restrict RDP to the workstation. They are different destinations and need separate rules. If an access policy only mentions the gateway's SSH port, and a subnet route is approved, check what the policy says about the workstation's address and port 3389.

## Tailscale identity and device authorization

- Use SSO with multi-factor authentication for the account that owns the tailnet.
- Consider **device approval** so new devices need your explicit approval to join.
- Remove devices you no longer use from the admin console.
- Enable key expiry for client devices. For the always-on gateway you may choose to disable expiry so it stays online; compensate by securing the device physically and keeping it updated.
- Prefer **tags** (for example `tag:gateway`) for infrastructure devices so policies do not depend on a person's account.

## Tailscale access policies

By default many tailnets allow everything between devices. Tighten it. Illustrative policy, **adapt it and check the current Tailscale policy syntax before applying** (Tailscale also offers a newer "grants" syntax):

```jsonc
{
  "tagOwners": {
    "tag:gateway": ["autogroup:admin"]
  },
  "acls": [
    // Only your own devices may SSH to the gateway
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:gateway:22"] },

    // Only your own devices may reach RDP on the workstation, through the subnet route
    { "action": "accept", "src": ["autogroup:member"], "dst": ["192.168.1.50:3389"] }
  ]
}
```

Replace `autogroup:member` with the specific users, groups or tagged devices that should have access. Do not add a broad rule to the whole LAN prefix unless you mean it.

Test the policy by trying to reach something that should be **blocked**, not only something that should work.

## Subnet-route access restrictions

An approved subnet route exposes every address in that prefix to everyone the policy permits. Reduce this:

1. Write policies that name the workstation's address and port, as above.
2. Advertise a narrower route, for example only the workstation's address. This is a hardening idea; **not tested** by the maintainers (see [tailscale-setup.md](tailscale-setup.md#narrowing-the-advertised-route)).
3. Keep unrelated devices (IoT, cameras, NAS) out of reach, ideally on a separate network segment.

## How subnet routing changes the source IP

By default a Tailscale subnet router **masquerades** forwarded traffic. The workstation therefore sees RDP connections coming from the **gateway's LAN address**, not from your laptop's Tailscale address.

Consequences:

- Workstation firewall rules cannot tell one tailnet device from another. Any device the Tailscale policy lets through looks the same. **Tailscale policies are your real access control.**
- Logs on the workstation show the gateway as the client. Correlate with Tailscale logs if you need to know which device connected.
- If you allow 3389 from the gateway's address in the workstation firewall, you allow everything that can use the gateway as a route.

Tailscale can disable this masquerading (SNAT) on subnet routers, but then your router must know how to route replies back to the tailnet, which is a larger change. This repo does not use or test that mode.

## SSH key authentication

- Use Ed25519 keys, one per client machine, with a passphrase.
- Authorize each client's public key on the gateway separately.
- Disable password authentication on the gateway once key login works.
- Use a dedicated, unprivileged account on the gateway. The scripts only need to run `wakeonlan`.
- Consider restricting that key in `authorized_keys` to the one command it needs. Test carefully; this is not set up by the scripts.
- The scripts run SSH with `BatchMode=yes`, so they fail instead of falling back to password prompts.

## Credential storage

| Item | Where it lives | Where it must never be |
|---|---|---|
| RDP password | macOS Keychain, or libsecret on Linux | config file, shell history, script text, environment, FreeRDP's `/p:` argument |
| SSH private key | `~/.ssh` with passphrase | the repository |
| Config file | `~/.config/remote-workstation-anywhere/config.env` with mode `600` | the repository (the `.gitignore` excludes it) |

The scripts pass the password to FreeRDP on **stdin** (`/from-stdin`) so it does not appear in the process list. It still exists briefly in the script's memory. The script refuses to run if the installed FreeRDP does not list `/from-stdin`, instead of falling back to an insecure method.

When setting passwords, use prompting commands (`security add-generic-password ... -w` with no value, `grdctl ... set-credentials` interactive) so nothing lands in shell history.

## Host certificate verification

RDP uses TLS with a certificate generated by GNOME Remote Desktop. A client cannot verify it against a public authority, so there are two sound choices:

1. **Trust on first use** (`/cert:tofu`, the default): the client records the fingerprint the first time and warns if it changes. The weak moment is the first connection. Make it safe by comparing the fingerprint shown by the client with the real one on the workstation:

   ```bash
   sudo grdctl --system status    # shows the TLS certificate path
   sudo openssl x509 -in /path/from/status/rdp-tls.crt -noout -fingerprint -sha256
   ```

2. **Pin the fingerprint** yourself and pass it through `RDP_CERT_OPTION`. The exact syntax depends on the FreeRDP version; check `sdl-freerdp /help` before relying on it.

Treat an unexpected certificate change as a reason to stop and investigate (workstation reinstalled, certificate regenerated, or someone in the path). Never answer "accept" reflexively.

Do **not** use options that ignore certificate errors.

## LAN firewall considerations

- If the workstation has a firewall, allow TCP 3389 only from the gateway (see above), not from the entire LAN.
- A device already on your LAN can reach the workstation directly, without Tailscale. LAN trust matters: guest Wi-Fi and IoT devices should not share a segment with it.
- The Wake-on-LAN packet needs no firewall rule on the workstation. Anyone on your LAN who knows the MAC can wake it; that is a nuisance, not a break-in.

## Do not weaken the OS for convenience

Do not disable the screen lock, auto-login without need, authentication, the firewall or updates to make remote access smoother. If something is annoying, fix the workflow, not the defences.

## Protect the client

The client holds the SSH key and the saved RDP password. Use full-disk encryption (FileVault, LUKS, BitLocker), a strong login password, automatic updates, and a screen lock. If a client is lost or stolen, remove it from the tailnet, remove its key from the gateway and change the RDP password.

## Security checklist

Complete after installation. Tick every box or write down why not.

**Network exposure**
- [ ] No router port forwarding for RDP, SSH or anything else to these machines
- [ ] Workstation and gateway are not in a router "DMZ"
- [ ] External port scan of your public IP shows nothing for 22 and 3389 (use a tool you trust, from outside your network)

**Tailscale**
- [ ] MFA enabled on the identity provider behind the tailnet
- [ ] Only your own devices are listed; stale devices removed
- [ ] Access policy limits SSH to the gateway and RDP to the workstation
- [ ] Verified a **blocked** case actually blocks (for example from an unauthorized device or to an unrelated LAN host)
- [ ] Subnet route approved only for what you need
- [ ] Key expiry decision made and recorded for the gateway

**Gateway**
- [ ] SSH key authentication works; password authentication disabled
- [ ] Dedicated unprivileged account used by the scripts
- [ ] Automatic security updates enabled
- [ ] Physical access considered

**Workstation**
- [ ] Strong, unique RDP password set with `grdctl --system rdp set-credentials`
- [ ] Only one RDP server installed and running
- [ ] Firewall allows 3389 only from the gateway address (or equivalent control in place)
- [ ] Screen lock and OS authentication still enabled
- [ ] TLS certificate fingerprint verified on first connection

**Client**
- [ ] Full-disk encryption on
- [ ] SSH key has a passphrase
- [ ] RDP password stored in the credential store only (not in config, history or scripts)
- [ ] Config file mode is `600`
- [ ] `git status` in your clone shows no config, keys or secrets staged

**Recovery**
- [ ] You know how to revoke a lost client (tailnet, gateway key, RDP password)
- [ ] You tested reaching the workstation locally in case remote access breaks
