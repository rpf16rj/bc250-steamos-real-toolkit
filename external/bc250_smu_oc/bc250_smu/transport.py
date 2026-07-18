import fcntl
import os
import struct
from typing import Optional


class Bc250PciTransport:
    def __init__(self, bdf: str, use_flock: bool = False):
        self._config_path = f"/sys/bus/pci/devices/{bdf}/config"
        self._use_flock = use_flock
        self._fd: Optional[int] = None

    def open(self) -> None:
        if self._fd is None:
            self._fd = os.open(self._config_path, os.O_RDWR | os.O_CLOEXEC)

    def close(self) -> None:
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None

    def _lock(self) -> None:
        if self._use_flock and self._fd is not None:
            fcntl.flock(self._fd, fcntl.LOCK_EX)

    def _unlock(self) -> None:
        if self._use_flock and self._fd is not None:
            fcntl.flock(self._fd, fcntl.LOCK_UN)

    def read_config32(self, offset: int) -> int:
        if self._fd is None:
            raise RuntimeError("transport not opened")
        self._lock()
        try:
            data = os.pread(self._fd, 4, offset)
        finally:
            self._unlock()
        return struct.unpack("<I", data)[0]

    def write_config32(self, offset: int, value: int) -> None:
        if self._fd is None:
            raise RuntimeError("transport not opened")
        data = struct.pack("<I", value)
        self._lock()
        try:
            os.pwrite(self._fd, data, offset)
        finally:
            self._unlock()

    def read_smu_reg(self, reg: int) -> int:
        self.write_config32(0xB8, reg)
        return self.read_config32(0xBC)

    def write_smu_reg(self, reg: int, value: int) -> None:
        self.write_config32(0xB8, reg)
        self.write_config32(0xBC, value)
