#!/usr/bin/env python3
"""Isolated install/uninstall fixtures. No real root and no network."""

from __future__ import annotations

import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.sh"
UNINSTALL = ROOT / "uninstall.sh"

KEY = "c8fa447c6d5c42f17a834dc44ec22c5322d62c274c0d2c51cb533aa2bf853619"
ROOM = "1234567890123456789"
ELF = b"\x7fELF" + b"\0" * 64
ELF_SHA = hashlib.sha256(ELF).hexdigest()

NEED_TOOLS = (
    "awk",
    "sed",
    "grep",
    "head",
    "tr",
    "cat",
    "chmod",
    "mkdir",
    "mv",
    "rm",
    "rmdir",
    "touch",
    "sleep",
    "dd",
    "mktemp",
    "sha256sum",
    "dirname",
    "basename",
    "env",
    "printf",
    "cut",
    "cp",
    "true",
    "false",
)


class Fail(Exception):
    pass


class Skip(Exception):
    pass


def find_sh() -> str:
    for name in ("sh", "dash", "bash"):
        path = shutil.which(name)
        if path:
            return path
    raise Fail("no POSIX sh on PATH")


SH = find_sh()


def posix_path(path: Path) -> str:
    text = path.resolve().as_posix()
    if len(text) >= 2 and text[1] == ":":
        text = "/" + text[0].lower() + text[2:]
    return text


