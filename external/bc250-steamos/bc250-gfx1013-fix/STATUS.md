# Status — 0.2.0-alpha

Regenerated drop. Versus the previous state of this repo:

- **Patch set regenerated from the shipping tree.** One coherent Mesa series
  (`patches/mesa/series`, 5 patches against pristine `mesa-26.2.0-rc3`) replaces the previous
  overlapping set; every patch applies in order and the result builds. Kernel set is the three
  V33 patches plus the Cyan Skillfish SCLK range widening patch (350–2230 MHz).
  - 0001: compute queue fix (always active)
  - 0002/0003: mesh/task shaders + queries (applied, gated by RADV_GFX103=1 at runtime)
  - 0004: RADV_GFX103 env var promotion
  - 0005: FSR4 sdot_4x8 dp4a selective reassociation (always active, from dmorazasanchez/bc250-fsr4 v2)
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
