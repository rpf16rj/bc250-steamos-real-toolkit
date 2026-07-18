# smu-oc-patches

Local patches for [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
(CPU overclock/undervolt via SMU). Consumed by `bc250-power.sh cpu-oc`,
which fetches the upstream repo as a tarball **pinned to the commit in
`OC_PIN`**, overlays the two `.py` files here on top, and stages the result to
`~/.local/share/bc250-fixes/bc250-steamos/smu-oc/`. No local clone is kept;
`cpu-oc update`
re-fetches.

The overlay files are canonical (what actually gets installed). The `.patch`
files are the same changes as diffs against the pinned commit, kept for review
and for upstreaming.

## transport.py — transaction-level flock (0001)

Upstream flocks each 32-bit PCI config access individually, but SMU access
goes through the shared 0xB8 (address) / 0xBC (data) indirect window. The
running cyan-skillfish GPU governor flocks the same config file and can move
0xB8 between an unlocked pair, corrupting the transaction in either direction.
The patch holds the lock across each whole `read_smu_reg`/`write_smu_reg`
pair. Marker grepped by the power script: `lock across the whole pair`.

## stress_helper.py — no-`stress` fallback (0002)

Stock SteamOS has no `stress` binary and pacman installs are wiped by OS
updates. When `stress` is absent, spawn one Python busy-loop process per CPU
instead; `stress` is still preferred when present. (`cpu-oc detect` also
tries a pacman install of `stress` first — this fallback covers the cases
where that fails or the package was wiped since.) Marker: `_burn`.

## Bumping the pinned upstream commit

1. Update `OC_PIN` in `bc250-power.sh`.
2. Check the `.patch` files still apply to the new commit
   (`curl -fL <tarball> | tar -xz`; `git apply --check --directory=<dir> *.patch`)
   — if upstream changed `transport.py` or `stress_helper.py`, re-merge the
   overlay files by hand and regenerate the diffs.
3. `sudo ./bc250-power.sh cpu-oc update` to restage.
