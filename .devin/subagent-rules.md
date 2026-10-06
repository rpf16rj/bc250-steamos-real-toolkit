# Shared Subagent Rules — BC-250 SteamOS Real Toolkit

Every subagent working in this repository MUST read this file before acting.
These rules exist because this repo drives a real, unique piece of hardware
(the user's daily-driver BC-250 board) — a mistake is not a broken CI job, it
is a bricked boot or a wedged SMU that needs physical access to recover.

## Absolute prohibitions

- NEVER reboot, poweroff, or touch bootloader state (GRUB entries, grub.cfg,
  /efi, efibootmgr).
- NEVER write to SMU registers, SMN transport, VCN/power-domain control, or
  any /sys/kernel/debug amdgpu power knobs. The VCN work is PAUSED — do not
  run `enable_vcn.py`, SMU unlocks, or handler-repoint experiments. Reading
  research material about it is fine; executing any of it is not.
- NEVER commit, push, tag, or create releases — only the root agent may, and
  only on explicit user request.
- NEVER run `sudo`, `steamos-readonly disable`, or write outside the repo +
  /tmp unless the task explicitly includes an install/test step the parent
  agent described. Write-capable means *repo* write, not system write.
- NEVER delete files, `rm -rf`, or modify installed system state
  (/etc, /usr, /var/lib/bc250, ~/.local/share/Steam).
- Do not invent upstream facts. Distinguish clearly: "upstream claims" vs
  "measured on this hardware" vs "verified in code".

## Project architecture invariants (must hold in any code you produce)

- `start.sh` is a single-file interactive TUI run as root on real SteamOS.
  Every user-facing component follows the same contract:
  - `install_<name>()` — idempotent, SteamOS-readonly aware
    (`steamos-readonly disable/enable` around rootfs writes), prints via
    `print_step/print_info/print_error/print_success`.
  - `revert_<name>()` — removes exactly what install created.
  - `<name>_installed()` — cheap probe used by menus and persist detect.
  - persistence: `persist_state_add "<name>"` on install, a
    `reapply_installed_components` case, and (if it writes rootfs files)
    entries in the atomic-update keep list in `install_persistence()`.
- Root filesystem is wiped on SteamOS updates. Persistent payloads go to
  `/var/lib/bc250` (survives) or must be listed in the keep list.
  User-level state goes under `$REAL_HOME` (home partition persists).
- Anything touching `flatpak`, Steam runtime, or gamescope must account for
  the sandbox/pressure-vessel environments (host ld.so.conf.d and env files
  do not reach Flatpak sandboxes; Steam pins its own runtime libs).
- Bash style: compact, no comments unless asked, existing helpers only
  (confirm, print_*, is_steamos, fixes_repo_sync, REAL_USER/REAL_HOME).
  Always `bash -n` the file after editing.
- Knowledge lives in `.kb/` (local-only, gitignored) — read the relevant
  file before designing anything touching that subsystem.

## Output contract

- Report back concisely: what you changed/found, file:line references, what
  you verified (`bash -n`, patch dry-run), what remains unverified and needs
  the user's real-hardware test. Do not claim hardware behavior you did not
  measure.
- If a task looks infeasible or unsafe, say so and stop — do not silently
  downgrade scope.
