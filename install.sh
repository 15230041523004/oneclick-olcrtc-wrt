#!/bin/sh
# oneclick-olcrtc-wrt — OpenWrt installer for current OlcRTC mode:srv
# (Yandex Telemost + vp8channel).
#
# One-liner:
#   ROOM_ID='<telemost-room-id>' \
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/install.sh)"
#
# Dry-run (no OpenWrt, no downloads):
#   ROOM_ID=... ENCRYPTION_KEY=... sh install.sh --dump-config
#   ROOM_ID=... ENCRYPTION_KEY=... sh install.sh --dump-uri
set -eu

###############################################################################
# USER SETTINGS
#
# Environment variables override these defaults.
# Edit the values after :- if you copied the script onto the router.
###############################################################################

ROOM_ID="${ROOM_ID:-}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-}"

PROVIDER="${PROVIDER:-telemost}"
TRANSPORT="${TRANSPORT:-vp8channel}"

DNS_SERVER="${DNS_SERVER:-8.8.8.8:53}"

# Current recommended upstream settings for telemost + vp8channel.
VP8_FPS="${VP8_FPS:-30}"
VP8_BATCH_SIZE="${VP8_BATCH_SIZE:-64}"

# true = verbose OlcRTC logs.
# Only exact true/false count: a generic DEBUG=1 from the host env must
# not break a one-liner install (common on Windows / some IDEs).
case "${DEBUG:-false}" in
    true | false)
        DEBUG="${DEBUG:-false}"
        ;;
    *)
        DEBUG="false"
        ;;
esac

# "" = uname -m; "arm64" or "amd64" to force.
ARCH_OVERRIDE="${ARCH_OVERRIDE:-}"

GITHUB_REPO="${GITHUB_REPO:-15230041523004/oneclick-olcrtc-wrt}"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-https://github.com/${GITHUB_REPO}/releases/latest/download}"

# Leave empty to use this repo's GitHub Release assets.
BINARY_URL_ARM64="${BINARY_URL_ARM64:-}"
BINARY_URL_AMD64="${BINARY_URL_AMD64:-}"

# Leave empty to take the digest from SHA256SUMS on the same release.
# Required-empty only when BINARY_URL_* is a custom override.
BINARY_SHA256_ARM64="${BINARY_SHA256_ARM64:-}"
BINARY_SHA256_AMD64="${BINARY_SHA256_AMD64:-}"

# Optional outbound SOCKS5 for the server itself (not a listen port).
UPSTREAM_PROXY_ADDR="${UPSTREAM_PROXY_ADDR:-}"
UPSTREAM_PROXY_PORT="${UPSTREAM_PROXY_PORT:-0}"
UPSTREAM_PROXY_USER="${UPSTREAM_PROXY_USER:-}"
UPSTREAM_PROXY_PASS="${UPSTREAM_PROXY_PASS:-}"

INSTALL_BIN="${INSTALL_BIN:-/usr/bin/olcrtc}"
CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc}"
CONFIG_FILE="${CONFIG_FILE:-/etc/olcrtc/server.yaml}"
INIT_FILE="${INIT_FILE:-/etc/init.d/olcrtc-srv}"
SERVICE_NAME="${SERVICE_NAME:-olcrtc-srv}"
SYSUPGRADE_CONF="${SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"

STARTUP_WAIT="${STARTUP_WAIT:-6}"
MIN_FREE_KB="${MIN_FREE_KB:-49152}"
URI_LABEL="${URI_LABEL:-OpenWRT-Telemost-srv}"

###############################################################################
# END USER SETTINGS
###############################################################################

DUMP_CONFIG=0
DUMP_URI=0

usage() {
    cat <<'EOF'
Usage: install.sh [--dump-config|--dump-uri|--help]

  ROOM_ID is required. ENCRYPTION_KEY is optional (generated or reused).

  --dump-config   print server.yaml to stdout and exit (no install)
  --dump-uri      print the client olcrtc:// URI to stdout and exit
  --help          show this help
EOF
}

