#!/usr/bin/env python3
"""Patch a display EDID to enable FreeSync VRR over a PCON (DP→HDMI) connection.

When a display with HDMI 2.1 VRR (VTEM) is connected via a DP→HDMI PCON adapter,
the amdgpu driver may use VTEM packets which the PCON does not support, causing
flickering. This script works around that by:
  1. Zeroing VRR min/max in the existing HF-VSDB (keeps ALLM, HDR10+, etc.)
     so the driver does not detect HDMI VRR and avoids VTEM packets
  2. Replacing the display's native AMD VSDB (if any) with a v1 format VSDB,
     because the DMUB firmware on the Steam Deck only recognizes AMD VSDB v1

The VRR min/max range is extracted from the existing HF-VSDB or AMD VSDB.
If neither has VRR data, defaults to 48-120 Hz.

Requires amdgpu.freesync_pcon_allow_all=1 in kernel cmdline.

Usage:
  python3 patch_edid_vrr.py [input_edid.bin] [output_edid.bin]

If no arguments, reads from /sys/class/drm/card0-DP-1/edid and writes to stdout path.
"""

import struct
import sys

def checksum_block(block):
    s = sum(block[:127]) & 0xFF
    return (256 - s) & 0xFF

HDMI_FORUM_OUI = 0xC45DD8
AMD_OUI = 0x00001A

def build_amd_vsdb_v1(min_hz, max_hz):
    payload = bytearray()
    payload.append(0x1A)  # OUI AMD (LE)
    payload.append(0x00)
    payload.append(0x00)
    payload.append(0x01)  # Version 1
    payload.extend(struct.pack('<H', min_hz))
    payload.extend(struct.pack('<H', max_hz))
    tag = 0x03
    length = len(payload)
    return bytes([(tag << 5) | length] + list(payload))

def get_block_oui(block):
    """Extract OUI from a vendor-specific block.
    tag=3: OUI at bytes 1,2,3 (LE)
    tag=7 with ext_tag=0x01: OUI at bytes 2,3,4 (LE)"""
    if len(block) < 4:
        return None
    tag = (block[0] >> 5) & 0x07
    if tag == 3:
        return f"{block[1]:02X}-{block[2]:02X}-{block[3]:02X}"
    elif tag == 7 and len(block) >= 5 and block[1] == 0x01:
        return f"{block[2]:02X}-{block[3]:02X}-{block[4]:02X}"
    return None

def parse_detailed_timing(dt):
    """Parse an 18-byte detailed timing descriptor, return (h_active, v_active, refresh_hz) or None."""
    if dt[0] == 0 and dt[1] == 0:
        return None  # Not a timing, it's a descriptor
    pixel_clock_hz = (dt[0] | (dt[1] << 8)) * 10000  # 10kHz units → Hz
    if pixel_clock_hz == 0:
        return None
    h_active = ((dt[4] >> 4) << 8) | dt[2]
    v_active = ((dt[7] >> 4) << 8) | dt[5]
    h_blanking = ((dt[4] & 0x0F) << 8) | dt[3]
    v_blanking = ((dt[7] & 0x0F) << 8) | dt[6]
    h_total = h_active + h_blanking
    v_total = v_active + v_blanking
    if h_total == 0 or v_total == 0:
        return None
    refresh = round(pixel_clock_hz / (h_total * v_total))
    return (h_active, v_active, refresh)

def swap_preferred_timing(edid, target_w, target_h, target_refresh):
    """Swap the first detailed timing with one matching target resolution/refresh.
    The first detailed timing in the base EDID is the 'preferred' mode."""
    swapped = False
    for i in range(4):
        offset = 54 + i * 18
        dt = edid[offset:offset + 18]
        info = parse_detailed_timing(dt)
        if info is None:
            continue
        h, v, r = info
        print(f"  Detailed timing {i}: {h}x{v}@{r}")
        if h == target_w and v == target_h and abs(r - target_refresh) <= 2:
            if i == 0:
                print(f"  Already preferred: {h}x{v}@{r}")
                return False
            # Swap timing 0 with timing i
            edid[54:72], edid[offset:offset + 18] = \
                edid[offset:offset + 18], edid[54:72]
            print(f"  Swapped detailed timing {i} → position 0 (preferred)")
            swapped = True
            break
    if not swapped:
        print(f"  No detailed timing matching {target_w}x{target_h}@{target_refresh} found")
    return swapped

