import asyncio
import json
import os
import re
import shlex
from pathlib import Path

import decky


STATE_DIR = Path("/var/lib/toolkit-steamos-control")
FAN_CONFIG = STATE_DIR / "fan.json"
FAN_SERVICE = "toolkit-steamos-fan.service"
FAN_UNIT = Path("/etc/systemd/system/toolkit-steamos-fan.service")
LED_SERVICE = "steamos-led.service"
LED_DROPIN = Path("/etc/systemd/system/steamos-led.service.d/toolkit-steamos-control.conf")
DEFAULT_CONFIG = {
    "mode": "automatic",
    "manual_percent": 50,
    "active_profile": "Balanced",
    "profiles": {
        "Quiet": [[45, 25], [60, 45], [75, 75], [90, 100]],
        "Balanced": [[45, 30], [60, 55], [75, 85], [90, 100]],
        "Performance": [[40, 40], [55, 65], [70, 90], [80, 100]],
    },
}


class Plugin:
    def __init__(self):
        self.root = Path(__file__).parent
        self.lock = asyncio.Lock()

    @staticmethod
    def _read(path, fallback=""):
        try:
            return Path(path).read_text().strip()
        except OSError:
            return fallback

    def _load_config(self):
        config = json.loads(json.dumps(DEFAULT_CONFIG))
        try:
            saved = json.loads(FAN_CONFIG.read_text())
            config.update({key: value for key, value in saved.items() if key in config})
        except (OSError, ValueError, TypeError):
            pass
        return config

    def _save_config(self, config):
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        temporary = FAN_CONFIG.with_suffix(".tmp")
        temporary.write_text(json.dumps(config, indent=2) + "\n")
        temporary.replace(FAN_CONFIG)

    async def _run(self, *args, check=True):
        process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env={key: value for key, value in os.environ.items() if key != "LD_LIBRARY_PATH"},
        )
        stdout, stderr = await process.communicate()
        output = (stdout.decode(errors="replace") + stderr.decode(errors="replace")).strip()
        if check and process.returncode:
            raise RuntimeError(output or f"Command failed: {args[0]}")
        return process.returncode, output

    def _service_state(self, name):
        try:
            active = os.popen(f"/usr/bin/systemctl is-active {shlex.quote(name)} 2>/dev/null").read().strip()
            enabled = os.popen(f"/usr/bin/systemctl is-enabled {shlex.quote(name)} 2>/dev/null").read().strip()
        except OSError:
            active, enabled = "unknown", "unknown"
        return {"active": active, "enabled": enabled}

    def _pump_fan(self):
        for hwmon in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
            for label in hwmon.glob("fan*_label"):
                if self._read(label).strip().lower() != "pump fan":
                    continue
                match = re.fullmatch(r"fan(\d+)_label", label.name)
                if match is None:
                    continue
                channel = match.group(1)
                pwm = hwmon / f"pwm{channel}"
                if not pwm.is_file():
                    continue
                try:
                    raw = int(pwm.read_text().strip())
                except (OSError, ValueError):
                    continue
                name = self._read(hwmon / "name", hwmon.name)
                enable = pwm.with_name(f"pwm{channel}_enable")
                return {
                    "path": str(pwm), "device": name, "channel": pwm.name,
                    "rpm": self._read(hwmon / f"fan{channel}_input", "Unavailable"),
                    "percent": round(raw * 100 / 255),
                    "enable": self._read(enable, "unknown"),
                }
        return None

    def _temperature(self):
        values = []
        for path in Path("/sys/class/thermal").glob("thermal_zone*/temp"):
            try:
                values.append(int(path.read_text().strip()) / 1000)
            except (OSError, ValueError):
                pass
        for path in Path("/sys/class/drm").glob("card*/device/hwmon/hwmon*/temp*_input"):
            try:
                values.append(int(path.read_text().strip()) / 1000)
            except (OSError, ValueError):
                pass
        return round(max(values), 1) if values else None

    async def _install_fan_service(self):
        source = self.root / "fan_manager.py"
        if not source.is_file():
            raise RuntimeError("Fan manager helper is missing. Reinstall the plugin.")
        FAN_UNIT.write_text(
            "[Unit]\nDescription=Toolkit SteamOS Control managed Pump Fan curve\nAfter=multi-user.target\n\n"
            f"[Service]\nType=simple\nExecStart=/usr/bin/python3 {shlex.quote(str(source))}\nRestart=always\nRestartSec=2\n\n"
            "[Install]\nWantedBy=multi-user.target\n"
        )
        await self._run("/usr/bin/systemctl", "daemon-reload")

    async def get_status(self):
        config = self._load_config()
        return {
            "fan": {
                "available": self._pump_fan() is not None,
                "config": config,
                "device": self._pump_fan(),
                "temperature": self._temperature(),
                "service": self._service_state(FAN_SERVICE),
            },
            "led": await self._led_status(),
        }

    async def set_fan_mode(self, mode, manual_percent=50):
        if mode not in {"automatic", "manual", "managed"}:
            raise RuntimeError("Invalid fan mode")
        async with self.lock:
            if self._pump_fan() is None:
                raise RuntimeError("Pump Fan PWM control was not detected. Install the NCT6687 PWM driver first.")
            config = self._load_config()
            config["mode"] = mode
            config["manual_percent"] = max(0, min(100, int(manual_percent)))
            self._save_config(config)
            await self._install_fan_service()
            if mode == "managed":
                await self._run("/usr/bin/systemctl", "enable", "--now", FAN_SERVICE)
            else:
                await self._run("/usr/bin/systemctl", "disable", "--now", FAN_SERVICE, check=False)
                await self._run("/usr/bin/python3", str(self.root / "fan_manager.py"), "--apply-once")
        return await self.get_status()

    async def save_profile(self, name, points):
        clean_name = str(name).strip()
        if not re.fullmatch(r"[A-Za-z0-9 _-]{1,32}", clean_name):
            raise RuntimeError("Profile name must be 1-32 letters, numbers, spaces, _ or -")
        if not isinstance(points, list) or not 2 <= len(points) <= 8:
            raise RuntimeError("A profile requires between 2 and 8 curve points")
        clean_points = []
        last_temp = -1
        for point in points:
            temp, speed = int(point[0]), int(point[1])
            if not 30 <= temp <= 100 or not 0 <= speed <= 100 or temp <= last_temp:
                raise RuntimeError("Curve temperatures must rise from 30-100°C; speeds must be 0-100%")
            clean_points.append([temp, speed])
            last_temp = temp
        async with self.lock:
            config = self._load_config()
            config["profiles"][clean_name] = clean_points
            config["active_profile"] = clean_name
            self._save_config(config)
            if config["mode"] == "managed":
                await self._run("/usr/bin/systemctl", "restart", FAN_SERVICE)
        return await self.get_status()

    async def select_profile(self, name):
        async with self.lock:
            config = self._load_config()
            if name not in config["profiles"]:
                raise RuntimeError("Profile not found")
            config["active_profile"] = name
            self._save_config(config)
            if config["mode"] == "managed":
                await self._run("/usr/bin/systemctl", "restart", FAN_SERVICE)
        return await self.get_status()

    async def delete_profile(self, name):
        if name in {"Quiet", "Balanced", "Performance"}:
            raise RuntimeError("Built-in profiles cannot be deleted")
        async with self.lock:
            config = self._load_config()
            if name not in config["profiles"]:
                raise RuntimeError("Profile not found")
            del config["profiles"][name]
            if config["active_profile"] == name:
                config["active_profile"] = "Balanced"
            self._save_config(config)
        return await self.get_status()

    async def _led_status(self):
        _, unit = await self._run("/usr/bin/systemctl", "cat", LED_SERVICE, check=False)
        flags = {"temperature": "--temp" in unit, "audio": "--audio" in unit, "notifications": "--notify" in unit}
        return {"available": "ExecStart=" in unit, "effects": flags, "service": self._service_state(LED_SERVICE)}

    async def set_led_effects(self, temperature, audio, notifications):
        async with self.lock:
            _, unit = await self._run("/usr/bin/systemctl", "cat", LED_SERVICE, check=False)
            command = ""
            for line in unit.splitlines():
                if line.startswith("ExecStart="):
                    command = line.removeprefix("ExecStart=").strip()
            if not command:
                raise RuntimeError("SteamOS LED bar service was not found")
            try:
                argv = shlex.split(command)
            except ValueError as error:
                raise RuntimeError(f"Could not read LED service command: {error}") from error
            argv = [value for value in argv if value not in {"--temp", "--audio", "--notify"}]
            if temperature:
                argv.append("--temp")
            if audio:
                argv.append("--audio")
            if notifications:
                argv.append("--notify")
            LED_DROPIN.parent.mkdir(parents=True, exist_ok=True)
            LED_DROPIN.write_text("[Service]\nExecStart=\nExecStart=" + " ".join(shlex.quote(value) for value in argv) + "\n")
            await self._run("/usr/bin/systemctl", "daemon-reload")
            await self._run("/usr/bin/systemctl", "restart", LED_SERVICE)
        return await self.get_status()

    async def _main(self):
        decky.logger.info("Toolkit SteamOS Control started")

    async def _unload(self):
        decky.logger.info("Toolkit SteamOS Control stopped")