log() {
    printf '%s\n' "[olcrtc-installer] $*" >&2
}

die() {
    printf '%s\n' "[olcrtc-installer] ERROR: $*" >&2
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --dump-config)
            DUMP_CONFIG=1
            ;;
        --dump-uri)
            DUMP_URI=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $arg (try --help)"
            ;;
    esac
done


###############################################################################
# Shared validation / helpers
###############################################################################

is_hex64() {
    [ "${#1}" -eq 64 ] || return 1
    case "$1" in
        *[!0-9A-Fa-f]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

reject_yaml_string() {
    # $1 = value, $2 = name
    case "$1" in
        *"'"*|*"
"*)
            die "$2 must not contain a single quote or newline"
            ;;
    esac
}

extract_existing_key() {
    # Print a 64-hex crypto.key from an existing YAML, if present.
    [ -r "$1" ] || return 1
    sed -n "s/^[[:space:]]*key:[[:space:]]*['\"]*\\([0-9A-Fa-f]\\{64\\}\\)['\"]*[[:space:]]*\$/\\1/p" "$1" |
        head -n 1
}

generate_key() {
    key="$(
        dd if=/dev/urandom bs=32 count=1 2>/dev/null |
            od -An -tx1 |
            tr -d ' \n'
    )"
    is_hex64 "$key" || die "failed to generate a 32-byte encryption key"
    printf '%s' "$key"
}

resolve_encryption_key() {
    if [ -n "$ENCRYPTION_KEY" ]; then
        is_hex64 "$ENCRYPTION_KEY" ||
            die "ENCRYPTION_KEY must be exactly 64 hex characters"
        return 0
    fi

    if [ "$DUMP_CONFIG" -eq 0 ] && [ "$DUMP_URI" -eq 0 ]; then
        existing="$(extract_existing_key "$CONFIG_FILE" || true)"
        if is_hex64 "$existing"; then
            ENCRYPTION_KEY="$existing"
            log "reusing encryption key from $CONFIG_FILE"
            return 0
        fi
    fi

    ENCRYPTION_KEY="$(generate_key)"
    log "generated a new 32-byte encryption key"
}

client_uri() {
    printf '%s' "olcrtc://${PROVIDER}?${TRANSPORT}<vp8-fps=${VP8_FPS}&vp8-batch=${VP8_BATCH_SIZE}>@${ROOM_ID}#${ENCRYPTION_KEY}\$${URI_LABEL}"
}

emit_server_yaml() {
    cat <<EOF_CONFIG
mode: srv

auth:
  provider: ${PROVIDER}

room:
  id: '${ROOM_ID}'

crypto:
  key: '${ENCRYPTION_KEY}'

net:
  transport: ${TRANSPORT}
  dns: '${DNS_SERVER}'

liveness:
  interval: 10s
  timeout: 15s
  failures: 4

vp8:
  fps: ${VP8_FPS}
  batch_size: ${VP8_BATCH_SIZE}

debug: ${DEBUG}
EOF_CONFIG

    if [ -n "$UPSTREAM_PROXY_ADDR" ]; then
        cat <<EOF_PROXY

socks:
  proxy_addr: '${UPSTREAM_PROXY_ADDR}'
  proxy_port: ${UPSTREAM_PROXY_PORT}
  proxy_user: '${UPSTREAM_PROXY_USER}'
  proxy_pass: '${UPSTREAM_PROXY_PASS}'
EOF_PROXY
    fi
}

write_server_yaml() {
    # $1 = output path, or empty for stdout
    out="${1:-}"
    umask 077

    if [ -n "$out" ]; then
        emit_server_yaml >"$out"
        chmod 0600 "$out"
    else
        emit_server_yaml
    fi
}

