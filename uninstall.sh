#!/bin/sh
# oneclick-olcrtc-wrt — remove the OpenWrt srv install created by install.sh
#
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/uninstall.sh)"
set -eu

INSTALL_BIN="${INSTALL_BIN:-/usr/bin/olcrtc}"
CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc}"
CONFIG_FILE="${CONFIG_FILE:-/etc/olcrtc/server.yaml}"
INIT_FILE="${INIT_FILE:-/etc/init.d/olcrtc-srv}"
SERVICE_NAME="${SERVICE_NAME:-olcrtc-srv}"
SYSUPGRADE_CONF="${SYSUPGRADE_CONF:-/etc/sysupgrade.conf}"

log() {
    printf '%s\n' "[olcrtc-uninstaller] $*"
}

if [ "$(id -u)" != "0" ]; then
    printf '%s\n' "[olcrtc-uninstaller] ERROR: run as root" >&2
    exit 1
fi

if [ -x "$INIT_FILE" ]; then
    log "stopping $SERVICE_NAME"
    "$INIT_FILE" stop 2>/dev/null || true
    log "disabling $SERVICE_NAME"
    "$INIT_FILE" disable 2>/dev/null || true
fi

rm -f "$INIT_FILE"
rm -f "$INSTALL_BIN"
rm -f "$CONFIG_FILE"
rm -f "$CONFIG_DIR/OLCRTC_COMMIT"
rmdir "$CONFIG_DIR" 2>/dev/null || true

if [ -f "$SYSUPGRADE_CONF" ]; then
    tmp="/tmp/olcrtc-sysupgrade.$$"
    {
        grep -v '^/usr/bin/olcrtc$' "$SYSUPGRADE_CONF" |
            grep -v '^/etc/olcrtc/$' |
            grep -v '^/etc/init.d/olcrtc-srv$' || true
    } >"$tmp"
    cat "$tmp" >"$SYSUPGRADE_CONF"
    rm -f "$tmp"
    log "removed sysupgrade keep-list entries"
fi

log "removed $SERVICE_NAME files"
log "done"
