---
name: task-loop
description: Use when the user explicitly asks to start or continue executing the current project task list, run a task loop, execute .ralph/TASKS.md, or work through todo items until blocked or complete. Do not use for requirements discussion, solution design, task decomposition, status-only requests, handoff, or checkpoint actions.
---

# Task Loop Skill

This is an action skill. Use it only after the user explicitly enters the
execution phase for the current task list.

# Purpose

- Drive the active `.ralph/TASKS.md` tasks forward without creating a second task
  system.
- Keep implementation, verification, and task-state updates in the same loop.
- Continue while the next action is clear and in scope; pause when a user
  decision, blocker, or no-progress condition appears.

# Inputs

Read:

- `AGENTS.md`
- `.ralph/TASKS.md`
- `.ralph/PROMPT.md` when the task prefix or HUMAN/REVIEW behavior matters
- nearby project docs named by the active task

Do not read `handoff.md` by default. It is continuation state, not a task
source. Read it only when the user explicitly asks to resume from handoff or
clearly asks to continue a previous task-loop session.

Do not create `fix_plan.md` or any parallel task source. Do not initialize a
new `.ralph/` unless the active task explicitly asks for deployment or
scaffolding.
Do not use root `task.md` as the active task source unless the user explicitly
asks for v0.1 historical task context.

# Scope

- Default scope: advance the first unchecked top-level task in `.ralph/TASKS.md`.
- If the user names a task, advance that task.
- If the user asks to execute the whole todo list, work from top
  to bottom and run the exit gate after each task.
- Do not change `.ralph/TASKS.md` structure beyond task-state updates and
  task-local notes that match the existing file style.
- Do not use the loop to compensate for oversized tasks. If a task needs
  decomposition before it can be executed safely, pause and ask to split it.

# Loop

For each loop slice:

1. Select the active task and state the loop goal internally.
2. Execute only work needed for that task and slice.
3. Run verification that matches the change.
4. Update `.ralph/TASKS.md` only when task state changes:
   - Mark `[x]` only after implementation and matching verification are done.
   - Add concise completion, verification, and unverified-scope notes when the
     existing task format supports them.
   - Leave the task unchecked and add `阻塞` or `需要决策` when blocked.
   - Do not record per-loop running notes or failed attempts in `.ralph/TASKS.md`.
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
- The task would require changing `.ralph/TASKS.md` structure or creating another task
  source.

# Exit Gate

A task is ready only when all of the following are true:

- The implementation work for the active task is complete.
- Matching verification is complete, or any blocked verification is explicit.
- If the task changes provider adapters, sandbox/approval/trust behavior, or a
  release gate, real provider smoke status is explicit: passed, failed, blocked
  by local auth, or not run with reason.
- `.ralph/TASKS.md` is updated according to the active task format.
- No blocker, decision need, or critical unverified scope is hidden.

# Loop Close Output

End each task loop response with:

- Completed work.
- Verification evidence, following `AGENTS.md` Verification Minimums.
- `.ralph/TASKS.md` updates.
- Unverified scope.
- Blockers or decisions needed.
- Next action.
- Exit readiness: `ready`, `not ready`, or `blocked`.

User-facing loop output should be in Chinese unless the user asks otherwise.
