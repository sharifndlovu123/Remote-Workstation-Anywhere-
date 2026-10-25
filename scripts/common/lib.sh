#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for Remote Workstation Anywhere.
# Source this file; do not execute it.
#
# Compatible with bash 3.2 (the macOS system bash): no associative arrays,
# no ${var,,}, no mapfile.

RWA_CONFIG_KEYS="WORKSTATION_IP WORKSTATION_MAC RDP_PORT RDP_USERNAME GATEWAY_SSH_HOST WOL_BROADCAST BOOT_TIMEOUT KEYCHAIN_SERVICE DISPLAY_SCALE RDP_CERT_OPTION FREERDP_BIN"

# ---------------------------------------------------------------- logging ---

info() { printf '[info]  %s\n' "$*" >&2; }
warn() { printf '[warn]  %s\n' "$*" >&2; }
err()  { printf '[error] %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ----------------------------------------------------------------- config ---

rwa_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

rwa_config_path() {
    if [ -n "${RWA_CONFIG:-}" ]; then
        printf '%s\n' "$RWA_CONFIG"
    else
        printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/remote-workstation-anywhere/config.env"
    fi
}

# Parse KEY="value" lines. The file is never sourced or evaluated.
# Values already present in the environment win over the file.
rwa_load_config() {
    local file line key value
    file="$(rwa_config_path)"
    RWA_CONFIG_FILE_USED=""

    if [ ! -f "$file" ]; then
        return 0
    fi
    RWA_CONFIG_FILE_USED="$file"

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(rwa_trim "$line")"
        case "$line" in
            ''|'#'*) continue ;;
        esac
        case "$line" in
            *=*) ;;
            *) warn "Ignoring malformed line in $file: $line"; continue ;;
        esac

        key="$(rwa_trim "${line%%=*}")"
        key="${key#export }"
        key="$(rwa_trim "$key")"
        value="$(rwa_trim "${line#*=}")"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac

        case " $RWA_CONFIG_KEYS " in
            *" $key "*)
                if [ -z "${!key:-}" ]; then
                    printf -v "$key" '%s' "$value"
                fi
                ;;
            *)
                warn "Ignoring unknown setting '$key' in $file"
                ;;
        esac
    done < "$file"
}

rwa_apply_defaults() {
    : "${RDP_PORT:=3389}"
    : "${BOOT_TIMEOUT:=120}"
    : "${DISPLAY_SCALE:=100}"
    : "${RDP_CERT_OPTION:=tofu}"
}

