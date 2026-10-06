# Specs — spec-driven development for this toolkit

Lightweight specs for **features and investigations only**. Plain bugfixes,
typos, and routine upstream-sync tweaks go straight to `develop` — no spec.

## When a spec exists

A spec is worth it when the change is any of:

- a new toolkit component (install/revert/persist trio)
- a kernel or Mesa patch series change
- an investigation that may or may not become code (e.g. VCN bring-up)
- anything whose blast radius reaches boot, display, or gamescope

## Lifecycle

1. **Draft** — `.devin/specs/<slug>/spec.md` from `_template.md`, written by
   the agent with whatever context exists (upstream links, KB notes).
2. **Review** — the user reads/edits the spec before implementation. Nothing
   below "reviewed" gets implemented by an agent.
3. **Implement** — delegated to specialist subagents
   (`.devin/agents/`): `researcher` for upstream deltas, `linux-systems` /
   `amd-gaming` / `steamos` for code, `reviewer` as the pre-commit gate.
4. **Testing** — user validates on real hardware. This gate is mandatory:
   no release without it.
5. **Done / parked** — spec updated with the outcome; parked specs keep
   their investigation notes (they are the memory of *why we stopped*).

## Conventions

- One directory per spec: `.devin/specs/<slug>/` — `spec.md` plus any
  scratch artifacts (diffs, test logs) worth keeping.
- Specs are committed; `.kb/` stays local-only. Put durable findings in
  both: the spec records *what we decided*, the KB records *what is true*.
- Status field in the spec header is the source of truth — keep it current.
- `parked` is a first-class outcome, not a failure.

See `.devin/workflows/spec.md` for the operator workflow.
