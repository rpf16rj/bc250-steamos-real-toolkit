from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import pwd
import shutil
import subprocess
import tarfile
from typing import Any

import decky


SERVICE = "bc250-display-capture.service"
PLUGIN_NAME = "BC-250 Display Capture"


class Plugin:
    def __init__(self) -> None:
        self.user = decky.DECKY_USER
        self.home = pathlib.Path(decky.DECKY_USER_HOME)
        self.capture_root = self.home / "bc250-display-captures"
        self.collector = pathlib.Path(__file__).with_name("collector.py")

    async def _main(self) -> None:
        self.capture_root.mkdir(mode=0o755, exist_ok=True)
        decky.logger.info("%s backend started", PLUGIN_NAME)

    async def _unload(self) -> None:
        decky.logger.info("%s backend stopped", PLUGIN_NAME)

    def _active(self) -> bool:
        result = subprocess.run(
            ["/usr/bin/systemctl", "is-active", "--quiet", SERVICE],
            check=False,
        )
        return result.returncode == 0

    def _latest_dir(self) -> pathlib.Path | None:
        dirs = [path for path in self.capture_root.glob("20*") if path.is_dir()]
        return max(dirs, default=None, key=lambda path: path.name)

    def _latest_archive(self) -> pathlib.Path | None:
        archives = list(self.capture_root.glob("*.tar.gz"))
        return max(archives, default=None, key=lambda path: path.stat().st_mtime)

    async def get_status(self) -> dict[str, Any]:
        latest = self._latest_dir()
        archive = self._latest_archive()
        return {
            "running": self._active(),
            "directory": str(latest) if latest else "",
            "archive": str(archive) if archive else "",
        }

    async def start_capture(self) -> dict[str, Any]:
        if self._active():
            return await self.get_status()

        self.capture_root.mkdir(mode=0o755, exist_ok=True)
        name = dt.datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
        output = self.capture_root / name
        output.mkdir(mode=0o755)
        command = [
            "/usr/bin/systemd-run",
            "--unit=bc250-display-capture",
            "--description=BC-250 display diagnostic capture",
            "--collect",
            "/usr/bin/python3",
            str(self.collector),
            "--output",
            str(output),
        ]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            shutil.rmtree(output, ignore_errors=True)
            raise RuntimeError(result.stderr.strip() or result.stdout.strip() or "Unable to start capture")
        return await self.get_status()

    async def stop_capture(self) -> dict[str, Any]:
        if self._active():
            result = subprocess.run(
                ["/usr/bin/systemctl", "stop", SERVICE],
                capture_output=True,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(result.stderr.strip() or "Unable to stop capture")

        directory = self._latest_dir()
        if directory and not (self.capture_root / f"{directory.name}.tar.gz").exists():
            archive = self.capture_root / f"{directory.name}.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(directory, arcname=directory.name)
            owner = pwd.getpwnam(self.user)
            for root, dirs, files in os.walk(directory):
                for name in dirs + files:
                    os.chown(os.path.join(root, name), owner.pw_uid, owner.pw_gid)
            for path in self.capture_root.glob(f"{directory.name}*"):
                os.chown(path, owner.pw_uid, owner.pw_gid)
        return await self.get_status()
