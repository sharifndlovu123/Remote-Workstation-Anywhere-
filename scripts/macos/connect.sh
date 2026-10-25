#!/usr/bin/env bash
#
# macOS launcher: wake the workstation if needed, wait for RDP, read the
# password from the macOS Keychain and start FreeRDP.
#
# Verified with: macOS, Homebrew FreeRDP 3 (sdl-freerdp), Tailscale.
# Install as a command:  ln -s "$PWD/scripts/macos/connect.sh" ~/bin/remote-workstation
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

FREERDP_CANDIDATES="sdl-freerdp sdl-freerdp3"
FREERDP_INSTALL_HINT="Install it with: brew install freerdp"

# Print the password on stdout. Keychain entry: account = RDP_USERNAME,
# service = KEYCHAIN_SERVICE. The password is never placed in an argument list.
get_password() {
    command -v security >/dev/null 2>&1 || return 1
    security find-generic-password -a "$RDP_USERNAME" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
}

rwa_connect "$@"
