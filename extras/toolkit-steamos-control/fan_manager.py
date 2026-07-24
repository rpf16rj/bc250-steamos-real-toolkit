#!/usr/bin/env python3
import json
import re
import time
from pathlib import Path

CONFIG = Path("/var/lib/toolkit-steamos-control/fan.json")


def load_config():
    return json.loads(CONFIG.read_text())


def temperature():
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
    return max(values) if values else None


def pump_pwm_path():
    for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
        for label in hwmon.glob("fan*_label"):
            try:
                if label.read_text().strip().lower() != "pump fan":
                    continue
            except OSError:
                continue
            match = re.fullmatch(r"fan(\d+)_label", label.name)
            if match is None:
                continue
            pwm = hwmon / f"pwm{match.group(1)}"
            if pwm.is_file():
                return pwm
    return None


def write_fan(percent, automatic=False):
    pwm = pump_pwm_path()
    if pwm is None:
        raise RuntimeError("Pump Fan PWM control was not detected")
    value = max(0, min(255, round(percent * 255 / 100)))
    enable = pwm.with_name(f"{pwm.name}_enable")
    if enable.is_file():
        enable.write_text("2\n" if automatic else "1\n")
    if not automatic:
        pwm.write_text(f"{value}\n")


def curve_speed(points, current):
    if current <= points[0][0]:
        return points[0][1]
    for (low_temp, low_speed), (high_temp, high_speed) in zip(points, points[1:]):
        if current <= high_temp:
            ratio = (current - low_temp) / (high_temp - low_temp)
            return round(low_speed + ratio * (high_speed - low_speed))
    return points[-1][1]


def apply_once():
    config = load_config()
    mode = config.get("mode", "automatic")
    if mode == "automatic":
        write_fan(0, automatic=True)
        return
    if mode == "manual":
        write_fan(config.get("manual_percent", 50))
        return
    points = config.get("profiles", {}).get(config.get("active_profile"), [])
    current = temperature()
    if current is not None and points:
        write_fan(curve_speed(points, current))


def main():
    if "--apply-once" in __import__("sys").argv:
        apply_once()
        return
    while True:
        try:
            apply_once()
        except (OSError, ValueError, TypeError, KeyError):
            pass
        time.sleep(2)


if __name__ == "__main__":
    main()
