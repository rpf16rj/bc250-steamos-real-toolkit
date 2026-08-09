# Status — 0.2.0-alpha

Regenerated drop. Versus the previous state of this repo:

- **Patch set regenerated from the shipping tree.** One coherent Mesa series
  (`patches/mesa/series`, 3 patches against pristine `mesa-26.2.0-rc3`) replaces the previous
  overlapping set; every patch applies in order and the result builds. Kernel set is the three
  V33 patches only.
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
