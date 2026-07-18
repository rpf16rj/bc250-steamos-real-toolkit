from __future__ import annotations

import asyncio
import glob
import math
import os
import pwd
import re
import shlex
import signal
import stat
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - used by older SteamOS Python
    import tomli as tomllib


BASH = "/usr/bin/bash"
BUSCTL = "/usr/bin/busctl"
ENV = "/usr/bin/env"
RUNUSER = "/usr/bin/runuser"
PYTHON3 = "/usr/bin/python3"
SYSTEMCTL = "/usr/bin/systemctl"
GPU_CONFIG_PATH = Path("/etc/cyan-skillfish-governor-smu/config.toml")
GPU_STATE_PATH = Path("/var/lib/bc250-control/governor/freq-state")
CPU_HELPER_PATH = Path("/var/lib/bc250-control/helper/bc250-power.sh")
CPU_STATE_DIR = Path("/var/lib/bc250-control/smu-oc")
ROOT_UMR_PATH = Path("/var/lib/bc250-control/umr/bin/umr")
ROOT_UMR_DATABASE_PATH = Path("/var/lib/bc250-control/umr/share/umr/database")
MIGRATED_UMR_DATABASE_PATH = Path(
    "/var/lib/bc250-control/legacy-bc250-40cu/share/umr/database"
)
LEGACY_UMR_DATABASE_PATH = Path("/var/lib/bc250-40cu/share/umr/database")
CU_CONFIG_PATH = Path("/etc/bc250-cu-live-manager.conf")
CU_MANAGER_PATHS = (
    Path("/var/lib/bc250-control/helper/bc250-cu-live-manager"),
    Path("/var/lib/bc250-40cu/bc250-cu-live-manager"),
    Path("/var/lib/bc250-40cu/bc250-cu-live-manager.sh"),
    Path("/usr/local/bin/bc250-cu-live-manager"),
    Path("/var/usrlocal/bin/bc250-cu-live-manager"),
)

CU_MAP_SCRIPT = r"""
import ctypes
import glob
import os
import struct
import sys

render_nodes = []
for device in glob.glob("/sys/class/drm/renderD*/device"):
    try:
        with open(os.path.join(device, "vendor"), encoding="ascii") as stream:
            vendor = stream.read().strip().lower()
        with open(os.path.join(device, "device"), encoding="ascii") as stream:
            product = stream.read().strip().lower()
    except OSError:
        continue
    if vendor == "0x1002" and product == "0x13fe":
        render_nodes.append("/dev/dri/" + os.path.basename(os.path.dirname(device)))

if len(render_nodes) != 1:
    sys.exit(1)

fd = -1
dev = ctypes.c_void_p()
try:
    libdrm = ctypes.CDLL("libdrm_amdgpu.so.1")
    fd = os.open(render_nodes[0], os.O_RDWR)
    major = ctypes.c_uint32()
    minor = ctypes.c_uint32()
    if libdrm.amdgpu_device_initialize(
        fd, ctypes.byref(major), ctypes.byref(minor), ctypes.byref(dev)
    ) != 0:
        sys.exit(1)
    buffer = (ctypes.c_uint8 * 1024)()
    if libdrm.amdgpu_query_info(dev, 0x16, 1024, ctypes.byref(buffer)) != 0:
        sys.exit(1)
    raw = bytes(buffer)
    if struct.unpack_from("<I", raw, 20)[0] < 2:
        sys.exit(1)
    if struct.unpack_from("<I", raw, 24)[0] < 2:
        sys.exit(1)
    for se in range(2):
        for sh in range(2):
            mask = struct.unpack_from("<I", raw, 56 + (se * 4 + sh) * 4)[0]
            print(f"{se} {sh} 0x{mask & 0x3ff:03x}")
finally:
    if dev:
        try:
            libdrm.amdgpu_device_deinitialize(dev)
        except Exception:
            pass
    if fd >= 0:
        os.close(fd)
"""

# Decky Loader's PyInstaller environment can shadow system libraries used by
# busctl and systemctl. Subprocesses must resolve the SteamOS libraries instead.
CLEAN_ENV = {
    key: value for key, value in os.environ.items() if key != "LD_LIBRARY_PATH"
}


class CommandError(RuntimeError):
    pass


