# Spec — MastaG sync (Nov 8 → Nov 12, 2026)

## Goal
Port the two highest-value deltas from the Nov-8→12 research window; keep KytyPS5
and Mesa 26.3.0 as watch items.

## In scope

### 1. DirectMesh v1.4 (lonewolf `cac0bcc`, via MastaG `f1f2dc6`)
- Replaces `patches/mesa/0002-bc250-directmesh.patch` (currently v1.3.1+auto-IDX).
- Feature: Task index route — Task+Mesh pipelines that previously failed creation
  (black-3D-world games) now run Task as compute producer + Mesh via ordinary
  vertex pipeline. `RADV_BC250_MESH_TASK_IDX=0` opt-out. Still opt-in via
  `RADV_DIRECTMESH=1`.
- Base: stay on Mesa **26.2.4** (do NOT bump to 26.2.6 or 26.3.0 — deliberate pin).
  Researcher dry-ran upstream's 26.2.6 patch vs 26.2.4: 100 hunks OK, **1 FAILED** —
  `radv_shader.h` `radv_compiler_info` padding: on 26.2.4 the 28 bc250 flags fit the
  28-bit padding exactly; drop the patch's third-word `padding : 31` line. One fuzz-1
  hunk elsewhere acceptable.
- Use the **pre-`928c9ea`** version of MastaG's 0002 (the 26.2.6 base), NOT HEAD
  (HEAD is the 26.3.0 port).
- Verify: dry-run apply + reverse on pristine mesa-26.2.4 tarball tree; record
  offsets/fuzz; update `.kb/patches.md` provenance (v1.4 `cac0bcc` via `f1f2dc6`).
- Risk: GPU command-path; upstream skipped v1.4.1 (hangs) — we take exactly v1.4.
  Requires Mesa rebuild + repackaged prebuilt + real-hardware test by user.

### 2. Proton/FreeFG docs sync (MastaG `03b3442`, `e2cba49`, `24628e6`)
- `freefg-all` single payload with all 5 upscalers.
- **New prefixes default to "No upscaling"** — update `start.sh` option-13 text
  (line ~4384: "default: freefg-hlxfsr4" is stale) + FSR4 Decky plugin labels +
  Launch Coach if it references the old default.
- `PROTON_OPTISCALER_MENU=0` now functional; new `~/.config/bc250-fsr4/settings`
  (`menu=0`, `default=off|freefg-all|…`); old variant names still force upscalers.
- HLX FSR 4 native Vulkan path (`ffx_vk`/HLXFSR4V) — mention in docs.
- FreeFG 1.4.0: preset dir renamed `HLX DLSS Preset K` → `hlx-dlss-k`.
- GTK4 menu now gates new-prefix upscaler choice — flag as hardware-test item.

## Out of scope (watch)
- Mesa 26.3.0 rebase, MFG Unlocker 1.7.1 (MastaG still pins 1.7.0), KytyPS5
  (own spec later — `--prepare-system` overlaps our GRUB/ram-split machinery),
  kernel 0029+ (none), dual-audio/vrm/CH7218 (no movement), WP 0.5.18 alsa.lua,
  `0017/0022-ch7218-vrr-*` (no CH7218+VRR issue reported yet).

## Steps
1. amd-gaming subagent: port DirectMesh v1.4 → 26.2.4, dry-run apply+reverse.
2. Root: docs sync (start.sh, plugins, .kb, changelogs EN/PT).
3. bash -n + reviewer gate.
4. User tests on hardware (Mesa rebuild via option/Combined Fix; DirectMesh games;
   GTK4 menu in a fresh prefix). No commit until user green-lights.
