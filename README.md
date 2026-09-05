# oneclick-olcrtc-wrt

**Версия `0.0.3-untested` — Pre-release.** Предыдущая версия `0.0.2` проверена на **Debian VDS**, а путь OpenWrt — на Xiaomi AX3000-3600 + Yandex Telemost + [olcbox](https://github.com/alananisimov/olcbox). Эта версия добавляет ARMv7 для **Raspberry Pi OS** и других Debian-family систем с systemd. Живой прогон на Raspberry Pi (служба, Telemost, olcbox, нагрузка) **ещё не сделан**.

Однокомандная установка **текущего** [OlcRTC](https://github.com/openlibrecommunity/olcrtc) в режиме **`mode: srv`** на OpenWrt или Debian-family VDS.

Роутер или VDS становится выходным узлом через **Yandex Telemost + `vp8channel`**. Клиент заходит в ту же комнату и ходит в интернет через этот узел.

Это **не** клиентский TUN/LuCI-пакет вроде `alekvol/openwrt-olcrtc`. Старый CLI (`-mode cnc -carrier …`) и сборки v0.1.2 с текущими клиентами **не соединяются** (другой wire-format, OLC2).

Ставить эту тестовую версию нужно из [Pre-release v0.0.3-untested](https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/tag/v0.0.3-untested). Команды ниже привязаны к нему: `latest` выбирает стабильный релиз и не включает этот Pre-release. При `VERSION=0.0.3-untested` push в `main` запускает сборку и публикацию этого Pre-release; ссылки заработают после успешного завершения release-workflow. Стабильный релиз публикуется отдельно пушем соответствующего тега.

## Debian / Ubuntu на VDS

Нужны Debian 12/13, Ubuntu, Raspberry Pi OS (`ID=debian` или `ID=raspbian`) или другой дистрибутив с `ID_LIKE=debian`, работающий **systemd**, `apt-get`, доступ root или sudo, `x86_64/amd64`, `aarch64/arm64` либо 32-bit `armv7l`, доступ к GitHub и Telemost. Контейнер без systemd этот установщик отклонит до загрузки бинарника. Ориентир по RAM — от 512 МиБ; потребление под нагрузкой на VDS и на Pi отдельно не измерялось.

Raspberry Pi 3B+ (Cortex-A53, 1 ГиБ): **64-bit** Raspberry Pi OS — уже путь `arm64` (тот же ELF, что на Debian VDS). **32-bit** Raspberry Pi OS (`uname -m=armv7l`, либо 64-bit ядро + 32-bit userland) ставит `olcrtc-linux-armv7`. Сборка этого ELF подтверждена; установка → служба → Telemost + olcbox на Pi **не прогонялись**.

Используется тот же Linux-бинарник из Release (`CGO_ENABLED=0`), сборка Go на VDS не нужна. Режим остаётся серверным: TUN, IP forwarding, NAT и входящий SOCKS-порт для этой схемы не требуются. Скрипт не меняет маршруты и правила firewall. Провайдер VDS должен разрешать исходящие соединения, необходимые Telemost/WebRTC.

С VDS (подставьте Room ID из Телемоста):

```sh
curl -fL -o /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Если `curl` нет, а есть `wget`:

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Уже root — без `sudo`: `env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh`. `sudo env` нужен, чтобы `ROOM_ID` не потерялся. Не используйте `sh -c "$(curl …)"`.

Скрипт определит Debian-family, при необходимости поставит `ca-certificates` через apt (`curl` — только если нет другого загрузчика), создаст YAML с правами `0600`, включит и запустит `olcrtc-srv.service`. Для службы сохранены `GOMEMLIMIT=80MiB`, `GOGC=50` и перезапуск через 5 секунд. По умолчанию служба работает от root, как на OpenWrt.

```sh
sudo systemctl status olcrtc-srv.service --no-pager
sudo journalctl -u olcrtc-srv.service -n 80 --no-pager
sudo systemctl restart olcrtc-srv.service
```

Импортируйте выданный `olcrtc://` URI в совместимый клиент. Проверку `curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com` выполняйте **на клиенте с локальным SOCKS5**: ожидается исходящий IP VDS. Статус `active` и постоянный PID подтверждают только работу процесса.

Повторная установка с тем же `ROOM_ID` и без `ENCRYPTION_KEY` сохранит существующий ключ. Остальные настройки при повторной установке нужно передать снова: YAML перезаписывается из параметров установщика.

Удаление (также удаляет конфигурацию и ключ):

```sh
curl -fL -o /tmp/olcrtc-uninstall.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/uninstall.sh && sudo sh /tmp/olcrtc-uninstall.sh
```

Проверить содержимое unit-файла без установки: `sh ./install.sh --dump-systemd`.

## Что нужно заранее (OpenWrt)

1. Создайте видеовстречу в [Телемосте](https://telemost.yandex.ru/) и скопируйте Room ID. Текущий OlcRTC **не умеет** создавать комнаты Telemost сам.
2. Роутер: OpenWrt, `uname -m` = `aarch64`, `x86_64` или `armv7l` (32-bit ARM — тот же `olcrtc-linux-armv7`, живой Telemost на Pi не прогнан).
3. RAM:
   - **512 МиБ — поддерживаемый минимум** (AX3600-класс);
   - 256 МиБ — только после отдельного soak, из коробки не обещаем;
   - 128 МиБ — **не поддерживается**.
4. Свободно ~50 МиБ на overlay **и** ~32 МиБ в `/tmp` (скачивание идёт в RAM-backed tmpfs).
5. На роутере есть `wget` (на OpenWrt это обычно `uclient-fetch`).
6. Роутер **только скачивает** готовые файлы из GitHub Release. Go/mage/исходники на коробку не ставятся.

## Установка на OpenWrt

С консоли роутера, одна строка (подставьте Room ID из Телемоста):

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

`ROOM_ID` должен стоять **перед `sh`**, не перед `wget`: иначе скрипт его не увидит.

Дальше скрипт **сам** скачает `olcrtc-linux-arm64`, `olcrtc-linux-amd64` или `olcrtc-linux-armv7` из того же Release, сверит SHA-256 и ELF (`EI_CLASS` / `e_machine`) **до** остановки действующей службы, поставит `/usr/bin/olcrtc`, YAML и procd. Бинарник руками качать не нужно.

Свой ключ (64 hex) — добавьте `ENCRYPTION_KEY='…'` тоже перед `sh`. Если ключ не задан, при повторной установке берётся `/etc/olcrtc/server.yaml`, иначе генерируется новый.

Не используйте `sh -c "$(wget -qO- …)"` — при 404 получится пустой успешный `sh`. Команды выше уже привязаны к конкретному тегу `v0.0.3-untested`.

**URI содержит ключ шифрования.** Не публикуйте его в issue, чате или скриншоте.

### Полезные переменные

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `ROOM_ID` | — | обязательный ID комнаты Telemost |
| `ENCRYPTION_KEY` | сгенерировать / переиспользовать | 64 hex |
| `DEBUG` | `false` | подробные логи OlcRTC |
| `VP8_FPS` / `VP8_BATCH_SIZE` | `30` / `64` | рекомендация upstream |
| `DNS_SERVER` | `8.8.8.8:53` | DNS на стороне `srv` |
| `ARCH_OVERRIDE` | `uname -m` + ELF userland | `arm64`, `amd64` или `armv7` |
| `BINARY_URL_ARM64` / `BINARY_URL_AMD64` / `BINARY_URL_ARMV7` | asset из того же Release | свой HTTPS URL |
| `UPSTREAM_PROXY_ADDR` | пусто | исходящий SOCKS5 для самого сервера |

`PROVIDER` и `TRANSPORT` зафиксированы: `telemost` + `vp8channel`.

## Что ставится

| Путь | Назначение |
|---|---|
| `/usr/bin/olcrtc` | current upstream, `CGO_ENABLED=0` |
| `/etc/olcrtc/server.yaml` | `mode: srv`, права `0600` |
| `/etc/init.d/olcrtc-srv` | procd на OpenWrt, `olcrtc /etc/olcrtc/server.yaml` |
| `/etc/systemd/system/olcrtc-srv.service` | автозапуск на Debian-family (вместо procd) |
| `/etc/sysupgrade.conf` | сохранить файлы при sysupgrade (только OpenWrt) |

Сервис: `START=95`, `respawn 3600 5 0` на OpenWrt; на systemd — `Restart=always` / `RestartSec=5s`. `GOMEMLIMIT=80MiB`. Входящего TCP-порта нет. DNAT не нужен.

Не ставятся: `kmod-tun`, `hev-socks5-tunnel`, LuCI, локальный SOCKS на роутере или VDS.

## Проверка на роутере

```sh
ubus call service list '{"name":"olcrtc-srv"}'
logread | grep -i olcrtc | tail -n 80
```

В JSON должно быть `"running": true`. В логе — `Link connected`. Это процесс и вход в комнату Telemost, не проверка телефона.

## Клиент

Проверен и работает из коробки с URI этого инсталлятора на **Debian VDS** и на **OpenWrt**: **[olcbox](https://github.com/alananisimov/olcbox)**. Тот же Room ID и ключ, что на сервере.

Не проверены на этой связке (рабочей инструкции нет): [owenclave](https://github.com/owenewans/owenclave), [veil](https://github.com/venterum/veil), голый `cnc`. owenclave с той же конфигурацией, что принимает olcbox, туннель не поднял.

Проверка на клиенте (порт слушает телефон / ПК, не роутер и не VDS):

```sh
curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com
```

Должен вернуться адрес выхода **роутера / VDS**.

## Удаление на OpenWrt

```sh
wget -O /tmp/olcrtc-uninstall.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/uninstall.sh && sh /tmp/olcrtc-uninstall.sh
```

## Бинарники

Их собирает **GitHub Actions** из зафиксированного коммита (`versions.env`) и кладёт **в GitHub Release**, не в корень репо. 

Ассеты: `install.sh`, `uninstall.sh`, `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, `olcrtc-linux-armv7`, `SHA256SUMS`, `OLCRTC_COMMIT.txt`.

**Не собирайте на роутере или VDS.** `scripts/build-olcrtc.sh` — мейнтейнер / CI.

## Проверка изменений установщика

```sh
sh scripts/check-installer.sh
python3 scripts/check-platforms.py
```

Вторая команда проверяет установку, повторную установку и удаление на изолированных файловых фикстурах Debian/Ubuntu/Raspbian/OpenWrt, выбор архитектуры (включая armv7l и 32-bit userland на aarch64), сохранение ключа, контроль SHA-256/ELF и отказ при нестабильном процессе. Системные команды и загрузки подменены; root и сеть не требуются. Это не проверка реального systemd или соединения с Telemost. В CI добавлены проверки обоих путей установки и обязательных секций systemd unit-файла (`systemd-analyze verify` не используется). Существующая проверка ShellCheck сохранена.

## English

Version `0.0.3-untested` is a **Pre-release**. Version `0.0.2` was live-tested on Debian VDS + Telemost + [olcbox](https://github.com/alananisimov/olcbox); OpenWrt (Xiaomi AX3000-3600) was verified on that scheme earlier. This version adds `olcrtc-linux-armv7` (`GOARCH=arm GOARM=7`); a live Raspberry Pi install → service → Telemost + olcbox soak has not been done. Use the explicit prerelease URLs below; `latest` continues to select a stable release.

OpenWrt:

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Debian/Ubuntu VDS:

```sh
curl -fL -o /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.3-untested/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Put `ROOM_ID` on `sh`, not on `wget`/`curl`. That script downloads `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, or `olcrtc-linux-armv7` from the same Release. Do not use `sh -c "$(wget -qO- …)"`. olcbox is the verified phone client on Debian VDS and OpenWrt; owenclave / veil / raw `cnc` are unproven here. ARMv7 is compile-supported, not live-tested on a Pi. Supported RAM floor is **512 MiB** (warning, not an install reject). See [docs/upstream.md](docs/upstream.md).

## License

MIT for the installer scripts. The shipped `olcrtc` binary is WTFPL, from [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc).
