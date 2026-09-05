# oneclick-olcrtc-wrt

**Версия `0.0.2`.** Прогнано на OpenWrt (Xiaomi AX3000-3600) + Yandex Telemost + [olcbox](https://github.com/alananisimov/olcbox). Добавлена однокомандная установка на **Debian 12/13, Ubuntu и другие Debian-family системы с systemd** (изолированные фикстуры установщика). Живой сеанс Debian/Ubuntu VDS → Telemost → olcbox **не проверялся**. Стабильный тег `v0.0.2` публикуется только пушем тега; `/releases/latest` до этого остаётся `v0.0.1`.

Однокомандная установка **текущего** [OlcRTC](https://github.com/openlibrecommunity/olcrtc) в режиме **`mode: srv`** на OpenWrt или Debian-family VDS.

Роутер или VDS становится выходным узлом через **Yandex Telemost + `vp8channel`**. Клиент заходит в ту же комнату и ходит в интернет через этот узел.

Это **не** клиентский TUN/LuCI-пакет вроде `alekvol/openwrt-olcrtc`. Старый CLI (`-mode cnc -carrier …`) и сборки v0.1.2 с текущими клиентами **не соединяются** (другой wire-format, OLC2).

Корень репозитория — исходники, не канал установки. Ставить нужно файлы из [GitHub Release](https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest). Стабильный тег публикуется только пушем тега, не каждым коммитом в `main`.

## Debian / Ubuntu на VDS

Нужны Debian 12/13, Ubuntu или другой дистрибутив с `ID_LIKE=debian`, работающий **systemd**, `apt-get`, доступ root или sudo, `x86_64/amd64` либо `aarch64/arm64`, доступ к GitHub и Telemost. Контейнер без systemd этот установщик отклонит до загрузки бинарника. Ориентир по RAM — от 512 МиБ; потребление под нагрузкой на VDS отдельно не измерялось.

Используется тот же Linux-бинарник из Release (`CGO_ENABLED=0`), сборка Go на VDS не нужна. Режим остаётся серверным: TUN, IP forwarding, NAT и входящий SOCKS-порт для этой схемы не требуются. Скрипт не меняет маршруты и правила firewall. Провайдер VDS должен разрешать исходящие соединения, необходимые Telemost/WebRTC.

После публикации тега `v0.0.2` (`/releases/latest` до этого — OpenWrt-only `v0.0.1`):

```sh
curl -fL -o /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.2/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Если `curl` нет, а есть `wget`:

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.2/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
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
curl -fL -o /tmp/olcrtc-uninstall.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.2/uninstall.sh && sudo sh /tmp/olcrtc-uninstall.sh
```

Проверить содержимое unit-файла без установки: `sh ./install.sh --dump-systemd`.

## Что нужно заранее (OpenWrt)

1. Создайте видеовстречу в [Телемосте](https://telemost.yandex.ru/) и скопируйте Room ID. Текущий OlcRTC **не умеет** создавать комнаты Telemost сам.
2. Роутер: OpenWrt, `uname -m` = `aarch64` или `x86_64`.
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
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

`ROOM_ID` должен стоять **перед `sh`**, не перед `wget`: иначе скрипт его не увидит.

Дальше скрипт **сам** скачает `olcrtc-linux-arm64` или `olcrtc-linux-amd64` из того же Release, сверит SHA-256, поставит `/usr/bin/olcrtc`, YAML и procd. Бинарник руками качать не нужно.

Свой ключ (64 hex) — добавьте `ENCRYPTION_KEY='…'` тоже перед `sh`. Если ключ не задан, при повторной установке берётся `/etc/olcrtc/server.yaml`, иначе генерируется новый.

Не используйте `sh -c "$(wget -qO- …)"` — при 404 получится пустой успешный `sh`. Pin на конкретный тег: замените `latest/download` на `download/v0.0.2`.

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

Проверен и работает из коробки с URI этого инсталлятора на OpenWrt: **[olcbox](https://github.com/alananisimov/olcbox)**. Тот же Room ID и ключ, что на сервере.

Не проверены на этой связке (рабочей инструкции нет): [owenclave](https://github.com/owenewans/owenclave), [veil](https://github.com/venterum/veil), голый `cnc`. owenclave с той же конфигурацией, что принимает olcbox, туннель не поднял.

Проверка на клиенте (порт слушает телефон / ПК, не роутер и не VDS):

```sh
curl --socks5-hostname 127.0.0.1:8808 https://icanhazip.com
```

Должен вернуться адрес выхода **роутера / VDS**.

## Удаление на OpenWrt

```sh
wget -O /tmp/olcrtc-uninstall.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/uninstall.sh && sh /tmp/olcrtc-uninstall.sh
```

## Бинарники

Их собирает **GitHub Actions** из зафиксированного коммита (`versions.env`) и кладёт **в GitHub Release**, не в корень репо. 

Ассеты: `install.sh`, `uninstall.sh`, `olcrtc-linux-arm64`, `olcrtc-linux-amd64`, `SHA256SUMS`, `OLCRTC_COMMIT.txt`.

**Не собирайте на роутере или VDS.** `scripts/build-olcrtc.sh` — мейнтейнер / CI.

## Проверка изменений установщика

```sh
sh scripts/check-installer.sh
python3 scripts/check-platforms.py
```

Вторая команда проверяет установку, повторную установку и удаление на изолированных файловых фикстурах Debian/Ubuntu/OpenWrt, выбор архитектуры, сохранение ключа, контроль SHA-256 и отказ при нестабильном процессе. Системные команды и загрузки подменены; root и сеть не требуются. Это не проверка реального systemd или соединения с Telemost. В CI добавлены проверки обоих путей установки и обязательных секций systemd unit-файла (`systemd-analyze verify` не используется). Существующая проверка ShellCheck сохранена.

## English

Version `0.0.2`. Tested on OpenWrt + Telemost + [olcbox](https://github.com/alananisimov/olcbox). This release adds Debian-family/systemd support (Debian 12/13, Ubuntu, `ID_LIKE=debian`), covered by isolated installer fixtures. A live Debian/Ubuntu VDS → Telemost → olcbox session has not been verified. `/releases/latest` stays OpenWrt-only `v0.0.1` until tag `v0.0.2` is pushed.

OpenWrt:

```sh
wget -O /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/latest/download/install.sh && ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Debian/Ubuntu VDS:

```sh
curl -fL -o /tmp/olcrtc-install.sh https://github.com/15230041523004/oneclick-olcrtc-wrt/releases/download/v0.0.2/install.sh && sudo env ROOM_ID='<telemost-room-id>' sh /tmp/olcrtc-install.sh
```

Put `ROOM_ID` on `sh`, not on `wget`/`curl`. That script downloads `olcrtc-linux-arm64` or `olcrtc-linux-amd64` from the same Release. Do not use `sh -c "$(wget -qO- …)"`. olcbox is the verified phone client on OpenWrt; owenclave / veil / raw `cnc` are unproven here. Supported RAM floor is **512 MiB**. See [docs/upstream.md](docs/upstream.md).

## License

MIT for the installer scripts. The shipped `olcrtc` binary is WTFPL, from [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc).
