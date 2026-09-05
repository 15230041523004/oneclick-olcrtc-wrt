#!/bin/sh
# oneclick-olcrtc-wrt — remove the OpenWrt / Debian-family srv install
# created by install.sh
#
# One line (not sh -c "$(wget -qO- …)"):
#   wget -O /tmp/olcrtc-uninstall.sh \
#     https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/uninstall.sh \
#     && sh /tmp/olcrtc-uninstall.sh
# Debian-family VDS:
#   curl -fL -o /tmp/olcrtc-uninstall.sh \
#     https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/uninstall.sh \
#     && sudo sh /tmp/olcrtc-uninstall.sh
set -eu

INSTALL_BIN="${INSTALL_BIN:-/usr/bin/olcrtc}"
CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc}"
CONFIG_FILE="${CONFIG_FILE:-/etc/olcrtc/server.yaml}"
INIT_FILE="${INIT_FILE:-/etc/init.d/olcrtc-srv}"
SERVICE_NAME="${SERVICE_NAME:-olcrtc-srv}"
SYSTEMD_UNIT_FILE="${SYSTEMD_UNIT_FILE:-/etc/systemd/system/${SERVICE_NAME}.service}"
SYSUPGRADE_CONF="${SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

platform=""
os_id_like=""
service_manager=""

log() {
    printf '%s\n' "[olcrtc-uninstaller] $*"
}

die() {
    printf '%s\n' "[olcrtc-uninstaller] ERROR: $*" >&2
    exit 1
}

case "${1:-}" in
    --help | -h)
        printf '%s\n' "Usage: sh uninstall.sh (root, OpenWrt or Debian-family with systemd)"
        exit 0
        ;;
esac
[ "$#" -eq 0 ] || die "unknown arguments (try --help)"

if [ "$(id -u)" != "0" ]; then
    printf '%s\n' "[olcrtc-uninstaller] ERROR: run as root" >&2
    exit 1
fi

case "$SERVICE_NAME" in
    '' | .* | -* | *[!A-Za-z0-9_.@-]*) die "invalid SERVICE_NAME" ;;
esac

strip_cr() {
    old_ifs=$IFS
    IFS=$(printf '\r')
    # shellcheck disable=SC2086
    set -- $1
    IFS=$old_ifs
    printf '%s' "${1:-}"
}

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
    case "$SYSTEMD_UNIT_FILE" in
        /*) ;;
        *) die "SYSTEMD_UNIT_FILE must be absolute" ;;
    esac
    [ "${SYSTEMD_UNIT_FILE##*/}" = "${SERVICE_NAME}.service" ] ||
        die "SYSTEMD_UNIT_FILE must be named ${SERVICE_NAME}.service"
}

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

if [ "$service_manager" = systemd ]; then
    if [ -f "$SYSTEMD_UNIT_FILE" ]; then
        log "stopping and disabling $SERVICE_NAME"
        systemctl disable --now "${SERVICE_NAME}.service" || true
    fi
    rm -f "$SYSTEMD_UNIT_FILE"
    systemctl daemon-reload
    systemctl reset-failed "${SERVICE_NAME}.service" 2>/dev/null || true
elif [ -x "$INIT_FILE" ]; then
    log "stopping $SERVICE_NAME"
    "$INIT_FILE" stop 2>/dev/null || true
    log "disabling $SERVICE_NAME"
    "$INIT_FILE" disable 2>/dev/null || true
fi

if [ "$service_manager" = procd ]; then
    rm -f "$INIT_FILE"
fi
rm -f "$INSTALL_BIN"
rm -f "$CONFIG_FILE"
rm -f "$CONFIG_DIR/OLCRTC_COMMIT"
rmdir "$CONFIG_DIR" 2>/dev/null || true

if [ "$service_manager" = procd ] && [ -f "$SYSUPGRADE_CONF" ]; then
    tmp="$(mktemp "${TMPDIR:-/tmp}/olcrtc-sysupgrade.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT INT TERM
    {
        grep -vxF "$INSTALL_BIN" "$SYSUPGRADE_CONF" |
            grep -vxF "${CONFIG_DIR}/" |
            grep -vxF "$INIT_FILE" || true
    } >"$tmp"
    cat "$tmp" >"$SYSUPGRADE_CONF"
    rm -f "$tmp"
    log "removed sysupgrade keep-list entries"
fi

log "removed $SERVICE_NAME files"
log "done"
