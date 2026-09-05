#!/bin/sh
# oneclick-olcrtc-wrt — OpenWrt / Debian-family installer for current OlcRTC
# mode:srv (Yandex Telemost + vp8channel).
#
# One line (OpenWrt wget / uclient-fetch), not raw main.
# ROOM_ID must be on the `sh` after && — a prefix only applies to wget.
#   wget -O /tmp/olcrtc-install.sh \
#     https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh \
#     && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
# Debian-family VDS (curl; sudo keeps ROOM_ID):
#   curl -fL -o /tmp/olcrtc-install.sh \
#     https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh \
#     && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
# The script then downloads olcrtc-linux-arm64|amd64 from the same Release.
# Do not use sh -c "$(wget -qO- …)" (a 404 becomes an empty successful sh).
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

# Empty in git. The release workflow bakes the tag, e.g. v0.0.2-untested, so a
# downloaded installer pulls binaries from that same Release — not from
# a floating main / a different latest.
INSTALLER_RELEASE="${INSTALLER_RELEASE:-}"

if [ -z "${RELEASE_BASE_URL:-}" ]; then
    if [ -n "$INSTALLER_RELEASE" ]; then
        RELEASE_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${INSTALLER_RELEASE}"
    else
        RELEASE_BASE_URL="https://github.com/${GITHUB_REPO}/releases/latest/download"
    fi
fi

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
SYSTEMD_UNIT_FILE="${SYSTEMD_UNIT_FILE:-/etc/systemd/system/${SERVICE_NAME}.service}"
SYSUPGRADE_CONF="${SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
CA_CERTS_FILE="${CA_CERTS_FILE:-/etc/ssl/certs/ca-certificates.crt}"
SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/cert.pem}"

# The service must stay running for STABLE_NEEDED samples, STABLE_INTERVAL
# seconds apart, within STABLE_MAX seconds. One "running" snapshot is
# not enough: respawn can look alive while the process is crash-looping.
STABLE_NEEDED="${STABLE_NEEDED:-4}"
STABLE_INTERVAL="${STABLE_INTERVAL:-10}"
STABLE_MAX="${STABLE_MAX:-60}"

MIN_FREE_KB="${MIN_FREE_KB:-49152}"
MIN_TMP_KB="${MIN_TMP_KB:-32768}"
URI_LABEL="${URI_LABEL:-}"

# Go heap cap for a 512 MiB LTE router (supported minimum).
GOMEMLIMIT="${GOMEMLIMIT:-80MiB}"
# Warn below 512 MiB MemAvailable. 256 MiB is unproven; 128 MiB is unsupported.
MEM_WARN_KB="${MEM_WARN_KB:-524288}"

###############################################################################
# END USER SETTINGS
###############################################################################

DUMP_CONFIG=0
DUMP_URI=0
DUMP_INIT=0
DUMP_SYSTEMD=0
DUMP_RELEASE_URL=0
MEM_WARN=""
platform=""
os_id_like=""
service_manager=""

usage() {
    cat <<'EOF'
Usage: install.sh [--dump-config|--dump-uri|--dump-init|--dump-systemd|--dump-release-url|--help]

  Real installation requires root on OpenWrt or Debian-family with systemd.

  ROOM_ID is required. ENCRYPTION_KEY is optional (generated or reused).

  --dump-config       print server.yaml to stdout and exit (no install)
  --dump-uri          print the client olcrtc:// URI to stdout and exit
  --dump-init         print the procd init script to stdout and exit
  --dump-systemd      print the systemd unit to stdout and exit (no Room ID needed)
  --dump-release-url  print the binary download base URL and exit
  --help              show this help
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
        --dump-init)
            DUMP_INIT=1
            ;;
        --dump-systemd)
            DUMP_SYSTEMD=1
            ;;
        --dump-release-url)
            DUMP_RELEASE_URL=1
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
    # Default OpenWrt BusyBox has no od/hexdump/xxd. sha256sum is required
    # later to verify the ELF; hash 32 random bytes to get 64 hex chars.
    command -v sha256sum >/dev/null 2>&1 ||
        die "sha256sum is required to generate an encryption key"
    key="$(
        dd if=/dev/urandom bs=32 count=1 2>/dev/null |
            sha256sum |
            awk '{print $1}'
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

    if [ "$DUMP_CONFIG" -eq 0 ] && [ "$DUMP_URI" -eq 0 ] && [ "$DUMP_INIT" -eq 0 ]; then
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

