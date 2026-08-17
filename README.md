# oneclick-olcrtc-wrt

**Версия `0.0.1`.** Прогнано на OpenWrt (Xiaomi AX3000-3600) + Yandex Telemost + [olcbox](https://github.com/alananisimov/olcbox).

Однокомандная установка **текущего** [OlcRTC](https://github.com/openlibrecommunity/olcrtc) в режиме **`mode: srv`** на OpenWrt.

Роутер становится выходным узлом через **Yandex Telemost + `vp8channel`**. Клиент заходит в ту же комнату и ходит в интернет через WAN роутера.

Это **не** клиентский TUN/LuCI-пакет вроде `alekvol/openwrt-olcrtc`. Старый CLI (`-mode cnc -carrier …`) и сборки v0.1.2 с текущими клиентами **не соединяются** (другой wire-format, OLC2).

Корень репозитория — исходники, не канал установки. Ставить нужно файлы из [GitHub Release](https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest). Стабильный тег (`v0.0.1`) публикуется только пушем тега, не каждым коммитом в `main`.

## Что нужно заранее

1. Создайте видеовстречу в [Телемосте](https://telemost.yandex.ru/) и скопируйте Room ID. Текущий OlcRTC **не умеет** создавать комнаты Telemost сам.
2. Роутер: OpenWrt, `uname -m` = `aarch64` или `x86_64`.
3. RAM:
   - **512 МиБ — поддерживаемый минимум** (AX3600-класс);
   - 256 МиБ — только после отдельного soak, из коробки не обещаем;
   - 128 МиБ — **не поддерживается**.
4. Свободно ~50 МиБ на overlay **и** ~32 МиБ в `/tmp` (скачивание идёт в RAM-backed tmpfs).
5. На роутере есть `wget` (на OpenWrt это обычно `uclient-fetch`).
6. Роутер **только скачивает** готовые файлы из GitHub Release. Go/mage/исходники на коробку не ставятся.

## Установка

С консоли роутера, одна строка (подставьте Room ID из Телемоста):

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

`ROOM_ID` должен стоять **перед `sh`**, не перед `wget`: иначе скрипт его не увидит.

Дальше скрипт **сам** скачает `olcrtc-linux-arm64` или `olcrtc-linux-amd64` из того же Release, сверит SHA-256, поставит `/usr/bin/olcrtc`, YAML и procd. Бинарник руками качать не нужно.

Свой ключ (64 hex) — добавьте `ENCRYPTION_KEY='…'` тоже перед `sh`. Если ключ не задан, при повторной установке берётся `/etc/olcrtc/server.yaml`, иначе генерируется новый.

Не используйте `sh -c "$(wget -qO- …)"` — при 404 получится пустой успешный `sh`. Pin на конкретный тег: замените `latest/download` на `download/v0.0.1`.

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
| `BINARY_URL_ARM64` / `BINARY_URL_AMD64` | asset из того же Release | свой HTTPS URL |
| `UPSTREAM_PROXY_ADDR` | пусто | исходящий SOCKS5 для самого сервера |

`PROVIDER` и `TRANSPORT` зафиксированы: `telemost` + `vp8channel`.

## Что ставится

| Путь | Назначение |
|---|---|
| `/usr/bin/olcrtc` | current upstream, `CGO_ENABLED=0` |
| `/etc/olcrtc/server.yaml` | `mode: srv`, права `0600` |
| `/etc/init.d/olcrtc-srv` | procd, `olcrtc /etc/olcrtc/server.yaml` |
| `/etc/sysupgrade.conf` | сохранить файлы при sysupgrade |

Сервис: `START=95`, `respawn 3600 5 0`, `GOMEMLIMIT=80MiB`. Входящего TCP-порта нет. DNAT не нужен.

Не ставятся: `kmod-tun`, `hev-socks5-tunnel`, LuCI, локальный SOCKS на роутере.

## Проверка на роутере

```sh
ubus call service list '{"name":"olcrtc-srv"}'
logread | grep -i olcrtc | tail -n 80
```

В JSON должно быть `"running": true`. В логе — `Link connected`. Это процесс и вход в комнату Telemost, не проверка телефона.

## Клиент

Проверен и работает из коробки с URI этого инсталлятора: **[olcbox](https://github.com/alananisimov/olcbox)**. Тот же Room ID и ключ, что на роутере.

Не проверены на этой связке (рабочей инструкции нет): [owenclave](https://github.com/owenewans/owenclave), [veil](https://github.com/venterum/veil), голый `cnc`. owenclave с той же конфигурацией, что принимает olcbox, туннель не поднял.

Проверка на клиенте (порт слушает телефон / ПК, не роутер):

```sh
curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com
```

Должен вернуться адрес выхода **роутера / оператора роутера**.

## Удаление

```sh
wget -O /tmp/olcrtc-uninstall.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/uninstall.sh && sh /tmp/olcrtc-uninstall.sh
```

## Бинарники

Их собирает **GitHub Actions** из зафиксированного коммита (`versions.env`) и кладёт **в GitHub Release**, не в корень репо. Стабильный `0.0.1` выходит тегом `v0.0.1` (`/releases/latest`).

Ассеты: `install.sh`, `uninstall.sh`, `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, `SHA256SUMS`, `OLCRTC_COMMIT.txt`.

**Не собирайте на роутере.** `scripts/build-olcrtc.sh` — мейнтейнер / CI.

## English

Version `0.0.1`. Tested on OpenWrt + Telemost + [olcbox](https://github.com/alananisimov/olcbox). One line on the router:

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Put `ROOM_ID` on `sh`, not on `wget`. That script downloads `olcrtc-linux-arm64` or `olcrtc-linux-amd64` from the same Release. Do not use `sh -c "$(wget -qO- …)"`. olcbox is the verified phone client; owenclave / veil / raw `cnc` are unproven here. Supported RAM floor is **512 MiB**. See [docs/upstream.md](docs/upstream.md).

## License

MIT for the installer scripts. The shipped `olcrtc` binary is WTFPL, from [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc).