rwa_is_ipv4() {
    local ip="$1" a b c d re='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
    [[ $ip =~ $re ]] || return 1
    IFS=. read -r a b c d <<EOF
$ip
EOF
    [ $((10#$a)) -le 255 ] && [ $((10#$b)) -le 255 ] && [ $((10#$c)) -le 255 ] && [ $((10#$d)) -le 255 ]
}

# Validate settings before any of them reach a command line.
# $1 = connect | wake
rwa_validate() {
    local mode="$1" need k missing=""
    local re_host='^[A-Za-z0-9][A-Za-z0-9.-]*$'
    local re_ssh='^[A-Za-z0-9][A-Za-z0-9._@-]*$'
    local re_mac='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
    local re_num='^[0-9]+$'
    local re_user='^[A-Za-z0-9._][A-Za-z0-9._@-]*$'
    local re_svc='^[A-Za-z0-9._][A-Za-z0-9._ -]*$'
    local re_cert='^[A-Za-z0-9][A-Za-z0-9:,._/+=-]*$'
    local re_bin='^[A-Za-z0-9][A-Za-z0-9._-]*$'

    case "$mode" in
        connect) need="WORKSTATION_IP WORKSTATION_MAC RDP_USERNAME GATEWAY_SSH_HOST KEYCHAIN_SERVICE" ;;
        wake)    need="WORKSTATION_MAC GATEWAY_SSH_HOST" ;;
        *)       die "internal error: unknown validation mode '$mode'" ;;
    esac

    for k in $need; do
        [ -n "${!k:-}" ] || missing="$missing $k"
    done
    if [ -n "$missing" ]; then
        err "Missing required setting(s):$missing"
        err "Set them in $(rwa_config_path) (template: examples/config.example.env) or as environment variables."
        exit 2
    fi

    if [ "$mode" = connect ]; then
        [[ $WORKSTATION_IP =~ $re_host ]] \
            || { err "WORKSTATION_IP must be an IP address or hostname (got '$WORKSTATION_IP')."; exit 2; }
        [[ $RDP_USERNAME =~ $re_user ]] \
            || { err "RDP_USERNAME contains unsupported characters (allowed: letters, digits, . _ @ -)."; exit 2; }
        [[ $KEYCHAIN_SERVICE =~ $re_svc ]] \
            || { err "KEYCHAIN_SERVICE contains unsupported characters (allowed: letters, digits, . _ - and space)."; exit 2; }
        [[ $RDP_PORT =~ $re_num ]] && [ "$((10#$RDP_PORT))" -ge 1 ] && [ "$((10#$RDP_PORT))" -le 65535 ] \
            || { err "RDP_PORT must be a number between 1 and 65535 (got '$RDP_PORT')."; exit 2; }
        [[ $BOOT_TIMEOUT =~ $re_num ]] && [ "$((10#$BOOT_TIMEOUT))" -ge 1 ] \
            || { err "BOOT_TIMEOUT must be a positive number of seconds (got '$BOOT_TIMEOUT')."; exit 2; }
        case "$DISPLAY_SCALE" in
            100|140|180) ;;
            *) err "DISPLAY_SCALE must be 100, 140 or 180 (FreeRDP's accepted values). Got '$DISPLAY_SCALE'."; exit 2 ;;
        esac
        [[ $RDP_CERT_OPTION =~ $re_cert ]] \
            || { err "RDP_CERT_OPTION contains unsupported characters."; exit 2; }
        if [ -n "${FREERDP_BIN:-}" ]; then
            [[ $FREERDP_BIN =~ $re_bin ]] \
                || { err "FREERDP_BIN must be a plain executable name on PATH."; exit 2; }
        fi
    fi

    [[ $WORKSTATION_MAC =~ $re_mac ]] \
        || { err "WORKSTATION_MAC must look like 00:11:22:33:44:55 (got '$WORKSTATION_MAC')."; exit 2; }
    [[ $GATEWAY_SSH_HOST =~ $re_ssh ]] \
        || { err "GATEWAY_SSH_HOST must be an SSH alias, hostname or user@host (got '$GATEWAY_SSH_HOST')."; exit 2; }
    if [ -n "${WOL_BROADCAST:-}" ]; then
        rwa_is_ipv4 "$WOL_BROADCAST" \
            || { err "WOL_BROADCAST must be an IPv4 address such as 192.168.1.255 (got '$WOL_BROADCAST')."; exit 2; }
    fi
}

rwa_init() {
    rwa_load_config
    rwa_apply_defaults
    rwa_validate "$1"
}

# ---------------------------------------------------------------- probing ---

# TCP reachability only. Success does NOT prove RDP login will work.
rdp_port_open() {
    case "$(uname -s)" in
        Darwin) nc -z -G 3 "$WORKSTATION_IP" "$RDP_PORT" >/dev/null 2>&1 ;;
        *)      nc -z -w 3 "$WORKSTATION_IP" "$RDP_PORT" >/dev/null 2>&1 ;;
    esac
}

# Informational only: ICMP may be blocked even when the host is up.
host_answers_ping() {
    case "$(uname -s)" in
        Darwin) ping -c 1 -t 2 "$WORKSTATION_IP" >/dev/null 2>&1 ;;
        *)      ping -c 1 -W 2 "$WORKSTATION_IP" >/dev/null 2>&1 ;;
    esac
}

# ------------------------------------------------------------ wake on lan ---

# Ask the gateway to send a magic packet on its own LAN.
# All interpolated values were validated by rwa_validate.
send_wol() {
    local cmd="wakeonlan" rc=0
    if [ -n "${WOL_BROADCAST:-}" ]; then
        cmd="$cmd -i $WOL_BROADCAST"
    fi
    cmd="$cmd $WORKSTATION_MAC"

    info "Asking gateway '$GATEWAY_SSH_HOST' to send a Wake-on-LAN packet..."
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$GATEWAY_SSH_HOST" "$cmd" >/dev/null || rc=$?

    case "$rc" in
        0)   info "Magic packet sent. (Sent is not the same as received: see docs/wake-on-lan.md if nothing wakes.)" ;;
        255) die "Could not SSH to the gateway '$GATEWAY_SSH_HOST'. Check Tailscale is connected, the route to the gateway works, and key authentication is set up ('ssh -v $GATEWAY_SSH_HOST')." ;;
        127) die "'wakeonlan' is not installed on the gateway. Install it there (for example: sudo apt install wakeonlan)." ;;
        *)   die "Wake-on-LAN command failed on the gateway (exit status $rc). Run it by hand: ssh $GATEWAY_SSH_HOST '$cmd'" ;;
    esac
}