# Keep this heredoc identical to files/olcrtc-srv.init (CI compares them).
emit_init_script() {
    sed -e "s#@INSTALL_BIN@#${INSTALL_BIN}#g" \
        -e "s#@CONFIG_FILE@#${CONFIG_FILE}#g" \
        -e "s#@GOMEMLIMIT@#${GOMEMLIMIT}#g" <<'EOF_INIT'
#!/bin/sh /etc/rc.common

USE_PROCD=1

START=95
STOP=10

PROG="@INSTALL_BIN@"
CONF="@CONFIG_FILE@"


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

    # Cap Go heap so VP8 on a 512 MiB LTE box is less likely to OOM
    # the whole router. Do not set RLIMIT_AS: Go reserves a large
    # virtual address space and a tight "as=" limit prevents startup.
    procd_set_param env GOMEMLIMIT="@GOMEMLIMIT@" GOGC=50

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
}

strip_cr() {
    old_ifs=$IFS
    IFS=$(printf '\r')
    # shellcheck disable=SC2086
    set -- $1
    IFS=$old_ifs
    printf '%s' "${1:-}"
}

read_os_release() {
    if [ -r "$OS_RELEASE_FILE" ]; then
        platform="$(
            # shellcheck source=/dev/null
            . "$OS_RELEASE_FILE"
            printf '%s' "${ID:-}"
        )"
        os_id_like="$(
            # shellcheck source=/dev/null
            . "$OS_RELEASE_FILE"
            printf '%s' "${ID_LIKE:-}"
        )"
        platform="$(strip_cr "$platform")"
        os_id_like="$(strip_cr "$os_id_like")"
    elif [ -r /etc/openwrt_release ]; then
        platform=openwrt
        os_id_like=""
    else
        die "cannot detect OS (need OpenWrt or Debian-family with systemd)"
    fi
}

id_like_has_debian() {
    # ID_LIKE is a space-separated token list from os-release.
    # shellcheck disable=SC2086
    for like in $os_id_like; do
        [ "$like" = debian ] && return 0
    done
    return 1
}

require_systemd_family() {
    service_manager=systemd
    command -v apt-get >/dev/null 2>&1 ||
        die "apt-get is required on Debian-family systems"
    command -v systemctl >/dev/null 2>&1 ||
        die "systemctl is required on Debian-family systems"
    systemctl show-environment >/dev/null 2>&1 ||
        die "systemd must be running (a container without systemd is not supported)"
    validate_systemd_settings
}

detect_platform() {
    read_os_release

    case "$platform" in
        openwrt)
            service_manager=procd
            ;;
        debian | ubuntu)
            require_systemd_family
            ;;
        *)
            if id_like_has_debian; then
                require_systemd_family
            else
                die "unsupported OS: $platform (need OpenWrt or Debian-family with systemd)"
            fi
            ;;
    esac
}

validate_systemd_settings() {
    # These values are embedded in a systemd command and a sed replacement.
    # Reject expansions and whitespace rather than silently changing a path.
    for path in "$INSTALL_BIN" "$CONFIG_FILE"; do
        case "$path" in
            /*) ;;
            *) die "systemd binary and config paths must be absolute" ;;
        esac
        case "$path" in
            *[!A-Za-z0-9_./-]*) die "systemd binary and config paths must not contain spaces or special characters" ;;
        esac
    done
    case "$GOMEMLIMIT" in
        *[!A-Za-z0-9]*) die "invalid GOMEMLIMIT for systemd" ;;
    esac
    case "$SYSTEMD_UNIT_FILE" in
        /*) ;;
        *) die "SYSTEMD_UNIT_FILE must be absolute" ;;
    esac
    [ "${SYSTEMD_UNIT_FILE##*/}" = "${SERVICE_NAME}.service" ] ||
        die "SYSTEMD_UNIT_FILE must be named ${SERVICE_NAME}.service"
}

