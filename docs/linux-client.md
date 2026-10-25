# Linux client (experimental)

> **Status: experimental.** `scripts/linux/connect.sh` shares its logic with the verified macOS script, but it has **not** been run on real Linux client hardware by the maintainers. Package names, binary names and FreeRDP behaviour differ between distributions. Please report results.

## 1. Install

- Tailscale: <https://tailscale.com/download/linux>
- A FreeRDP **3.x** client. The script looks for `sdl-freerdp3`, `sdl-freerdp`, `xfreerdp3`, then `xfreerdp`.
- `netcat`, `openssh-client`
- Optional: `libsecret-tools` for `secret-tool`

Example on Debian/Ubuntu-style systems (package names vary by release; check what your distribution offers):

```bash
sudo apt install freerdp3-x11 netcat-openbsd openssh-client libsecret-tools
```

The binary names and options differ between FreeRDP 2 and 3. The script refuses to run on a client it can positively identify as older than 3, because option syntax (for example certificate handling) changed.

Do not assume the options used on macOS exist in your build. The script reads `/help` from the installed client and checks that required options are present before using them.

## 2. Tailscale routes

Linux does not accept subnet routes by default:

```bash
sudo tailscale set --accept-routes=true
```

## 3. Credentials

The script tries `secret-tool` (libsecret, backed by GNOME Keyring or KWallet) and falls back to an interactive prompt.

```bash
secret-tool store --label="Remote workstation" service remote-workstation account youruser
```

`service` must equal `KEYCHAIN_SERVICE` and `account` must equal `RDP_USERNAME`. `secret-tool store` prompts for the secret.

If `secret-tool` is missing or the lookup is empty, the script asks for the password on the terminal without echo. It never reads a password from the config file or an environment variable.

## 4. Configure and run

```bash
mkdir -p ~/.config/remote-workstation-anywhere ~/.local/bin
cp examples/config.example.env ~/.config/remote-workstation-anywhere/config.env
chmod 600 ~/.config/remote-workstation-anywhere/config.env
${EDITOR:-nano} ~/.config/remote-workstation-anywhere/config.env
ln -s "$PWD/scripts/linux/connect.sh" ~/.local/bin/remote-workstation
chmod +x scripts/linux/connect.sh scripts/common/wake.sh

remote-workstation --check
remote-workstation
```

To force a particular client, set `FREERDP_BIN` in the config or environment.

## Known unknowns

- Wayland versus X11 client behaviour (fullscreen, HiDPI, `/dynamic-resolution`) varies by FreeRDP build.
- `/scale` accepts only `100`, `140`, `180`. Fractional scaling on the client desktop may interact in unexpected ways.
- Whether `/from-stdin` reads the password the same way in every 3.x build. The script refuses to continue if the option is missing from `/help`, rather than falling back to a password on the command line.