wait_for_rdp() {
    local timeout="$((10#$BOOT_TIMEOUT))" start="$SECONDS" last=-1 elapsed
    info "Waiting up to ${timeout}s for $WORKSTATION_IP:$RDP_PORT ..."
    until rdp_port_open; do
        elapsed=$((SECONDS - start))
        if [ "$elapsed" -ge "$timeout" ]; then
            return 1
        fi
        if [ $((elapsed / 15)) -gt "$last" ] && [ "$elapsed" -ge 15 ]; then
            last=$((elapsed / 15))
            info "Still waiting (${elapsed}s)..."
        fi
        sleep 3
    done
    return 0
}

# Make sure the RDP port answers, waking the workstation if that is plausible.
ensure_workstation_ready() {
    info "Checking $WORKSTATION_IP:$RDP_PORT ..."
    if rdp_port_open; then
        info "RDP port is reachable."
        return 0
    fi

    warn "RDP port is not reachable. The workstation may be off, asleep or still booting, or it may be running with its RDP service stopped or firewalled, or the network route may be down."

    local was_running=0
    if host_answers_ping; then
        was_running=1
        info "The host answers ping, so it is probably already running. Skipping Wake-on-LAN and waiting for the RDP service."
    else
        send_wol
    fi

    if ! wait_for_rdp; then
        err "RDP did not become reachable within ${BOOT_TIMEOUT}s."
        err "Possible causes:"
        if [ "$was_running" = 1 ]; then
            err "  - The host is up but the RDP service is stopped, not configured, or firewalled (docs/ubuntu-gnome.md)."
            err "  - The RDP port differs from RDP_PORT=$RDP_PORT."
        else
            err "  - The workstation did not wake: check Wake-on-LAN (docs/wake-on-lan.md)."
            err "  - The workstation woke but the RDP service did not start (docs/ubuntu-gnome.md)."
            err "  - Slow boot: raise BOOT_TIMEOUT."
        fi
        err "  - No route to the workstation: check 'tailscale status' and the approved subnet route."
        err "  - A firewall on the workstation blocks the gateway's address."
        exit 1
    fi
    info "RDP port is now reachable."
}

# ---------------------------------------------------------------- FreeRDP ---

rwa_find_freerdp() {
    local candidates c
    if [ -n "${FREERDP_BIN:-}" ]; then
        candidates="$FREERDP_BIN"
    else
        candidates="$FREERDP_CANDIDATES"
    fi
    for c in $candidates; do
        if command -v "$c" >/dev/null 2>&1; then
            FREERDP_PATH="$(command -v "$c")"
            return 0
        fi
    done
    die "No FreeRDP client found (looked for: $candidates). ${FREERDP_INSTALL_HINT:-Install FreeRDP 3.}"
}

rwa_freerdp_has() {
    case "$RWA_FREERDP_HELP" in
        *"$1"*) return 0 ;;
    esac
    return 1
}

