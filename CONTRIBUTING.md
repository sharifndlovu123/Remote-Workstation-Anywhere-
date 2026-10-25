# Contributing

Thanks for helping. This project values **correctness, security and small scope** over features.

## Ground rules

- **No personal data.** Do not commit or paste real IP addresses, MAC addresses, hostnames, usernames, tailnet names, certificate fingerprints or credentials. Use the placeholders already used in the docs: `192.168.1.x`, `00:11:22:33:44:55`, `youruser`, `gateway`.
- **Be honest about testing.** New platforms are labelled *Untested* or *Experimental* until someone has run them end to end on real hardware. A test report (OS versions, client/server versions, what worked, what did not) is one of the most useful contributions.
- **Keep dependencies minimal.** Bash plus tools the user needs anyway.
- **Do not weaken security for convenience.** No disabling lock screens, no plaintext passwords, no passwords in argv.

## Scripts

- Target bash 3.2 compatibility (macOS ships it). No associative arrays, no `${var,,}`, no `mapfile`.
- Run `bash -n` and `shellcheck` on everything under `scripts/`.
- Validate every value that ends up in a command line (see `rwa_validate` in `scripts/common/lib.sh`).

## Docs

- Keep Mermaid sources in `assets/` and the copies embedded in docs in sync.
- Check that relative links resolve.
- Update the support matrix in `README.md` and `docs/prerequisites.md` when status changes.

## Pull request checklist

- [ ] `bash -n` and `shellcheck` clean
- [ ] No personal data (search your diff for your own IPs, MACs, usernames)
- [ ] Docs updated, links checked
- [ ] Claims match what you actually tested
