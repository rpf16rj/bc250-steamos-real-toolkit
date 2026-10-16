# Spec: Persistent AUR package cache for post-update re-apply

Date: 2026-10-16
Slug: aur-pkg-cache

## Problem

SteamOS atomic updates wipe `/usr`, removing every pacman/AUR-installed package
(`cyan-skillfish-governor-smu`, `coolercontrold-bin`, `xone-*`,
`openlinkhub-git`, …). The persist service (`bc250-toolkit-persist.service` →
`reapply_installed_components`) reinstalls them by running the full
`aur_install` path again — AUR helper + source build. Confirmed failure on
2026-10-16 (log `bc250-toolkit-error-20261016-191535.log`):

- GPU governor reapply rebuilds `cyan-skillfish-governor-smu` from source:
  pulls `rust`, `compiler-rt`, `lld`, `libgit2` (~370 MB installed) and
  compiles ~100 crates — minutes of work on every boot-after-update.
- The build is interruptible (user SIGINT / lost TTY → `Aborted by user`),
  leaving the component absent.
- If the AUR helper itself was wiped from `/usr`, `aur_install` cannot run at
  all.

## Design

Cache every successfully built AUR `.pkg.tar.zst` in persistent storage
(`$PERSIST_STATE_DIR/aur-packages`, under `/home` — survives atomic updates)
and prefer `pacman -U` from that cache during unattended re-apply
(`AUTO=1`).

### Changes in `start.sh`

1. New `AUR_PKG_CACHE="$PERSIST_STATE_DIR/aur-packages"`.
2. `aur_pkg_cache_find <pkg>` — newest cached `<pkg>-*.pkg.tar.*` (excl. `.sig`).
3. `aur_pkg_cache_store <pkg>` — after a successful helper install, copy the
   built package out of the helper build dir
   (`~/.cache/paru/clone/<pkg>`, `~/.cache/yay/<pkg>`) into `AUR_PKG_CACHE`.
   No-op for shelly (no known build dir) — harmless.
4. `aur_install <pkg>`:
   - `AUTO=1` + cache hit → `pacman -U --needed --noconfirm <cached>` and
     return. No helper, no toolchain, no compile. Works even when the AUR
     helper itself was wiped by the update.
   - Cache miss / `pacman -U` failure → delete the stale cache file, fall
     through to the existing helper build path.
   - On successful helper install → `aur_pkg_cache_store`.
   - Manual path (`AUTO=0`) unchanged: always fetches latest from AUR so a
     manual reinstall still picks up new upstream versions.
5. `aur_needs_build_deps <pkg>` — false when `AUTO=1` and the cache will
   satisfy the install; used to gate `ensure_build_deps` at the GPU governor
   call site so the re-apply does not install base-devel/Rust just to
   `pacman -U` a cached file. (The sensors/xone sites keep it unconditionally
   — DKMS rebuilds genuinely need the toolchain even with a cached package.)
6. `aur_remove` also drops cached package files for the removed package.
7. `reapply_resolve_state_dir` — the persist service runs as root, so
   `REAL_HOME` resolved to `/root` and `PERSIST_STATE_FILE` would never be
   found (`/root/.bc250-toolkit` vs the real `/home/<user>/.bc250-toolkit`).
   On re-apply, when the state file is missing under the default dir, scan
   `/home/*/.bc250-toolkit` for `installed-components` and re-derive
   `REAL_USER`/`REAL_HOME`/state paths (and `AUR_PKG_CACHE`) from it. Without
   this, re-apply printed "No persisted toolkit state" and did nothing.
8. `persist_state_add` prints a one-per-run hint on SteamOS when the persist
   service is not installed, so users discover option P before an update
   wipes their components (this user's machine had state recorded but the
   service was never installed).

## Guarantees

- Reversible: cache is plain files under `~/.bc250-toolkit/aur-packages`;
  `aur_remove` and component reverts clean it.
- Safe: `pacman -U` validates deps/signatures; corrupt/stale caches fall back
  to a normal AUR build. That fallback is best-effort under the root-run
  persist service (no makepkg toolchain guaranteed and the helper's internal
  sudo may lack a TTY) — correct by construction since a failed reinstall is
  no worse than today's behavior.
- Archive identity is verified via `.PKGINFO` (`bsdtar`), not filename globs:
  helper build dirs can contain prefix-colliding split packages
  (`coolercontrold-bin-debug`) and helpers clone by *pkgbase* (`xone-dkms`
  lives in `clone/xone`), so store scans every clone dir and both store/find
  verify `pkgname = <pkg>` before accepting a file.
- Generic: every `aur_install` caller benefits (governor, coolercontrol,
  xone, openlinkhub) — not just option 02.
- No behavior change for manual installs or non-SteamOS systems.

## Test plan (user, real hardware)

1. `sudo ./start.sh` → option 02 (fresh install) → confirm
   `~/.bc250-toolkit/aur-packages/cyan-skillfish-governor-smu-*.pkg.tar.zst`
   exists.
2. Simulate post-update: `sudo pacman -Rns cyan-skillfish-governor-smu`,
   `rm -f /usr/lib/systemd/system/cyan-skillfish-governor-smu.service`, then
   `AUTO=1 sudo ./start.sh --reapply-all` → governor restored via `pacman -U`
   in seconds, service enabled, no rust/toolchain download.
3. `bash -n start.sh` + shellcheck-clean diff review.
