# Issue batch — v1.10.2 candidates (GitHub issues #34 #38 #40 #41 #43)

Date: 2026-10-06. Source: open issues + attached error logs (/tmp/issue-logs/).

## #34 — GPU governor service enable fails (stale unit state)

Reporter log: unit enters failed state, `ExecStartPre=/usr/libexec/bc250-control-center/bc250-cyan-overlay-preflight` exits 203/EXEC (binary missing). Reporter fixed manually by removing `/etc/systemd/system/cyan-skillfish-governor-smu.service*`, its `.service.d/` drop-in dir and `multi-user.target.wants/` symlink, then reinstalling.

Fix: `gpu_governor_setup()` — before `systemctl enable --now`, purge stale
admin-unit artifacts unconditionally: anything for this unit under
`/etc/systemd/system/` is foreign (the package ships its unit in `/usr/lib`);
remove the unit file, `.service.d/` drop-ins and stale wants symlinks,
`daemon-reload`, then enable.

## #41 (+ #38 pipx half) — pipx JSONDecodeError

`pipx install` → `list_installed_packages` → `json.loads` on EMPTY stdout:
the pip subprocess inside the venv produces nothing. Root cause: stale
`$PIPX_HOME/shared` venv created under an older Python — after a SteamOS
Python bump (3.13→3.14) the shared venv's pip is unusable → pipx injects
nothing → `pip list --format=json` prints nothing.

Fix: `cpu_governor_seed_shared()` must validate the shared venv:
`shared/bin/python -m pip --version` must succeed AND its python major.minor
must equal system python3's. If either fails, `rm -rf shared` and recreate
with `--system-site-packages`. Same validation before pipx adopts it.

## #38 — `bc250-detect` fails: `OSError: Exec format error: 'stress'`

`stress_helper.py` Popen(["stress", ...]) — the installed `stress` binary is
corrupt/wrong-arch (their pacman log shows ~12 retried `pacman -Syu ...
python-pipx stress` runs, so the package is suspect).

Fix: after the dep install step, sanity-check `command -v stress` +
`stress --version`; on failure reinstall `stress` once via pacman, then
fail with a clear message if still broken.

## #40 — /var partition fills up → Combined Fix fails on "/etc too full"

`/var` is ~230MB on SteamOS; reporter had 170MB of umr leftovers in
`/var/lib/umr`. `validate_combined_fix_prerequisites` only checks /home.

Fix:
1. Add a `/var` (the /etc overlay upper) free-space check to
   `validate_combined_fix_prerequisites` — fail early under 100MB free (listing top /var/lib
   consumers), warn under 250MB.
2. In `run_with_retry`, when a pacman command fails with a "too full / not
   enough space" pattern, surface a disk-space-specific error message instead
   of the generic retry path (avoids the misleading vermagic-guard message).

## #43 — FSR4 Proton download fails

`pacman -Sw` verifies package signatures — a stale/broken keyring makes it
fail exactly like the reported option-10 keyring errors. v1.10.1 already
routes `-Sw` through `run_with_retry` + keyring repair. No code change —
reply on the issue asking for the exact error text if retry on v1.10.1
still fails.

## Non-goals

- No changes to working governor/detect logic beyond the fixes above.
- No redesign of /var layout (documented as follow-up: keep build trees on /home).

## Status (2026-10-06)

Implemented on develop (uncommitted): pipx shared-venv validation+recreate,
stress sanity-check + reinstall, GPU-governor stale-/etc-unit purge before
enable, /var free-space gate in validate_combined_fix_prerequisites +
disk-full detection in run_with_retry. #43 needs no code change (v1.10.1
already routes pacman -Sw through the keyring repair path).