def write_exec(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8", newline="\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def copy_tool(fakebin: Path, name: str) -> None:
    src = shutil.which(name)
    if src is None:
        return
    dest = fakebin / name
    if dest.exists():
        return
    if os.name == "nt" and src.lower().endswith(".exe"):
        exe = fakebin / (name + ".exe")
        shutil.copy(src, exe)
        write_exec(dest, '#!/bin/sh\nexec "%s" "$@"\n' % posix_path(exe))
        return
    shutil.copy(src, dest)
    dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class Fixture:
    def __init__(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="olcrtc-plat-"))
        self.bin = self.tmp / "bin"
        self.state = self.tmp / "state"
        self.assets = self.tmp / "assets"
        self.root = self.tmp / "root"
        self.tmpdir = self.tmp / "tmp"
        for d in (self.bin, self.state, self.assets, self.root, self.tmpdir):
            d.mkdir()

        self.install_bin = self.root / "usr" / "bin" / "olcrtc"
        self.config_dir = self.root / "etc" / "olcrtc"
        self.config_file = self.config_dir / "server.yaml"
        self.init_file = self.root / "etc" / "init.d" / "olcrtc-srv"
        self.unit_file = self.root / "etc" / "systemd" / "system" / "olcrtc-srv.service"
        self.sysupgrade = self.root / "etc" / "sysupgrade.conf"
        self.os_release = self.root / "etc" / "os-release"
        self.ca_certs = self.root / "etc" / "ssl" / "certs" / "ca-certificates.crt"
        self.ssl_cert = self.root / "etc" / "ssl" / "cert.pem"
        self.rc_common = self.tmp / "rc.common"
        (self.root / "etc" / "ssl" / "certs").mkdir(parents=True)
        (self.root / "usr" / "bin").mkdir(parents=True)
        (self.root / "etc" / "init.d").mkdir(parents=True)
        (self.root / "etc" / "systemd" / "system").mkdir(parents=True)
        self.ca_certs.parent.mkdir(parents=True, exist_ok=True)
        self.ca_certs.write_bytes(b"dummy-ca\n")

        (self.assets / "olcrtc-linux-amd64").write_bytes(ELF)
        (self.assets / "olcrtc-linux-arm64").write_bytes(ELF)
        (self.assets / "SHA256SUMS").write_text(
            f"{ELF_SHA}  olcrtc-linux-amd64\n{ELF_SHA}  olcrtc-linux-arm64\n",
            encoding="utf-8",
        )
        (self.assets / "OLCRTC_COMMIT.txt").write_text("deadbeef\n", encoding="utf-8")
        self.rc_common.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8", newline="\n")

        if os.name != "nt":
            for name in NEED_TOOLS:
                copy_tool(self.bin, name)

        write_exec(
            self.bin / "id",
            "#!/bin/sh\nprintf '%s\\n' 0\n",
        )
        write_exec(
            self.bin / "uname",
            "#!/bin/sh\n[ \"$1\" = -m ] && printf '%s\\n' x86_64 && exit 0\nprintf '%s\\n' Linux\n",
        )
        write_exec(
            self.bin / "df",
            "#!/bin/sh\nprintf '%s\\n' 'Filesystem 1K-blocks Used Available Use% Mounted on'\n"
            "printf '%s\\n' '/dev/x 10000000 1 9999999 1% /'\n",
        )
        self._write_wget()
        self._write_systemctl()
        self._write_apt()
        self._write_ubus()

        self.env = os.environ.copy()
        # Isolated PATH: stubs in fakebin win over host tools.
        # Git bash on Windows still needs /usr/bin for awk/sed/sha256sum.
        self.path_value = posix_path(self.bin)
        if os.name == "nt":
            self.path_value += ":/usr/bin:/bin"
        self.env["PATH"] = self.path_value
        self.env["TMPDIR"] = posix_path(self.tmpdir)
        self.env["ROOM_ID"] = ROOM
        self.env["ENCRYPTION_KEY"] = KEY
        self.env["OS_RELEASE_FILE"] = posix_path(self.os_release)
        self.env["INSTALL_BIN"] = posix_path(self.install_bin)
        self.env["CONFIG_DIR"] = posix_path(self.config_dir)
        self.env["CONFIG_FILE"] = posix_path(self.config_file)
        self.env["INIT_FILE"] = posix_path(self.init_file)
        self.env["SYSTEMD_UNIT_FILE"] = posix_path(self.unit_file)
        self.env["SYSUPGRADE_CONF"] = posix_path(self.sysupgrade)
        self.env["CA_CERTS_FILE"] = posix_path(self.ca_certs)
        self.env["SSL_CERT_FILE"] = posix_path(self.ssl_cert)
        self.env["SERVICE_NAME"] = "olcrtc-srv"
        self.env["ARCH_OVERRIDE"] = "amd64"
        self.env["RELEASE_BASE_URL"] = "https://example.test/v0.0.2"
        self.env["GITHUB_REPO"] = "15230041523004/oneclick-olcrtc-wrt"
        self.env["STABLE_NEEDED"] = "1"
        self.env["STABLE_INTERVAL"] = "1"
        self.env["STABLE_MAX"] = "3"
        self.env["OLCRTC_FAKE_STATE"] = posix_path(self.state)
        self.env["OLCRTC_FAKE_ASSETS"] = posix_path(self.assets)
        self.env["OLCRTC_FAKE_BIN"] = posix_path(self.bin)
        self.env.pop("DEBUG", None)

        (self.state / "pid").write_text("4242\n", encoding="utf-8", newline="\n")
        (self.state / "pid_mode").write_text("stable\n", encoding="utf-8", newline="\n")
        (self.state / "systemd_running").write_text("1\n", encoding="utf-8", newline="\n")
        (self.state / "active").write_text("1\n", encoding="utf-8", newline="\n")

    def _write_wget(self) -> None:
        write_exec(
            self.bin / "wget",
            r"""#!/bin/sh
set -eu
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        -qO-|-q) shift ;;
        *) url="$1"; shift ;;
    esac
done
base="${url##*/}"
src="${OLCRTC_FAKE_ASSETS}/${base}"
[ -n "$out" ] || exit 1
[ -f "$src" ] || exit 1
cp "$src" "$out"
printf '%s\n' "$url -> $out" >>"${OLCRTC_FAKE_STATE}/wget.log"
""",
        )

    def _write_curl(self) -> None:
        write_exec(
            self.bin / "curl",
            r"""#!/bin/sh
set -eu
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -f|-L|--retry) shift ;;
        --retry) shift 2 ;;
        -fL) shift ;;
        *) url="$1"; shift ;;
    esac
done
base="${url##*/}"
src="${OLCRTC_FAKE_ASSETS}/${base}"
[ -n "$out" ] || exit 1
[ -f "$src" ] || exit 1
cp "$src" "$out"
printf '%s\n' "$url -> $out" >>"${OLCRTC_FAKE_STATE}/curl.log"
""",
        )

    def _write_systemctl(self) -> None:
        write_exec(
            self.bin / "systemctl",
            r"""#!/bin/sh
set -eu
STATE="${OLCRTC_FAKE_STATE}"
printf '%s\n' "$*" >>"${STATE}/systemctl.log"
if [ "${1:-}" = show-environment ]; then
    [ -f "${STATE}/systemd_running" ] || exit 1
    exit 0
fi
if [ "${1:-}" = is-active ]; then
    [ -f "${STATE}/active" ] || exit 3
    mode="$(tr -d ' \n\r' <"${STATE}/pid_mode" 2>/dev/null || true)"
    [ "$mode" != missing ] || exit 3
    exit 0
fi
if [ "${1:-}" = show ]; then
    mode="$(tr -d ' \n\r' <"${STATE}/pid_mode" 2>/dev/null || true)"
    case "$mode" in
        zero) printf '%s\n' 0 ;;
        missing) printf '%s\n' "" ;;
        changing)
            n="$(tr -d ' \n\r' <"${STATE}/pid" 2>/dev/null || printf 100)"
            n=$((n + 1))
            printf '%s\n' "$n" >"${STATE}/pid"
            printf '%s\n' "$n"
            ;;
        *) tr -d ' \n\r' <"${STATE}/pid"; printf '\n' ;;
    esac
    exit 0
fi
if [ "${1:-}" = stop ]; then
    [ -f "${STATE}/stop_fail" ] && exit 1
    exit 0
fi
if [ "${1:-}" = disable ]; then
    [ -f "${STATE}/disable_fail" ] && exit 1
    exit 0
fi
exit 0
""",
        )

    def _write_apt(self) -> None:
        write_exec(
            self.bin / "apt-get",
            r"""#!/bin/sh
set -eu
printf 'DEBIAN_FRONTEND=%s args=%s\n' "${DEBIAN_FRONTEND-}" "$*" >>"${OLCRTC_FAKE_STATE}/apt.log"
curl_wanted=0
for arg in "$@"; do
    [ "$arg" = curl ] && curl_wanted=1
done
if [ "$curl_wanted" -eq 1 ]; then
    cat >"${OLCRTC_FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
set -eu
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        --retry) shift 2 ;;
        -f|-L|-fL) shift ;;
        *) url="$1"; shift ;;
    esac
done
base="${url##*/}"
src="${OLCRTC_FAKE_ASSETS}/${base}"
[ -n "$out" ] || exit 1
[ -f "$src" ] || exit 1
cp "$src" "$out"
printf '%s\n' "$url -> $out" >>"${OLCRTC_FAKE_STATE}/curl.log"
EOF
    chmod 0755 "${OLCRTC_FAKE_BIN}/curl"
fi
exit 0
""",
        )

    def _write_ubus(self) -> None:
        write_exec(
            self.bin / "ubus",
            r"""#!/bin/sh
set -eu
STATE="${OLCRTC_FAKE_STATE}"
mode="$(tr -d ' \n\r' <"${STATE}/pid_mode" 2>/dev/null || true)"
case "$mode" in
    missing)
        printf '%s\n' '{"olcrtc-srv":{"running": false}}'
        exit 0
        ;;
    zero)
        printf '%s\n' '{"olcrtc-srv":{"running": true, "pid": 0}}'
        exit 0
        ;;
    changing)
        n="$(tr -d ' \n\r' <"${STATE}/pid" 2>/dev/null || printf 100)"
        n=$((n + 1))
        printf '%s\n' "$n" >"${STATE}/pid"
        printf '%s\n' "{\"olcrtc-srv\":{\"running\": true, \"pid\": ${n}}}"
        exit 0
        ;;
esac
pid="$(tr -d ' \n\r' <"${STATE}/pid" 2>/dev/null || printf 4242)"
printf '%s\n' "{\"olcrtc-srv\":{\"running\": true, \"pid\": ${pid}}}"
""",
        )

    def write_os(self, os_id: str, id_like: str = "") -> None:
        lines = [f"ID={os_id}"]
        if id_like:
            lines.append(f"ID_LIKE=\"{id_like}\"")
        self.os_release.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")

    def hide_ca(self) -> None:
        if self.ca_certs.exists():
            self.ca_certs.unlink()
        if self.ssl_cert.exists():
            self.ssl_cert.unlink()
        missing = self.tmp / "missing-ca"
        self.env["CA_CERTS_FILE"] = posix_path(missing / "ca-certificates.crt")
        self.env["SSL_CERT_FILE"] = posix_path(missing / "cert.pem")

    def drop_downloaders(self) -> None:
        for name in ("wget", "curl", "uclient-fetch"):
            path = self.bin / name
            if path.exists():
                path.unlink()

    def cleanup(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run(self, script: Path, args: list[str] | None = None, extra_env: dict | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        lf_script = self.tmp / Path(script).name
        lf_script.write_text(
            Path(script).read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n"),
            encoding="utf-8",
            newline="\n",
        )
        posix_script = posix_path(lf_script)
        cmd = [
            SH,
            "-c",
            'PATH="$1"; export PATH; shift; script="$1"; shift; . "$script"',
            "run",
            self.path_value,
            posix_script,
            *(args or []),
        ]
        if self.os_release.exists() and "ID=openwrt" in self.os_release.read_text(encoding="utf-8"):
            cmd = self._unshare_cmd(cmd)
        proc = subprocess.run(
            cmd,
            env=env,
            cwd=str(ROOT),
            text=True,
            capture_output=True,
            check=False,
        )
        if check and proc.returncode != 0:
            raise Fail(
                f"{script.name} failed ({proc.returncode})\n"
                f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
            )
        return proc

    def _unshare_cmd(self, cmd: list[str]) -> list[str]:
        unshare = shutil.which("unshare")
        if unshare is None:
            return cmd
        mount = "/bin/mount"
        if not Path(mount).exists():
            mount = shutil.which("mount") or "mount"
        inner = f'"{mount}" --bind "$1" /etc/rc.common && shift && exec "$@"'
        return [
            unshare,
            "--user",
            "--map-root-user",
            "--mount",
            SH,
            "-c",
            inner,
            "_",
            str(self.rc_common),
            *cmd,
        ]


def expect_ok(proc: subprocess.CompletedProcess[str], label: str) -> None:
    if proc.returncode != 0:
        raise Fail(f"{label}: expected success, got {proc.returncode}\n{proc.stderr}\n{proc.stdout}")


def expect_fail(proc: subprocess.CompletedProcess[str], label: str, needle: str = "") -> None:
    if proc.returncode == 0:
        raise Fail(f"{label}: expected failure\n{proc.stdout}\n{proc.stderr}")
    blob = proc.stdout + proc.stderr
    if needle and needle not in blob:
        raise Fail(f"{label}: missing {needle!r} in output\n{blob}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_debian_install() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        proc = fx.run(INSTALL)
        expect_ok(proc, "debian install")
        if "OS:             debian" not in proc.stdout:
            raise Fail("debian OS id not preserved")
        if not fx.unit_file.is_file():
            raise Fail("debian missing systemd unit")
        if fx.init_file.exists():
            raise Fail("debian wrote procd init")
        if fx.sysupgrade.exists():
            raise Fail("debian wrote sysupgrade.conf")
        yaml = read(fx.config_file)
        if "mode: srv" not in yaml or KEY not in yaml:
            raise Fail("debian yaml missing")
        if b"\x7fELF" != fx.install_bin.read_bytes()[:4]:
            raise Fail("debian binary is not ELF")
        if "Debian-Telemost-srv" not in proc.stdout:
            raise Fail("debian URI label missing")
    finally:
        fx.cleanup()


def test_ubuntu_install() -> None:
    fx = Fixture()
    try:
        fx.write_os("ubuntu")
        proc = fx.run(INSTALL)
        expect_ok(proc, "ubuntu install")
        if "OS:             ubuntu" not in proc.stdout:
            raise Fail("ubuntu OS id not preserved")
        if not fx.unit_file.is_file():
            raise Fail("ubuntu missing systemd unit")
        if fx.init_file.exists():
            raise Fail("ubuntu wrote procd init")
    finally:
        fx.cleanup()


def test_id_like_debian_install() -> None:
    fx = Fixture()
    try:
        fx.write_os("linuxmint", "ubuntu debian")
        proc = fx.run(INSTALL)
        expect_ok(proc, "id_like install")
        if "OS:             linuxmint" not in proc.stdout:
            raise Fail("linuxmint OS id not preserved")
        if not fx.unit_file.is_file():
            raise Fail("id_like missing systemd unit")
    finally:
        fx.cleanup()


def have_unshare() -> bool:
    return shutil.which("unshare") is not None


def test_openwrt_install() -> None:
    if not have_unshare():
        raise Skip("needs unshare to bind /etc/rc.common")
    fx = Fixture()
    try:
        fx.write_os("openwrt")
        proc = fx.run(INSTALL)
        expect_ok(proc, "openwrt install")
        if "OS:             openwrt" not in proc.stdout:
            raise Fail("openwrt OS id not preserved")
        if not fx.init_file.is_file():
            raise Fail("openwrt missing init")
        if fx.unit_file.exists():
            raise Fail("openwrt wrote systemd unit")
        keep = read(fx.sysupgrade)
        if posix_path(fx.install_bin) not in keep or posix_path(fx.config_dir) + "/" not in keep:
            raise Fail("openwrt sysupgrade keep-list missing")
        if "OpenWRT-Telemost-srv" not in proc.stdout:
            raise Fail("openwrt URI label missing")
    finally:
        fx.cleanup()


def test_reinstall_keeps_key(os_id: str) -> None:
    if os_id == "openwrt" and not have_unshare():
        raise Skip("needs unshare")
    fx = Fixture()
    try:
        fx.write_os(os_id)
        fx.run(INSTALL)
        first = read(fx.config_file)
        env = {"ENCRYPTION_KEY": "", "ROOM_ID": ROOM, "DEBUG": "true"}
        proc = fx.run(INSTALL, extra_env=env)
        expect_ok(proc, f"{os_id} reinstall")
        second = read(fx.config_file)
        if KEY not in second:
            raise Fail(f"{os_id} reinstall dropped key")
        if "debug: true" not in second:
            raise Fail(f"{os_id} reinstall did not rewrite yaml")
        if "reusing encryption key" not in proc.stderr:
            raise Fail(f"{os_id} reinstall did not log key reuse")
        if first.split("key:")[1].splitlines()[0] not in second:
            raise Fail(f"{os_id} key line changed")
    finally:
        fx.cleanup()


def test_uninstall(os_id: str) -> None:
    if os_id == "openwrt" and not have_unshare():
        raise Skip("needs unshare")
    fx = Fixture()
    try:
        fx.write_os(os_id)
        fx.run(INSTALL)
        proc = fx.run(UNINSTALL)
        expect_ok(proc, f"{os_id} uninstall")
        if fx.install_bin.exists() or fx.config_file.exists():
            raise Fail(f"{os_id} uninstall left files")
        if os_id == "openwrt":
            if fx.init_file.exists():
                raise Fail("openwrt uninstall left init")
        else:
            if fx.unit_file.exists():
                raise Fail(f"{os_id} uninstall left unit")
            if fx.init_file.exists():
                raise Fail(f"{os_id} uninstall should not have created init")
    finally:
        fx.cleanup()


def test_fedora_rejected() -> None:
    fx = Fixture()
    try:
        fx.write_os("fedora")
        proc = fx.run(INSTALL, check=False)
        expect_fail(proc, "fedora", "unsupported OS")
    finally:
        fx.cleanup()


def test_missing_apt() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.bin / "apt-get").unlink()
        proc = fx.run(INSTALL, check=False)
        expect_fail(proc, "missing apt-get", "apt-get is required")
    finally:
        fx.cleanup()


def test_missing_systemctl() -> None:
    fx = Fixture()
    try:
        fx.write_os("ubuntu")
        (fx.bin / "systemctl").unlink()
        proc = fx.run(INSTALL, check=False)
        expect_fail(proc, "missing systemctl", "systemctl is required")
    finally:
        fx.cleanup()


def test_systemd_not_running() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.state / "systemd_running").unlink()
        proc = fx.run(INSTALL, check=False)
        expect_fail(proc, "dead systemd", "systemd must be running")
    finally:
        fx.cleanup()


def test_uninstall_missing_apt() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.bin / "apt-get").unlink()
        proc = fx.run(UNINSTALL, check=False)
        expect_fail(proc, "uninstall missing apt-get", "apt-get is required")
    finally:
        fx.cleanup()


