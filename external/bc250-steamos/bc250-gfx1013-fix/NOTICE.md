# Attribution

## Code developed by this project

[DryhoppedIPA](https://github.com/DryhoppedIPA) developed the scoped V33 kernel repair and the narrow
Mesa GFX1013 compute, mesh, and task implementation through direct testing on BC-250 hardware. These
changes retain the GPU's real GFX10.1 identity and replace the need for a process-wide GFX10.3 spoof.

## 40-CU unlock

The 40-CU unlock is not distributed here. It is
[duggasco/bc250-40cu-unlock](https://github.com/duggasco/bc250-40cu-unlock)
(commit `ae7c30c78e253a5e2c6af0e9c090f807b825191c` at the time of testing); DryhoppedIPA audited
it and validated its composition with V33, and the published benchmark numbers were taken with it
active. DryhoppedIPA does not claim authorship of the unlock.

## Mesa prior work

[vogar345/Bc250-radeon-patch](https://github.com/vogar345/Bc250-radeon-patch) demonstrated that a
Mesa modification could get Final Fantasy VII Rebirth through its feature gate and into accelerated
gameplay. That result provided important evidence and a comparison point for this project.

[lonewolf0622's per-application derivative](https://github.com/lonewolf0622/BC-250-Mesh-Shader-Patch---driconf-Edition-opt-in-per-application-)
made the experiment easier to opt into for individual games and contributed additional community
testing.

The Mesa implementation distributed here is narrower: it keeps GFX1013 classified as GFX10.1,
requires the repaired compute-queue contract, and enables only the task/mesh behavior validated by
this project.

## Compute-queue research

Community work by `akandr`, `anrp`, and `ahorek` documented reproducible GFX1013 compute failures and
earlier kernel-workaround directions. Their results helped establish the initial problem surface.
The V33 repair in this repository was derived through a separate controlled hardware investigation
that localized the failure to the PASID invalidation transaction and its GFXOFF contract.

## Upstream projects

Linux kernel patches remain subject to `GPL-2.0-only`. Mesa patches remain subject to Mesa's MIT
license. Their inclusion does not imply endorsement by the Linux, Mesa, AMD, or Valve projects.
