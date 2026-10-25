# Windows client (untested)

> **Status: untested.** No connect script is provided for Windows. The steps below are a documented manual procedure based on how the other platforms work. They have **not** been verified against a GNOME Remote Desktop workstation. A correct, maintainable Windows script would need its own Credential Manager integration and testing, so none is shipped.

## 1. Install

- Tailscale for Windows. Approved subnet routes are used automatically.
- Use the built-in **Remote Desktop Connection** (`mstsc`). Alternatively, FreeRDP builds for Windows exist; their executable names and options differ from the macOS/Linux ones, so do not copy those commands.

## 2. Connect manually

1. Make sure Tailscale is connected.
2. Wake the workstation. From PowerShell with the OpenSSH client installed:

   ```powershell
   ssh gateway "wakeonlan -i 192.168.1.255 00:11:22:33:44:55"
   ```

3. Wait for the workstation to boot (a minute or two, depending on hardware).
4. Test the port:

   ```powershell
   Test-NetConnection 192.168.1.50 -Port 3389
   ```

   `TcpTestSucceeded : True` only proves TCP reachability, not that login will work.
5. Open `mstsc`, enter the workstation's LAN address, set the username, and leave **RD Gateway** unset.
6. Enter the RDP password when prompted. Only tick "remember credentials" if you accept that Windows Credential Manager will store it.

## Things that may differ

- Certificate warnings: `mstsc` shows the workstation's certificate on first connect. Compare its thumbprint with the one from the workstation (see [security.md](security.md#host-certificate-verification)) before accepting.
- Microsoft clients on other platforms failed against GNOME Remote Desktop in our macOS test. The Windows client may or may not behave the same; we have no data.
- HiDPI scaling is controlled in `mstsc` display options and Windows display settings, not by FreeRDP flags.

## Contributing a tested script

If you have this working, a PowerShell script (config loading, validation, WoL via the gateway, port wait, Credential Manager lookup, launch) would be welcome. See [CONTRIBUTING.md](../CONTRIBUTING.md).
