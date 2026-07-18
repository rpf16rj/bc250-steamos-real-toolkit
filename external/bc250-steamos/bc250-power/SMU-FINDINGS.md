# BC-250 (Cyan Skillfish) SMU / power-management analysis

Static teardown of the BC-250's platform BIOS SMU firmware, to answer: **can the
board reach a real low-power sleep state, and what power levers actually exist?**

> **Correction (this revision).** An earlier version of this file claimed the
> SMU exposed only "13 handlers / 64 slots, no deep-sleep, sleep impossible."
> That was wrong — it read a *tick/feature slot table*, not the message queue.
> The real message table has ~120 handlers across 4 queues (~35 in the
> host/driver queue), **including deep-sleep, WGP power-gating, and S3
> power-off messages**. Corrected below. Credit to
> [bc250-collective/amd_smu_reverse_engineering](https://github.com/bc250-collective/amd_smu_reverse_engineering)
> — Xtensa Ghidra specs + decoded message tables — which enabled the fix.

## TL;DR
- The SMU core is **Xtensa**. Firmware is plaintext (signed, not encrypted).
- The PMFW **implements** deep-sleep gfxclk, WGP (compute-unit) power-gating,
  and S3 suspend power-off messages. The stock amdgpu driver maps only 11
  messages and **never sends them** — so these are reachable by *driver*
  patching, no firmware mod, no PSP-signing wall.
- What is genuinely **absent** (no handler in firmware): `AllowGfxOff` /
  `EnterBaco` by name — i.e. full GFXOFF / BACO chip-off. `RequestActiveWgp`
  is a partial GPU power-gate; `ConfigureS3PwrOff*` means S3 suspend is
  firmware-supported.
- `bc250-smu-deepsleep.patch` here is a first driver patch that maps and uses
  `SetMinDeepSleepGfxclkFreq` (idle power, no perf cost under load).

**Target BIOS: Robin 3.00** ("Robin X.00" is ASRock's naming for the stock
BC-250 releases). All addresses, offsets, and the driver patch here are for
3.00. 5.00 was examined only for cross-version findings — see the note at the
end; it is not a target.

## Provenance
| Artifact | SHA-256 |
|---|---|
| `BC250_3.00_CHIPSETMENU.ROM` | `48fbe5d366e6a56e2fdffdca848426216ba1f083610dab63db89d2f4e6c940b5` |
| `cyan-skillfish-smu-fw.bin` (SMU from 3.00) | `6a3da1ef6024c3143283fb92468fd71d628e9402a751c4a9799a20f473549ad9` |

## Locating the SMU firmware (3.00)
AMI Aptio BIOS with an AMD PSP directory (`$PSP` @ flash `0x8e0000`). SMU is
PSP entry type `0x08` (the `0x12` B-slot is blank):

```
type=0x08 SMU_FW size=262656 -> flash 0x8ff000
```

Layout: 0x100-byte PSP entry header, then 256 KiB payload. Runtime→file map:
`file_offset = runtime_addr + 0x104` (validated: the Queue 0 handler table at
runtime `0x7070` lands at file `0x7174` with the expected `TestMessage` /
`GetSmuVersion` pointers).

## The message queue table (3.00)
At runtime `0x7070` (file `0x7174`): **4 queues, 8-byte entries**
`{func_ptr, config}`. Queue 0 is the host/driver PPSMC interface, ~35 real
handlers. Power/sleep-relevant handlers **present** (func addresses read from
the 3.00 binary; all non-null):

| msg id | handler (3.00) | name | note |
|---|---|---|---|
| `0x16/0x17` | `0x24f28/0x24f58` | ConfigureS3PwrOffRegisterAddress Hi/Lo | S3 suspend power-off |
| `0x18` | `0x2b1d0` | RequestActiveWgp | GPU compute-unit power gate |
| `0x19` | `0x2b2b4` | SetMinDeepSleepGfxclkFreq | idle gfxclk floor |
| `0x1A` | `0x2b2f4` | SetMaxDeepSleepDfllGfxDiv | deep-sleep DFLL divider |
| `0x1E` | `0x2b350` | QueryActiveWgp | read active WGP count |
| `0x0E` | `0x2b0c0` | RequestGfxclk | GFX clock (driver uses) |
| `0x3B/0x3C` | `0x2c048/0x1db14` | Force/UnforceGfxVid | GFX voltage (driver uses) |

The stock `cyan_skillfish_ppt.c` `cyan_skillfish_message_map` maps only 11 of
these. The rest are implemented in firmware but never called by Linux. Message
IDs (`0x16`, `0x19`, …) are the fixed PPSMC protocol from `smu_v11_8_ppsmc.h`,
so the driver patch is keyed to IDs, not these build-specific addresses.

Not present anywhere in the table: `AllowGfxOff`, `EnterBaco`, `ArmD3` — so
full GFXOFF / BACO chip-off is genuinely unavailable, and (firmware being
PSP-signed) cannot be added.

## Sleep verdict
- **Full GPU chip-off (GFXOFF/BACO):** no — handler absent, can't be signed in.
- **S3 suspend-to-RAM:** firmware-supported (`ConfigureS3PwrOff*`); needs
  driver/ACPI wiring to exercise.
- **Deep-sleep gfxclk + WGP power-gating:** firmware-supported, driver-unused →
  reachable by patching amdgpu. This is the practical path to lower idle/GPU
  power, well past clock-gating alone.

## Reachable levers, in order
1. AMD CBS knobs (BIOS) — `AMDSETUP-power-knobs.txt` (PPT cap, C-states, DF
   C-states, deep-sleep clocks).
2. GFX undervolt/downclock — `pp_od_clk_voltage` VDDC curve.
3. **Driver-side, using existing PMFW messages** — `bc250-smu-deepsleep.patch`
   (deep-sleep gfxclk floor; WGP gating mapped for follow-up).

## Caveats
- Handler *identification* comes from the RE repo's Xtensa disassembly; this
  file validates the table against the 3.00 binary but does not re-disassemble.
- Offsets are for Robin 3.00. Re-extract for other builds.
- Live corroboration on the board: `GetEnabledSmuFeatures` returns a bitmask of
  which power features the PMFW currently has enabled.

## Method / tooling
- BIOS FV/PSP extraction: `uefi-firmware-parser`.
- PSP-dir + SMU-header parse, entropy, table validation: ad-hoc Python (no
  external binaries executed).
- Message-name decode + Xtensa disassembly: the RE repo linked above.

## Cross-version note (5.00 — reference only, not a target)
5.00 (`BC250_5.00_clv.bin`, SMU sha `13c93c08…`) was examined only to check
whether a newer BIOS adds power capability. It does not:
- Version constant `0x00580600` (3.00) → `0x00580701` (5.00); the code half is a
  full recompile (~98% byte-diff, entropy ~7.3), but the **message set is the
  same** — same deep-sleep/WGP/S3 handlers, no GFXOFF/BACO added.
- Its handler addresses differ (build-specific), which is why the driver patch
  keys to PPSMC message IDs, not addresses — so it is unaffected either way.
- Reports of 5.00 causing issues trace to the **metrics table** (`SmuMetrics_t`)
  layout / **DriverIfVersion**, not the message interface — out of scope here.
