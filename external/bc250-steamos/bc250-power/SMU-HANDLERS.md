# BC-250 (Robin 3.00) SMU message handlers — decompiled

What the SMU message handlers actually *do*, from decompiling the Robin 3.00
PMFW (`cyan-skillfish-smu-fw.bin`). Focus: the Q2/Q3 "extended" handlers the
Linux `amdgpu` driver never calls, plus the Q0 deep-sleep/WGP/S3 handlers.

Raw decompilation: `smu-decompiled-3.00.txt`. Message-id → handler map:
`SMU-FINDINGS.md`. Decode credit: Xtensa disassembly built on
[bc250-collective/amd_smu_reverse_engineering](https://github.com/bc250-collective/amd_smu_reverse_engineering).

## Mailbox ABI (decoded)
Per-queue descriptor at `*(0x00000ba0) + queue*0xc`: `+0xc` = ARG ptr,
`+0x10` = RSP ptr. Helpers:
- `FUN_00000ffc(q)` → read ARG value
- `FUN_00001014(q)` → ARG pointer (for multi-word args)
- `FUN_00000fe4(q,v)` → write return value
- `FUN_00000fa8(q,s)` → write status: `1` = OK, `0xff` = reject

A handler that "just tail-calls `FUN_00000ffc`" is **not** a stub — Ghidra's
"Non-Returning Functions - Discovered" analyzer mis-marks `FUN_00000ffc` and
truncates the body. Disable that analyzer (repo README) to get full bodies.

## Feature framework (the central power lever)
- `Q2_0x05 enable_smu_features(mask)` → `feature_mask |= mask` at `0x17374`,
  then `FUN_0001d940` walks all **64** features and calls each one's
  enable/disable callback to reconcile.
- `Q2_0x06 disable_smu_features(mask)` → `feature_mask &= ~mask`.
- `GetEnabledSmuFeatures` (Q0 0x3D, **driver-mapped**) reads the mask.

**Feature 6 gates the GPU power path:** both `RequestActiveWgp` and the
`q1_0x08` state action check `FUN_0001db54(6)` and reject (`0xff`) if feature 6
is off. So WGP gating is only usable once feature 6 is enabled.

## Q0 — deep-sleep / WGP / S3 (present, driver-unused)
| msg | handler | decoded behaviour |
|---|---|---|
| `0x18 RequestActiveWgp` | `0x2b1d0` | **feature-6 gated.** arg ≤ 18 → `FUN_0002b224(n)` sets active WGP count; current count at `0x18018[0x7f]`. GPU compute-unit power gate. |
| `0x1e QueryActiveWgp` | `0x2b350` | returns current active WGP count. |
| `0x19 SetMinDeepSleepGfxclkFreq` | `0x2b2b4` | arg×scale → `FUN_00023f00(0x19,f)` + `(0x1a,f)`: sets the deep-sleep gfxclk floor. (This is what `bc250-smu-deepsleep.patch` sends.) |
| `0x1a SetMaxDeepSleepDfllGfxDiv` | `0x2b2f4` | arg 1–6 → sets deep-sleep DFLL divider. |
| `0x16 ConfigureS3PwrOff…Hi` | `0x24f28` | sets the S3 power-off register-address config bit. S3 suspend infra. |

## Q2/Q3 — extended CPU+GPU tuning interface (driver-unused)
| handler | decoded behaviour |
|---|---|
| `Q2_0x2c power_limit_set` | `set_power_limit(arg×scale)` → writes **both** fast+slow PPT fields (`0x18450`). Runtime board power cap, no BIOS. |
| `Q2_0x2d power_query` | returns a scaled power value (getter sibling of 0x2c). |
| `Q3_0x0f set/unforce cpu_gpu_vid` | arg hi16: `0` → clear CPU VID force (`0x17110[6]`), `1` → clear GPU VID force (`0x17110[0x26]`). CPU **and** GPU voltage control (driver only does GPU). |
| `Q3_0x24 / Q3_0x25` | per-domain OC clock **set / clear**: writes scaled float + flag into 8 domain structs (`0x1719c`, stride `0x3c4`; idx 0–7 or `0xff`=all). |
| `Q2_0x07 / Q2_0x08` | write a config pair into subsystem `0x17e78`. |
| `Q2_0x0b` | getter: per-index table (≤20 entries, stride `0x20`) → two converted values (per-core config/telemetry). |
| `Q3_0x0a / Q3_0x0b / Q3_0x10 / Q3_0x26` | telemetry / value getters. |
| `Q2_0x16 / Q2_0x20` | toggle a policy pair (`FUN_0001f634` / `FUN_0001f910`), scalar vs bitmask. |
| `Q2_0x0c` | **reset/halt**: arg low16 ∈ {3,4,5} + key hi16 ∈ {0x11,0x22,0} → reset routine then infinite loop. Dangerous. |
| `q1_0x08` | **feature-6 gated** state transition (`FUN_0001ecf4` toggles hardware config bits across units; branches on a persistent flag). Power-down / reset-ish; exact effect still opaque. |

## Power levers this exposes (all driver-unused)
1. `enable_smu_features` — turn on dormant policies (incl. feature 6, which
   unlocks WGP gating).
2. `RequestActiveWgp` — power GPU compute units off/on at idle.
3. `SetMinDeepSleepGfxclkFreq` — idle gfxclk floor (the driver patch).
4. `power_limit_set` (Q2 0x2c) — runtime PPT cap without a BIOS flash.
5. `set_cpu_gpu_vid` (Q3 0x0f) — CPU + GPU voltage (driver only forces GPU).

All Q2/Q3 messages use separate mailbox register sets; the Linux driver drives
only Q0. Reachability is settled below.

## Communication / reachability
Confirmed by [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
(a userspace CPU-OC tool) and reproduced in `bc250-smu-poke.py`:

- **Transport is PCI config space, no kernel module, no MMIO.** Open
  `/sys/bus/pci/devices/<bdf>/config`; the SMN index/data window is at config
  offsets **`0xB8` (index) / `0xBC` (data)**. `write32(0xB8,reg);
  read32(0xBC)` reads any SMN register (incl. the SMU mailboxes). Root only.
- **Each queue is an SMN `(cmd, rsp, arg)` register triple** — these are the
  `queue_descriptor_table` pointers, with concrete addresses:

  | queue | cmd | rsp | arg | notes |
  |---|---|---|---|---|
  | 0 | `0x03B10A08` | `0x03B10A68` | `0x03B10A48` | **amdgpu-owned — racy** |
  | 1 | `0x03B10A00` | `0x03B10A60` | `0x03B10A40` | |
  | 2 | `0x03B10528` | `0x03B10564` | `0x03B10998` | safe |
  | 3 | `0x03B10A20` | `0x03B10A80` | `0x03B10A88` | safe (OC tool uses this) |
  | 4 | `0x03B10A24` | `0x03B10A84` | `0x03B10A8C` | |

- **`send`:** `rsp=0`; `arg`=arg, `arg+4`=arg_high; `cmd`=msg_id; poll `rsp`
  for `0x01`(OK)/`0xFF`/`0xFE`/`0xFD`/`0xFC` — the same status codes the
  handlers write via `FUN_00000fa8`.
- **Q1–Q4 are freely host-reachable** alongside amdgpu. Only **Q0 races the
  driver** (it owns Q0), so Q0 handlers — `SetMinDeepSleepGfxclkFreq` (0x19),
  `RequestActiveWgp` (0x18), `GetEnabledSmuFeatures` (0x3D) — are better driven
  in-kernel (`bc250-smu-deepsleep.patch`) than from userspace.

So the two clean paths to the power levers:
- **Userspace (Q2/Q3):** `enable_smu_features` (Q2 0x05), `power_limit_set`
  (Q2 0x2c), `set_cpu_gpu_vid` (Q3 0x0f) — see `bc250-smu-poke.py`.
- **In-kernel (Q0):** deep-sleep floor + WGP gating — the driver patch.

## Reproducing the decode
Ghidra 12 ships a built-in Xtensa processor, but it misses a few AMD-SMU
opcodes (e.g. `set_oc_clk` decodes as "bad instruction data"). Fix: overlay the
repo's `ghidra/xtensa{Arch,Instructions,Main}.sinc` + `xtensa_le.slaspec` onto a
**copy** of Ghidra's Xtensa module (keeps `cust.sinc`/`flix.sinc`), recompile
with `support/sleigh`, and analyze with "Non-Returning Functions - Discovered"
disabled. Load the trimmed firmware (`dd bs=256 skip=1`) as `Xtensa:LE:32` at
base `0x0`.