# Keep this heredoc identical to files/olcrtc-srv.service (CI compares them).
emit_systemd_unit() {
    sed -e "s#@INSTALL_BIN@#$INSTALL_BIN#g" \
        -e "s#@CONFIG_FILE@#$CONFIG_FILE#g" \
        -e "s#@GOMEMLIMIT@#$GOMEMLIMIT#g" <<'EOF_SYSTEMD'
[Unit]
Description=OlcRTC Telemost server
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=@INSTALL_BIN@ @CONFIG_FILE@
Environment=GOMEMLIMIT=@GOMEMLIMIT@
Environment=GOGC=50
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
}

is_elf() {
    # 0x7f 'E' 'L' 'F'. Avoid od: it is not in default OpenWrt BusyBox.
    [ "$(dd if="$1" bs=4 count=1 2>/dev/null)" = "$(printf '\177ELF')" ]
}

has_http_downloader() {
    command -v uclient-fetch >/dev/null 2>&1 && return 0
    command -v wget >/dev/null 2>&1 && return 0
    command -v curl >/dev/null 2>&1 && return 0
    return 1
}

run_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

validate_settings() {
    [ "$PROVIDER" = "telemost" ] ||
        die "PROVIDER must be telemost in this installer"

    [ "$TRANSPORT" = "vp8channel" ] ||
        die "TRANSPORT must be vp8channel in this installer"

    if [ -z "$ROOM_ID" ] || [ "$ROOM_ID" = "REPLACE_WITH_TELEMOST_ROOM_ID" ]; then
        die "set ROOM_ID (environment variable or the header of this script)"
    fi

    reject_yaml_string "$ROOM_ID" "ROOM_ID"

    case "$DEBUG" in
        true | false) ;;
        *)
            die "DEBUG must be true or false"
            ;;
    esac

    case "$VP8_FPS$VP8_BATCH_SIZE$UPSTREAM_PROXY_PORT$STABLE_NEEDED$STABLE_INTERVAL$STABLE_MAX" in
        *[!0-9]*)
            die "VP8_FPS, VP8_BATCH_SIZE, UPSTREAM_PROXY_PORT and STABLE_* must be integers"
            ;;
    esac

    if [ -z "$VP8_FPS" ] || [ -z "$VP8_BATCH_SIZE" ] || [ -z "$UPSTREAM_PROXY_PORT" ]; then
        die "VP8_FPS, VP8_BATCH_SIZE and UPSTREAM_PROXY_PORT must be integers"
    fi

    reject_yaml_string "$DNS_SERVER" "DNS_SERVER"
    reject_yaml_string "$UPSTREAM_PROXY_ADDR" "UPSTREAM_PROXY_ADDR"
    reject_yaml_string "$UPSTREAM_PROXY_USER" "UPSTREAM_PROXY_USER"
    reject_yaml_string "$UPSTREAM_PROXY_PASS" "UPSTREAM_PROXY_PASS"
    reject_yaml_string "$URI_LABEL" "URI_LABEL"

    case "$SERVICE_NAME" in
        '' | .* | -* | *[!A-Za-z0-9_.@-]*) die "invalid SERVICE_NAME" ;;
    esac
    [ "$STABLE_NEEDED" -gt 0 ] && [ "$STABLE_INTERVAL" -gt 0 ] && [ "$STABLE_MAX" -gt 0 ] ||
        die "STABLE_NEEDED, STABLE_INTERVAL and STABLE_MAX must be greater than zero"
}


###############################################################################
# Early dry-run exits
###############################################################################

if [ "$DUMP_RELEASE_URL" -eq 1 ]; then
    printf '%s\n' "$RELEASE_BASE_URL"
    exit 0
fi

if [ "$DUMP_SYSTEMD" -eq 1 ]; then
    validate_systemd_settings
    emit_systemd_unit
    exit 0
fi

if [ "$DUMP_CONFIG" -eq 0 ] && [ "$DUMP_URI" -eq 0 ] && [ "$DUMP_INIT" -eq 0 ]; then
    [ "$(id -u)" = "0" ] || die "run as root"
    detect_platform
    if [ "$service_manager" = systemd ]; then
        URI_LABEL="${URI_LABEL:-Debian-Telemost-srv}"
    fi
fi
URI_LABEL="${URI_LABEL:-OpenWRT-Telemost-srv}"

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

if [ "$DUMP_INIT" -eq 1 ]; then
    emit_init_script
    exit 0
fi


###############################################################################
# Sanity checks (real install)
###############################################################################

