---
description: Spec-driven feature flow — draft spec, delegate to specialist subagents, review gate, hardware test
---

# Spec workflow

Use this when the user asks for a feature or investigation big enough to
warrant a spec (see `.devin/specs/README.md` for when). For small fixes,
skip this entirely.

## 1. Draft

- Create `.devin/specs/<slug>/spec.md` from `.devin/specs/_template.md`.
- Gather cheap context first: relevant `.kb/` files, `git log` on the
  affected subsystem, upstream links the user gave.
- If upstream research is needed, spawn the `researcher` subagent
  (`.devin/agents/researcher.md`) in the background — it is read-only and
  cheap. Fold its delta report into the spec's Investigation notes.
- Mark Status: `draft`. Show the user the spec and STOP. Do not implement
  until the user says go.

## 2. Implement (after user approves the spec)

- Mark Status: `implementing`.
- Fan out to the specialist that owns the area — `.devin/agents/`:
  - `linux-systems` — kernel patches, start.sh plumbing, systemd, persist
  - `amd-gaming` — Mesa/RADV patch series, Proton/OptiScaler, VA-API
  - `steamos` — read-only rootfs handling, atomic-update survival, Flatpak,
    Steam runtime quirks
  A spec may need more than one; keep their file sets disjoint.
- Specialists must read `.devin/subagent-rules.md` (their prompts enforce
  it) — the non-negotiables: no commits/pushes, no boot/SMU/VCN writes,
  install+revert+persist contract, `bash -n` after edits.

## 3. Review gate

- Spawn `reviewer` on the resulting diff before showing the user.
- BLOCKED findings get fixed and re-reviewed; PASS-WITH-NOTES goes to the
  user with the notes visible.

## 4. Hand off for hardware test

- Mark Status: `testing`. Summarize exactly what to run and what to
  observe. The user tests on real hardware — never claim success from
  dry-runs alone.

## 5. Close

- After user confirms: Status `done`, fill Result (version, upstream sync
  point, follow-ups). Update `.kb/` with durable findings.
- If the user hits problems: keep the spec open, log findings in
  Investigation notes, iterate or park.

## Forbidden at every stage

Committing, pushing, tagging, or releasing — those happen only when the
user asks, per `AGENTS.local.md` and the `release` workflow.