validate_settings() {
    [ "$PROVIDER" = "telemost" ] ||
        die "PROVIDER must be telemost in this installer"

    [ "$TRANSPORT" = "vp8channel" ] ||
        die "TRANSPORT must be vp8channel in this installer"

    [ -n "$ROOM_ID" ] &&
        [ "$ROOM_ID" != "REPLACE_WITH_TELEMOST_ROOM_ID" ] ||
        die "set ROOM_ID (environment variable or the header of this script)"

    reject_yaml_string "$ROOM_ID" "ROOM_ID"

    case "$DEBUG" in
        true | false) ;;
        *)
            die "DEBUG must be true or false"
            ;;
    esac

    case "$VP8_FPS$VP8_BATCH_SIZE$UPSTREAM_PROXY_PORT" in
        *[!0-9]*)
            die "VP8_FPS, VP8_BATCH_SIZE and UPSTREAM_PROXY_PORT must be integers"
            ;;
    esac

    [ -n "$VP8_FPS" ] && [ -n "$VP8_BATCH_SIZE" ] && [ -n "$UPSTREAM_PROXY_PORT" ] ||
        die "VP8_FPS, VP8_BATCH_SIZE and UPSTREAM_PROXY_PORT must be integers"

    reject_yaml_string "$DNS_SERVER" "DNS_SERVER"
    reject_yaml_string "$UPSTREAM_PROXY_ADDR" "UPSTREAM_PROXY_ADDR"
    reject_yaml_string "$UPSTREAM_PROXY_USER" "UPSTREAM_PROXY_USER"
    reject_yaml_string "$UPSTREAM_PROXY_PASS" "UPSTREAM_PROXY_PASS"
    reject_yaml_string "$URI_LABEL" "URI_LABEL"
}


###############################################################################
# Early dry-run exits
###############################################################################

validate_settings
resolve_encryption_key

if [ "$DUMP_CONFIG" -eq 1 ]; then
    write_server_yaml
    exit 0
fi

if [ "$DUMP_URI" -eq 1 ]; then
    client_uri
    printf '\n'
    exit 0
fi


###############################################################################
# Sanity checks (real install)
###############################################################################

[ "$(id -u)" = "0" ] || die "run as root"

[ -r /etc/openwrt_release ] ||
    die "this installer is intended for OpenWrt"


###############################################################################
# Architecture
###############################################################################

arch="${ARCH_OVERRIDE:-}"

if [ -z "$arch" ]; then
    machine="$(uname -m)"
    case "$machine" in
        x86_64 | amd64)
            arch="amd64"
            ;;
        aarch64 | arm64)
            arch="arm64"
            ;;
        *)
            die "unsupported architecture: $machine (need aarch64/arm64 or x86_64/amd64)"
            ;;
    esac
fi

case "$arch" in
    arm64)
        binary_url="$BINARY_URL_ARM64"
        binary_sha="$BINARY_SHA256_ARM64"
        binary_name="olcrtc-linux-arm64"
        ;;
    amd64)
        binary_url="$BINARY_URL_AMD64"
        binary_sha="$BINARY_SHA256_AMD64"
        binary_name="olcrtc-linux-amd64"
        ;;
    *)
        die "ARCH_OVERRIDE must be arm64 or amd64"
        ;;
esac

using_release=0
if [ -z "$binary_url" ]; then
    binary_url="${RELEASE_BASE_URL}/${binary_name}"
    using_release=1
fi

case "$binary_url" in
    https://*) ;;
    *)
        die "binary URL must be HTTPS: $binary_url"
        ;;
esac


###############################################################################
# Free space
###############################################################################

check_space() {
    mountpoint="$1"
    avail="$(df -k "$mountpoint" 2>/dev/null | awk 'NR==2 {print $4}')"
    case "$avail" in
        '' | *[!0-9]*)
            log "WARNING: could not determine free space on $mountpoint"
            return 0
            ;;
    esac
    if [ "$avail" -lt "$MIN_FREE_KB" ]; then
        die "not enough free space on $mountpoint: ${avail} KiB (need ${MIN_FREE_KB} KiB)"
    fi
}

