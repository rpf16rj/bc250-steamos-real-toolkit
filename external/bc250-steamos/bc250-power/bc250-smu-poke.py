#!/usr/bin/env python3
# EXPERIMENTAL userspace SMU poker for the BC-250 (Robin 3.00).
#
# Talks to the SMU straight from userspace over PCI config space — no kernel
# module, no MMIO. Model taken from bc250-collective/bc250_smu_oc: an SMN
# index/data window at config offsets 0xB8/0xBC, and per-queue (cmd,rsp,arg)
# SMN register triples. Handler semantics from bc250-power/SMU-HANDLERS.md.
#
#   sudo ./bc250-smu-poke.py                    # probe SMU (safe, Q3 only)
#   sudo ./bc250-smu-poke.py --read-features    # read the feature mask (Q0*)
#   sudo ./bc250-smu-poke.py --power-limit 60 --yes        # Q2 0x2c
#   sudo ./bc250-smu-poke.py --enable-features 0x40 --yes  # Q2 0x05 (bit 6)
#
# * --read-features and any write to Q0 RACE amdgpu (it owns Q0). Q2/Q3 are
#   safe alongside the driver. WRITES CAN HANG OR CRASH THE GPU — they change
#   live SMU state the driver assumes it controls. Untested; use on a box you
#   can hard-reboot. Default action writes nothing.

import argparse
import fcntl
import os
import struct
import sys
from contextlib import contextmanager

# (cmd, rsp, arg) SMN register addresses per queue (from bc250_smu_oc).
QUEUE = {
    0: (0x03B10A08, 0x03B10A68, 0x03B10A48),  # amdgpu-owned — racy
    2: (0x03B10528, 0x03B10564, 0x03B10998),  # safe
    3: (0x03B10A20, 0x03B10A80, 0x03B10A88),  # safe (bc250_smu_oc uses this)
}
DONE = {0x01: "OK", 0xFF: "FAILED", 0xFE: "UNKNOWN_CMD",
        0xFD: "REJECTED_PREREQ", 0xFC: "REJECTED_BUSY"}
OK = 0x01


class Smu:
    def __init__(self, bdf="0000:00:00.0"):
        self.fd = os.open(f"/sys/bus/pci/devices/{bdf}/config",
                          os.O_RDWR | os.O_CLOEXEC)

    def _w32(self, off, val):
        os.pwrite(self.fd, struct.pack("<I", val & 0xFFFFFFFF), off)

    def _r32(self, off):
        return struct.unpack("<I", os.pread(self.fd, 4, off))[0]

    @contextmanager
    def transaction(self):
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(self.fd, fcntl.LOCK_UN)

    def close(self):
        os.close(self.fd)

    def __enter__(self):
        return self

    def __exit__(self, _exc_type, _exc_value, _traceback):
        self.close()

    def rd(self, reg):                 # read SMN register via 0xB8/0xBC
        self._w32(0xB8, reg)
        return self._r32(0xBC)

    def wr(self, reg, val):
        self._w32(0xB8, reg)
        self._w32(0xBC, val)

    def send(self, q, msg, arg=0, arg_high=0, timeout=100):
        cmd, rsp, argr = QUEUE[q]
        self.wr(rsp, 0)
        self.wr(argr, arg & 0xFFFFFFFF)
        self.wr(argr + 4, arg_high & 0xFFFFFFFF)
        self.wr(cmd, msg)
        s = 0
        for _ in range(timeout):
            s = self.rd(rsp)
            if s in DONE:
                return s
        return s

    def read_arg(self, q):
        return self.rd(QUEUE[q][2])

    def read_arg_high(self, q):
        return self.rd(QUEUE[q][2] + 4)


def probe(smu):
    # TestMessage (Q3 msg 0x01) returns arg+1 — safe, Q3 is not driver-owned.
    with smu.transaction():
        s = smu.send(3, 0x01, arg=123)
        if s != OK:
            sys.exit(f"probe failed: status 0x{s:02X} ({DONE.get(s,'?')})")
        r = smu.read_arg(3)
    if r != 124:
        sys.exit(f"probe bad response: {r} (expected 124)")
    print("SMU probe OK (Q3 TestMessage 123 -> 124)")


def read_features(smu):
    # GetEnabledSmuFeatures = Q0 msg 0x3D. Q0 is amdgpu-owned -> racy read.
    print("WARNING: reading on Q0 races amdgpu (usually tolerable for one read)")
    with smu.transaction():
        s = smu.send(0, 0x3D)
        if s != OK:
            sys.exit(f"GetEnabledSmuFeatures failed: 0x{s:02X} ({DONE.get(s,'?')})")
        lo, hi = smu.read_arg(0), smu.read_arg_high(0)
    mask = (hi << 32) | lo
    bits = [i for i in range(64) if mask & (1 << i)]
    print(f"enabled feature mask = 0x{mask:016X}")
    print(f"enabled bits = {bits}")
    print("feature roster (names, bit positions unconfirmed): tdc, edc, thermal,")
    print("  prochot, cclk_controller, gfx_dpm, fclk_dpm, pll_power_down, stapm,")
    print("  cstate_boost, umc_cal_sharing  (see SMU-HANDLERS.md)")


def main():
    ap = argparse.ArgumentParser(description="Experimental BC-250 SMU poker (Robin 3.00)")
    ap.add_argument("--bdf", default="0000:00:00.0", help="PCI BDF of the BC-250 device")
    ap.add_argument("--read-features", action="store_true", help="read GetEnabledSmuFeatures (Q0, racy)")
    ap.add_argument("--power-limit", type=int, metavar="W", help="Q2 0x2c set_power_limit (watts)")
    ap.add_argument("--enable-features", type=lambda x: int(x, 0), metavar="MASK", help="Q2 0x05 enable_smu_features")
    ap.add_argument("--disable-features", type=lambda x: int(x, 0), metavar="MASK", help="Q2 0x06 disable_smu_features")
    ap.add_argument("--yes", action="store_true", help="confirm a write (required for any write)")
    args = ap.parse_args()

    if os.geteuid() != 0:
        sys.exit("must run as root (PCI config space access)")

    with Smu(args.bdf) as smu:
        probe(smu)

        if args.read_features:
            read_features(smu)

        writes = [("--power-limit", args.power_limit, 2, 0x2C),
                  ("--enable-features", args.enable_features, 2, 0x05),
                  ("--disable-features", args.disable_features, 2, 0x06)]
        pending = [(n, v, q, m) for (n, v, q, m) in writes if v is not None]
        if pending and not args.yes:
            sys.exit("refusing to write without --yes (writes can hang the GPU)")
        for name, val, q, msg in pending:
            if val < 0 or val > 0xFFFFFFFF:
                sys.exit(f"{name} must be between 0 and 0xffffffff")
            if name == "--power-limit" and not 1 <= val <= 200:
                sys.exit("--power-limit must be between 1 and 200 W")
            print(f"WRITE {name}={val} -> Q{q} msg 0x{msg:02X}")
            with smu.transaction():
                s = smu.send(q, msg, arg=val)
            print(f"  status 0x{s:02X} ({DONE.get(s,'?')})")
            if s != OK:
                sys.exit(1)


if __name__ == "__main__":
    main()
