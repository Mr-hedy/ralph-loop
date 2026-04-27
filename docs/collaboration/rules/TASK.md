# Task Protocol

Read this before changing root `task.md` or deciding where iteration tasks
should live.

# Purpose

`task.md` is the active iteration board. It is not a backlog, not a roadmap, and
not a session log.

The goal is to keep one small execution surface for the current loop while
preserving durable project knowledge in the correct places.

`task.md` only covers stages 3-5 of the collaboration workflow:

1. Iteration planning.
2. Task breakdown.
3. Task execution.

Requirement clarification and solution discussion happen before `task.md`. If
those earlier stages produce durable project facts, update `docs/roadmap.md`,
architecture docs, or development docs instead of storing the discussion in
`task.md`.

# File Boundaries

| File | Responsibility |
|---|---|
| `docs/roadmap.md` | Long-term phases, acceptance criteria, and checked-off iteration outcomes |
| `task.md` | Current iteration tasks only |
| `handoff.md` | Cross-session state and next-step handoff |
| `docs/collaboration/checkpoints/` | Generated checkpoint notes |
| `docs/collaboration/postmortems/` | Generated failure-pattern entries |

# Task Board Lifecycle

1. Confirm that requirement clarification and solution discussion are complete
   enough to choose an iteration.
2. Choose the next iteration from `docs/roadmap.md`.
3. Write only the current iteration objective and roadmap anchor into `task.md`.
4. Break the iteration into ordered, executable checklist items.
5. Execute from top to bottom, starting with the first unchecked task.
6. Mark a task `[x]` only after it is actually complete.
7. Record `完成`, `变更`, `验证`, and `注意` for completed tasks.
8. If blocked, leave the task unchecked and add `阻塞` or `需要决策`.
9. At iteration close, update `docs/roadmap.md`, update `handoff.md`,
   and create a checkpoint only when a rollback anchor is useful.
10. Reset `task.md` for the next iteration instead of appending permanent history.

For development tasks, `完成` includes the task-scoped verification. Before
marking a development task `[x]`, run the smallest sufficient tests for that
task and record `验证：<command + result>`. If required unit or integration
coverage does not exist yet, keep the task unchecked and record `阻塞` or
`注意` instead of treating compile success as task completion.

# Execution Driver

Use `.agents/skills/task-loop/SKILL.md` only when the user explicitly asks to
execute the current task list in a loop. The skill drives `task.md`; it does not
change this protocol, create another task source, or use `handoff.md` as a task
source. If a task is too broad to execute in loop slices, split it during the
planning or task-breakdown stage instead of using the loop as a substitute for
decomposition.

# Format

Use plain checklist tasks:

```md
- [ ] Implement the first scoped feature.
  - 预期：用户能完成目标流程。
  - 参考：`docs/architecture/overview.md`、`docs/development/testing.md`
```

Use completion notes only after the task is complete:

```md
- [x] Implement the first scoped feature.
  - 完成：完成目标流程的核心实现。
  - 变更：`<paths-or-modules>`
  - 验证：`<command + pass/fail>`
  - 注意：`<verification gap or follow-up>`
```

# Running Notes

Do not record per-loop running notes, exploratory attempts, or raw command
outputs in `task.md`. Keep `task.md` as state, not a session log. Use handoff,
checkpoint, postmortem, or the final response when that detail is actually
needed.

Do not record broad requirement exploration, solution alternatives, or rejected
designs in `task.md`. Keep those in the conversation unless they become stable
project facts that belong in roadmap, architecture, or development docs.

# Escalation

Add a short decision task when execution cannot proceed safely:

```md
- [ ] Decide persistence boundary.
  - 需要决策：changing persistence may affect user data and rollback.
```

Do not invent role prefixes unless the prefix changes behavior. Plain tasks are
preferred over `PLAN-*`, `DEV-*`, `QA-*`, or `REVIEW-*` labels.
