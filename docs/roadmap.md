# Suggested future enhancements

Nothing here is implemented. Items are ordered roughly by value to the primary goal. None should bloat the scripts.

1. **Tested Linux client report.** Run the experimental script on real hardware (X11 and Wayland, FreeRDP 3), then promote it to verified or fix it.
2. **Windows client script** with Credential Manager integration (PowerShell), plus a test report.
3. **Smarter readiness check.** Beyond a TCP probe: complete the RDP/TLS handshake or use a FreeRDP authentication-only mode if one exists, to detect "port open but service not ready".
4. **Alternative Wake-on-LAN senders** on the gateway (`etherwake`, `wol`) selectable by config.
5. **Gateway-side restricted SSH command** (forced command in `authorized_keys`) with a tiny helper that only sends the packet.
6. **Narrow subnet-route guide**, tested: advertising only the workstation's `/32`.
7. **Tailscale policy examples** validated against the current policy syntax, including grants.
8. **Certificate pinning helper** that prints the workstation's fingerprint in the format FreeRDP expects.
9. **Other workstation platforms**, each documented separately and labelled honestly: KDE, XRDP, Windows host.
10. **Shutdown helper** to power the workstation off or suspend it when you finish (explicit, opt-in).
11. **Multi-workstation profiles** with a simple selector.
12. **CI** running `shellcheck`, `bash -n`, a link checker and a secrets/PII scan on every pull request.
13. **Automated script tests** using stubbed `nc`, `ssh`, `ping` and FreeRDP binaries.
