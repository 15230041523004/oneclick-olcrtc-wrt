# oneclick-olcrtc-wrt

Однокомандная установка **текущего** [OlcRTC](https://github.com/openlibrecommunity/olcrtc) в режиме **`mode: srv`** на OpenWrt.

Роутер становится выходным узлом через **Yandex Telemost + `vp8channel`**. Клиент (`cnc` / Android) заходит в ту же комнату и ходит в интернет через WAN роутера.

Это **не** клиентский TUN/LuCI-пакет вроде `alekvol/openwrt-olcrtc`. Старый CLI (`-mode cnc -carrier …`) и сборки v0.1.2 с текущими клиентами **не соединяются** (другой wire-format, OLC2).

## Что нужно заранее

1. Создайте видеовстречу в [Телемосте](https://telemost.yandex.ru/) и скопируйте Room ID. Текущий OlcRTC **не умеет** создавать комнаты Telemost сам.
2. Роутер: OpenWrt, `uname -m` = `aarch64` или `x86_64`, примерно 128 МиБ RAM и 50 МиБ свободной flash.
3. GitHub Release этого репозитория должен содержать `olcrtc-linux-arm64`, `olcrtc-linux-amd64` и `SHA256SUMS`. Роутер **только скачивает** готовый ELF. Go, mage и исходники OlcRTC на коробку не ставятся.

## Установка

```sh
ROOM_ID='<telemost-room-id>' \
sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/install.sh)"
```

Ключ можно задать явно (64 hex-символа). Если не задан — при повторной установке берётся ключ из `/etc/olcrtc/server.yaml`, иначе генерируется новый:

```sh
ROOM_ID='<telemost-room-id>' \
ENCRYPTION_KEY='<64-hex>' \
sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/install.sh)"
```

Скрипт ничего не спрашивает. Он скачивает pinned-бинарник из Releases этого репозитория, проверяет SHA-256, пишет YAML, ставит procd-сервис, включает автозапуск и печатает клиентский `olcrtc://` URI.

**URI содержит ключ шифрования.** Не публикуйте его в issue, чате или скриншоте.

### Полезные переменные

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `ROOM_ID` | — | обязательный ID комнаты Telemost |
| `ENCRYPTION_KEY` | сгенерировать / переиспользовать | 64 hex |
| `DEBUG` | `false` | подробные логи OlcRTC |
| `VP8_FPS` / `VP8_BATCH_SIZE` | `30` / `64` | рекомендация upstream |
| `DNS_SERVER` | `8.8.8.8:53` | DNS на стороне `srv` |
| `ARCH_OVERRIDE` | `uname -m` | `arm64` или `amd64` |
| `BINARY_URL_ARM64` / `BINARY_URL_AMD64` | asset из Releases | свой HTTPS URL |
| `UPSTREAM_PROXY_ADDR` | пусто | исходящий SOCKS5 для самого сервера |

`PROVIDER` и `TRANSPORT` зафиксированы: `telemost` + `vp8channel`.

## Что ставится

| Путь | Назначение |
|---|---|
| `/usr/bin/olcrtc` | current upstream, `CGO_ENABLED=0` |
| `/etc/olcrtc/server.yaml` | `mode: srv`, права `0600` |
| `/etc/init.d/olcrtc-srv` | procd, `olcrtc /etc/olcrtc/server.yaml` |
| `/etc/sysupgrade.conf` | сохранить файлы при sysupgrade |

Сервис: `START=95`, `respawn 3600 5 0` (бесконечные перезапуски — удобно, когда LTE поднимается позже procd). Входящего TCP-порта нет: `mode: srv` сам ходит наружу через WebRTC. Проброс портов и DNAT не нужны. CGNAT оператора не мешает **входящему** TCP, но Telemost/WebRTC оператор всё равно должен пропускать.

Не ставятся: `kmod-tun`, `hev-socks5-tunnel`, LuCI, локальный SOCKS на роутере.

## Проверка на роутере

```sh
ubus call service list '{"name":"olcrtc-srv"}'
logread | grep -i olcrtc | tail -n 80
/etc/init.d/olcrtc-srv restart
```

В JSON instance должно быть `"running": true`.

## Клиент

Нужен **текущий** OLC2-клиент с тем же Room ID и ключом: [owenclave](https://github.com/owenewans/owenclave), [veil](https://github.com/venterum/veil), [olcbox](https://github.com/alananisimov/olcbox) или свой `cnc` из того же поколения, что и серверный бинарник.

Пример клиентского YAML (порт 8808 слушает **телефон / ПК**, не роутер):

```yaml
mode: cnc
auth:
  provider: telemost
room:
  id: '<тот же Room ID>'
crypto:
  key: '<тот же 64-hex ключ>'
net:
  transport: vp8channel
  dns: '8.8.8.8:53'
socks:
  host: '127.0.0.1'
  port: 8808
vp8:
  fps: 30
  batch_size: 64
```

Проверка туннеля на клиенте:

```sh
curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com
```

Должен вернуться адрес выхода **роутера / оператора роутера**.

## Удаление

```sh
sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/uninstall.sh)"
```

## Бинарники

У `openlibrecommunity/olcrtc` нет официальных Release binaries. Их собирает **GitHub Actions** этого репозитория из зафиксированного коммита (`versions.env`):

```text
CGO_ENABLED=0 GOOS=linux GOARCH=arm64|amd64
go build -trimpath -ldflags='-s -w' -o olcrtc-linux-<arch> ./cmd/olcrtc
```

Ассеты релиза: `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, `SHA256SUMS`, `OLCRTC_COMMIT.txt`.

**Не делайте этого на роутере:** не ставьте Go/mage, не клонируйте `olcrtc` на overlay, не запускайте `scripts/build-olcrtc.sh`. На типичном LTE-роутере (в том числе AX3600) не хватит RAM и flash; upstream сам предупреждает, что при < 4 ГиБ RAM сборке нужен swap.

`scripts/build-olcrtc.sh` — только для мейнтейнера / CI. Пользователю достаточно one-liner выше.

Релиз: тег `v*` или Actions → `release` → Run workflow.

## English

One-command OpenWrt installer for **current** OlcRTC `mode: srv` using **Yandex Telemost + `vp8channel`**. The router is the exit node. Create a Telemost room first, then:

```sh
ROOM_ID='<telemost-room-id>' \
sh -c "$(wget -qO- https://raw.githubusercontent.com/15230041523004/oneclick-olcrtc-wrt/main/install.sh)"
```

The router only downloads a GitHub Release ELF. Do not install Go on the router and do not run `scripts/build-olcrtc.sh` there. Do not use `alekvol/openwrt-olcrtc` v0.1.2 binaries with a modern phone client. See [docs/upstream.md](docs/upstream.md).

## License

MIT for the installer scripts in this repository. The shipped `olcrtc` binary is WTFPL, from [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc).
