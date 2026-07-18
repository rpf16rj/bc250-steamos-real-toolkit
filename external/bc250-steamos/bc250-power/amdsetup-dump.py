#!/usr/bin/env python3
# Read-only dump of the BC-250's live AMD CBS/SMU power knobs.
#
# Every knob in the "CHIPSETMENU" BIOS (SMU Features / SMU Debug / DF Debug /
# DRAM Power / etc.) is a byte offset into ONE UEFI variable, AmdSetup. This
# script reads that variable straight out of efivarfs and decodes each knob's
# current value — so you can see what is Auto vs explicitly set BEFORE changing
# anything. It never writes.
#
#   sudo ./amdsetup-dump.py            # decode the live variable
#   sudo ./amdsetup-dump.py -b out.bin # also save a raw backup of the 2229 bytes
#
# Offsets/labels were extracted from BC250_3.00_CHIPSETMENU.ROM (CbsSetupDxe
# IFR). If you flash a different BIOS build, re-extract — offsets can move.
#
# To CHANGE a knob (not done here): the variable is immutable by default, so
#   sudo chattr -i <efivar>
#   then write byte (4-byte attr header precedes the data, so file pos = 4+off)
#   reboot — AGESA consumes AmdSetup at POST.
# Change ONE knob at a time and keep a recovery SPI flash handy.

import os, sys, glob, struct

VAR  = "AmdSetup"
GUID = "3a997502-647a-4c82-998e-52ef9486a247"
SIZE = 2229  # data bytes (excludes the 4-byte efivarfs attribute header)

# (offset, name, type, width, {value: label})
KNOBS = [(5, 'Global C-state Control', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (8, 'SMTEN', 'oneof', 1, {0: 'Disable', 1: 'Auto'}), (584, 'DF Pstate change quiesce ctrl', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (585, 'DF Cstate clk pwr down ctrl', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (586, 'DF Cstate self refresh ctrl', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (587, 'DF Cstate GMI pwr dn ctrl', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (588, 'DF Cstate xGMI pwr dn ctrl', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 3: 'Auto'}), (644, 'PCIe Memory Power Deep Sleep in L1', 'oneof', 1, {15: 'Auto', 0: 'Disabled', 1: 'Enabled'}), (739, 'NBIO Global CG Override', 'oneof', 1, {15: 'Auto', 0: 'Disabled'}), (740, 'MMHUB Light Sleep', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (865, 'Power Down Enable', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 255: 'Auto'}), (866, 'Power Down Mode', 'oneof', 1, {0: 'Channel', 1: 'Chip Select', 255: 'Auto'}), (867, 'Power Down Delay Control', 'oneof', 1, {1: 'Manual', 255: 'Auto'}), (868, 'Power Down Delay', 'numeric', 1, {}), (869, 'Aggressive Power Down Enable', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 255: 'Auto'}), (870, 'Aggressive Power Down Delay Control', 'oneof', 1, {1: 'Manual', 255: 'Auto'}), (871, 'Aggressive Power Down Delay', 'numeric', 1, {}), (873, 'Power Down Phy Power Save Disable', 'oneof', 1, {0: '0', 1: '1', 255: 'Auto'}), (877, 'Memory P-state', 'oneof', 1, {255: 'Auto', 1: 'Enabled', 0: 'Disabled'}), (1697, 'THERMAL', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1698, 'PLL_POWER_DOWN', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1699, 'FCLK_DPM', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1701, 'DS_GFXCLK', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1702, 'DS_SOCCLK', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1704, 'CORE_CSTATES', 'oneof', 1, {0: 'Disable', 1: 'Enable', 15: 'Auto'}), (1707, 'SOC_DPM', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1719, 'DS_MP3FCLK', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1727, 'PPT', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1728, 'STAPM', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1729, 'CSTATE_BOOST', 'oneof', 1, {0: 'Disabled', 1: 'Enabled', 15: 'Auto'}), (1730, 'Thermal Control', 'oneof', 1, {1: 'Manual', 0: 'Auto'}), (1804, 'FAST_PPT_LIMIT', 'numeric', 1, {}), (1808, 'SLOW_PPT_LIMIT', 'numeric', 1, {}), (1812, 'SLOW_PPT_TIME_CONSTANT', 'numeric', 1, {}), (1816, 'VRM_CURRENT_LIMIT', 'numeric', 1, {}), (1820, 'VRM_MAXIMUM_CURRENT_LIMIT', 'numeric', 1, {}), (1840, 'GfxClkDfll', 'oneof', 1, {255: 'Auto', 0: 'Gfx CLK use original DFS', 1: 'Gfx CLK uses DFLL'})]

def find_var():
    cands  = glob.glob(f"/sys/firmware/efi/efivars/{VAR}-{GUID}")
    cands += glob.glob(f"/sys/firmware/efi/efivars/{VAR}-*")
    return cands[0] if cands else None

def main():
    backup = None
    if "-b" in sys.argv:
        i = sys.argv.index("-b")
        backup = sys.argv[i + 1] if i + 1 < len(sys.argv) else "amdsetup.bin"

    if not os.path.isdir("/sys/firmware/efi"):
        sys.exit("not booted in UEFI mode (no /sys/firmware/efi) — run on the BC-250")
    path = find_var()
    if not path:
        sys.exit(f"variable {VAR}-{GUID} not found in efivarfs.\n"
                 f"Enter the BIOS setup once and save, or confirm this is the CHIPSETMENU BIOS.")

    raw = open(path, "rb").read()
    if len(raw) < 4:
        sys.exit(f"{path}: too short ({len(raw)} bytes)")
    attr = struct.unpack_from("<I", raw, 0)[0]
    data = raw[4:]                      # first 4 bytes = EFI variable attributes
    print(f"# {os.path.basename(path)}")
    print(f"# attributes=0x{attr:08x}  data={len(data)} bytes (expected ~{SIZE})\n")
    if len(data) < SIZE:
        print(f"WARNING: variable shorter than expected — offsets may not line up.\n")

    print(f"  {'offset':7} {'knob':36} {'raw':>4}  decoded")
    print(f"  {'-'*7} {'-'*36} {'-'*4}  {'-'*24}")
    setcount = 0
    for off, name, typ, width, opts in KNOBS:
        if off + width > len(data):
            print(f"  0x{off:04x}  {name:36} --   (past end of variable)")
            continue
        val = int.from_bytes(data[off:off + width], "little")
        if typ == "numeric":
            dec = f"{val}  (raw; PPT/VRM likely watts/amps — check menu range)"
        else:
            lbl = opts.get(val)
            dec = lbl if lbl is not None else f"?? (undecoded value {val})"
            if lbl not in (None, "Auto"):
                setcount += 1
        print(f"  0x{off:04x}  {name:36} {val:>4}  {dec}")

    print(f"\n# {setcount} oneof knob(s) explicitly set (not Auto).")
    if backup:
        open(backup, "wb").write(data)
        print(f"# raw {len(data)}-byte variable data written to {backup}")

if __name__ == "__main__":
    main()
