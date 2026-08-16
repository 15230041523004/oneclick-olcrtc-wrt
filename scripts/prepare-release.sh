#!/bin/sh
# Bake INSTALLER_RELEASE into install.sh and stage release files in dist/.
# Usage: sh scripts/prepare-release.sh v0.0.1-untested
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG="${1:-}"

case "$TAG" in
    v[0-9]*) ;;
    *)
        printf '%s\n' "usage: $0 vX.Y.Z" >&2
        exit 1
        ;;
esac

DIST="${DIST:-$ROOT/dist}"
mkdir -p "$DIST"

# The repo line must stay exactly this so the substitution is unique.
# shellcheck disable=SC2016
src_line='INSTALLER_RELEASE="${INSTALLER_RELEASE:-}"'
dst_line="INSTALLER_RELEASE=\"\${INSTALLER_RELEASE:-${TAG}}\""

if ! grep -qxF "$src_line" "$ROOT/install.sh"; then
    printf '%s\n' "install.sh is missing the empty INSTALLER_RELEASE default" >&2
    exit 1
fi

sed "s#^${src_line}\$#${dst_line}#" "$ROOT/install.sh" >"$DIST/install.sh"
chmod 0755 "$DIST/install.sh"

if ! grep -q "INSTALLER_RELEASE=\"\${INSTALLER_RELEASE:-${TAG}}\"" "$DIST/install.sh"; then
    printf '%s\n' "failed to bake INSTALLER_RELEASE=$TAG into dist/install.sh" >&2
    exit 1
fi

baked_url="$(
    INSTALLER_RELEASE='' RELEASE_BASE_URL='' \
        sh "$DIST/install.sh" --dump-release-url
)"
want_url="https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/${TAG}"
if [ "$baked_url" != "$want_url" ]; then
    printf '%s\n' "baked release URL mismatch:" >&2
    printf '%s\n' " got: $baked_url" >&2
    printf '%s\n' "want: $want_url" >&2
    exit 1
fi

head -n 1 "$DIST/install.sh" | grep -q '^#!/bin/sh' || {
    printf '%s\n' "dist/install.sh lost its shebang" >&2
    exit 1
}

cp "$ROOT/uninstall.sh" "$DIST/uninstall.sh"
chmod 0755 "$DIST/uninstall.sh"
head -n 1 "$DIST/uninstall.sh" | grep -q '^#!/bin/sh' || {
    printf '%s\n' "dist/uninstall.sh lost its shebang" >&2
    exit 1
}

printf '%s\n' "prepared $DIST/install.sh and $DIST/uninstall.sh for $TAG"
