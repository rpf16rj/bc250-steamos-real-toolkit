# v1.12.0 — Issue-fix release + Lichii perf

Status: DRAFT — awaiting user review.
Scope: fix all actionable open GitHub issues + Lichii Windows-parity tuning.

## Issue triage (11 open)

| # | Issue | Root cause | Fix |
|---|-------|-----------|-----|
| #55, #53 | `coolercontrold-bin` not found | AUR `-bin` packages **deleted** — only `-git` remains | Install official upstream binary from GitLab releases (coolercontrold_5.1.1 ELF + vendored systemd unit + desktop binary for GUI), AUR-git as fallback |
| #54, #49, #45 | Black/green screen + Rust segfault during GPU governor | AUR builds via cargo on-device → toolchain segfaults; `udevadm trigger drm` mid-install may kill display | Prebuilt upstream tarball v0.4.15 (sha256-pinned): binary + config.toml + udev rule + our service unit + dbus conf + perf-mode script from git tag. Skip `udevadm trigger` (applies next boot). AUR build as fallback only |
| #41 | pipx JSONDecodeError (persists 1.10.4) | pipx shared-venv/pip bootstrap fragility on new Python | Drop pipx for bc250_smu_oc: plain venv at /var/lib/bc250/smu-oc-venv (--system-site-packages) + /usr/local/bin wrappers. Migration: detect old pipx install → uninstall → new path |
| #57, #52 | vermagic/ABI mismatch on 7.2.7 | Likely headers≠running kernel (updated, no reboot) or stale artifact | Pre-build check: compare `make kernelrelease` vs `uname -r` → if differ, warn "reboot first" and abort cleanly instead of building mismatched module |
| #50 | segfault building amdgpu module | Unknown (toolchain/OOM) — already retries -j1 | Capture which binary segfaulted (dmesg tail) + check free RAM/swap before build; surface actionable hint in fail_with_log |
| #56 | SteamOS stable support + version matrix | Docs gap | README/release notes: supported kernel × SteamOS channel matrix; startup warning when `uname -r` isn't in tested list |
| #51 | cosmetic garbled layout | Likely non-UTF-8 locale or box chars | Detect locale/TERM → ASCII fallback for box drawing (verify vs screenshot) |

## Lichii perf (pending researcher output)

Compare Windows build launch opts/config vs our wrapper + oot.ini:
- New env knobs (EDEN_NX2_*/EDEN_VI2_*) → adopt
- Newer eden-cli builds with perf fixes → note version
- Mesh-emulation tuning (MKW hits ReportUnsupportedMeshPipeline heavily)
- Possible `RADV_DIRECTMESH=1` benefit — needs hardware test, keep opt-in note in .kb
- Deliverable: updated wrapper + oot.ini diff + .kb/lichii.md update

## Explicitly out of scope

- SteamOS stable-channel *kernel patch* support (needs separate backport; #56 fixed via docs + warning for now)
- No commit/tag/release without explicit user OK

## Verification

- `bash -n start.sh`; all new code paths have `persist_state_add` + revert coverage
- coolercontrold install tested on this box (binary already verified: `coolercontrold 5.1.1` runs, no missing libs)
- Governor: dry-run file layout matches PKGBUILD package() (binary path /usr/bin vs upstream's /etc — keep upstream layout for their uninstall.sh compat? DECIDE)
- pipx→venv migration tested locally (vendored package installs + bc250-detect runs)
- Reviewer subagent gate before user hardware test
