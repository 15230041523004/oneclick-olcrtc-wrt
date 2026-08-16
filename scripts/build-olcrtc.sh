#!/bin/sh
# Clone the pinned openlibrecommunity/olcrtc commit and cross-build
# linux/arm64 + linux/amd64 with the same flags as upstream magefile.go.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/versions.env"

: "${OLCRTC_REPO:?OLCRTC_REPO missing in versions.env}"
: "${OLCRTC_COMMIT:?OLCRTC_COMMIT missing in versions.env}"

DIST="${DIST:-$ROOT/dist}"
WORKDIR="${WORKDIR:-$ROOT/.build/olcrtc}"

command -v git >/dev/null 2>&1 || {
    printf '%s\n' "git is required" >&2
    exit 1
}
command -v go >/dev/null 2>&1 || {
    printf '%s\n' "go is required (want ${GO_VERSION:-1.26+})" >&2
    exit 1
}

rm -rf "$DIST"
mkdir -p "$DIST"

if [ -d "$WORKDIR/.git" ]; then
    git -C "$WORKDIR" fetch --tags --recurse-submodules origin
    git -C "$WORKDIR" checkout --force "$OLCRTC_COMMIT"
    git -C "$WORKDIR" submodule update --init --recursive
else
    rm -rf "$WORKDIR"
    git clone --recurse-submodules "$OLCRTC_REPO" "$WORKDIR"
    git -C "$WORKDIR" checkout --force "$OLCRTC_COMMIT"
    git -C "$WORKDIR" submodule update --init --recursive
fi

actual="$(git -C "$WORKDIR" rev-parse HEAD)"
if [ "$actual" != "$OLCRTC_COMMIT" ]; then
    printf '%s\n' "commit mismatch: wanted $OLCRTC_COMMIT got $actual" >&2
    exit 1
fi

build_one() {
    arch=$1
    out="olcrtc-linux-$arch"
    printf '%s\n' "building $out from $OLCRTC_COMMIT"
    (
        cd "$WORKDIR" || exit 1
        CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
            go build -trimpath -ldflags='-s -w' -o "$DIST/$out" ./cmd/olcrtc
    )
    [ -s "$DIST/$out" ] || {
        printf '%s\n' "build produced empty $out" >&2
        exit 1
    }
}

build_one arm64
build_one amd64

(
    cd "$DIST" || exit 1
    sha256sum olcrtc-linux-arm64 olcrtc-linux-amd64 >SHA256SUMS
)

printf '%s\n' "$OLCRTC_COMMIT" >"$DIST/OLCRTC_COMMIT.txt"

printf '%s\n' "built:"
ls -l "$DIST"
cat "$DIST/SHA256SUMS"
