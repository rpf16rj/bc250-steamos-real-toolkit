# BC250 SMU Python Library

This package provides a Python API for interacting with the BC250 SMU mailboxes
through PCI config space. It is hardware-specific and targets the BC250 board
only.

**ROOT REQUIRED**

## Design Overview

- `Bc250Smu` is the public entry point. It exposes generic send/read helpers
  and queue-specific convenience methods.
- Queue-specific methods are organized in mixin modules:
  `api_q0.py`, `api_q1.py`, `api_q2.py`, `api_q3.py`, `api_q4.py`.
- `transport.py` performs raw PCI config space reads/writes.
- `mailbox.py` implements mailbox command/response flow with per-queue locks.
- `codec.py` contains simple packing helpers.

## Safety Notes

- Accessing SMU mailboxes can conflict with the OS driver. Queue 0 is disabled
  by default and must be explicitly enabled.
- This library reads/writes `/sys/bus/pci/devices/0000:00:00.0/config` and requires root privileges.
- You should avoid concurrent access from multiple processes unless you enable
  `use_flock=True` and other coordination primitives.

## Installation

This is a local package. Import directly from the repository:

```python
from bc250_smu import Bc250Smu
```

## Quick Start

```python
from bc250_smu import Bc250Smu

smu = Bc250Smu(use_flock=True)

# Basic health check
smu.check_test_message()

# Read SMU version and GFX clock (MHz)
print(smu.get_smu_version())
print(smu.query_gfxclk())

# Force GFX frequency (argument is MHz)
smu.force_gfx_freq(1200)

# Read current GFX VID in mV
print(smu.get_gfx_vid())

smu.close()
```

## Queue Access

Default queue mailbox addresses are filled from the Ghidra descriptor table
with the `+0x00b00000` offset:

- Queue 0: CMD `0x03B10A08`, RSP `0x03B10A68`, ARG `0x03B10A48`
- Queue 1: CMD `0x03B10A00`, RSP `0x03B10A60`, ARG `0x03B10A40`
- Queue 2: CMD `0x03B10528`, RSP `0x03B10564`, ARG `0x03B10998`
- Queue 3: CMD `0x03B10A20`, RSP `0x03B10A80`, ARG `0x03B10A88`
- Queue 4: CMD `0x03B10A24`, RSP `0x03B10A84`, ARG `0x03B10A8C`

You can override any of these using the `queue_addrs` parameter:

```python
smu = Bc250Smu(queue_addrs={2: (cmd, rsp, arg)})
```

## Status Codes

Mailbox operations return a status byte. Common values include:

- `0x01` OK
- `0xFF` Failed
- `0xFE` Unknown command
- `0xFD` Rejected: prerequisite
- `0xFC` Rejected: busy

Some convenience methods allow non-OK statuses and will return the raw status.

## Naming Conventions

- Methods with known semantics use descriptive names.
- Unknown messages keep the `qX_0xYY...` naming.
- Methods prefixed with `_` are pending verification and may change.

## VID Conversion

The firmware uses VID codes. The library converts to/from millivolts using:

```
voltage = (vid * -0.00625) + 1.55
```

Helper functions are in `codec.py`:
- `mv_to_vid(mv)`
- `vid_to_mv(vid)`

## License

See `LICENSE` in the repository root.
