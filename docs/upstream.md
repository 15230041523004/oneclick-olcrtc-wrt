# Upstream notes

This installer targets **current** [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc) (YAML CLI, OLC2 wire-format). It does not use the old `-mode` / `-carrier` flags.

Pinned revision is in [`versions.env`](../versions.env). GitHub Releases of this repo ship `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, and `olcrtc-linux-armv7` built from that commit with:

```text
CGO_ENABLED=0 GOOS=linux GOARCH=arm64|amd64
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7
go build -trimpath -ldflags='-s -w' -o olcrtc-linux-<name> ./cmd/olcrtc
```

`linux/arm64` and `linux/amd64` match upstream `magefile.go` (`mage cross` Linux targets). `linux/arm` `GOARM=7` is an extra target for 32-bit Raspberry Pi OS / `armv7l`; it is **not** an official `mage cross` platform. GitHub Actions publishes a stable release only from a pushed `v*` tag that matches `VERSION` (no `-untested` / `-alpha` / `-rc` suffix). Do not clone or compile OlcRTC on the router, VDS, or Pi. 512 MiB is a MemAvailable **warning**, not an install reject.

The same Linux ELF is used on OpenWrt (procd) and on Debian-family VDS (systemd). The systemd unit is a foreground `Type=simple` service with `Restart=always` / `RestartSec=5s`, matching procd `respawn 3600 5 0`.

## Documents used

| Document | Why |
|---|---|
| [settings.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/settings.md) | Telemost E2E matrix (`vp8channel` only), YAML fields, `vp8.fps` / `batch_size`, liveness, `mode: gen` cannot create Telemost rooms |
| [configuration.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/configuration.md) | CLI is a single YAML path argument |
| [uri.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md) | Compact `olcrtc://` client convention (`vp8-fps`, `vp8-batch`) |
| [manual.md](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/manual.md) | Go 1.26+, off-router cross-build, SOCKS5 check on the **client** |
| [OpenWrt procd init scripts](https://openwrt.org/docs/guide-developer/procd-init-scripts) | Foreground command, `respawn`, stdout/stderr |
| [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) | Debian/Ubuntu VDS unit: `Type=simple`, `Restart=always` |

## Combinations this installer will not use

- `alekvol/openwrt-olcrtc` v0.1.2 — client/TUN/LuCI, old CLI, old crypto record format (OLC2 will not connect)
- `Oleglog/Olcrtc_manager` prebuilts — fork wire-format; only pair with that fork’s clients
- Telemost + `datachannel` / `seichannel` — not supported by current upstream
- `cmd/olcrtc-cgo`, mips — not shipped (not official `mage cross` Linux targets)
- armv7 — shipped as `olcrtc-linux-armv7` (`GOARM=7`); not an official `mage cross` target

Phone client for this installer: [alananisimov/olcbox](https://github.com/alananisimov/olcbox) (same Room ID + key / `olcrtc://` URI).

Not this installer: [owenewans/owenclave](https://github.com/owenewans/owenclave), [venterum/veil](https://github.com/venterum/veil), and a self-built `cnc`.
