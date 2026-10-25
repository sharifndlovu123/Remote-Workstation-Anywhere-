#!/usr/bin/env bash
#
# Send a Wake-on-LAN magic packet to the workstation, via the gateway.
# Reads WORKSTATION_MAC, GATEWAY_SSH_HOST and (optionally) WOL_BROADCAST
# from the config file or environment. Works on macOS and Linux.
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
# shellcheck source=lib.sh
. "$RWA_SCRIPT_DIR/lib.sh"

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: $(basename "$0")

Asks the gateway (over SSH) to send a Wake-on-LAN magic packet to the
workstation. Settings come from: $(rwa_config_path)
EOF
        exit 0
        ;;
    "") ;;
    *) err "Unknown argument: $1"; exit 2 ;;
esac

rwa_init wake
send_wol
