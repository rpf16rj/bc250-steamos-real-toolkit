# Spec — MastaG upstream sync (Oct 11)

## Scope

Port 5 upstream items from `MastaG/linux-cachyos-bc250` (+ satellites) into
the toolkit. Explicitly NOT ported: VCN (upstream confirmed dead — register
file unreachable, freezes on first UVD_POWER_STATUS read; corroborates
`.kb/vcn.md`), `bc250_memory` (SMU SRAM write — prohibited class),
`bc250-ch7218-fw` flasher (document-only, brick risk), `0011-bc250-40cu`
(kernel-path CU unlock — we have the runtime path), telemetry split
(cosmetic), HelixSR packages themselves (we `pacman -Sw` his pkgs — automatic).

## Items

1. **DirectMesh v1.3.1** — replace
   `external/bc250-steamos/bc250-gfx1013-fix/patches/mesa/0002-bc250-directmesh.patch`
   with upstream (lonewolf0622/bc250meshtaskwork@3977ab4, via MastaG
   `patches/mesa/0002-bc250-directmesh.patch`). Fixes VRAM→GTT index-route
   storage (v1.3 pinned up to 128MiB of the 512MiB carveout → 4K hang).
   **Policy override:** upstream defaults ON when a BC-250 is present
   (`decided = on ? !strcmp(on,"1") : radv_bc250_present()`); our contract is
   opt-in `RADV_DIRECTMESH=1` — patch the requested() fallback to `false` and
   fix the comment text. Must dry-run apply AND reverse on the pristine
   mesa-26.2.4 tree.

2. **CH7218 DSC-restore ungate** — in
   `external/bc250-steamos/bc250-audio-fix/bc250-ch7218-pcon-quirk.patch`,
   the `DP_DSC_SUPPORT` restore (fires only when CH7218 fw clears the bit but
   returns a populated DSC block — impossible state) must run unconditionally,
   like upstream `0016-ch7218-dsc-restore.patch` (opt-out remains
   `bc250_hdmi21=0`). Keep the rest of the quirk gated. Dry-run apply/reverse.

3. **CEC remote keymap** — port upstream `packages/bc250-cec/`
   (@dd37c19): udev rule `71-bc250-cec-keys.rules` + `bc250-cec-keymap.sh`
   (CEC OK→KEY_ENTER, Back/Exit→KEY_ESC so TV remote works in Steam UI;
   `BC250_CEC_REMOTE_KEYS=0` opt-out) into our vendored
   `external/bc250-steamos/bc250-cec-retrain/` package + start.sh
   install/revert/status contract.

4. **Dual-audio v0.15** — bump `external/bc250-dual-audio/` vendored copy
   v0.14→v0.15 (upstream `MastaG/bc250-dual-audio`@02f7319, "hold the
   automatic output across native HDMI hotplug"). MUST preserve every
   SteamOS adaptation documented in `.kb/dual_audio.md` (sink name
   `dolby_digital_ac3`, `node.virtual=false` Game Mode visibility, `~/`
   vs `/etc` paths, readonly trap, timing params). Update version strings
   in start.sh menu/status.

5. **HelixSR docs** — upstream made HelixSR the default upscaler (pinned
   1.4.3); our `start.sh:4454` hint (`PROTON_USE_OPTISCALER=helixsr`) is now
   redundant — reword; verify `fsr411f` line still accurate.

## Verification

- `bash -n` all touched .sh; patch dry-run apply + reverse on pristine trees
- No `RADV_DIRECTMESH` default-on path survives; grep the patched tree
- Reviewer subagent gate before any commit. No commit/push/release without
  explicit user go-ahead.
