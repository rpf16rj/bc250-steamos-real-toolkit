# Spec — Emulators section (KytyPS5 + Lichii + EmuDeck)

## Goal
New top-level menu "6) Emulators" with a submenu installing BC-250-specific
emulators that have SteamOS-installable artifacts.

## Facts established (research)
- **KytyPS5-Native beta4** (`dmorazasanchez/KytyPS5-Native-beta`): AppImage +
  `SHA256SUMS`. On SteamOS, `--prepare-system` writes ONLY `/etc` + `/var`
  (survive updates): `/etc/modprobe.d/kytyps5-native.conf` (sched_policy=2
  vm_update_mode=0 cwsr_enable=0), `/etc/default/grub.d/kytyps5-native.cfg` +
  update-grub (ttm.pages_limit=3670016 = 14 GiB GTT), `kyty-lodhw` systemd
  service. Has `--dry-run`, `--status`, `--revert`; never overwrites a value the
  user already set (reports CONFLICT). Records changes in
  `/var/lib/kyty-beta-system/prepare-system.json`. `--install-desktop` adds menu
  entry. `--uninstall-system` removes helper+Minimal Mode.
  Kernel prereqs: our vendored patches already active (bc250_gfx_queues,
  bc250_gfx_eop_events, bc250_mtype_rw — check via `modinfo amdgpu | grep`).
  When our patched module is loaded `--prepare-system` adjusts options itself.
  RAM-split (UMA 512MB) already covers upstream VRAM guidance.
- **Lichii BC-250 v7** (`lethevimlet/lichii-bc250`): prebuilt eden-cli tarball
  (~100 MB) + .sha256; upstream installer `tools/bc250/bc250-install.sh`
  (user-level, curl+tar+python3, no container needed on the prebuilt path),
  installs to `~/Applications/lichii-bc250/lichii`. Needs UMA 512MB (our
  RAM-split default) — warn if not applied. Repo renamed from oot-bc250
  (redirects). Has an uninstaller per README.
- **EmuDeck**: generic emulator suite — menu entry downloads the official
  installer .desktop to ~/Desktop only (no implicit install).
- **Hookshot**: no releases yet — skip.

## Implementation
- `run_emulators_menu` + main-menu item "6".
- `install_kyty()`: prereq check (modinfo amdgpu bc250_gfx_queues; warn not
  block — Kyty works on stock amdgpu, ours improves it), download AppImage +
  SHA256SUMS to `~/Applications/kytyps5-beta/` (as REAL_USER), sha256 verify,
  chmod +x, show `--prepare-system --dry-run` output, confirm → run
  `--prepare-system` (sudo) → `--install-desktop` (as REAL_USER) → tell user to
  reboot + add to Steam as non-Steam game. Note: if our GRUB ram-split already
  set ttm.pages_limit, upstream reports CONFLICT — informational.
- `kyty_installed()`: AppImage exists + kyty-lodhw.service exists.
- `revert_kyty()`: `--prepare-system --revert`, `--install-desktop --remove` if
  supported (else warn), offer `--uninstall-system`, rm AppImage dir; keep
  saves (`~/.local/share/KytyPS5-Beta`) unless user confirms purge.
- `install_lichii()`: download upstream `bc250-install.sh` + run as REAL_USER
  (prebuilt path). UMA check: warn if ram-split not applied.
- `lichii_installed()`: `~/Applications/lichii-bc250/` exists.
- `revert_lichii()`: upstream uninstaller if present else rm the app dir
  (confirm; keep user data dir).
- `install_emudeck()`: download `EmuDeck.desktop` installer to `~/Desktop`,
  tell user to run it.
- Status line in submenu per item.
- Contract: install_*/revert_*/\*_installed only (no persistence — feature
  removed; /etc+systemd persistence is native).

## Risks
- Kyty beta quality (upstream-flagged). Ghost of Yōtei COND_EXEC 0x22 fix
  claims SteamOS-tested — verify on hardware.
- `--prepare-system` runs `update-grub` — momentary rootfs unlock is handled
  by upstream; our steamos_writable not needed for it.
- 939 MB AppImage download — show progress, resumable curl.
