---
name: task-loop
description: Use when the user explicitly asks to start or continue executing the current AIP task list, run a task loop, execute task.md, or work through todo items until blocked or complete. Do not use for requirements discussion, solution design, iteration planning, task decomposition, status-only requests, handoff, or checkpoint actions.
---

# Task Loop Skill

This is an action skill. Use it only after the user explicitly enters the
execution phase for the current task list.

# Purpose

- Drive the active `task.md` tasks forward without creating a second task
  system.
- Keep implementation, verification, and task-state updates in the same loop.
- Continue while the next action is clear and in scope; pause when a user
  decision, blocker, or no-progress condition appears.

# Inputs

Read:

- `docs/collaboration/rules/TASK.md`
- root `task.md`

Do not read `handoff.md` by default. It is continuation state, not a task
source. Read it only when the user explicitly asks to resume from handoff or
clearly asks to continue a previous task-loop session.

Do not create `.ralph/`, `fix_plan.md`, or any parallel task source.

# Scope

- Default scope: advance the first unchecked task in `task.md`.
- If the user names a task, advance that task.
- If the user asks to execute the whole todo list or iteration, work from top
  to bottom and run the exit gate after each task.
- Do not change `task.md` structure. Follow `docs/collaboration/rules/TASK.md`.
- Do not use the loop to compensate for oversized tasks. If a task needs
  decomposition before it can be executed safely, pause and ask to split it.

# Loop

For each loop slice:

1. Select the active task and state the loop goal internally.
2. Execute only work needed for that task and slice.
3. Run verification that matches the change.
4. Update `task.md` only when task state changes:
   - Mark `[x]` only after implementation and matching verification are done.
   - Add `完成`, `变更`, and `注意` for completed tasks.
   - Leave the task unchecked and add `阻塞` or `需要决策` when blocked.
   - Do not record per-loop running notes or failed attempts in `task.md`.
5. Decide whether to continue or pause.

# Continue / Pause Rules

Continue when:

- The next action is clear.
- The work remains inside the active task or the user-authorized todo-list
  scope.
- Verification can still make progress.

Pause and report when:

- Requirements or scope are unclear.
- A user decision is needed.
- Verification is blocked by environment or credentials.
- The same failure repeats without a new concrete path forward.
- The active task is too broad to complete safely in loop slices.
- The task would require changing `task.md` structure or creating another task
  source.

# Exit Gate

A task is ready only when all of the following are true:

- The implementation work for the active task is complete.
- Matching verification is complete, or any blocked verification is explicit.
- `task.md` is updated according to `docs/collaboration/rules/TASK.md`.
- No blocker, decision need, or critical unverified scope is hidden.

# Loop Close Output

End each task loop response with:

- Completed work.
- Verification evidence, following `AGENTS.md` Verification Minimums.
- `task.md` updates.
- Unverified scope.
- Blockers or decisions needed.
- Next action.
- Exit readiness: `ready`, `not ready`, or `blocked`.

User-facing loop output should be in Chinese unless the user asks otherwise.
