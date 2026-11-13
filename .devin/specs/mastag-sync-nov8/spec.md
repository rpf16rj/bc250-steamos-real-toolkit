# MastaG/community sync — Nov 8 (delta Oct 24 → Nov 8)

User asked for everything incl. watch items.

## Phase 1 — docs/trivial (this session)
- **Dual-audio v0.17 hunk**: `90-bc250-audio-mode.lua` — keep streams whose
  `target.object` names another device's sink (DualSense haptics, USB DACs).
  ~30-line Lua hunk alongside our SteamOS adaptations. v0.16 alsa.lua SKIP
  (requires WirePlumber 0.5.18; we pin 0.5.17).
- **FSR4/Proton docs+labels sync**: default now `freefg-hlxfsr4`; HelixSR
  3.2.1/Scaler 2.2.0; old names are aliases (`helixsr`/`helixsr-ffx`/
  `freefg-helixsr`→`freefg-hlxdlss`; `hlxfsr4`/`freefg-hlxfsr4full`→
  `freefg-hlxfsr4`; `fsr411f`/`signed`/`fsr412f`→`freefg`); FG OFF by
  default; new first-launch GTK4 menu (`PROTON_OPTISCALER_MENU=1` re-show,
  SteamOS untested); game-presets DB; MFG Unlocker (XeFG 3×/4×);
  `BC250_XEFG_NO_STAGGERED_SUBMIT=0`. Update start.sh hints +
  both Decky plugins (fsr4-launch-options, launch-coach) + .kb/toolkit.md.
- **.kb updates**: ROCm sched_policy=2 recommendation; runlist-flush
  unstable-under-load warning; VA-API v0.5.4 knob list; KytyPS5 watch;
  DirectMesh v1.4.1 withdrawn/blacklist + repo rename
  (`lonewolf0622/Mesh-Shaders-for-Rdna-1-`).

## Phase 2 — kernel patches (vendor, inert-at-default)
Fetch from MastaG linux-cachyos-bc250, adapt to Valve neptune-72 (7.2.7):
- `0025` kfd-nohws-vmid-flush (9-line kfd_priv.h)
- `0026` bc250_tlb_flush_type knob (~15 lines gmc_v10_0.c)
- `0028` gmc-kfd-vmid-mmio-flush (KIQ→MMIO type-0 for KFD VMIDs; our
  0003-scoped-pasid-type0 already has the matching refactor)
- `0023`/`0024`/`0027` KytyPS5 enablement (2nd gfx ring, eop events,
  mtype rw) — inert at defaults, vendored for future Kyty support
- `0008` runlist-flush rewrite → WATCH only (upstream now flags
  unstable-under-load on sched_policy=0); note in .kb, do not port
Dry-run apply + reverse against `valve-kernel/` pristine tree; rebuild
amdgpu prebuilt; update fingerprint/flags.

## Phase 3 — new components
- **bc250_vrm v1.1.0** (Hexxeh/bc250-vrm-dkms): VRM rail V/I/temp/power via
  NCT6687 SMBus — no wiring mod. New optional component:
  install_*/revert_*/installed contract + DKMS. Verify coexistence with
  our nct6687 hwmon usage first (port-0/1 sharing).
- **KytyPS5-Native**: runtime packaging on SteamOS (no pacman repo) —
  needs upstream artifact fetch + `kyty-lodhw` root helper + cmdline
  opts. Large; vendor kernel prereqs now, installer if artifact shape allows.

## Explicitly NOT doing (documented)
- DirectMesh v1.4/v1.4.1: v1.4.1 withdrawn same-day (hangs/mem); raw v1.4
  doesn't apply to our base — wait for MastaG rebase.
- HelixSR 3.3.0: released upstream but not pinned in MastaG packages —
  auto-arrives when he bumps.
- Kernel 7.3/7.4, BORE variant: we stay on Valve 7.2.

## Test plan
- bash -n; patch dry-run apply+reverse on pristine valve-kernel tree
- reviewer gate; user hardware test (kernel module + dual-audio + VRM)
- no commit/release until user tests
