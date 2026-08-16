# oneclick-olcrtc-wrt

**Версия `0.0.1-untested`.** Пока нет прогона на живом OpenWrt + Telemost + клиент. Это не релиз для продакшена: нет Release GO (публичных assets) и нет Deployment GO.

Однокомандная установка **текущего** [OlcRTC](https://github.com/openlibrecommunity/olcrtc) в режиме **`mode: srv`** на OpenWrt.

Роутер становится выходным узлом через **Yandex Telemost + `vp8channel`**. Клиент (`cnc` / Android) заходит в ту же комнату и ходит в интернет через WAN роутера.

Это **не** клиентский TUN/LuCI-пакет вроде `alekvol/openwrt-olcrtc`. Старый CLI (`-mode cnc -carrier …`) и сборки v0.1.2 с текущими клиентами **не соединяются** (другой wire-format, OLC2).

Два разных статуса готовности:

| Статус | Что значит |
|---|---|
| **Release GO** | URL релиза отвечают, installer запускается, 404/HTML не маскируются, procd **стабильно** держит процесс |
| **Deployment GO** | после reboot клиент проходит `curl --socks5-hostname 127.0.0.1:8808` через ту же Telemost-комнату |

Этот репозиторий закрывает Release GO после публикации тега. Deployment GO проверяется на роутере и телефоне.

## Что нужно заранее

1. Создайте видеовстречу в [Телемосте](https://telemost.yandex.ru/) и скопируйте Room ID. Текущий OlcRTC **не умеет** создавать комнаты Telemost сам.
2. Роутер: OpenWrt, `uname -m` = `aarch64` или `x86_64`.
3. RAM:
   - **512 МиБ — поддерживаемый минимум** (AX3600-класс);
   - 256 МиБ — только после отдельного soak, из коробки не обещаем;
   - 128 МиБ — **не поддерживается**.
4. Свободно ~50 МиБ на overlay **и** ~32 МиБ в `/tmp` (скачивание идёт в RAM-backed tmpfs).
5. На роутере есть `wget` **или** `uclient-fetch`.
6. Релиз этого репозитория содержит `install.sh`, `uninstall.sh`, оба ELF и `SHA256SUMS`. Роутер **только скачивает**. Go/mage/исходники на коробку не ставятся.

## Установка

Не используйте `sh -c "$(wget -qO- …)"`: при 404 это даёт пустой успешный `sh -c`.

```sh
INSTALL_URL='https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh'
rm -f /tmp/olcrtc-install.sh
if command -v wget >/dev/null 2>&1; then
    wget -O /tmp/olcrtc-install.sh "$INSTALL_URL" || exit 1
elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -O /tmp/olcrtc-install.sh "$INSTALL_URL" || exit 1
else
    echo "need wget or uclient-fetch" >&2
    exit 1
fi
head -n 1 /tmp/olcrtc-install.sh | grep -q '^#!/bin/sh' || exit 1
ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Свой ключ (64 hex) — та же схема, плюс `ENCRYPTION_KEY='…'` перед `sh /tmp/olcrtc-install.sh`. Если ключ не задан, при повторной установке берётся `/etc/olcrtc/server.yaml`, иначе генерируется новый.

Скачанный `install.sh` уже привязан к **тому же тегу**, что и бинарники. Скрипт ничего не спрашивает: качает ELF, проверяет SHA-256 и что это ELF, пишет YAML, ставит procd, ждёт несколько подряд `running: true`, иначе выходит с кодом 1.

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

## Проверка (Release GO на роутере)

```sh
ubus call service list '{"name":"olcrtc-srv"}'
logread | grep -i olcrtc | tail -n 80
```

Несколько выборок подряд должны показывать `"running": true`. Это процесс, не туннель.

## Клиент (Deployment GO)

Нужен **текущий** OLC2-клиент с тем же Room ID и ключом: [owenclave](https://github.com/owenewans/owenclave), [veil](https://github.com/venterum/veil), [olcbox](https://github.com/alananisimov/olcbox) или свой `cnc`.

После reboot роутера, на клиенте:

```sh
curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com
```

Должен вернуться адрес выхода **роутера / оператора роутера**. Порт 8808 слушает телефон/ПК, не роутер.

## Удаление

Тот же fetch, URL `.../releases/latest/download/uninstall.sh`, затем `sh /tmp/olcrtc-uninstall.sh`.

## Бинарники

Их собирает **GitHub Actions** из зафиксированного коммита (`versions.env`) и кладёт в Release **только по push тега `v*`**. Ручной `workflow_dispatch` отключён: иначе можно собрать `main` и подписать чужим тегом.

Ассеты: `install.sh`, `uninstall.sh`, `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, `SHA256SUMS`, `OLCRTC_COMMIT.txt`.

**Не собирайте на роутере.** `scripts/build-olcrtc.sh` — мейнтейнер / CI.

## English

Release GO: GitHub Release assets + installer that fails closed. Deployment GO: reboot and a phone SOCKS check. Supported RAM floor is **512 MiB**. Fetch `install.sh` from `releases/latest/download` with `wget` or `uclient-fetch` into a file; do not pipe wget into `sh -c`. See [docs/upstream.md](docs/upstream.md).

## License

MIT for the installer scripts. The shipped `olcrtc` binary is WTFPL, from [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc).
