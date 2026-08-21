# BC-250 Native Mesh Shaders for RADV

Experimental native `VK_EXT_mesh_shader` support for the AMD BC-250 (`CHIP_GFX1013`) in Mesa RADV.

The goal is to run the **MESH stage natively on the BC-250's physical GFX10/RDNA1-class GPU** without globally pretending the device is GFX10.3.

> **Status:** Native MESH V1 is the current known-good milestone with 15/15 validated project runtime cases. Native TASK execution is **not** enabled. Hybrid TASK support is a separate work-in-progress.

## What V1 does

`bc250-native-mesh-v1-known-good.patch` adds a narrowly scoped BC-250 native-MESH path while preserving the real hardware identity:

```text
family    = CHIP_GFX1013
gfx_level = GFX10
```

Key points:

- Removes the old BC-250 device-level `GFX10_3` spoof.
- Allows ACO to compile **MESH-only** shaders on this specific GFX10 device through a narrow `allow_gfx10_mesh_shader` exception.
- Exposes the MESH portion of `VK_EXT_mesh_shader`.
- Keeps actual native TASK compilation/execution fail-closed.
- Rejects `CullPrimitive` on the BC-250 path.
- Enables validated per-primitive PS input and PrimitiveId state.
- Uses native direct, indirect, indirect-count, and DGC mesh launch paths.
- Keeps the rest of GFX10 ISA, hazard, scheduling, and register policy intact.

## Why this is needed

Upstream RADV/ACO normally assumes mesh shading starts at GFX10.3. The BC-250 is unusual: it is `CHIP_GFX1013`, but its graphics path is physically GFX10-class.

The project therefore avoids globally doing:

```c
info->gfx_level = GFX10_3;
```

and instead adds small, feature-specific exceptions only where BC-250 behavior has been validated.

## Current validation

Current native-MESH milestone: **15/15 PASS**.

| Area | Status |
|---|---|
| Direct MESH | ✅ PASS |
| Indirect MESH | ✅ PASS |
| Indirect-count MESH | ✅ PASS |
| Per-vertex outputs | ✅ PASS |
| Per-primitive outputs | ✅ PASS |
| PrimitiveId | ✅ PASS |
| Points | ✅ PASS |
| Lines | ✅ PASS |
| Triangles | ✅ PASS |
| Subgroup operations | ✅ PASS |
| Workgroup barriers | ✅ PASS |
| LDS/shared memory | ✅ PASS |
| Larger ordinary outputs | ✅ PASS |
| Ordinary register spilling | ✅ PASS |
| DGC direct + DGC mesh-count | ✅ PASS |

Representative native direct result:

```text
center_rgba=255,0,0,255
NON_BLACK_PIXELS=968
BOUNDING_BOX=10,10,53,52
PASS
```

Ordinary register spilling has also been exercised with:

```text
scratch bytes            = 3072
needs_ms_scratch_ring    = false
```

DGC direct and mesh-count execution both passed through generated IB chaining.

Project testing has also included Final Fantasy VII Rebirth rendering correctly through the native MESH path. That is a practical compatibility result, not a claim of full Vulkan conformance.

### vkd3d-proton feature-level override

For titles or launchers that otherwise fail the Direct3D feature-level check, the project testing setup uses:

```bash
VKD3D_FEATURE_LEVEL=12_2
```

For example:

```bash
VKD3D_FEATURE_LEVEL=12_2 %command%
```

when setting a Steam launch option.

This only overrides vkd3d-proton's reported/selected D3D feature level for compatibility testing; it does not turn unsupported GPU features into hardware support.

## Architecture

### Direct MESH

BC-250 uses the legacy/mode-1 NGG MESH path:

```text
vkCmdDrawMeshTasksEXT
        |
        v
inline NumWorkGroups XYZ user SGPRs
        |
        v
DRAW_INDEX_AUTO / graphics launch
        |
        v
native MESA_SHADER_MESH
```

### Indirect MESH

The native indirect path uses:

```text
PKT3_DISPATCH_MESH_INDIRECT_MULTI
opcode 0x4C
```

The validated indirect command format is the normal 12-byte XYZ record:

```c
struct {
    uint32_t groupCountX;
    uint32_t groupCountY;
    uint32_t groupCountZ;
};
```

### NumWorkGroups ABI

The BC-250 mode-1 MESH path uses inline user SGPRs:

```text
+0   groupCountX
+4   groupCountY
+8   groupCountZ
+12  DrawID when required
```

No pointer/SMEM grid-size ABI is used for this path.

## Important V1 fixes

### Physical GFX10 identity

The patch keeps:

```text
CHIP_GFX1013
GFX10
```