# Validate the installed client instead of assuming option names.
rwa_probe_freerdp() {
    local ver major
    ver="$("$FREERDP_PATH" --version 2>&1 || true)"
    major="$(printf '%s\n' "$ver" | sed -n 's/.*[Vv]ersion \([0-9][0-9]*\)\..*/\1/p' | sed -n '1p')"
    if [ -n "$major" ] && [ "$major" -lt 3 ]; then
        die "FreeRDP $major.x found at $FREERDP_PATH, but FreeRDP 3.x is required (option syntax differs)."
    fi
    if [ -z "$major" ]; then
        warn "Could not determine the FreeRDP version from '$FREERDP_PATH --version'. Continuing."
    fi

    RWA_FREERDP_HELP="$("$FREERDP_PATH" /help 2>&1 || true)"
    USE_DYNAMIC_RES=1
    USE_SCALE=0

    if [ -z "$RWA_FREERDP_HELP" ]; then
        warn "Could not read '$FREERDP_PATH /help', so options cannot be verified. Assuming they exist."
        if [ "$DISPLAY_SCALE" != "100" ]; then
            USE_SCALE=1
        fi
        return 0
    fi

    # Never fall back to passing the password on the command line.
    rwa_freerdp_has "from-stdin" \
        || die "This FreeRDP build does not list /from-stdin, which is required so the password stays off the command line."

    if ! rwa_freerdp_has "dynamic-resolution"; then
        warn "This FreeRDP build does not list /dynamic-resolution; omitting it."
        USE_DYNAMIC_RES=0
    fi
    if [ "$DISPLAY_SCALE" != "100" ]; then
        if rwa_freerdp_has "/scale"; then
            USE_SCALE=1
        else
            warn "This FreeRDP build does not list /scale; omitting HiDPI scaling."
        fi
    fi
}

# get_password is defined by the platform script.
launch_freerdp() {
    local password rc=0
    local args

    args=("/v:${WORKSTATION_IP}:${RDP_PORT}" "/u:${RDP_USERNAME}" "/from-stdin" "/f" "/cert:${RDP_CERT_OPTION}")
    if [ "$USE_DYNAMIC_RES" = 1 ]; then
        args+=("/dynamic-resolution")
    fi
    if [ "$USE_SCALE" = 1 ]; then
        args+=("/scale:${DISPLAY_SCALE}")
    fi

    info "Retrieving the RDP password from the credential store..."
    password="$(get_password)" || die "Could not read the password for account '$RDP_USERNAME', service '$KEYCHAIN_SERVICE' from the credential store. Check the entry exists and that you allowed access (see docs)."
    [ -n "$password" ] || die "The credential store returned an empty password for service '$KEYCHAIN_SERVICE'."

    info "Launching FreeRDP ($FREERDP_PATH)..."
    printf '%s\n' "$password" | "$FREERDP_PATH" "${args[@]}" || rc=$?
    unset password

    if [ "$rc" -ne 0 ]; then
        warn "FreeRDP exited with status $rc. If you did not close it deliberately, check the workstation logs (docs/troubleshooting.md)."
    fi
    return "$rc"
}

# ------------------------------------------------------------------ entry ---

rwa_usage() {
    cat <<EOF
Usage: ${RWA_SCRIPT_NAME:-connect.sh} [--check | --help]

Wakes the workstation if needed, waits for RDP, reads the password from the
credential store and starts FreeRDP.

  --check   Validate configuration, FreeRDP and the credential, and report
            whether the RDP port is reachable. Does not wake or connect.
  --help    Show this help.

Config file: $(rwa_config_path)
Override with RWA_CONFIG=/path/to/config.env
EOF
}

rwa_connect() {
    local check_only=0
    case "${1:-}" in
        -h|--help) rwa_usage; exit 0 ;;
        --check)   check_only=1 ;;
        "")        ;;
        *)         err "Unknown argument: $1"; rwa_usage >&2; exit 2 ;;
    esac

    rwa_init connect
    if [ -n "${RWA_CONFIG_FILE_USED:-}" ]; then
        info "Config: $RWA_CONFIG_FILE_USED"
    else
        info "No config file at $(rwa_config_path); using environment variables only."
    fi

    rwa_find_freerdp
    rwa_probe_freerdp

    if [ "$check_only" = 1 ]; then
        info "FreeRDP client: $FREERDP_PATH"
        if get_password >/dev/null 2>&1; then
            info "Credential found for account '$RDP_USERNAME', service '$KEYCHAIN_SERVICE'."
        else
            warn "No usable credential for account '$RDP_USERNAME', service '$KEYCHAIN_SERVICE'."
        fi
        if rdp_port_open; then
            info "RDP port $WORKSTATION_IP:$RDP_PORT is reachable (TCP only; login not tested)."
        else
            warn "RDP port $WORKSTATION_IP:$RDP_PORT is not reachable right now (off, asleep, booting, service down, or no route)."
        fi
        info "Check finished."
        exit 0
    fi

    ensure_workstation_ready
    launch_freerdp
}
