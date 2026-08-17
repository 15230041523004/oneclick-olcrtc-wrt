# Upstream notes

This installer targets **current** [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) (YAML CLI, OLC2 wire-format). It does not use the old `-mode` / `-carrier` flags.

Pinned revision is in [`versions.env`](../versions.env). GitHub Releases of this repo ship `olcrtc-linux-arm64` and `olcrtc-linux-amd64` built from that commit with:

```text
CGO_ENABLED=0 GOOS=linux GOARCH=arm64|amd64
go build -trimpath -ldflags='-s -w' -o olcrtc-linux-<arch> ./cmd/olcrtc
```

Those flags match upstream `magefile.go` (`mage cross` Linux targets). GitHub Actions publishes a stable release only from a pushed `v*` tag that matches `VERSION` (no `-untested` / `-alpha` / `-rc` suffix). Do not clone or compile OlcRTC on the router. Supported RAM floor is 512 MiB.

## Documents used

| Document | Why |
|---|---|
| [settings.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/settings.md) | Telemost E2E matrix (`vp8channel` only), YAML fields, `vp8.fps` / `batch_size`, liveness, `mode: gen` cannot create Telemost rooms |
| [configuration.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/configuration.md) | CLI is a single YAML path argument |
| [uri.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md) | Compact `olcrtc://` client convention (`vp8-fps`, `vp8-batch`) |
| [manual.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/manual.md) | Go 1.26+, off-router cross-build, SOCKS5 check on the **client** |
| [OpenWrt procd init scripts](https://openwrt.org/docs/guide-developer/procd-init-scripts) | Foreground command, `respawn`, stdout/stderr |

## Combinations this installer will not use

- `alekvol/openwrt-olcrtc` v0.1.2 — client/TUN/LuCI, old CLI, old crypto record format (OLC2 will not connect)
- `Oleglog/Olcrtc_manager` prebuilts — fork wire-format; only pair with that fork’s clients
- Telemost + `datachannel` / `seichannel` — not supported by current upstream
- `cmd/olcrtc-cgo`, armv7, mips — not official `mage cross` Linux targets

Verified phone client for this installer: [alananisimov/olcbox](https://github.com/alananisimov/olcbox) (same Room ID + key / `olcrtc://` URI).

Unproven on this OpenWrt + Telemost path: [owenewans/owenclave](https://github.com/owenewans/owenclave), [venterum/veil](https://github.com/venterum/veil), and a self-built `cnc`. owenclave did not bring the tunnel up with the same config olcbox accepts.
