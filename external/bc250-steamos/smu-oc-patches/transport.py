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

    def _read_config32_unlocked(self, offset: int) -> int:
        if self._fd is None:
            raise RuntimeError("transport not opened")
        data = os.pread(self._fd, 4, offset)
        return struct.unpack("<I", data)[0]

    def _write_config32_unlocked(self, offset: int, value: int) -> None:
        if self._fd is None:
            raise RuntimeError("transport not opened")
        os.pwrite(self._fd, struct.pack("<I", value), offset)

    def read_config32(self, offset: int) -> int:
        self._lock()
        try:
            return self._read_config32_unlocked(offset)
        finally:
            self._unlock()

    def write_config32(self, offset: int, value: int) -> None:
        self._lock()
        try:
            self._write_config32_unlocked(offset, value)
        finally:
            self._unlock()

    # The 0xB8 (address) / 0xBC (data) pair is a shared indirect window:
    # another SMU client (e.g. cyan-skillfish-governor-smu, which flocks the
    # same config file) may move 0xB8 between our two accesses. Hold the
    # lock across the whole pair, not per 32-bit access.
    def read_smu_reg(self, reg: int) -> int:
        self._lock()
        try:
            self._write_config32_unlocked(0xB8, reg)
            return self._read_config32_unlocked(0xBC)
        finally:
            self._unlock()

    def write_smu_reg(self, reg: int, value: int) -> None:
        self._lock()
        try:
            self._write_config32_unlocked(0xB8, reg)
            self._write_config32_unlocked(0xBC, value)
        finally:
            self._unlock()