mem_avail_kb="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null || true)"
case "$mem_avail_kb" in
    '' | *[!0-9]*) ;;
    *)
        if [ "$mem_avail_kb" -lt "$MEM_WARN_KB" ]; then
            MEM_WARN="MemAvailable ${mem_avail_kb} KiB (< ${MEM_WARN_KB} KiB); vp8channel may OOM under load"
            log "WARNING: $MEM_WARN"
        fi
        ;;
esac


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
    need="${2:-$MIN_FREE_KB}"
    avail="$(df -k "$mountpoint" 2>/dev/null | awk 'NR==2 {print $4}')"
    case "$avail" in
        '' | *[!0-9]*)
            log "WARNING: could not determine free space on $mountpoint"
            return 0
            ;;
    esac
    if [ "$avail" -lt "$need" ]; then
        die "not enough free space on $mountpoint: ${avail} KiB (need ${need} KiB)"
    fi
}

check_space "${TMPDIR:-/tmp}" "$MIN_TMP_KB"
check_space /usr "$MIN_FREE_KB"


###############################################################################
# TLS CA bundle (for the installer download and for olcrtc HTTPS)
###############################################################################

if [ ! -e "$CA_CERTS_FILE" ] &&
    [ ! -e "$SSL_CERT_FILE" ]; then

    if [ "$service_manager" = systemd ]; then
        if has_http_downloader; then
            log "installing ca-certificates with apt-get"
            run_apt_get update
            run_apt_get install -y --no-install-recommends ca-certificates
        else
            log "installing ca-certificates and curl with apt-get"
            run_apt_get update
            run_apt_get install -y --no-install-recommends ca-certificates curl
        fi
    elif command -v apk >/dev/null 2>&1; then
        log "installing ca-bundle with apk"
        apk update
        apk add ca-bundle
    elif command -v opkg >/dev/null 2>&1; then
        log "installing ca-bundle with opkg"
        opkg update
        opkg install ca-bundle
    else
        die "no supported package manager and no CA certificate bundle present"
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
        if [ "$service_manager" = systemd ]; then
            run_apt_get update || return 1
            run_apt_get install -y --no-install-recommends curl || return 1
        elif command -v apk >/dev/null 2>&1; then
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
            die "$1 (tag a release and publish Release assets first, or set BINARY_URL_${arch})"
            ;;
        *)
            die "$1"
            ;;
    esac
}


###############################################################################
# Resolve SHA-256
###############################################################################

workdir="$(mktemp -d "${TMPDIR:-/tmp}/olcrtc-install.XXXXXX")"
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

if ! is_elf "$tmp"; then
    release_hint "downloaded file is not an ELF binary (got an HTML error page or the wrong asset)"
fi

if [ -n "$binary_sha" ]; then
    command -v sha256sum >/dev/null 2>&1 ||
        die "sha256sum is required to verify the binary"

    got="$(sha256sum "$tmp" | awk '{print $1}')"
    if [ "$got" != "$binary_sha" ]; then
        die "SHA256 mismatch: got $got want $binary_sha"
    fi
    log "SHA256 OK"
fi

if [ "$service_manager" = systemd ]; then
    if [ -f "$SYSTEMD_UNIT_FILE" ]; then
        log "stopping $SERVICE_NAME before replacing the binary"
        systemctl stop "${SERVICE_NAME}.service" || true
    fi
elif [ -x "$INIT_FILE" ]; then
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
# Config + service + OpenWrt sysupgrade
###############################################################################

log "writing $CONFIG_FILE"
write_server_yaml "$CONFIG_FILE"

if [ "$service_manager" = systemd ]; then
    service_file="$SYSTEMD_UNIT_FILE"
    log "writing $service_file"
    mkdir -p "$(dirname "$service_file")"
    emit_systemd_unit >"$service_file"
    chmod 0644 "$service_file"
else
    service_file="$INIT_FILE"
    log "writing $service_file"
    emit_init_script >"$service_file"
    chmod 0755 "$service_file"
fi

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

if [ "$service_manager" = procd ]; then
    ensure_sysupgrade_entry "$INSTALL_BIN"
    ensure_sysupgrade_entry "$CONFIG_DIR/"
    ensure_sysupgrade_entry "$INIT_FILE"
fi


###############################################################################
# Enable and start
###############################################################################

