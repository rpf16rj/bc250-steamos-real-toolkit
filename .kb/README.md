# BC-250 SteamOS Real Toolkit — Knowledge Base

Local knowledge base for Cascade. Not committed to git.

## Structure

- `toolkit.md` — Project overview, structure, components, key files, git policy
- `hardware.md` — BC-250 hardware specs, APU, GPU, PCON, display pipeline
- `kernel.md` — SteamOS kernel (Neptune), versions, patches, module params
- `display.md` — Display pipeline: DP→HDMI PCON, FRL, EDID override, VRR, ALLM
- `patches.md` — All kernel patches in the toolkit, what they do, when to apply
- `start_sh.md` — start.sh architecture, functions, menu structure
- `build.md` — Build system: patch-driver.sh, fetch-sources.sh, build.sh
- `steamos.md` — SteamOS specifics: read-only fs, GRUB, EFI boot, mkinitcpio
- `troubleshooting.md` — Known issues, diagnostics, solutions

## Rules
1. Always check this KB first when the user asks for something
2. Always search the web first when the user asks to investigate something
3. Always ask for user confirmation before applying any changes
4. Update the KB whenever new knowledge is created
5. When the user says something worked or looks good, update the KB immediately
6. Always simplify: prefer the simplest functional solution, minimal code, efficient logic
7. For any command, always look in the KB first
8. When editing a very large file, use a piecemeal edit approach to save time and tokens

## Tags
Each file starts with `<!-- tags: ... -->` listing keywords for fast grep-based lookup.
Search with: `grep -r '<!-- tags:' .kb/` to find all tagged files, or grep for a specific tag.
