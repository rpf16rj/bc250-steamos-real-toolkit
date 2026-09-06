---
description: Work on the BC-250 SteamOS Real Toolkit — development, patches, debugging, and architecture
---

## Knowledge Base

The local KB at `.kb/` contains accumulated knowledge about this project.
Always read relevant KB files before starting work:

- `.kb/hardware.md` — BC-250 hardware specs, APU, GPU, PCON CH7218, Samsung Q80A
- `.kb/kernel.md` — SteamOS Neptune kernel, versions, patches, module params, GRUB
- `.kb/display.md` — Display pipeline: DP→HDMI PCON, FRL, EDID override, VRR, ALLM
- `.kb/patches.md` — All kernel patches, what they do, when to apply
- `.kb/start_sh.md` — start.sh architecture, functions, menu structure
- `.kb/build.md` — Build system: patch-driver.sh, fetch-sources.sh, build.sh, Mesa
- `.kb/steamos.md` — SteamOS specifics: read-only fs, GRUB, EFI boot, mkinitcpio
- `.kb/troubleshooting.md` — Known issues, diagnostics, solutions

## Key Rules

1. **Always check the KB first** — read relevant `.kb/*.md` files before starting any work
2. **Search the web first** when asked to investigate something new
3. **Ask for user confirmation before applying any changes** — edits, commands, patches
4. **Never commit to develop or main without explicit user permission**
5. **The KB at `.kb/` is local only** — never commit it (it's in .gitignore)
6. **Update the KB** when you learn something new about the project

## Architecture Quick Reference

- **Entry point**: `start.sh` — TUI with install/revert menus
- **Patches**: `external/bc250-steamos/bc250-audio-fix/*.patch`
- **Build**: `external/bc250-steamos/bc250-audio-fix/patch-driver.sh`
- **Mesa**: `external/bc250-steamos/bc250-gfx1013-fix/build-mesa.sh`
- **EDID override**: `edid/samsung-q80a-hdmi21.bin`
- **Boot**: EFI → steamcl.efi → GRUB → vmlinuz-linux-neptune-72