check_space /usr


###############################################################################
# TLS CA bundle (for the installer download and for olcrtc HTTPS)
###############################################################################

if [ ! -e /etc/ssl/certs/ca-certificates.crt ] &&
    [ ! -e /etc/ssl/cert.pem ]; then

    if command -v apk >/dev/null 2>&1; then
        log "installing ca-bundle with apk"
        apk update
        apk add ca-bundle
    elif command -v opkg >/dev/null 2>&1; then
        log "installing ca-bundle with opkg"
        opkg update
        opkg install ca-bundle
    else
        die "no apk/opkg found and no CA certificate bundle present"
    fi
fi


###############################################################################
# Download helper
###############################################################################

fetch() {
    url="$1"
    out="$2"

    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -O "$out" "$url" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$out" "$url" || return 1
    else
        if command -v apk >/dev/null 2>&1; then
            apk add curl || return 1
        elif command -v opkg >/dev/null 2>&1; then
            opkg update || return 1
            opkg install curl || return 1
        else
            die "no downloader and no supported package manager"
        fi
        curl -fL --retry 3 -o "$out" "$url" || return 1
    fi
}

release_hint() {
    case "$binary_url" in
        *"/${GITHUB_REPO}/releases/"*)
            die "$1 (tag v0.1.0 and publish Release assets first, or set BINARY_URL_${arch})"
            ;;
        *)
            die "$1"
            ;;
    esac
}


###############################################################################
# Resolve SHA-256
###############################################################################

workdir="/tmp/olcrtc-install.$$"
mkdir -p "$workdir"
trap 'rm -rf "$workdir"' EXIT INT TERM

if [ -z "$binary_sha" ] && [ "$using_release" -eq 1 ]; then
    sums_url="${RELEASE_BASE_URL}/SHA256SUMS"
    log "downloading SHA256SUMS"
    if ! fetch "$sums_url" "$workdir/SHA256SUMS"; then
        release_hint "failed to download SHA256SUMS from $sums_url"
    fi
    [ -s "$workdir/SHA256SUMS" ] || release_hint "SHA256SUMS is empty"

    binary_sha="$(
        awk -v f="$binary_name" '
            $2 == f || $2 == "*" f || $2 ~ "/" f "$" { print $1; exit }
        ' "$workdir/SHA256SUMS"
    )"
    [ -n "$binary_sha" ] || die "no SHA256 entry for $binary_name in SHA256SUMS"
fi

if [ -z "$binary_sha" ]; then
    log "WARNING: no SHA256 configured for a custom BINARY_URL"
    log "WARNING: pin the binary and set BINARY_SHA256_${arch} for production use"
fi


###############################################################################
# Download and install the binary
###############################################################################

tmp="$workdir/$binary_name"

log "architecture: $arch"
log "downloading $binary_url"

if ! fetch "$binary_url" "$tmp"; then
    release_hint "failed to download $binary_url"
fi

[ -s "$tmp" ] || release_hint "downloaded binary is empty"

if [ -n "$binary_sha" ]; then
    command -v sha256sum >/dev/null 2>&1 ||
        die "sha256sum is required to verify the binary"

    got="$(sha256sum "$tmp" | awk '{print $1}')"
    if [ "$got" != "$binary_sha" ]; then
        die "SHA256 mismatch: got $got want $binary_sha"
    fi
    log "SHA256 OK"
fi

if [ -x "$INIT_FILE" ]; then
    log "stopping $SERVICE_NAME before replacing the binary"
    "$INIT_FILE" stop 2>/dev/null || true
fi

chmod 0755 "$tmp"
mkdir -p "$(dirname "$INSTALL_BIN")"
mkdir -p "$CONFIG_DIR"
mv "$tmp" "$INSTALL_BIN"
chmod 0755 "$INSTALL_BIN"

