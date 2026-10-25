#!/usr/bin/env bash
#
# Linux launcher (EXPERIMENTAL - not yet run on real Linux client hardware).
# Wake the workstation if needed, wait for RDP, read the password from
# libsecret (secret-tool) or prompt for it, then start FreeRDP 3.
#
# Install as a command:  ln -s "$PWD/scripts/linux/connect.sh" ~/.local/bin/remote-workstation
set -euo pipefail

rwa_script_dir() {
    local src="${BASH_SOURCE[0]}" dir
    while [ -h "$src" ]; do
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        case "$src" in
            /*) ;;
            *) src="$dir/$src" ;;
        esac
    done
    cd -P "$(dirname "$src")" && pwd
}

RWA_SCRIPT_DIR="$(rwa_script_dir)"
RWA_SCRIPT_NAME="$(basename "$0")"
# shellcheck source=../common/lib.sh
. "$RWA_SCRIPT_DIR/../common/lib.sh"

FREERDP_CANDIDATES="sdl-freerdp3 sdl-freerdp xfreerdp3 xfreerdp"
FREERDP_INSTALL_HINT="Install a FreeRDP 3.x client from your distribution (see docs/linux-client.md)."

# Print the password on stdout.
# 1. libsecret entry with attributes: service = KEYCHAIN_SERVICE, account = RDP_USERNAME
# 2. otherwise prompt on the terminal without echo
# A password is never read from the config file or the environment.
get_password() {
    local pw=""
    if command -v secret-tool >/dev/null 2>&1; then
        pw="$(secret-tool lookup service "$KEYCHAIN_SERVICE" account "$RDP_USERNAME" 2>/dev/null || true)"
    fi
    if [ -n "$pw" ]; then
        printf '%s\n' "$pw"
        return 0
    fi
    if [ -r /dev/tty ] && [ -t 2 ]; then
        printf 'RDP password for %s: ' "$RDP_USERNAME" >&2
        IFS= read -r -s pw < /dev/tty || true
        printf '\n' >&2
        [ -n "$pw" ] || return 1
        printf '%s\n' "$pw"
        return 0
    fi
    return 1
}

rwa_connect "$@"
