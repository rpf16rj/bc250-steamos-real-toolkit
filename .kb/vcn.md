<!-- tags: vcn, uvd, psp, gpcom, harvest, experimental, ungate, bc250 -->
# VCN 2.0.3 on BC-250 — Investigation Status

**Status: experimental, NOT working. Hidden from the toolkit menu.**

The BC-250 (Cyan Skillfish 2, PCI 0x13FE) ships with the VCN 2.0.3 block
harvested/gated. This file records what was tried and what remains.

Full raw research log: `~/vcn-research/REPORT.md` (outside this repo).

## Path A — PSP GPCOM probing: CLOSED (conclusive)

The GPCOM ring transport works, but every command needed to create the
missing VCN slot is rejected by the CSF TEE:

| Command | Result | Meaning |
|---|---|---|
| `LOAD_IP_FW` type 13 (VCN) | `0xffff0008` ITEM_NOT_FOUND | VCN slot absent — feature-enable never ran |
| VCN RAM types 49/50 | `0xffff0006` BAD_PARAMETERS | handler exists, dies on slot/config |
| `SETUP_TMR` (0x05) | `0xffff0007` BAD_STATE | TEE already initialized, no re-setup |
| `LOAD_TOC` / `PROG_REG` / `AUTOLOAD_RLC` | NOT_IMPLEMENTED | absent |
| `LOAD_TA` / `LOAD_ASD` (navi10 AND CSF-signed BIOS blobs) | `0x00000034` | categorical rejection — no session, no INVOKE_CMD |
| `BOOT_CFG` (0x22) | NOT_SUPPORTED | recognized, blocked |
| `SAVE_RESTORE` (0x08) | BAD_PARAMETERS | exists but needs a valid payload |

Static RE of the TEE module: `fn_121ee` (the feature-enable walk that
would populate the VCN table at `0xe97b40`) only runs at boot and no
GPCOM command re-triggers it. Conclusion: without an exploit or a BIOS
modification, the PSP path cannot ungate VCN.

## Path B — Kernel-side ungate: built, boot-wedged once, now runtime-gated

`external/bc250-steamos/bc250-audio-fix/bc250-vcn-ungate.patch` removes
the three driver gates, **only when the module parameter is set**:

- `amdgpu_discovery.c`: `case IP_VERSION(2,0,3)` registers
  `vcn_v2_0_ip_block`; harvest quirk clears `vcn.harvest_config` and sets
  `inst_mask` for CSF2; `harvest_ip` skips setting `VCN/JPEG_MASK`
- `amdgpu_ucode.c`: `IP_VERSION(2,0,3)` → `"navi10_vcn"`
- `amdgpu_drv.c` + `amdgpu.h`: `amdgpu_bc250_vcn_ungate` module param,
  **default 0** — the patched kernel boots normally; ungate is opt-in
  per boot via `amdgpu.bc250_vcn_ungate=1` on the kernel cmdline.

VCN ucode loads via `AMDGPU_FW_LOAD_DIRECT` (MMIO `mmUVD_VCPU_CACHE_*`),
no PSP involvement — so the test answers whether the register file is
hardware-clamped by the PSP fuse or just driver-skipped.

### Test procedure (manual, hidden from menu)

```bash
cd external/bc250-steamos/bc250-audio-fix
./patch-driver.sh --gfx1013 --audio --dsc --vcn   # your normal set + --vcn
# reboot normally — ungate is OFF by default, system must boot fine
# then at GRUB press 'e', append to the linux line:
amdgpu.bc250_vcn_ungate=1
```

After boot: `dmesg | grep -iE 'vcn|uvd'` — `detected ip block
<vcn_v2_0_0>` + ring test = VCN alive; stuck/zero regs = hardware clamp
confirmed. If it hangs: power cycle, boot without the param, and collect
`journalctl -b -1 | grep -iE 'vcn|uvd|amdgpu'` to locate where
`vcn_v2_0_hw_init` died.

## Incidents / lessons

- **Unconditional ungate did not boot** (first patch version added the IP
  block always → kernel never reached userspace; recovery needed). That
  is why the param exists and why the option is hidden from the menu.
- **Patch context collision**: `bc250-dcn201-pcon-hdmi21.patch` (DSC) is
  applied as uncommitted working-tree changes, so `git diff` of the tree
  mixes `amdgpu_bc250_hdmi21` hunks into any new patch touching
  `amdgpu_drv.c`/`amdgpu.h`. All VCN hunks are anchored on pristine lines
  ≥3 context lines away from the PCON insertion points (`sg_display`),
  making the patch order-independent. When regenerating, temporarily
  remove the hdmi21 lines or the diff will swallow them.
- **Never hand-revert hunks**: reverting only some files leaves the tree
  partially patched; the build then fails or miscompiles. `build.sh` now
  `die`s if the real `patch -R` fails and detects a partial VCN
  application via a `bc250_vcn_ungate` marker grep.

## Remaining option if the ungate test fails

BIOS patch: the feature-enable site `0x9970f4` in the PSP/ABL image is
verified (`cbz r4` → nop forces the enable path). Requires SPI flash
(dump + verify + write), real brick risk without a CH341A backup. Not
pursued yet.
