---
name: checkpoint
description: Use when the user asks to create a checkpoint, save progress, create a rollback anchor, or preserve a stable saved point for project work.
---

# Checkpoint Skill

This is an action skill. Use it only when a checkpoint or rollback anchor is
explicitly requested or clearly needed before a high-risk transition.

# Purpose

- Preserve a known useful state.
- Create a rollback anchor before risky or cross-module changes.
- Avoid mixing unrelated dirty work into one commit.
- Help the next agent understand scope, verification, and residual risk.

# Output

- Output directory: `docs/checkpoints/`.
- Template: `.agents/skills/checkpoint/TEMPLATE.md`.
- Filename: `YYYY-MM-DD-NN-slug.md`.
- `NN` is a two-digit daily sequence starting at `01`.
- `slug` is short kebab-case.
- Write the checkpoint note in the project's agreed language; if none exists,
  follow the language already used in nearby project docs.

# When To Create

Create a checkpoint when:

- The user explicitly asks to save progress, create a checkpoint, or create a
  rollback anchor.
- The current iteration has reached a useful state and the next work is risky.
- Several fixes have converged to a stable point.

Do not create a checkpoint when:

- The current state is a draft or disposable experiment.
- The working tree contains unrelated changes that cannot be safely separated.
- No useful state exists yet.

# Workflow

1. Define checkpoint purpose, scope, and slug.
2. Read `docs/checkpoints/README.md` and any relevant recent checkpoint note so
   the new checkpoint does not duplicate or contradict the previous anchor.
3. Run a postmortem sweep:
   - Read `docs/postmortems/README.md`.
   - Review the current iteration for repeated failures, regressions, failed
     prevention checks, surprising boundary issues, and user corrections that
     reveal reusable agent behavior problems.
   - If a reusable failure pattern exists, pause checkpoint creation and handle
     the postmortem as a separate action before continuing.
   - If no postmortem is needed, record that outcome in the checkpoint note.
4. Collect decisive state:
   - `git branch --show-current`
   - `git status --short`
   - `git diff --stat`
5. Stop if the working tree contains unrelated changes that cannot be safely
   separated.
6. Create `docs/checkpoints/YYYY-MM-DD-NN-slug.md` from
   `.agents/skills/checkpoint/TEMPLATE.md`.
7. Run `git diff --check` and any scope-specific verification.
8. Stage only the coherent checkpoint scope and the checkpoint note.
9. Create a non-interactive commit whose body contains
   `Checkpoint-Note: docs/checkpoints/<file>.md`.
10. Confirm with `git log -1 --stat --oneline` and `git status --short`.

Do not use `git add .`. Do not include `.env` or unrelated changes.