def test_sha256_mismatch() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.assets / "SHA256SUMS").write_text(
            "0" * 64 + "  olcrtc-linux-amd64\n",
            encoding="utf-8",
        )
        proc = fx.run(INSTALL, check=False)
        expect_fail(proc, "sha mismatch", "SHA256 mismatch")
        if fx.install_bin.exists():
            raise Fail("mismatch still installed binary")
    finally:
        fx.cleanup()


def test_changing_pid() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.state / "pid_mode").write_text("changing\n", encoding="utf-8", newline="\n")
        proc = fx.run(
            INSTALL,
            extra_env={"STABLE_NEEDED": "2", "STABLE_INTERVAL": "1", "STABLE_MAX": "2"},
            check=False,
        )
        expect_fail(proc, "changing pid", "did not stay running")
    finally:
        fx.cleanup()


def test_zero_pid() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.state / "pid_mode").write_text("zero\n", encoding="utf-8", newline="\n")
        proc = fx.run(
            INSTALL,
            extra_env={"STABLE_NEEDED": "1", "STABLE_INTERVAL": "1", "STABLE_MAX": "1"},
            check=False,
        )
        expect_fail(proc, "zero pid", "did not stay running")
    finally:
        fx.cleanup()


def test_missing_pid() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        (fx.state / "pid_mode").write_text("missing\n", encoding="utf-8", newline="\n")
        proc = fx.run(
            INSTALL,
            extra_env={"STABLE_NEEDED": "1", "STABLE_INTERVAL": "1", "STABLE_MAX": "1"},
            check=False,
        )
        expect_fail(proc, "missing pid", "did not stay running")
    finally:
        fx.cleanup()


