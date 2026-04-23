---
name: handoff
description: Use when the user asks to create, refresh, compact, or update the project session handoff. This skill updates root handoff.md according to the project handoff protocol.
---

# Handoff Skill

This is an action skill. Use it only when a handoff is explicitly needed, such
as session handoff, context compaction, resuming work, or preparing the next
agent.

# Purpose

- Help the next session recover current context quickly.
- Make phase, scope, verification state, blockers, and residual risk explicit.
- Prevent `handoff.md` from becoming an append-only diary or raw log dump.

# Output

- Output file: root `handoff.md`.
- Template: `.agents/skills/handoff/TEMPLATE.md`.
- Default behavior: overwrite the current handoff with the latest continuation state.
- Skip handoff updates for tiny changes that create no useful continuation state.
- Write the handoff in the project's agreed language; if none exists, follow
  the language already used in nearby project docs.

# Required Content

The handoff must state:

- Current phase and scope.
- Stable decisions that the next session should not re-litigate.
- Completed work and changed areas.
- Verification commands that passed, failed, were not run, or were blocked.
- Whether a `docs/postmortems/` entry was found, added, or updated.
- Whether a checkpoint exists. If yes, include the checkpoint note path and commit.
- Current working tree state and the most useful next action.

# Workflow

1. Collect decisive state:
   - `git branch --show-current`
   - `git status --short`
   - `git log -5 --oneline`
   - verification commands already run in this session
2. Read existing `handoff.md` and preserve still-valid continuation context.
3. Overwrite `handoff.md` using `.agents/skills/handoff/TEMPLATE.md`.
4. Record verified, unverified, blocked, checkpoint, and postmortem status.

Do not append a running diary. Handoff is current continuation state, not
permanent history.