class ToolkitBackend:
    def __init__(self, user: str, user_home: str) -> None:
        self.user = user
        self.user_home = Path(user_home)
        self.user_uid = pwd.getpwnam(user).pw_uid
        override = os.environ.get("BC250_TOOLKIT_DIR")
        self.toolkit = Path(override) if override else (
            self.user_home / ".local/share/bc250-fixes/bc250-steamos"
        )
        self._mutation_lock = asyncio.Lock()
        self._umr_lock = asyncio.Lock()

    async def _exec(
        self,
        argv: list[str],
        *,
        timeout: float = 20,
        check: bool = True,
        env: dict[str, str] | None = None,
    ) -> tuple[int, str, str]:
        process = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env if env is not None else CLEAN_ENV,
            start_new_session=True,
        )
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout)
        except asyncio.CancelledError:
            await asyncio.shield(self._terminate(process))
            raise
        except asyncio.TimeoutError as error:
            await self._terminate(process)
            raise CommandError(f"Command timed out: {argv[0]}") from error
        out = stdout.decode("utf-8", "replace").strip()
        err = stderr.decode("utf-8", "replace").strip()
        if check and process.returncode != 0:
            detail = err or out or f"exit {process.returncode}"
            raise CommandError(detail[-1200:])
        return process.returncode or 0, out, err

    @staticmethod
    async def _terminate(process: asyncio.subprocess.Process) -> None:
        if process.returncode is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            await asyncio.wait_for(process.wait(), 10)
        except asyncio.TimeoutError:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            await process.wait()

    def _user_argv(self, argv: list[str]) -> list[str]:
        runtime = f"/run/user/{self.user_uid}"
        environment = [
            ENV,
            "-i",
            "PATH=/usr/local/bin:/usr/bin",
            f"HOME={self.user_home}",
            f"USER={self.user}",
            f"LOGNAME={self.user}",
            f"XDG_RUNTIME_DIR={runtime}",
            f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
            *argv,
        ]
        if os.geteuid() == self.user_uid:
            return environment
        return [RUNUSER, "-u", self.user, "--", *environment]

    async def _user_exec(
        self, argv: list[str], *, timeout: float = 20, check: bool = True
    ) -> tuple[int, str, str]:
        return await self._exec(
            self._user_argv(argv), timeout=timeout, check=check
        )

    def _user_script(self, name: str) -> Path:
        script = self.toolkit / name
        if not self._user_script_available(name):
            raise CommandError(f"Toolkit script is missing: {script}")
        return script

    def _user_script_available(self, name: str) -> bool:
        script = self.toolkit / name
        return script.is_file() and not script.is_symlink()

    async def _user_tool(self, name: str, *args: str, timeout: float = 30) -> str:
        argv = [BASH, str(self._user_script(name)), *args]
        _, out, _ = await self._user_exec(argv, timeout=timeout)
        return out

    @staticmethod
    def _trusted_root_path(path: Path, expected_type: int) -> bool:
        try:
            if not path.is_absolute():
                return False
            current = path
            first = True
            while True:
                metadata = current.lstat()
                if stat.S_ISLNK(metadata.st_mode):
                    return False
                if first:
                    if stat.S_IFMT(metadata.st_mode) != expected_type:
                        return False
                elif not stat.S_ISDIR(metadata.st_mode):
                    return False
                if metadata.st_uid != 0 or metadata.st_mode & 0o022:
                    return False
                if current.parent == current:
                    return True
                current = current.parent
                first = False
        except OSError:
            return False

    @classmethod
    def _trusted_root_file(cls, path: Path) -> bool:
        return cls._trusted_root_path(path, stat.S_IFREG)

    @classmethod
    def _trusted_root_directory(cls, path: Path) -> bool:
        return cls._trusted_root_path(path, stat.S_IFDIR)

    async def _cpu_tool(self, *args: str, timeout: float = 30) -> str:
        if not self._trusted_root_file(CPU_HELPER_PATH):
            raise CommandError(
                "CPU tuning helper is missing or unsafe; reinstall the plugin."
            )
        env = {
            "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "HOME": "/root",
            "USER": "root",
            "LOGNAME": "root",
            "REAL_HOME": str(self.user_home),
            "FIXES_REPO_DIR": str(self.toolkit),
            "BC250_OC_DIR": str(CPU_STATE_DIR),
        }
        _, out, _ = await self._exec(
            [BASH, str(CPU_HELPER_PATH), *args], timeout=timeout, env=env
        )
        return out

    async def _service(self, name: str, *, user: bool = False) -> dict[str, str]:
        runner = self._user_exec if user else self._exec
        enabled_args = (
            [SYSTEMCTL, "--user", "is-enabled", name]
            if user
            else [SYSTEMCTL, "is-enabled", name]
        )
        enabled_rc, enabled, _ = await runner(
            enabled_args,
            check=False,
            timeout=5,
        )
        if user:
            active_rc, active, _ = await runner(
                [SYSTEMCTL, "--user", "is-active", name],
                check=False,
                timeout=5,
            )
        else:
            active_rc, active, _ = await runner(
                [SYSTEMCTL, "is-active", name], check=False, timeout=5
            )
        return {
            "enabled": enabled if enabled_rc == 0 else (enabled or "disabled"),
            "active": active if active_rc == 0 else (active or "inactive"),
        }

    @staticmethod
    def _read(path: str | Path, default: str = "") -> str:
        try:
            return Path(path).read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError):
            return default

    @staticmethod
    def _read_key_values(path: str | Path) -> dict[str, str]:
        values: dict[str, str] = {}
        text = ToolkitBackend._read(path)
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key.strip()):
                values[key.strip()] = value.strip().strip('"\'')
        return values

    @staticmethod
    def _safe_int(value: str | None, default: int = 0) -> int:
        try:
            return int(value or default)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _number(value: Any) -> int | float | None:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        return value if math.isfinite(value) else None

    @staticmethod
    def _read_toml(path: str | Path) -> dict[str, Any]:
        try:
            with Path(path).open("rb") as stream:
                return tomllib.load(stream)
        except (OSError, ValueError):
            return {}

    @staticmethod
    def _last_hex(text: str) -> int | None:
        matches = re.findall(r"0x[0-9a-fA-F]+", text)
        return int(matches[-1], 16) if matches else None

    def _trusted_umr(self) -> Path | None:
        configured = self._read_key_values(CU_CONFIG_PATH).get("UMR", "")
        candidates = [
            ROOT_UMR_PATH,
            Path(configured) if configured.startswith("/") else None,
            Path("/var/lib/bc250-40cu/bin/umr"),
            Path("/usr/bin/umr"),
            Path("/usr/local/bin/umr"),
        ]
        for candidate in candidates:
            if candidate is None or not self._trusted_root_file(candidate):
                continue
            try:
                if candidate.stat().st_mode & 0o111:
                    return candidate
            except OSError:
                continue
        return None

    def _trusted_umr_database(self, umr: Path) -> Path | None:
        configured = self._read_key_values(CU_CONFIG_PATH).get(
            "UMR_DATABASE_PATH", ""
        )
        candidates = [
            Path(configured) if configured.startswith("/") else None,
            ROOT_UMR_DATABASE_PATH,
            umr.parent.parent / "share/umr/database",
            MIGRATED_UMR_DATABASE_PATH,
            LEGACY_UMR_DATABASE_PATH,
        ]
        seen: set[Path] = set()
        for candidate in candidates:
            if candidate is None or candidate in seen:
                continue
            seen.add(candidate)
            required = (
                candidate / "cyan_skillfish.asic",
                candidate / "cyan_skillfish.soc15",
                candidate / "ip/gc_10_1_0.reg",
            )
            if not self._trusted_root_directory(candidate):
                continue
            try:
                if all(
                    self._trusted_root_file(path) and path.stat().st_size > 0
                    for path in required
                ):
                    return candidate
            except OSError:
                continue
        return None

    def _umr_database_args(self, umr: Path) -> list[str]:
        database = self._trusted_umr_database(umr)
        return ["--database-path", str(database)] if database is not None else []

    def _trusted_cu_manager(self) -> Path | None:
        for candidate in CU_MANAGER_PATHS:
            if not self._trusted_root_file(candidate):
                continue
            try:
                if candidate.stat().st_mode & 0o111:
                    return candidate
            except OSError:
                continue
        return None

    def _bc250_present(self) -> bool:
        for device in glob.glob("/sys/bus/pci/devices/*"):
            path = Path(device)
            if (
                self._read(path / "vendor").lower() == "0x1002"
                and self._read(path / "device").lower() == "0x13fe"
            ):
                return True
        return False

    def _umr_instance(self) -> int | None:
        configured = self._read_key_values(CU_CONFIG_PATH).get("UMR_INSTANCE", "")
        if configured.isdigit():
            return int(configured)

        slots = []
        for device in glob.glob("/sys/bus/pci/devices/*"):
            path = Path(device)
            if (
                self._read(path / "vendor").lower() == "0x1002"
                and self._read(path / "device").lower() == "0x13fe"
            ):
                slots.append(path.name)

        instances = []
        for name_path in glob.glob("/sys/kernel/debug/dri/[0-9]*/name"):
            instance = Path(name_path).parent.name
            if not instance.isdigit() or int(instance) >= 128:
                continue
            instances.append(int(instance))
            name = self._read(name_path).lower()
            if any(slot.lower() in name for slot in slots):
                return int(instance)
        return instances[0] if len(instances) == 1 else None

    async def _umr_register(self, register: str, se: int, sh: int) -> int | None:
        if os.geteuid() != 0:
            return None
        umr = self._trusted_umr()
        if umr is None:
            return None
        instance = self._umr_instance()
        instance_args = ["-i", str(instance)] if instance is not None else []
        database_args = self._umr_database_args(umr)
        asic = self._read_key_values(CU_CONFIG_PATH).get(
            "UMR_ASIC", "cyan_skillfish.gfx1013"
        )
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", asic):
            return None
        async with self._umr_lock:
            for bank_args in (
                ["-b", str(se), str(sh), "0xffffffff"],
                ["-b", str(se), str(sh)],
            ):
                _rc, out, err = await self._exec(
                    [
                        str(umr),
                        *database_args,
                        *instance_args,
                        "-r",
                        f"{asic}.{register}",
                        *bank_args,
                    ],
                    timeout=5,
                    check=False,
                )
                value = self._last_hex(f"{out}\n{err}")
                # Some UMR builds return a nonzero status after printing a valid
                # register value. The CU manager uses the parsed value as the
                # success signal as well, so keep both callers consistent.
                if value is not None:
                    return value
        return None

    async def _factory_cu_masks(self) -> list[int] | None:
        try:
            rc, out, _ = await self._exec(
                [PYTHON3, "-c", CU_MAP_SCRIPT], timeout=5, check=False
            )
        except (CommandError, OSError):
            return None
        if rc != 0:
            return None
        rows: dict[tuple[int, int], int] = {}
        for line in out.splitlines():
            match = re.fullmatch(r"([01]) ([01]) (0x[0-9a-fA-F]+)", line.strip())
            if match is None:
                return None
            se, sh, mask = int(match[1]), int(match[2]), int(match[3], 16)
            if mask > 0x3FF or (se, sh) in rows:
                return None
            rows[(se, sh)] = mask
        if set(rows) != {(0, 0), (0, 1), (1, 0), (1, 1)}:
            return None
        masks = [rows[(se, sh)] for se in range(2) for sh in range(2)]
        if sum(mask.bit_count() for mask in masks) != 24:
            return None
        return masks

    async def get_cu_status(self) -> dict[str, Any]:
        service_task = asyncio.create_task(
            self._service("bc250-cu-live-manager.service")
        )
        factory_masks = await self._factory_cu_masks()
        reads = []
        for se in range(2):
            for sh in range(2):
                reads.append(
                    self._umr_register("mmSPI_PG_ENABLE_STATIC_WGP_MASK", se, sh)
                )
        values = await asyncio.gather(*reads)
        rows = []
        total = 0
        for index, spi in enumerate(values):
            mask = (spi or 0) & 0x1F
            factory_mask = factory_masks[index] if factory_masks is not None else None
            count = bin(mask).count("1") * 2 if spi is not None else 0
            total += count
            rows.append(
                {
                    "se": index // 2,
                    "sh": index % 2,
                    "spi": spi,
                    "cc": None,
                    "wgps": [bool(mask & (1 << bit)) for bit in range(5)],
                    "cus": count,
                    "factoryCuMask": factory_mask,
                    "factoryWgps": [
                        bool(factory_mask & (0x3 << (bit * 2)))
                        for bit in range(5)
                    ]
                    if factory_mask is not None
                    else [False] * 5,
                }
            )
        saved = self._read_key_values(CU_CONFIG_PATH)
        saved_masks = []
        saved_values = saved.get("BC250_WGP_MASKS", "").split(",")
        try:
            parsed_masks = [int(value, 0) for value in saved_values]
        except ValueError:
            parsed_masks = []
        if len(parsed_masks) == 4 and all(0 <= mask <= 0x1F for mask in parsed_masks):
            saved_masks = parsed_masks
        available = all(row["spi"] is not None for row in rows)
        privileged = os.geteuid() == 0
        trusted_umr = self._trusted_umr()
        trusted_database = (
            self._trusted_umr_database(trusted_umr)
            if trusted_umr is not None
            else None
        )
        return {
            "available": available,
            "controllable": (
                available
                and privileged
                and factory_masks is not None
                and self._trusted_cu_manager() is not None
                and self._bc250_present()
            ),
            "liveReason": None
            if available
            else (
                "Decky launched the plugin without root access; reinstall it with the root flag."
                if not privileged
                else "Live status requires the plugin's root-owned UMR copy; reinstall the plugin after installing UMR."
                if trusted_umr is None
                else "The trusted UMR ASIC database is incomplete; reinstall the plugin."
                if trusted_database is None
                else "The trusted UMR installation could not read GPU registers."
            ),
            "total": total,
            "maximum": 40,
            "rows": rows,
            "savedMasks": saved_masks,
            "factoryMapAvailable": factory_masks is not None,
            "factoryTotal": 24 if factory_masks is not None else None,
            "service": await service_task,
            "protected": Path(
                "/etc/atomic-update.conf.d/bc250-compute.conf"
            ).is_file(),
        }

    def _temperatures(self) -> list[dict[str, Any]]:
        temperatures = []
        for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
            name = self._read(Path(hwmon) / "name", Path(hwmon).name)
            for source in glob.glob(f"{hwmon}/temp*_input"):
                match = re.search(r"temp(\d+)_input$", source)
                if not match:
                    continue
                index = match.group(1)
                raw = self._read(source)
                try:
                    value = round(int(raw) / 1000, 1)
                except ValueError:
                    continue
                label = self._read(
                    Path(hwmon) / f"temp{index}_label", f"temp{index}"
                )
                temperatures.append(
                    {"device": name, "label": label, "celsius": value}
                )
        return temperatures

    def _cpu_current_mhz(self) -> int | None:
        candidates = [Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")]
        candidates.extend(
            Path(path)
            for path in sorted(
                glob.glob("/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq")
            )
        )
        for path in candidates:
            current = self._read(path)
            if current.isdigit():
                return round(int(current) / 1000)
        return None

    def _cpu_governor(self) -> str:
        candidates = [Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")]
        candidates.extend(
            Path(path)
            for path in sorted(
                glob.glob("/sys/devices/system/cpu/cpufreq/policy*/scaling_governor")
            )
        )
        for path in candidates:
            governor = self._read(path)
            if governor:
                return governor
        return ""

    def _active_gpu_mhz(self) -> int | None:
        for path in glob.glob("/sys/class/drm/card*/device/pp_dpm_sclk"):
            levels = self._read(path)
            match = re.search(r"(\d+)Mhz\s+\*", levels, re.IGNORECASE)
            if match:
                return int(match.group(1))
        return None

    @staticmethod
    def _matching_temperature(
        temperatures: list[dict[str, Any]], pattern: str
    ) -> int | float | None:
        matcher = re.compile(pattern, re.IGNORECASE)
        for temperature in temperatures:
            if matcher.search(f"{temperature['device']} {temperature['label']}"):
                return temperature["celsius"]
        return None

    async def get_telemetry(self) -> dict[str, int | float | None]:
        temperatures = self._temperatures()
        return {
            "cpuClock": self._cpu_current_mhz(),
            "gpuClock": self._active_gpu_mhz(),
            "cpuTemp": self._matching_temperature(
                temperatures, r"k10temp|cpu|tctl|package"
            ),
            "gpuTemp": self._matching_temperature(
                temperatures, r"amdgpu|gpu|edge|junction"
            ),
        }

    async def get_power_status(self) -> dict[str, Any]:
        governor, acpi, cpufreq, restore = await asyncio.gather(
            self._service("cyan-skillfish-governor-smu.service"),
            self._service("bc250-acpi-heal.service"),
            self._service("bc250-cpufreq.service"),
            self._service("bc250-gpu-freq-restore.service"),
        )
        cpu_root = Path("/sys/devices/system/cpu/cpu0")
        return {
            "acpiActive": (cpu_root / "cpufreq").is_dir(),
            "cStates": len(list((cpu_root / "cpuidle").glob("state*"))),
            "cpuGovernor": self._cpu_governor(),
            "cpuCurrentMhz": self._cpu_current_mhz(),
            "governor": governor,
            "acpiService": acpi,
            "cpufreqService": cpufreq,
            "frequencyRestore": restore,
            "temperatures": self._temperatures(),
            "protected": Path(
                "/etc/atomic-update.conf.d/bc250-power.conf"
            ).is_file(),
        }

    def _gpu_config(self) -> dict[str, Any]:
        config = self._read_toml(GPU_CONFIG_PATH)
        points = []
        safe_points = config.get("safe-points", [])
        if not isinstance(safe_points, list):
            safe_points = []
        for point in safe_points:
            if isinstance(point, dict):
                points.append(
                    {
                        "frequency": self._number(point.get("frequency")),
                        "voltage": self._number(point.get("voltage")),
                    }
                )
        load = config.get("load-target", {})
        if not isinstance(load, dict):
            load = {}
        timing = config.get("timing", {})
        if not isinstance(timing, dict):
            timing = {}
        intervals = timing.get("intervals", {})
        if not isinstance(intervals, dict):
            intervals = {}
        rates = timing.get("ramp-rates", {})
        if not isinstance(rates, dict):
            rates = {}
        frequency_range = config.get("frequency-range", {})
        if not isinstance(frequency_range, dict):
            frequency_range = {}
        return {
            "safePoints": points,
            "configuredMax": self._number(frequency_range.get("max")),
            "loadUpper": self._number(load.get("upper")),
            "loadLower": self._number(load.get("lower")),
            "adjustMicros": self._number(intervals.get("adjust")),
            "rampNormal": self._number(rates.get("normal")),
            "downEvents": self._number(timing.get("down-events")),
        }

    @staticmethod
    def _atomic_write(path: Path, content: str, mode: int = 0o644) -> None:
        if path.is_symlink():
            raise CommandError(f"Refusing to replace symlink: {path}")
        metadata = None
        if path.exists():
            metadata = path.stat()
            if not stat.S_ISREG(metadata.st_mode):
                raise CommandError(f"Refusing to replace non-file: {path}")
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            os.fchmod(descriptor, stat.S_IMODE(metadata.st_mode) if metadata else mode)
            if metadata:
                os.fchown(descriptor, metadata.st_uid, metadata.st_gid)
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    @classmethod
    def _update_toml_values(
        cls, path: Path, updates: dict[str, dict[str, str]]
    ) -> None:
        if not path.is_file() or path.is_symlink():
            raise CommandError(f"Governor config is unavailable: {path}")
        lines = path.read_text(encoding="utf-8").splitlines()
        for section, values in updates.items():
            header = f"[{section}]"
            try:
                start = lines.index(header)
            except ValueError:
                if lines and lines[-1] != "":
                    lines.append("")
                lines.append(header)
                start = len(lines) - 1
            end = len(lines)
            for index in range(start + 1, len(lines)):
                if lines[index].startswith("["):
                    end = index
                    break
            for key, value in values.items():
                key_pattern = re.compile(rf"^{re.escape(key)}\s*=")
                found = None
                for index in range(start + 1, end):
                    if key_pattern.match(lines[index]):
                        found = index
                        break
                rendered = f"{key} = {value}"
                if found is None:
                    lines.insert(end, rendered)
                    end += 1
                else:
                    lines[found] = rendered
        candidate = "\n".join(lines) + "\n"
        try:
            tomllib.loads(candidate)
        except (TypeError, ValueError) as error:
            raise CommandError(f"Governor config update is invalid: {error}") from error
        cls._atomic_write(path, candidate)

    async def _gpu_call(self, method: str, *signature_and_args: str) -> None:
        await self._exec(
            [
                BUSCTL,
                "--system",
                "call",
                "com.cyanskillfish.Governor",
                "/com/cyanskillfish/Governor",
                "com.cyanskillfish.Governor.PerformanceMode",
                method,
                *signature_and_args,
            ],
            timeout=8,
        )

    async def _set_gpu_enabled(self, enabled: bool) -> None:
        await self._exec(
            [
                BUSCTL,
                "--system",
                "set-property",
                "com.cyanskillfish.Governor",
                "/com/cyanskillfish/Governor",
                "com.cyanskillfish.Governor.PerformanceMode",
                "Enabled",
                "b",
                "true" if enabled else "false",
            ],
            timeout=8,
        )

    async def _system_bus_property(
        self, path: str, interface: str, prop: str
    ) -> int | None:
        rc, out, _ = await self._exec(
            [
                BUSCTL,
                "--system",
                "get-property",
                "com.cyanskillfish.Governor",
                path,
                interface,
                prop,
            ],
            timeout=5,
            check=False,
        )
        value = self._bus_value(out) if rc == 0 else None
        return value if isinstance(value, int) else None

    def _write_frequency_state(
        self, mode: str, first: int = 0, second: int = 0
    ) -> None:
        state = GPU_STATE_PATH
        if str(state).startswith("/var/lib/bc250-control/"):
            parent = state.parent
            if not self._trusted_root_directory(parent):
                raise CommandError(f"GPU frequency state directory is unsafe: {parent}")
            if state.exists() and not self._trusted_root_file(state):
                raise CommandError(f"GPU frequency state is unsafe: {state}")
        if state.is_symlink():
            raise CommandError(f"Refusing to modify symlink: {state}")
        if mode == "adaptive":
            if state.exists():
                if not state.is_file():
                    raise CommandError(f"Refusing to remove non-file: {state}")
                state.unlink()
            return
        self._atomic_write(state, f"MODE={mode}\nA={first or ''}\nB={second or ''}\n")
        if os.geteuid() == 0:
            os.chown(state, 0, 0)
            os.chmod(state, 0o644)

    async def _apply_frequency(
        self, mode: str, first: int = 0, second: int = 0
    ) -> None:
        if mode == "adaptive":
            await self._set_gpu_enabled(False)
        elif mode == "max":
            await self._set_gpu_enabled(True)
        elif mode == "pin" and first:
            await self._gpu_call("SetFixedFrequency", "u", str(first))
        elif mode == "range" and second:
            await self._gpu_call("SetRange", "uu", str(first), str(second))
        else:
            raise CommandError("Saved GPU frequency state is invalid.")

    async def _apply_frequency_state(self) -> None:
        state = self._read_key_values(GPU_STATE_PATH)
        mode = state.get("MODE", "adaptive")
        first = self._safe_int(state.get("A"))
        second = self._safe_int(state.get("B"))
        await self._apply_frequency(mode, first, second)

    async def _wait_for_governor(self, timeout: int = 30) -> None:
        for _ in range(timeout):
            rc, _, _ = await self._exec(
                [BUSCTL, "--system", "status", "com.cyanskillfish.Governor"],
                timeout=3,
                check=False,
            )
            if rc == 0:
                return
            await asyncio.sleep(1)
        raise CommandError("GPU governor D-Bus service did not become ready.")

    async def _restart_governor_and_reapply(self) -> None:
        await self._exec(
            [SYSTEMCTL, "restart", "cyan-skillfish-governor-smu.service"]
        )
        await self._wait_for_governor()
        await self._apply_frequency_state()

    async def _restore_gpu_config(
        self, path: Path, content: str, was_active: bool
    ) -> None:
        self._atomic_write(path, content)
        if was_active:
            await self._restart_governor_and_reapply()

    async def _update_gpu_config(
        self,
        updates: dict[str, dict[str, str]],
        *,
        live_callback: Any = None,
        restart: bool = False,
    ) -> None:
        path = GPU_CONFIG_PATH
        if not path.is_file() or path.is_symlink():
            raise CommandError(f"Governor config is unavailable: {path}")
        governor = await self._service("cyan-skillfish-governor-smu.service")
        was_active = governor["active"] == "active"
        original = path.read_text(encoding="utf-8")
        self._update_toml_values(path, updates)
        try:
            if not was_active:
                return
            if live_callback is not None:
                try:
                    await live_callback()
                    return
                except CommandError:
                    pass
            if restart or live_callback is not None:
                await self._restart_governor_and_reapply()
        except BaseException as error:
            rollback = asyncio.ensure_future(
                self._restore_gpu_config(path, original, was_active)
            )
            try:
                await asyncio.shield(rollback)
            except asyncio.CancelledError:
                await rollback
            except Exception as rollback_error:
                raise CommandError(
                    f"{error}; config rollback failed: {rollback_error}"
                ) from error
            raise error

    async def get_gpu_status(self) -> dict[str, Any]:
        restore_service = await self._service("bc250-gpu-freq-restore.service")
        state = self._read_key_values(GPU_STATE_PATH)
        config = self._gpu_config()
        active_mhz = self._active_gpu_mhz()
        levels = ""
        for path in glob.glob("/sys/class/drm/card*/device/pp_dpm_sclk"):
            levels = self._read(path)
            if levels:
                break
        requested_mode = state.get("MODE", "adaptive")
        requested_min = self._safe_int(state.get("A"))
        requested_max = self._safe_int(state.get("B") or state.get("A"))
        (
            allowed_min,
            allowed_max,
            current_min,
            current_max,
            initial_min,
            initial_max,
            enabled,
        ) = await asyncio.gather(
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Allowed",
                "com.cyanskillfish.Governor.Range",
                "Min",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Allowed",
                "com.cyanskillfish.Governor.Range",
                "Max",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Current",
                "com.cyanskillfish.Governor.Range",
                "Min",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Current",
                "com.cyanskillfish.Governor.Range",
                "Max",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Initial",
                "com.cyanskillfish.Governor.Range",
                "Min",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor/Range/Initial",
                "com.cyanskillfish.Governor.Range",
                "Max",
            ),
            self._system_bus_property(
                "/com/cyanskillfish/Governor",
                "com.cyanskillfish.Governor.PerformanceMode",
                "Enabled",
            ),
        )
        dbus_ready = enabled is not None
        privileged = os.geteuid() == 0
        mode = requested_mode
        if dbus_ready and current_min is not None and current_max is not None:
            if requested_mode == "pin" and (
                current_min == requested_max and current_max == requested_max
            ):
                mode = "pin"
            elif requested_mode == "range" and (
                current_max == requested_max
                and (requested_min == 0 or current_min == requested_min)
            ):
                mode = "range"
            elif requested_mode == "max" and enabled is True:
                mode = "max"
            elif current_min == current_max:
                mode = "pin"
            elif current_min == initial_min and current_max == initial_max:
                mode = "adaptive"
            else:
                mode = "range"
        replay_applied = False
        if dbus_ready and requested_mode == "pin":
            replay_applied = (
                current_min == requested_max and current_max == requested_max
            )
        elif dbus_ready and requested_mode == "range":
            replay_applied = (
                current_max == requested_max
                and (requested_min == 0 or current_min == requested_min)
            )
        elif dbus_ready and requested_mode == "max":
            replay_applied = enabled is True
        elif dbus_ready and requested_mode == "adaptive":
            replay_applied = enabled is False and (
                current_min == initial_min and current_max == initial_max
            )
        span_min = allowed_min or 500
        span_max = config.get("configuredMax") or allowed_max or 2200
        normal = config.get("rampNormal")
        climb_ms = (
            round((span_max - span_min) / normal)
            if isinstance(normal, (int, float)) and normal > 0 and span_max > span_min
            else None
        )
        return {
            "available": GPU_CONFIG_PATH.is_file(),
            "controllable": dbus_ready and privileged,
            "dbusReady": dbus_ready,
            "mode": mode,
            "requestedMode": requested_mode,
            "requestedMinimum": requested_min,
            "requestedMaximum": requested_max,
            "minimum": current_min
            if dbus_ready and current_min is not None
            else self._safe_int(state.get("A")),
            "maximum": current_max
            if dbus_ready and current_max is not None
            else self._safe_int(state.get("B") or state.get("A")),
            "liveMinimum": current_min,
            "liveMaximum": current_max,
            "activeMhz": active_mhz,
            "levels": levels.splitlines(),
            "allowedMinimum": allowed_min,
            "allowedMaximum": allowed_max,
            "climbMs": climb_ms,
            "frequencyRestore": restore_service,
            "persistent": restore_service["enabled"] == "enabled",
            "replayApplied": replay_applied,
            **config,
        }

    def _cpu_config(self, path: str | Path) -> dict[str, Any]:
        values = self._read_key_values(path)
        detected = ""
        for line in self._read(path).splitlines():
            if line.startswith("# detected:"):
                detected = line[len("# detected:") :].strip()
        return {"values": values, "detected": detected}

    def _toolkit_file(self, path: Path) -> bool:
        try:
            metadata = path.stat()
            resolved = path.resolve(strict=True)
            toolkit = self.toolkit.resolve(strict=True)
        except OSError:
            return False
        return (
            not path.is_symlink()
            and stat.S_ISREG(metadata.st_mode)
            and metadata.st_uid in {0, self.user_uid}
            and os.path.commonpath((str(resolved), str(toolkit))) == str(toolkit)
        )

    async def get_cpu_status(self) -> dict[str, Any]:
        service = await self._service("bc250-smu-oc.service")
        installed_path = Path("/etc/bc250-smu-oc.conf")
        staged_path = CPU_STATE_DIR / "overclock.conf"
        return {
            "service": service,
            "installed": self._cpu_config(installed_path)
            if installed_path.is_file()
            else None,
            "staged": self._cpu_config(staged_path)
            if self._trusted_root_file(staged_path)
            else None,
            "toolAvailable": self._trusted_root_file(
                CPU_STATE_DIR / "bc250_apply.py"
            ),
        }

    @staticmethod
    def _bus_value(output: str) -> Any:
        try:
            parts = shlex.split(output)
        except ValueError:
            return output
        if len(parts) < 2:
            return None
        if parts[0] == "b":
            return parts[1] == "true"
        if parts[0] in {"y", "u", "i", "q", "n", "x", "t"}:
            try:
                return int(parts[1])
            except ValueError:
                return parts[1]
        if parts[0] == "s":
            return parts[1]
        return parts[1:]

    async def _cec_property(self, path: str, interface: str, prop: str) -> Any:
        rc, out, _ = await self._user_exec(
            [
                BUSCTL,
                "--user",
                "--timeout=3",
                "get-property",
                "com.steampowered.CecDaemon1",
                path,
                interface,
                prop,
            ],
            timeout=5,
            check=False,
        )
        return self._bus_value(out) if rc == 0 else None

    async def get_cec_status(self) -> dict[str, Any]:
        daemon_path = "/com/steampowered/CecDaemon1/Daemon"
        device_path = "/com/steampowered/CecDaemon1/Devices/Cec0"
        config_if = "com.steampowered.CecDaemon1.Config1"
        device_if = "com.steampowered.CecDaemon1.CecDevice1"
        properties = await asyncio.gather(
            self._cec_property(daemon_path, config_if, "OsdName"),
            self._cec_property(daemon_path, config_if, "WakeTv"),
            self._cec_property(daemon_path, config_if, "SuspendTv"),
            self._cec_property(daemon_path, config_if, "AllowStandby"),
            self._cec_property(daemon_path, config_if, "Uinput"),
            self._cec_property(device_path, device_if, "Active"),
            self._cec_property(device_path, device_if, "PhysicalAddress"),
            self._cec_property(device_path, device_if, "AudioLogicalAddress"),
        )
        # Property access can D-Bus-activate cecd, so capture service state after it.
        service = await self._service("cecd.service", user=True)
        if any(value is not None for value in properties):
            service["active"] = "active"
        return {
            "devicePresent": Path("/dev/cec0").exists(),
            "service": service,
            "osdName": properties[0],
            "wakeTv": properties[1],
            "suspendTv": properties[2],
            "allowStandby": properties[3],
            "uinput": properties[4],
            "active": properties[5],
            "physicalAddress": properties[6],
            "audioLogicalAddress": properties[7],
            "poweroffIntegration": Path(
                "/etc/systemd/system/bc250-cec-poweroff-standby.service"
            ).is_file(),
            "sleepIntegration": Path(
                "/etc/systemd/system-sleep/bc250-cec-amp.sh"
            ).is_file(),
            "protected": Path(
                "/etc/atomic-update.conf.d/bc250-cec.conf"
            ).is_file(),
        }

    async def _get_snapshot(self) -> dict[str, Any]:
        power_available = self._user_script_available("bc250-power.sh")
        cec_available = self._user_script_available("bc250-cec.sh")
        cpu_control_available = self._trusted_root_file(CPU_HELPER_PATH)
        toolkit_available = (
            self._user_script_available("bc250-40cu.sh")
            and power_available
            and cec_available
        )
        cu, power, gpu, cpu, cec = await asyncio.gather(
            self.get_cu_status(),
            self.get_power_status(),
            self.get_gpu_status(),
            self.get_cpu_status(),
            self.get_cec_status(),
        )
        return {
            "toolkit": {
                "available": toolkit_available,
                "privileged": os.geteuid() == 0,
                "powerAvailable": power_available,
                "cpuControlAvailable": cpu_control_available,
                "cecAvailable": cec_available,
                "path": str(self.toolkit),
            },
            "cu": cu,
            "power": power,
            "gpu": gpu,
            "cpu": cpu,
            "cec": cec,
        }

    async def get_snapshot(self) -> dict[str, Any]:
        async with self._mutation_lock:
            return await self._get_snapshot()

    async def _mutate(self, callback: Any) -> None:
        async with self._mutation_lock:
            await callback()

    async def set_cu_wgp(
        self, se: int, sh: int, wgp: int, enabled: bool
    ) -> None:
        if any(type(value) is not int for value in (se, sh, wgp)):
            raise CommandError("CU routing coordinates must be whole numbers.")
        if se not in {0, 1} or sh not in {0, 1} or wgp not in range(5):
            raise CommandError("CU routing coordinates are out of range.")
        if type(enabled) is not bool:
            raise CommandError("CU routing state must be a boolean.")

        async def action() -> None:
            if not self._bc250_present():
                raise CommandError("BC-250 GPU was not detected; refusing register writes.")
            umr = self._trusted_umr()
            manager = self._trusted_cu_manager()
            if umr is None or manager is None:
                raise CommandError(
                    "A root-owned UMR and CU manager installation is required."
                )
            if await self._umr_register(
                "mmSPI_PG_ENABLE_STATIC_WGP_MASK", se, sh
            ) is None:
                raise CommandError(
                    "UMR could not verify the live routing register; no change was made."
                )
            factory_masks = await self._factory_cu_masks()
            if factory_masks is None:
                raise CommandError(
                    "The factory 24-CU map is unavailable; no change was made."
                )
            factory_mask = factory_masks[se * 2 + sh]
            if factory_mask & (0x3 << (wgp * 2)):
                raise CommandError("Factory-enabled CUs are locked and cannot be changed.")

            config = self._read_key_values(CU_CONFIG_PATH)
            asic = config.get("UMR_ASIC", "cyan_skillfish.gfx1013")
            if not re.fullmatch(r"[A-Za-z0-9_.-]+", asic):
                raise CommandError("The configured UMR ASIC selector is invalid.")
            env = {
                "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                "HOME": "/root",
                "USER": "root",
                "LOGNAME": "root",
                "UMR": str(umr),
                "UMR_ASIC": asic,
            }
            database = self._trusted_umr_database(umr)
            if database is not None:
                env["UMR_DATABASE_PATH"] = str(database)
            instance = self._umr_instance()
            if instance is not None:
                env["UMR_INSTANCE"] = str(instance)
            command = "enable-wgp" if enabled else "disable-wgp"
            await self._exec(
                [str(manager), "--yes", command, f"{se}.{sh}.{wgp}"],
                timeout=30,
                env=env,
            )

        return await self._mutate(action)

    async def set_gpu_frequency(
        self, mode: str, minimum: int, maximum: int
    ) -> None:
        if type(mode) is not str or mode not in {"adaptive", "max", "pin", "range"}:
            raise CommandError("Unknown GPU frequency mode.")
        if type(minimum) is not int or type(maximum) is not int:
            raise CommandError("GPU frequencies must be whole numbers.")
        if mode == "pin" and not 100 <= maximum <= 2150:
            raise CommandError("Pinned frequency must be 100-2150 MHz.")
        if mode == "range":
            if not 0 <= minimum <= 2150 or not 100 <= maximum <= 2150:
                raise CommandError("Frequency range must be within 0-2150 MHz.")
            if minimum and minimum > maximum:
                raise CommandError("Minimum frequency exceeds maximum frequency.")

        async def action() -> None:
            state_path = GPU_STATE_PATH
            if state_path.is_symlink() or (
                state_path.exists() and not state_path.is_file()
            ):
                raise CommandError(f"GPU frequency state is unsafe: {state_path}")
            previous = (
                state_path.read_text(encoding="utf-8") if state_path.exists() else None
            )
            previous_values = self._read_key_values(state_path)
            previous_mode = previous_values.get("MODE", "adaptive")
            previous_first = self._safe_int(previous_values.get("A"))
            previous_second = self._safe_int(previous_values.get("B"))

            first = maximum if mode == "pin" else minimum if mode == "range" else 0
            second = maximum if mode == "range" else 0
            self._write_frequency_state(mode, first, second)
            try:
                await self._apply_frequency(mode, first, second)
            except BaseException as error:
                async def rollback() -> None:
                    if previous is None:
                        self._write_frequency_state("adaptive")
                    else:
                        self._atomic_write(state_path, previous)
                    await self._apply_frequency(
                        previous_mode, previous_first, previous_second
                    )

                rollback_task = asyncio.ensure_future(rollback())
                try:
                    await asyncio.shield(rollback_task)
                except asyncio.CancelledError:
                    await rollback_task
                except Exception as rollback_error:
                    raise CommandError(
                        f"{error}; frequency rollback failed: {rollback_error}"
                    ) from error
                raise error

        return await self._mutate(action)

    async def set_load_target(self, preset: str) -> None:
        if type(preset) is not str or preset not in {"eager", "reset"}:
            raise CommandError("Unknown load-target preset.")

        async def action() -> None:
            upper, lower = (0.40, 0.10) if preset == "eager" else (0.80, 0.65)

            async def apply_live() -> None:
                await self._gpu_call(
                    "SetLoadTarget", "dd", f"{lower:.2f}", f"{upper:.2f}"
                )

            await self._update_gpu_config(
                {"load-target": {"upper": f"{upper:.2f}", "lower": f"{lower:.2f}"}},
                live_callback=apply_live,
            )

        return await self._mutate(action)

    async def set_custom_load_target(self, minimum: int, maximum: int) -> None:
        if type(minimum) is not int or type(maximum) is not int:
            raise CommandError("GPU load targets must be whole percentages.")
        if not 0 < minimum < maximum < 100:
            raise CommandError(
                "Minimum GPU load must be below maximum load and both must be 1-99%."
            )

        async def action() -> None:
            lower = minimum / 100
            upper = maximum / 100

            async def apply_live() -> None:
                await self._gpu_call(
                    "SetLoadTarget", "dd", f"{lower:.2f}", f"{upper:.2f}"
                )

            await self._update_gpu_config(
                {"load-target": {"upper": f"{upper:.2f}", "lower": f"{lower:.2f}"}},
                live_callback=apply_live,
            )

        return await self._mutate(action)

    async def set_ramp(self, climb_ms: int) -> None:
        if type(climb_ms) is not int or not 200 <= climb_ms <= 5000:
            raise CommandError("Ramp time must be a whole number from 200-5000 ms.")

        async def action() -> None:
            config = self._read_toml(GPU_CONFIG_PATH)
            frequency = config.get("frequency-range", {})
            load = config.get("load-target", {})
            allowed_min, allowed_max = await asyncio.gather(
                self._system_bus_property(
                    "/com/cyanskillfish/Governor/Range/Allowed",
                    "com.cyanskillfish.Governor.Range",
                    "Min",
                ),
                self._system_bus_property(
                    "/com/cyanskillfish/Governor/Range/Allowed",
                    "com.cyanskillfish.Governor.Range",
                    "Max",
                ),
            )
            configured_min = (
                self._number(frequency.get("min"))
                if isinstance(frequency, dict)
                else None
            )
            configured_max = (
                self._number(frequency.get("max"))
                if isinstance(frequency, dict)
                else None
            )
            minimum = max(configured_min or allowed_min or 500, allowed_min or 0)
            maximum = min(configured_max or allowed_max or 2200, allowed_max or 9999)
            if maximum <= minimum:
                raise CommandError("GPU operating range is invalid.")
            upper = self._number(load.get("upper")) if isinstance(load, dict) else None
            lower = self._number(load.get("lower")) if isinstance(load, dict) else None
            upper = float(upper if upper is not None else 0.80)
            lower = float(lower if lower is not None else 0.65)
            if not 0 < lower < upper < 1:
                raise CommandError("GPU load targets are invalid.")
            span = maximum - minimum
            normal = span / climb_ms
            ceiling = minimum * (upper - lower) / upper
            step = max(30.0, 0.7 * ceiling)
            adjust_ms = max(50, min(200, round(step / normal)))
            actual_step = normal * adjust_ms
            if actual_step > ceiling >= 30:
                actual_step = ceiling
                normal = actual_step / adjust_ms
            down_events = max(2, round(1000 / adjust_ms))
            timing = config.get("timing", {})
            rates = (
                timing.get("ramp-rates", {}) if isinstance(timing, dict) else {}
            )
            burst_value = (
                self._number(rates.get("burst"))
                if isinstance(rates, dict)
                else None
            )
            burst = float(burst_value if burst_value is not None else 50)
            if burst <= normal:
                burst = 200 * normal
            await self._update_gpu_config(
                {
                    "timing.intervals": {"adjust": str(adjust_ms * 1000)},
                    "timing.ramp-rates": {
                        "normal": f"{normal:.3g}",
                        "burst": f"{burst:.3g}",
                    },
                    "timing": {"down-events": str(down_events)},
                },
                restart=True,
            )

        return await self._mutate(action)

    async def cpu_oc_action(
        self, action_name: str, frequency: int, voltage: int, temperature: int
    ) -> None:
        if type(action_name) is not str or action_name not in {
            "detect",
            "apply",
            "enable",
            "off",
        }:
            raise CommandError("Unknown CPU overclock action.")
        if action_name == "detect":
            if any(
                type(value) is not int
                for value in (frequency, voltage, temperature)
            ):
                raise CommandError("CPU tuning values must be whole numbers.")
            if not 3500 <= frequency <= 4500:
                raise CommandError("CPU target must be between 3500 and 4500 MHz.")
            if not 950 <= voltage <= 1325:
                raise CommandError("CPU VID limit must be between 950 and 1325 mV.")
            if not 50 <= temperature <= 100:
                raise CommandError(
                    "CPU temperature limit must be between 50 and 100 C."
                )

        async def action() -> None:
            args = ["cpu-oc", action_name]
            if action_name == "detect":
                args.extend((str(frequency), str(voltage), str(temperature)))
            await self._cpu_tool(
                *args,
                timeout=1800 if action_name == "detect" else 180,
            )

        return await self._mutate(action)

    async def cec_action(self, action_name: str) -> None:
        if type(action_name) is not str or action_name not in {
            "tv-on",
            "tv-off",
            "amp-on",
            "amp-off",
            "switch",
            "release",
            "vol-up",
            "vol-down",
            "mute",
        }:
            raise CommandError("Unknown CEC action.")

        async def action() -> None:
            await self._user_tool("bc250-cec.sh", action_name, timeout=15)

        return await self._mutate(action)

    async def set_cec_toggle(self, key: str, enabled: bool) -> None:
        if type(key) is not str or key not in {
            "wake-tv",
            "suspend-tv",
            "allow-standby",
            "uinput",
        }:
            raise CommandError("Unknown CEC toggle.")
        if type(enabled) is not bool:
            raise CommandError("CEC toggle state must be a boolean.")

        async def action() -> None:
            await self._user_tool(
                "bc250-cec.sh",
                "toggle",
                key,
                "on" if enabled else "off",
                timeout=20,
            )
            if key == "uinput":
                await self._user_exec(
                    [SYSTEMCTL, "--user", "restart", "cecd.service"],
                    timeout=10,
                )

        return await self._mutate(action)

    async def set_cec_name(self, name: str) -> None:
        if type(name) is not str:
            raise CommandError("CEC broadcast name must be text.")
        try:
            byte_length = len(name.encode("utf-8"))
        except UnicodeEncodeError as error:
            raise CommandError("CEC broadcast name contains invalid text.") from error
        if not name.strip() or byte_length > 14:
            raise CommandError("CEC broadcast name must be 1-14 bytes.")
        if not name.isprintable() or '"' in name or "\\" in name:
            raise CommandError(
                "CEC broadcast name cannot contain control characters, quotes, or backslashes."
            )

        async def action() -> None:
            await self._user_tool("bc250-cec.sh", "osd-name", name, timeout=20)

        return await self._mutate(action)