def test_stop_failure_does_not_abort() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        fx.run(INSTALL)
        (fx.state / "stop_fail").write_text("1\n", encoding="utf-8")
        proc = fx.run(INSTALL)
        expect_ok(proc, "stop failure reinstall")
    finally:
        fx.cleanup()


def test_disable_failure_does_not_abort() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        fx.run(INSTALL)
        (fx.state / "disable_fail").write_text("1\n", encoding="utf-8")
        proc = fx.run(UNINSTALL)
        expect_ok(proc, "disable failure uninstall")
        if fx.unit_file.exists() or fx.install_bin.exists():
            raise Fail("uninstall after disable failure left files")
    finally:
        fx.cleanup()


def test_missing_ca_installs_curl_without_downloader() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        fx.hide_ca()
        fx.drop_downloaders()
        proc = fx.run(INSTALL)
        expect_ok(proc, "ca+curl")
        apt = read(fx.state / "apt.log")
        if "DEBIAN_FRONTEND=noninteractive" not in apt:
            raise Fail("apt was not noninteractive")
        if "ca-certificates curl" not in apt:
            raise Fail(f"expected ca-certificates curl in apt log: {apt}")
        if not (fx.bin / "curl").exists():
            raise Fail("apt did not create curl")
    finally:
        fx.cleanup()