and passes a narrow ACO compiler option only for BC-250 MESH.

### PrimitiveId

BC-250 native MESH enables primitive-ID state when the MESH shader exports per-primitive PrimitiveId.

### Per-primitive fragment inputs

The BC-250 path allows the validated per-primitive PS input setup while the physical device remains GFX10.

### DGC compute-IB alignment

BC-250 has no usable compute/ACE queue, so:

```text
AMD_IP_COMPUTE.ib_alignment = 0
```

Mesh-only DGC has no ACE command stream. V1 therefore validates the compute IB alignment only when:

```text
cmdbuf_layout.ace_cmd_stride != 0
```

This fixes the mesh-only DGC preprocessing divide-by-zero/assertion without pretending the device has a usable compute queue.

## TASK status

`taskShader` may be advertised on BC-250 for API capability negotiation, but **native TASK execution is not supported by V1**.

V1 keeps TASK fail-closed:

- no native GFX10 TASK compilation
- no task rings
- no ACE/MEC TASK dispatch
- no gang submission
- no native TASK packet execution

A separate hybrid TASK design is in progress. See [`docs/HYBRID-TASK-WIP.md`](docs/HYBRID-TASK-WIP.md).

## Known limitations / quarantine

### MESH output scratch ring

**Quarantined.**

This is separate from ordinary register spilling, which is already validated.

The output-scratch-ring path is used when MESH outputs no longer fit the normal LDS-resident path. The descriptor/user-data ABI looks promising, but the ordered-wave-ID bound used to index the ring has not been proven safe on physical GFX1013/GFX10.

Do not interpret the validated larger-output test as proof of:

```text
needs_ms_scratch_ring = true
```

### CullPrimitive

**Quarantined — known whole-machine hard-lock risk.**

V1 rejects MESH shaders that write `CullPrimitive`.

Do not casually remove this guard. Previous testing reached a full-machine lock. In particular, do not change primitive-export bit 31 behavior or remove the known GFX10 pre-`GS_ALLOC_REQ` barrier without a concrete hardware explanation.

### Full conformance

This project does **not** claim complete `VK_EXT_mesh_shader` conformance.

The current result is a practical, tested native-MESH implementation for BC-250 with known unsupported areas documented above.

## Applying the patch

Clone or enter the Mesa source tree you want to patch, then apply the patch from this repository:

```bash
cd /path/to/mesa
git apply --check /path/to/bc250-native-mesh-v1-known-good.patch
git apply /path/to/bc250-native-mesh-v1-known-good.patch
```

Configure Mesa with your normal RADV build options. For example, if your Meson build directory is named `build`:

```bash
ninja -C build -k 0
```

The exact Meson options, install prefix, and build-directory name are intentionally not hard-coded here because they depend on each user's Mesa setup.

## Testing with an explicit RADV ICD

If you want to test a locally built RADV without replacing your system driver, point Vulkan at the ICD JSON generated or installed by your Mesa build:

```bash
VK_ICD_FILENAMES=/path/to/your/radeon_icd.x86_64.json \
MESA_SHADER_CACHE_DISABLE=true \
timeout 10s \
./tests/bc250-native-mesh/bc250-native-mesh-tests direct
```

Replace `/path/to/your/radeon_icd.x86_64.json` with the actual ICD path on your system.

Use the actual harness binary/mode names present in your checkout.

A userspace `timeout` cannot recover a GPU or whole-machine hard lock. Keep quarantined paths out of automated runs.

## Suggested repository layout

```text
.
├── README.md
├── bc250-native-mesh-v1-known-good.patch
├── docs/
│   ├── STATUS.md
│   └── HYBRID-TASK-WIP.md
└── tests/
    └── ...
```

## Development rules

1. Keep physical `gfx_level = GFX10`.
2. Do not globally spoof BC-250 as GFX10.3.
3. Prefer narrow `CHIP_GFX1013` exceptions over generation-wide changes.
4. Keep native MESH native.
5. Keep native TASK disabled unless hardware support is actually proven.
6. Do not automatically retry a hard-locking test.
7. Keep the known-good V1 patch independently usable while experimental TASK work continues.

## More detail

- [`docs/STATUS.md`](docs/STATUS.md) — validated MESH status and quarantined areas.
- [`docs/HYBRID-TASK-WIP.md`](docs/HYBRID-TASK-WIP.md) — current TASK→COMPUTE→native-MESH work.

## Disclaimer

This is experimental Mesa/RADV work for unusual hardware. Unsupported paths can cause GPU resets or system hangs. Test on hardware you can recover, keep backups, and do not assume unvalidated GFX10.3 paths are safe on GFX1013.