# Best-effort record of the pinned upstream commit.
if [ "$using_release" -eq 1 ]; then
    fetch "${RELEASE_BASE_URL}/OLCRTC_COMMIT.txt" "$CONFIG_DIR/OLCRTC_COMMIT" 2>/dev/null || true
fi


###############################################################################
# Config + procd + sysupgrade
###############################################################################

log "writing $CONFIG_FILE"
write_server_yaml "$CONFIG_FILE"

log "writing $INIT_FILE"
cat >"$INIT_FILE" <<'EOF_INIT'
#!/bin/sh /etc/rc.common

USE_PROCD=1

START=95
STOP=10

PROG="/usr/bin/olcrtc"
CONF="/etc/olcrtc/server.yaml"


start_service() {
    [ -x "$PROG" ] || return 1
    [ -r "$CONF" ] || return 1

    procd_open_instance

    # Current OlcRTC CLI:
    #
    #     olcrtc /path/to/server.yaml
    #
    # Process stays in foreground; procd supervises it.
    procd_set_param command "$PROG" "$CONF"

    # threshold=3600 s
    # retry delay=5 s
    # retry=0 => retry indefinitely
    #
    # This is useful on LTE/5G routers where WAN may become available
    # somewhat later than the service during boot.
    procd_set_param respawn 3600 5 0

    procd_set_param stdout 1
    procd_set_param stderr 1

    # Store this file as part of the procd service state.
    procd_set_param file "$CONF"

    procd_close_instance
}


reload_service() {
    stop
    start
}
EOF_INIT

chmod 0755 "$INIT_FILE"

ensure_sysupgrade_entry() {
    path="$1"
    [ -n "$path" ] || return 0
    if [ ! -f "$SYSUPGRADE_CONF" ]; then
        touch "$SYSUPGRADE_CONF"
    fi
    if grep -qxF "$path" "$SYSUPGRADE_CONF" 2>/dev/null; then
        return 0
    fi
    printf '%s\n' "$path" >>"$SYSUPGRADE_CONF"
}

ensure_sysupgrade_entry "$INSTALL_BIN"
ensure_sysupgrade_entry "$CONFIG_DIR/"
ensure_sysupgrade_entry "$INIT_FILE"


###############################################################################
# Enable and start
###############################################################################

log "enabling procd service"
"$INIT_FILE" enable

log "starting OlcRTC server"
"$INIT_FILE" restart

sleep "$STARTUP_WAIT"

status_json="$(
    ubus call service list "{\"name\":\"${SERVICE_NAME}\"}" 2>/dev/null || true
)"

if printf '%s' "$status_json" |
    grep -Eq '"running"[[:space:]]*:[[:space:]]*true'; then
    service_state="RUNNING"
else
    service_state="NOT CONFIRMED - inspect logread"
fi

CLIENT_URI="$(client_uri)"

cat <<EOF_DONE

============================================================
 OlcRTC server installation complete
============================================================

Service:        $SERVICE_NAME
State:          $service_state

Architecture:   $arch
Mode:           srv
Provider:       $PROVIDER
Transport:      $TRANSPORT
VP8 FPS:        $VP8_FPS
VP8 batch:      $VP8_BATCH_SIZE

Room ID:
$ROOM_ID

Encryption key:
$ENCRYPTION_KEY

Client URI:
$CLIENT_URI

Binary:
$INSTALL_BIN

Config:
$CONFIG_FILE

Service:
$INIT_FILE


Verification:

  ubus call service list '{"name":"$SERVICE_NAME"}'

  logread | grep -i olcrtc | tail -n 80

Restart:

  $INIT_FILE restart

Stop:

  $INIT_FILE stop

Start:

  $INIT_FILE start


IMPORTANT:
The current olcrtc CLI consumes YAML, not an olcrtc:// URI.
The URI is for compatible client apps. It contains the encryption
key — do not post it in a public chat, issue or screenshot.

============================================================
EOF_DONE