log "enabling $service_manager service"
if [ "$service_manager" = systemd ]; then
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    log "starting OlcRTC server"
    systemctl restart "${SERVICE_NAME}.service"
    status_command="systemctl status ${SERVICE_NAME}.service --no-pager"
    logs_command="journalctl -u ${SERVICE_NAME}.service -n 80 --no-pager"
    restart_command="systemctl restart ${SERVICE_NAME}.service"
    stop_command="systemctl stop ${SERVICE_NAME}.service"
    start_command="systemctl start ${SERVICE_NAME}.service"
else
    "$INIT_FILE" enable
    log "starting OlcRTC server"
    "$INIT_FILE" restart
    status_command="ubus call service list '{\"name\":\"$SERVICE_NAME\"}'"
    logs_command="logread | grep -i olcrtc | tail -n 80"
    restart_command="$INIT_FILE restart"
    stop_command="$INIT_FILE stop"
    start_command="$INIT_FILE start"
fi

procd_instance_pid() {
    status_json="$(
        ubus call service list "{\"name\":\"${SERVICE_NAME}\"}" 2>/dev/null || true
    )"
    printf '%s' "$status_json" |
        grep -Eq '"running"[[:space:]]*:[[:space:]]*true' || return 1
    # First numeric pid in the instance blob. A respawn changes this value.
    printf '%s' "$status_json" |
        tr ',' '\n' |
        sed -n 's/.*"pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' |
        head -n 1
}

service_instance_pid() {
    if [ "$service_manager" = systemd ]; then
        systemctl is-active --quiet "${SERVICE_NAME}.service" || return 1
        main_pid="$(systemctl show --property=MainPID --value "${SERVICE_NAME}.service")" || return 1
        case "$main_pid" in
            '' | 0 | *[!0-9]*) return 1 ;;
        esac
        printf '%s\n' "$main_pid"
    else
        procd_instance_pid
    fi
}

stable=0
seen_pid=""
elapsed=0
while [ "$elapsed" -lt "$STABLE_MAX" ]; do
    pid="$(service_instance_pid || true)"
    if [ -n "$pid" ]; then
        if [ -z "$seen_pid" ]; then
            seen_pid="$pid"
            stable=1
            log "$service_manager pid ${pid} (${stable}/${STABLE_NEEDED})"
        elif [ "$pid" = "$seen_pid" ]; then
            stable=$((stable + 1))
            log "$service_manager pid ${pid} still running (${stable}/${STABLE_NEEDED})"
        else
            log "$service_manager pid changed ${seen_pid} -> ${pid}; reset (respawn/crash-loop)"
            seen_pid="$pid"
            stable=1
        fi
        if [ "$stable" -ge "$STABLE_NEEDED" ]; then
            break
        fi
    else
        if [ "$stable" -gt 0 ]; then
            log "$service_manager not running; resetting stability counter"
        fi
        stable=0
        seen_pid=""
    fi
    sleep "$STABLE_INTERVAL"
    elapsed=$((elapsed + STABLE_INTERVAL))
done

if [ "$stable" -ge "$STABLE_NEEDED" ]; then
    service_state="RUNNING"
    install_ok=1
else
    service_state="NOT STABLE - inspect logs below"
    install_ok=0
fi

CLIENT_URI="$(client_uri)"

if [ "$install_ok" -eq 1 ]; then
    result_title="OlcRTC server installation complete"
else
    result_title="OlcRTC server FAILED to stay running"
fi

cat <<EOF_DONE

============================================================
 $result_title
============================================================

Service:        $SERVICE_NAME
State:          $service_state

Architecture:   $arch
OS:             $platform
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
$service_file

GOMEMLIMIT:
$GOMEMLIMIT
${MEM_WARN:+
WARNING:
$MEM_WARN
}

Verification:

  $status_command

  $logs_command

Restart:

  $restart_command

Stop:

  $stop_command

Start:

  $start_command


IMPORTANT:
The current olcrtc CLI consumes YAML, not an olcrtc:// URI.
The URI is for compatible client apps. It contains the encryption
key — do not post it in a public chat, issue or screenshot.

$service_manager "running" means the process stayed up. It is not a Telemost /
OLC2 / SOCKS check. That is Deployment GO on the client.

============================================================
EOF_DONE

if [ "$install_ok" -ne 1 ]; then
    die "service $SERVICE_NAME did not stay running for ${STABLE_NEEDED} consecutive checks"
fi
