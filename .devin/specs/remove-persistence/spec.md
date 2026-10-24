# Remove SteamOS update persistence feature

## Why
The persist service (`bc250-toolkit-persist.service`) runs a full re-apply on
**every** boot, not only after updates. In AUTO mode it auto-confirmed
"reinstall?" prompts → `aur_remove` deleted the package *and* the toolkit
package cache → forced a full rebuild → paru's internal `sudo` failed without
TTY → the GPU governor was left uninstalled after reboot. User decided to drop
the feature entirely rather than maintain it.

## Remove (toolkit)
- `install_persistence`, `run_persistence_menu`, `run_show_persistence_list`
- `reapply_installed_components`, `reapply_resolve_state_dir`, `--reapply-all`
- `persist_state_add/remove/has`, `persist_detect_and_record_installed`,
  `persist_snapshot_configs` + all call sites; `PERSIST_STATE_FILE`,
  `PERSIST_KEEP_FILE`, `_persist_hint_shown`
- AUR package cache machinery (only consumer was re-apply):
  `aur_pkg_*`, `aur_needs_build_deps`, `AUR_PKG_CACHE`, AUTO branches in
  `aur_install`, `run_gpu_governor`, `run_cpu_governor`; cache cleanup in
  `aur_remove`
- Menu entries P (main + extras) and persistence strings

## Keep
- `--revert-all` + `confirm`/`press_enter` AUTO checks (recovery feature)
- `PERSIST_STATE_DIR` (still hosts recovery-menu.conf / bc250-recovery-ctl.sh /
  toolkit-path); `derive_home_state_paths` minus `AUR_PKG_CACHE`
- `emergency_revert` keep.conf glob (harmless cleanup for pre-removal installs)
- live-output `run_with_retry` (independent fix)

## Verify-display change
`persist_state_has "gfx1013"` replaced by on-disk check
(`compgen -G "/usr/lib/modules/*/updates/amdgpu.ko*"`).

## Remove (system)
- `systemctl disable --now bc250-toolkit-persist.service`
- `/etc/systemd/system/bc250-toolkit-persist.service`,
  `/usr/local/bin/bc250-toolkit-reattach.sh`,
  `/etc/atomic-update.conf.d/bc250-toolkit.conf`
- `~/.bc250-toolkit/{installed-components,bc250-toolkit-keep.conf,
  bc250-toolkit-reattach.sh,bc250-toolkit-persist.service,aur-packages/,
  config-snapshots/}` — keep recovery files

## Consequence (documented)
After SteamOS updates, AUR packages and `/usr` toolkit files must be
reinstalled manually via the menu. Governor/service survive normal reboots
natively.