def patch_edid(input_path, output_path):
    with open(input_path, 'rb') as f:
        edid = bytearray(f.read())

    # Swap preferred timing to 2560x1440@120 if available
    print("Checking detailed timings in base EDID:")
    if swap_preferred_timing(edid, 2560, 1440, 120):
        edid[127] = checksum_block(edid[:128])
        print(f"  Base block checksum updated: 0x{edid[127]:02X}")

    cta = bytearray(edid[128:256])
    dtd_start = cta[2]

    # Parse existing data blocks (bytes 4 to dtd_start)
    db_start = 4
    db_end = dtd_start if dtd_start > 0 else 127
    pos = db_start
    blocks = []
    while pos < db_end:
        tag = (cta[pos] >> 5) & 0x07
        length = cta[pos] & 0x1F
        block = cta[pos:pos + 1 + length]
        blocks.append(block)
        oui = get_block_oui(block) if tag in (3, 7) else None
        print(f"  pos={pos}: tag={tag} len={length}" + (f" OUI_LE={oui}" if oui else ""))
        pos += 1 + length

    print(f"Found {len(blocks)} data blocks, total={sum(len(b) for b in blocks)} bytes")

    # Save DTDs
    dtd_data = bytearray()
    if dtd_start > 0 and dtd_start < 127:
        dtd_data = cta[dtd_start:127]
        print(f"DTDs: {len(dtd_data)} bytes at offset {dtd_start}")

    # Extract VRR range from existing HF-VSDB or AMD VSDB before patching
    vrr_min_hz = 48
    vrr_max_hz = 120
    for b in blocks:
        tag = (b[0] >> 5) & 0x07
        if tag == 3 and len(b) >= 4:
            oui_val = (b[3] << 16) | (b[2] << 8) | b[1]
            if oui_val == HDMI_FORUM_OUI and len(b) > 10:
                hf_min = b[9] & 0x3F
                hf_max = ((b[9] >> 6) & 0x03) * 256 + b[10]
                if hf_min > 0 and hf_max > 0:
                    vrr_min_hz = hf_min
                    vrr_max_hz = hf_max
                    print(f"VRR range from HF-VSDB: {vrr_min_hz}-{vrr_max_hz} Hz")
            elif oui_val == AMD_OUI and len(b) >= 8:
                amd_ver = b[3]
                if amd_ver == 2 and len(b) >= 8:
                    amd_min = b[4] | (b[5] << 8)
                    amd_max = b[6] | (b[7] << 8)
                    if amd_min > 0 and amd_max > 0:
                        vrr_min_hz = amd_min
                        vrr_max_hz = amd_max
                        print(f"VRR range from AMD VSDB v2: {vrr_min_hz}-{vrr_max_hz} Hz")

    # Zero out VRR min/max in existing HF-VSDB (keep ALLM, HDR, etc.)
    for i, b in enumerate(blocks):
        tag = (b[0] >> 5) & 0x07
        if tag == 3 and len(b) >= 4:
            oui_val = (b[3] << 16) | (b[2] << 8) | b[1]
            if oui_val == HDMI_FORUM_OUI:
                print(f"\nHF-VSDB before: {b.hex()}")
                if len(b) > 10:
                    b[9] = 0x00  # VRR min=0 → supported=false
                    b[10] = 0x00  # VRR max=0
                    print(f"HF-VSDB after:  {b.hex()} (VRR zeroed, ALLM preserved)")
                blocks[i] = b
                break

    # Replace native AMD VSDB with v1 format (DMUB firmware only supports v1)
    amd_v1 = build_amd_vsdb_v1(vrr_min_hz, vrr_max_hz)
    for i, b in enumerate(blocks):
        tag = (b[0] >> 5) & 0x07
        if tag == 3 and len(b) >= 4:
            oui_val = (b[3] << 16) | (b[2] << 8) | b[1]
            if oui_val == AMD_OUI:
                print(f"\nAMD VSDB before: {b.hex()} ({len(b)} bytes)")
                blocks[i] = bytearray(amd_v1)
                print(f"AMD VSDB v1 after:  {amd_v1.hex()} ({len(amd_v1)} bytes)")
                break
    else:
        # No existing AMD VSDB — add one
        blocks.append(bytearray(amd_v1))
        print(f"\nNo existing AMD VSDB found — added v1: {amd_v1.hex()} ({len(amd_v1)} bytes)")

    # Rebuild CTA block
    new_cta = bytearray(128)
    new_cta[0] = 0x02  # CTA-861 extension
    new_cta[1] = 0x03  # revision 3
    new_cta[3] = 0  # no native detailed modes

    # Write data blocks
    pos = 4
    for b in blocks:
        new_cta[pos:pos + len(b)] = b
        pos += len(b)

    # Set dtd_start and write DTDs
    if len(dtd_data) > 0:
        new_cta[2] = pos
        new_cta[pos:pos + len(dtd_data)] = dtd_data
    else:
        new_cta[2] = 127  # no DTDs

    # Calculate checksum
    new_cta[127] = checksum_block(new_cta)

    # Replace block 1
    edid[128:256] = new_cta

    with open(output_path, 'wb') as f:
        f.write(edid)

    print(f"\nPatched EDID written to {output_path}")
    print(f"Data blocks end at: {pos}")
    print(f"DTD start: {new_cta[2]}")
    print(f"Checksum: 0x{new_cta[127]:02X}")

if __name__ == '__main__':
    input_path = sys.argv[1] if len(sys.argv) > 1 else '/sys/class/drm/card0-DP-1/edid'
    output_path = sys.argv[2] if len(sys.argv) > 2 else '/tmp/q80a-edid-patched.bin'
    patch_edid(input_path, output_path)
