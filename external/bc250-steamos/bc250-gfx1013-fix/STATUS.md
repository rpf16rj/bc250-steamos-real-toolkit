# Status — 0.2.0-alpha

Regenerated drop. Versus the previous state of this repo:

- **Patch set synced to MastaG Oct-2026 stable series.** `patches/mesa/series`
  (7 patches against pristine `mesa-26.2.4`) adopts upstream's DirectMesh
  generation, replacing the earlier GFX10.3-spoof approach. Kernel set is the
  three gfx1013 patches plus the Cyan Skillfish telemetry/SCLK work.
  - 0001: compute queue fix (always active)
  - 0002: DirectMesh v1.3 — Mesh+Task, barycentrics, no-op VRS, DGC,
    multiview, indexed draws (opt-in via `RADV_DIRECTMESH=1`; the old
    `RADV_GFX103` switch is gone)
  - 0003-0007: FSR4 V3 deferred SDot, combined-unroll, imageprep/texture
    candidates, resolution variants, production defaults
- **Zero environment variables.** The `AMD_GFX1013_V33_*` gates are gone from the driver;
  feature selection happens by commenting patches out of the series before building.
- **`install.sh` rewritten as a source build.** No binary payloads, no stable/preview channels;
  `deps` → `build` → `install`. The boot-entry machinery (one-shot first boot, stock never
  touched, activate/boot-stock/uninstall) is unchanged.
- **40-CU unlock removed.** It's an independent project
  ([duggasco/bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock)); see README.

## Not yet done

- End-to-end reinstall from a fresh clone has been exercised piecewise (patch apply, both
  builds), not yet as one uninterrupted run on a clean box.
- Visual qualification of the regenerated driver (mesh/task/queries unconditional) is pending.
- Tested on one board, Fedora 43, kernel 7.1.5-101.fc43.x86_64.