def test_missing_ca_keeps_existing_downloader() -> None:
    fx = Fixture()
    try:
        fx.write_os("ubuntu")
        fx.hide_ca()
        proc = fx.run(INSTALL)
        expect_ok(proc, "ca only")
        apt = read(fx.state / "apt.log")
        if "DEBIAN_FRONTEND=noninteractive" not in apt:
            raise Fail("apt was not noninteractive")
        if "ca-certificates curl" in apt:
            raise Fail("installed curl despite wget")
        if "ca-certificates" not in apt:
            raise Fail(f"expected ca-certificates in apt log: {apt}")
    finally:
        fx.cleanup()


def test_unit_template_sections() -> None:
    fx = Fixture()
    try:
        fx.write_os("debian")
        fx.run(INSTALL)
        unit = read(fx.unit_file)
        for needle in (
            "[Unit]",
            "[Service]",
            "[Install]",
            "ExecStart=",
            "Restart=always",
            "WantedBy=multi-user.target",
            f"ExecStart={posix_path(fx.install_bin)} {posix_path(fx.config_file)}",
        ):
            if needle not in unit:
                raise Fail(f"unit missing {needle}")
    finally:
        fx.cleanup()


TESTS = [
    ("debian install", test_debian_install),
    ("ubuntu install", test_ubuntu_install),
    ("ID_LIKE=debian install", test_id_like_debian_install),
    ("openwrt install", test_openwrt_install),
    ("debian reinstall keeps key", lambda: test_reinstall_keeps_key("debian")),
    ("openwrt reinstall keeps key", lambda: test_reinstall_keeps_key("openwrt")),
    ("debian uninstall", lambda: test_uninstall("debian")),
    ("openwrt uninstall", lambda: test_uninstall("openwrt")),
    ("fedora rejected", test_fedora_rejected),
    ("missing apt-get", test_missing_apt),
    ("missing systemctl", test_missing_systemctl),
    ("systemd not running", test_systemd_not_running),
    ("uninstall missing apt-get", test_uninstall_missing_apt),
    ("SHA-256 mismatch", test_sha256_mismatch),
    ("changing PID", test_changing_pid),
    ("zero PID", test_zero_pid),
    ("missing PID", test_missing_pid),
    ("systemctl stop failure", test_stop_failure_does_not_abort),
    ("systemctl disable failure", test_disable_failure_does_not_abort),
    ("missing CA installs curl", test_missing_ca_installs_curl_without_downloader),
    ("missing CA keeps wget", test_missing_ca_keeps_existing_downloader),
    ("unit sections", test_unit_template_sections),
]


def main() -> int:
    failed = 0
    for name, fn in TESTS:
        try:
            fn()
            sys.stderr.write(f"PASS {name}\n")
        except Skip as exc:
            sys.stderr.write(f"SKIP {name}: {exc}\n")
        except Exception as exc:
            failed += 1
            sys.stderr.write(f"FAIL {name}: {exc}\n")
    if failed:
        sys.stderr.write(f"{failed}/{len(TESTS)} failed\n")
        return 1
    sys.stderr.write(f"ALL_{len(TESTS)}_PLATFORM_CHECKS_PASSED\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
