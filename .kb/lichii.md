# Lichii BC-250 (eden-cli fork, Switch 2 recompilation)

Install: toolkit menu 6 → option 4 runs upstream `bc250-install.sh` into
`~/Applications/lichii-bc250/` (wrapper `lichii-bc250`, package `lichii/`,
`eden-cli` is a symlink to `usr/bin/eden-cli`).

## Hard-won facts (Nov 13, real hardware)

- **Native mode is required.** Upstream's wrapper defaults
  `INSTALL_MODE="release"` → `distrobox enter lichii-bc250-runtime`
  (fedora:42). The container ships stock mesa-vulkan-drivers 25.1.9 —
  no gfx1013 patches, radv can't bind the BC-250 → falls to lavapipe →
  `VK_KHR_wayland_surface`/`VK_KHR_xlib_surface` "not available" →
  Vulkan init fails (or renders on CPU). Toolkit post-install seds the
  wrapper to `INSTALL_MODE="native"` — package is self-contained, host
  patched radv works (verified: MKW at ~59 game FPS + FSR3 FG).
- **Folder dumps are NOT loadable via `-g <dir>`.** Loader errors
  "Failed to obtain loader" even for correct `exefs/`+`romfs/` layout.
  Point `-g` at `exefs/main.npdm` (or `exefs/main`) — dumps often nest
  under `base/`, so resolve `*/exefs/main.npdm`. Option 5 auto-detects.
- **NCA "keys for gen 0x14+..0x17+" errors are non-fatal noise** when
  they reference `registered/` firmware NCAs — a romfs/exefs loose dump
  is already decrypted and needs no keys to boot. Real key problems hit
  the game's own files, not system NCAs.
- User data dirs differ per build: package uses `~/.local/share/eden/`,
  `~/.config/eden/`; user-built AppImages may use `eglantine` instead.
- `Failed to read title for ROM!` is cosmetic (missing title metadata).
- First boot: several minutes of pipeline building is normal.
- The distrobox container is left behind by the install (harmless, unused
  in native mode); upstream uninstaller `bc250-uninstall.sh` handles
  removal — check it cleans `lichii-bc250-runtime`.

## Per-game profiles & perf research (Nov 13, upstream nx2 source audit)

- **No Windows-only optimizations exist** — same source tree; the "Windows
  advantage" is a GPU with native VK_EXT_mesh_shader. Our lever:
  `RADV_DIRECTMESH=1` flips eden to the native task/mesh path (verified:
  BC250 mesh split log lines appear; emulated "ReportUnsupportedMeshPipeline"
  survey spam stops).
- **OoT env is harmful to other games**: VSYNC_HZ=30, SWAP_INTERVAL=2,
  VI2_MAX_RESOLUTION_MODE=1 are OoT-specific. Option 5 now generates
  per-game launchers (`lichii-<slug>`) + per-game ini (`<slug>.ini`):
  - `mkw`: safe knobs + 30 Hz trio (mkw_30fps recipe) + `mkw_30fps=true`
    in [Renderer] + `EDEN_NX2_MESH_ARENA_MIB=64` (mesh-heavy; default 16)
    + optional `RADV_DIRECTMESH=1` + `unset EDEN_NX2_FORCE_MESH_FALLBACK`
    (presence-check var — "=0" still forces emulation!)
  - `generic`: safe knobs only, no OoT trio.
- Emulated mesh path SKIPS indirect mesh draws entirely → possible missing
  geometry in MKW. DirectMesh may fix them.
- Verified MKW boots at ~59 game FPS + FSR3 FG→~68 presents (pre-profile,
  DirectMesh off, 20s sample); profile with DirectMesh boots and splits mesh
  shaders natively. Real in-game FPS: user test.
- Avoid: EDEN_NX2_NO_REACTIVE (-5fps MKW), BUFFER_DOWNLOADS, MESH_WIDE_BARRIER,
  NO_MESH, FRAMES_AHEAD=1.
- Diagnostics: EDEN_NX2_GPU_PROFILE=1, PRESENT_FENCE_TRACE, STUTTER_TRACE,
  MESH_ARENA_LOG. Upstream notes: MKW is GPU-THREAD-bound not host-GPU-bound.
- Medium-term: znver2+ThinLTO build (MastaG repo or our flags); cherry-picks
  #1577 (MKW .esetb precache via --build-warm), #1479, #1539, #1528+#1532.
- Upstream merge >v8 regresses OoT (Castle Town freeze) — don't merge; wait
  for their bisect (exp/v8-full-merge).
