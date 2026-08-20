# BC-250 Native MESH Status

This document tracks the validated state of the BC-250 native-MESH work.

## Stable milestone

**Patch:** `bc250-native-mesh-v1-known-good.patch`

**Target:**

```text
AMD BC-250
family    = CHIP_GFX1013
gfx_level = GFX10
```

V1 intentionally keeps the physical device at GFX10. It does not globally spoof GFX10.3.

## Runtime validation

Current project milestone: **15/15 PASS**.

| Area | Result | Status |
|---|---|---|
| Direct dispatch | Native direct MESH | ✅ Validated |
| Indirect dispatch | Native `DISPATCH_MESH_INDIRECT_MULTI` | ✅ Validated |
| Indirect count | Hardware count path | ✅ Validated |
| Vertex outputs | Per-vertex output | ✅ Validated |
| Primitive outputs | Per-primitive PS inputs | ✅ Validated |
| PrimitiveId | Per-primitive PrimitiveId | ✅ Validated |
| Topology | Triangles | ✅ Validated |
| Topology | Points | ✅ Validated |
| Topology | Lines | ✅ Validated |
| Subgroups | MESH subgroup behavior | ✅ Validated |
| Synchronization | Workgroup barriers | ✅ Validated |
| Shared memory | LDS | ✅ Validated |
| Output size | Modestly larger ordinary output | ✅ Validated |
| Private scratch | Ordinary register spilling | ✅ Validated |
| DGC | Direct + mesh-count generated commands | ✅ Validated |

No hard hang or device loss occurred in the currently validated suite.

## Known-good framebuffer reference

Representative direct/native MESH result:

```text
center_rgba=255,0,0,255
NON_BLACK_PIXELS=968
BOUNDING_BOX=10,10,53,52
PASS
```

Use the current harness as source of truth if test geometry changes.

## Ordinary register scratch

Ordinary compiler register spilling is considered validated.

Representative metadata:

```text
scratch bytes:            3072
needs_ms_scratch_ring:    false
```

This is the normal graphics scratch path and is not the separate MESH output scratch ring.

## DGC

### Direct DGC

Validated through actual generated-IB chaining.

```text
DGC DIRECT EXECUTION: PASS
GENERATED IB CHAINING: PASS
```

### Mesh-count DGC

Validated generated PM4 includes:

```text
DISPATCH_MESH_INDIRECT_MULTI
opcode 0x4C
```

Runtime result:

```text
DGC COUNT EXECUTION: PASS
```

### BC-250 DGC alignment fix

BC-250's compute IP is intentionally unavailable, leaving:

```text
AMD_IP_COMPUTE.ib_alignment = 0
```

Mesh-only DGC does not generate an ACE command stream, so the compute-IB alignment assertion is only used when:

```text
cmdbuf_layout.ace_cmd_stride != 0
```

## PrimitiveId

BC-250 native MESH enables primitive-ID state for per-primitive PrimitiveId export.

An earlier intermittent PrimitiveId failure was traced to stale shader compilation/cache state rather than a missing V1 driver fix. Development regression runs should disable the Mesa shader cache per process when investigating compiler changes.

## Per-primitive fragment inputs

The BC-250 path permits the narrowly validated per-primitive PS input setup while the physical device remains GFX10.

## Capability advertisement

### MESH

```text
meshShader = true
```

### TASK

```text
taskShader = true
```

On V1, TASK advertisement is for capability negotiation only. Native TASK execution remains fail-closed.

## Fail-closed / quarantined paths

### Native TASK

Not supported in V1.

Do not enter:

- native `MESA_SHADER_TASK` compilation on GFX10
- ACE/MEC task dispatch
- task control/draw/payload rings
- gang submission
- native TASK packets

Hybrid TASK development is tracked separately in `HYBRID-TASK-WIP.md`.

### CullPrimitive

**Quarantined.**

MESH pipeline and shader-object creation reject shaders that write `CullPrimitive`.

Reason: prior execution reached a whole-machine hard lock.

Do not remove this guard merely to increase feature coverage.

### MESH output scratch ring

**Quarantined.**

Current state:

```text
descriptor / hidden-SGPR ABI: promising
ordered-wave-ID bound:       unproven on physical GFX10
runtime needs_ms_scratch_ring test: not validated
```

This is a separate path from ordinary register scratch.

## Practical compatibility

The project has rendered Final Fantasy VII Rebirth correctly through the native MESH path during testing.

This is a useful compatibility result, not a conformance claim.

## What V1 deliberately avoids

V1 should remain free of:

- global GFX10.3 spoofing
- full software MESH emulation
- old translated `DRAW_INDIRECT` MESH bridge
- speculative native TASK enablement
- task-ring allocation
- ACE/MEC TASK execution
- speculative output-scratch-ring enablement
- CullPrimitive enablement
- unrelated RDNA2/FSR experiments
- temporary bring-up debug spam

## Safety policy

Safe regression coverage is the currently validated native-MESH suite.

Still excluded from automatic execution:

```text
CullPrimitive
MESH output scratch ring
native TASK
```

A userspace timeout cannot recover a whole-machine GPU lock.

For experimental tests, keep a persistent checkpoint such as:

```text
tests/bc250-native-mesh/.last-test
```

so the last test can be identified after a reboot.

## Next work

Native MESH V1 is considered a stable project milestone.

The active next-stage effort is **hybrid TASK + native MESH**:

```text
docs/HYBRID-TASK-WIP.md
```

CullPrimitive and MESH output scratch remain deliberately deferred until their hardware risks are better understood.
