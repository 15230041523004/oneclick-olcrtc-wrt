#!/bin/sh
# Local/CI helper: validate install.sh --dump-config / --dump-uri fixtures.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

KEY=c8fa447c6d5c42f17a834dc44ec22c5322d62c274c0d2c51cb533aa2bf853619
ROOM=1234567890123456789
INSTALL="$ROOT/install.sh"

yaml=$(ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" DEBUG=false sh "$INSTALL" --dump-config)
uri=$(ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" DEBUG=false sh "$INSTALL" --dump-uri)

printf '%s\n' "$yaml" | grep -q '^mode: srv$'
printf '%s\n' "$yaml" | grep -q 'provider: telemost'
printf '%s\n' "$yaml" | grep -q 'transport: vp8channel'
printf '%s\n' "$yaml" | grep -q "id: '$ROOM'"
printf '%s\n' "$yaml" | grep -q "key: '$KEY'"
printf '%s\n' "$yaml" | grep -q 'fps: 30'
printf '%s\n' "$yaml" | grep -q 'batch_size: 64'
printf '%s\n' "$yaml" | grep -q 'debug: false'

if printf '%s\n' "$yaml" | grep -q '^socks:'; then
    printf '%s\n' "unexpected socks block" >&2
    exit 1
fi

expected="olcrtc://telemost?vp8channel<vp8-fps=30&vp8-batch=64>@${ROOM}#${KEY}\$OpenWRT-Telemost-srv"
if [ "$uri" != "$expected" ]; then
    printf '%s\n' "URI mismatch:" >&2
    printf '%s\n' " got: $uri" >&2
    printf '%s\n' "want: $expected" >&2
    exit 1
fi

yaml2=$(
    ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" DEBUG=true \
        UPSTREAM_PROXY_ADDR=127.0.0.1 UPSTREAM_PROXY_PORT=1080 \
        sh "$INSTALL" --dump-config
)
printf '%s\n' "$yaml2" | grep -q 'debug: true'
printf '%s\n' "$yaml2" | grep -q "proxy_addr: '127.0.0.1'"
printf '%s\n' "$yaml2" | grep -q 'proxy_port: 1080'

sh "$INSTALL" --help >/dev/null

if ROOM_ID='' ENCRYPTION_KEY="$KEY" sh "$INSTALL" --dump-config >/dev/null 2>&1; then
    printf '%s\n' "expected ROOM_ID failure" >&2
    exit 1
fi

yaml3=$(ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" DEBUG=1 sh "$INSTALL" --dump-config)
printf '%s\n' "$yaml3" | grep -q 'debug: false'

init=$(ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" sh "$INSTALL" --dump-init)
printf '%s\n' "$init" | grep -q 'PROG="/usr/bin/olcrtc"'
printf '%s\n' "$init" | grep -q 'CONF="/etc/olcrtc/server.yaml"'
printf '%s\n' "$init" | grep -q 'GOMEMLIMIT="80MiB"'

init2=$(
    ROOM_ID="$ROOM" ENCRYPTION_KEY="$KEY" \
        INSTALL_BIN=/opt/olcrtc CONFIG_FILE=/opt/olcrtc.yaml GOMEMLIMIT=64MiB \
        sh "$INSTALL" --dump-init
)
printf '%s\n' "$init2" | grep -q 'PROG="/opt/olcrtc"'
printf '%s\n' "$init2" | grep -q 'CONF="/opt/olcrtc.yaml"'
printf '%s\n' "$init2" | grep -q 'GOMEMLIMIT="64MiB"'

url=$(INSTALLER_RELEASE=v9.9.9 sh "$INSTALL" --dump-release-url)
want_url="https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v9.9.9"
if [ "$url" != "$want_url" ]; then
    printf '%s\n' "release URL mismatch: got $url want $want_url" >&2
    exit 1
fi

url_latest=$(INSTALLER_RELEASE='' RELEASE_BASE_URL='' sh "$INSTALL" --dump-release-url)
want_latest="https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download"
if [ "$url_latest" != "$want_latest" ]; then
    printf '%s\n' "latest URL mismatch: got $url_latest want $want_latest" >&2
    exit 1
fi

from_file=$(
    sed -e 's#@INSTALL_BIN@#/usr/bin/olcrtc#g' \
        -e 's#@CONFIG_FILE@#/etc/olcrtc/server.yaml#g' \
        -e 's#@GOMEMLIMIT@#80MiB#g' \
        "$ROOT/files/olcrtc-srv.init"
)
if [ "$init" != "$from_file" ]; then
    printf '%s\n' "init template drifted from files/olcrtc-srv.init" >&2
    exit 1
fi

tmpd="${TMPDIR:-/tmp}/olcrtc-prep-$$"
mkdir -p "$tmpd"
DIST="$tmpd" sh "$ROOT/scripts/prepare-release.sh" v0.0.1
head -n 1 "$tmpd/install.sh" | grep -q '^#!/bin/sh'
# shellcheck disable=SC2016
grep -q 'INSTALLER_RELEASE="${INSTALLER_RELEASE:-v0.0.1}"' "$tmpd/install.sh"
rm -rf "$tmpd"

printf '%s\n' "ALL_CHECKS_PASSED"
