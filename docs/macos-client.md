# macOS client

**Verified:** macOS with Tailscale, FreeRDP 3 (`sdl-freerdp` from Homebrew) and the macOS Keychain.

## 1. Install

```bash
brew install freerdp
command -v sdl-freerdp
```

Install and sign in to Tailscale (App Store or tailscale.com). Confirm it is connected:

```bash
tailscale status
```

If the `tailscale` CLI is not on your PATH, use the app's bundled CLI or the menu bar app to verify the connection.

## 2. SSH alias for the gateway

See [tailscale-setup.md](tailscale-setup.md#6-ssh-public-key-authentication-to-the-gateway). Verify:

```bash
ssh gateway 'hostname'
```

## 3. Store the RDP password in the Keychain

The service name and account must match `KEYCHAIN_SERVICE` and `RDP_USERNAME` in your config.

```bash
security add-generic-password -U -a youruser -s remote-workstation -w
```

With `-w` as the last option and no value, `security` prompts for the password, so it does not appear in your history. `-U` updates an existing entry.

Check that an entry exists (this does not print the password):

```bash
security find-generic-password -a youruser -s remote-workstation
```

The first time the script reads it, macOS may ask whether to allow access. Choosing "Always Allow" lets the script read it without prompting; that is a convenience trade-off, so decide deliberately.

## 4. Configure

```bash
mkdir -p ~/.config/remote-workstation-anywhere
cp examples/config.example.env ~/.config/remote-workstation-anywhere/config.env
chmod 600 ~/.config/remote-workstation-anywhere/config.env
${EDITOR:-nano} ~/.config/remote-workstation-anywhere/config.env
```

Set at least `WORKSTATION_IP`, `WORKSTATION_MAC`, `RDP_USERNAME`, `GATEWAY_SSH_HOST` and `KEYCHAIN_SERVICE`. Use `DISPLAY_SCALE="180"` for a Retina display.

## 5. Install the command

```bash
mkdir -p ~/bin
ln -s "$PWD/scripts/macos/connect.sh" ~/bin/remote-workstation
chmod +x scripts/macos/connect.sh scripts/common/wake.sh
```

Add `~/bin` to your PATH if it is not there (zsh):

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
command -v remote-workstation
```

Keep the repository where it is: the symlink points into it, and the script loads `scripts/common/lib.sh` relative to the real file.

## 6. Run

```bash
remote-workstation --check     # config, FreeRDP options, Keychain entry, current reachability
remote-workstation             # wake if needed, wait, connect
```

## Retina / HiDPI scaling

FreeRDP opens a small window by default and a Retina screen makes the remote UI look tiny. The tested combination:

```text
/f  /dynamic-resolution  /scale:180
```

- `/f` fullscreen
- `/dynamic-resolution` follows window size changes
- `/scale:180` scales the UI

FreeRDP accepts only specific scale values (`100`, `140`, `180`). The script validates `DISPLAY_SCALE` against those and omits the option for `100`. If the result is wrong after an update, run `sdl-freerdp /help` and compare, and adjust GNOME's own scale in **Settings → Displays** on the workstation.

## Certificate handling

The default is trust-on-first-use (`RDP_CERT_OPTION="tofu"`). Verify the first fingerprint against the workstation, as described in [security.md](security.md#host-certificate-verification).

## Microsoft Windows App

During testing, Microsoft's macOS "Windows App" failed against GNOME Remote Desktop (error `0x204`, then a stall at "Securing connection to remote PC") while FreeRDP connected. This is an **observed compatibility issue in one setup**, not proof the app can never work. Details in [troubleshooting.md](troubleshooting.md#a-microsoft-client-fails-but-freerdp-works).

If you use a Microsoft client, point it directly at the workstation's LAN address and leave "RD Gateway" empty.

## Protect the Mac

It holds the SSH key and the Keychain secret. Use FileVault and a strong login password, and keep macOS, Tailscale and FreeRDP updated.
