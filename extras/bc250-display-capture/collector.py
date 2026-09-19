#!/usr/bin/env python3
"""Persistent BC-250 display diagnostics collector.

This process is launched by a transient system systemd unit so it survives
KDE -> gamescope session changes. It intentionally only reads diagnostics.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import signal
import subprocess
import time

STOP = False


def stop(_signum: int, _frame: object) -> None:
    global STOP
    STOP = True


def now() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def read(path: str) -> str:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError as error:
        return f"<unavailable: {error}>"


def command(argv: list[str], timeout: float = 20) -> str:
    try:
        result = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"<command failed: {error}>"
    return result.stdout + (f"\n[stderr]\n{result.stderr}" if result.stderr else "")


def write_snapshot(path: pathlib.Path, label: str) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(f"\n===== {label} {now()} =====\n")
        stream.write("--- kernel cmdline ---\n")
        stream.write(read("/proc/cmdline") + "\n")
        stream.write("--- connector status ---\n")
        stream.write(read("/sys/class/drm/card0-DP-1/status") + "\n")
        stream.write("--- connector modes ---\n")
        stream.write(read("/sys/class/drm/card0-DP-1/modes") + "\n")
        stream.write("--- GPU clock ---\n")
        stream.write(read("/sys/class/drm/card0/device/pp_dpm_sclk") + "\n")
        stream.write("--- GPU busy ---\n")
        stream.write(read("/sys/class/drm/card0/device/gpu_busy_percent") + "\n")
        stream.write("--- module parameters ---\n")
        for name in ("bc250_hdmi21", "freesync_pcon_allow_all", "dcdebugmask", "dcfeaturemask"):
            stream.write(f"{name}: {read('/sys/module/amdgpu/parameters/' + name)}\n")
        stream.write("--- DRM info ---\n")
        stream.write(command(["/usr/bin/drm_info"]) + "\n")
        stream.write("--- modetest connectors ---\n")
        stream.write(command(["/usr/bin/modetest", "-M", "amdgpu", "-c"]) + "\n")
        stream.write("--- modetest properties ---\n")
        stream.write(command(["/usr/bin/modetest", "-M", "amdgpu", "-p"]) + "\n")
        stream.flush()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    os.chdir(output)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    pathlib.Path("metadata.txt").write_text(
        f"started={now()}\n" f"kernel={read('/proc/sys/kernel/osrelease')}\n",
        encoding="utf-8",
    )
    write_snapshot(pathlib.Path("snapshots.log"), "START")

    journal = subprocess.Popen(
        ["/usr/bin/journalctl", "-k", "-b", "-f", "-o", "short-monotonic"],
        stdout=pathlib.Path("kernel-live.log").open("w", encoding="utf-8"),
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        next_snapshot = time.monotonic() + 5
        with pathlib.Path("drm-state.log").open("w", encoding="utf-8") as state:
            while not STOP:
                state.write(
                    f"{now()} status={read('/sys/class/drm/card0-DP-1/status')} "
                    f"busy={read('/sys/class/drm/card0/device/gpu_busy_percent')} "
                    f"sclk={read('/sys/class/drm/card0/device/pp_dpm_sclk').replace(chr(10), ' | ')}\n"
                )
                state.flush()
                if time.monotonic() >= next_snapshot:
                    write_snapshot(pathlib.Path("snapshots.log"), "PERIODIC")
                    next_snapshot = time.monotonic() + 5
                time.sleep(1)
    finally:
        journal.terminate()
        try:
            journal.wait(timeout=3)
        except subprocess.TimeoutExpired:
            journal.kill()
        write_snapshot(pathlib.Path("snapshots.log"), "STOP")
        pathlib.Path("metadata.txt").open("a", encoding="utf-8").write(f"stopped={now()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
