---
name: postmortem
description: Use when the user asks to write or update a postmortem, remember a mistake, record a reusable failure pattern, or when project work hits a significant failure, repeated failure, regression, broken prevention check, or system-level process gap.
---

# Postmortem Skill

This is an action skill. It records reusable failure patterns for the current
project.

## Runtime Read Gate

When a task hits a significant failure, repeated failure, regression, check
failure, broken prevention mechanism, or surprising project-boundary issue,
inspect `docs/postmortems/` before continuing:

1. Read `docs/postmortems/README.md`.
2. Search existing entries for related modules, commands, errors, paths, or
   failure patterns.
3. If an existing entry applies, follow its prevention checks and mention it in
   the final evidence.

Do not write a new postmortem for a one-off typo or disposable experiment.

## Sweep Mode

Run a postmortem sweep before creating a checkpoint or when closing a coherent
iteration. A sweep is a lightweight decision pass, not a requirement to write a
postmortem.

Check whether the iteration had:

- repeated failures or repeated fixes on the same class of issue
- regressions introduced by a fix
- failed or insufficient prevention checks
- surprising boundary, contract, permission, build, or verification failures
- user corrections that reveal a reusable agent behavior problem

Sweep outcomes:

- `none`: no reusable failure pattern; do not create a postmortem.
- `existing`: an existing `docs/postmortems/` entry applies; follow or cite its
  prevention checks.
- `new-or-update`: create or update a postmortem using this skill before the
  checkpoint is finalized.

When called from checkpoint creation, record the sweep outcome in the checkpoint
note.

## Trigger Conditions

Create or update a postmortem when:

- A fix introduces a new regression.
- The same class of problem appears again.
- A failure exposes a system gap in module boundaries, protocol compatibility,
  security defaults, permissions, build flow, or verification.
- An existing prevention check fails or is missing.
- The user explicitly asks to remember a pitfall.

## Workflow

1. Decide whether the issue is a reusable failure pattern.
2. Check existing `docs/postmortems/` entries and update one if it already
   covers the pattern.
3. Analyze:
   - observed symptom
   - direct trigger
   - root cause
   - fix
   - prevention check
4. If creating a new entry, use `.agents/skills/postmortem/TEMPLATE.md`.
5. Write the entry to `docs/postmortems/pm-<domain>-<pattern-slug>.md`.
6. Update `docs/postmortems/README.md` if the index or status changes.
7. If the lesson changes future agent behavior, extract the rule into a skill,
   `.spec/`, script, or test. The postmortem alone is evidence, not a rule.
8. Run verification that matches the changed files.

## Output Constraints

- Include a root cause, not only a trigger.
- Include at least one automated or manually reproducible prevention check.
- State scope so local lessons are not generalized globally.
- Do not include secrets, full credentials, external tool dumps, or raw logs.
- Project facts, architecture decisions, and runbooks belong in their
  authoritative docs, not only in the postmortem.

Use the project's agreed language; if none exists, follow the language already
used in nearby project docs.
