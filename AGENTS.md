# BC-250 SteamOS Real Toolkit — Agent Notes

Single-file bash TUI (`start.sh`) that patches and configures real SteamOS on
the AMD BC-250 (Cyan Skillfish / GFX1013). Run on the user's daily-driver
hardware — correctness and reversibility outrank cleverness.

## Working agreements

- Branching: work on `develop`; `main` only gets merges at release time.
  Never commit/push/tag/release unless the user asks **at that moment**.
- New user-facing components follow the contract: `install_*` +
  `revert_*` + `*_installed` + `persist_state_add` + a reapply `case` +
  atomic-update keep-list entries when writing rootfs.
- `bash -n start.sh` after every edit. Patch changes are verified with
  dry-run apply *and* reverse against a pristine tree.
- The user tests on real hardware before anything ships — never claim
  hardware behavior from dry-runs or upstream READMEs.

## Specs & subagents — REQUIRED workflow

- **Every feature, investigation, or non-trivial change runs spec-driven**:
  draft `.devin/specs/<slug>/spec.md` (template: `.devin/specs/_template.md`)
  → user review → implement → reviewer gate → user tests → commit. Process:
  `.devin/specs/README.md`, workflow: `.devin/workflows/spec.md`. Only
  trivial bugfixes/docs edits skip the spec.
- **Use the specialist subagents proactively** — `.devin/agents/`:
  `researcher` (upstream/patch comparison — dispatch for any "investigate
  X upstream" task), `linux-systems` (kernel/bash/systemd write work),
  `amd-gaming` (Mesa/RADV/Proton write work), `steamos` (read-only fs /
  atomic-update / Flatpak questions), `reviewer` (mandatory review gate
  before any commit/release the user requests). All must obey
  `.devin/subagent-rules.md`. Parallel-dispatch independent work instead of
  doing it serially in the root agent.
- **Invoke matching skills/tools first** — `devin-cli` for Devin questions,
  `declarative-repo-setup` for environment.yaml, `upload-secrets` for
  secrets. Check `.devin/workflows/` for canned procedures.
- `.kb/` holds the durable knowledge base (local-only, gitignored) — consult
  it before touching a subsystem; update it with findings that outlive a
  single change.
