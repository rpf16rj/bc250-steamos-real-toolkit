# KytyPS5-Native — watch / prerequisites

PS5 games running GPU-natively on gfx1013 (superkeka/KytyPS5-Native, packaged
nightly by MastaG since Oct-29). Upstream-tested on BC-250: ASTRO BOT via
Steam shortcut in Gaming Mode, HDR, DualSense motion/haptics/speaker.

## Requirements (from upstream)
- Kernel patches `0023`–`0027` — vendored in this toolkit (inert at
  defaults): `bc250_gfx_queues` (2nd gfx ring), `bc250_gfx_eop_events`
  (EOP→KFD events + private ioctl), `bc250_mtype_rw` (C_SHARED semantics).
- Cmdline: `ttm.pages_limit=3670016 amdgpu.sched_policy=2
  amdgpu.vm_update_mode=0 amdgpu.cwsr_enable=0` + 512MB VRAM (our
  RAM-split covers it).
- Root helper service `kyty-lodhw`.
- Runtime artifact — no pacman repo on SteamOS; installer TBD.

## Status
Kernel prerequisites shipped (Nov-8 sync). No SteamOS installer yet —
large feature, needs artifact packaging + service + user testing.

## Install path — shipped (Nov-12)
Main menu 6 → Emulators → option 1. Uses dmorazasanchez beta AppImage
(`--prepare-system` on SteamOS writes only /etc+/var: modprobe.d conf,
grub.d ttm.pages_limit drop-in, kyty-lodhw service; --dry-run/--status/
--revert, never overwrites user-set values — CONFLICT marker instead).
AppImage lives at ~/Applications/kytyps5-beta/. Saves at
~/.local/share/KytyPS5-Beta (kept on revert).
