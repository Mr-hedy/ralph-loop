---
name: ralph
description: Use when the user explicitly asks to run or inspect Ralph, execute the project task list through Ralph, continue a Ralph run, monitor Ralph status/watch output, or diagnose a Ralph CLI run. Do not use for requirements discussion, solution design, task decomposition, handoff, checkpoint, or postmortem actions unless Ralph is the tool being operated.
---

# Ralph

Use the Ralph CLI shipped in the workspace. Ralph owns loading its prompt,
task source, provider adapter, run state, and artifacts; this skill should say
how to operate Ralph, not reimplement Ralph's task loop.

# Commands

Run from the workspace root:

```bash
./.ralph/bin/ralph run
```

If no provider is configured in `.ralph/.env`, pass one explicitly:

```bash
./.ralph/bin/ralph run --provider claude
./.ralph/bin/ralph run --provider codex
./.ralph/bin/ralph run --provider antigravity
```

Useful controls:

- `--max-round <n>`: cap rounds per task.
- `--round-timeout <sec>`: cap a provider oneshot.
- `--stall-limit <n>`: stop after repeated no-progress rounds.
- `--verbose` / `-v`: show live provider events when attached to a TTY.

# Background execution

The host is the workbench running the Main Agent. The provider is the CLI
Ralph invokes for oneshots. Choose background task management by the host's
capabilities, independently of `--provider`.

When the user asks Ralph to execute prepared tasks, use background execution
by default unless they explicitly request foreground execution:

1. Use the host's native managed background command facility. It must expose
   a running-task indicator and a handle for inspecting command output and
   completion. Do not substitute `nohup`, `disown`, or an unmanaged `&` launch
   that loses the host's task tracking. If the capability is unavailable or
   unknown, explain the limitation and let the user choose foreground or
   manual execution before launching.
   Record the existing Ralph run state before launching the command.
2. Perform a bounded startup check. Confirm the managed command is still
   running and correlate it with Ralph's current `run_id` and workspace.
   Stale status alone is insufficient. Keep the command, workspace, native
   handle and `run_id` in the conversation, and in handoff material if a
   handoff occurs. Report what actually started and how to inspect it.
   If startup failed or the command already finished, report that outcome.
   If correlation remains uncertain, report the uncertainty and retain the
   handle; do not declare startup successful or launch another run.
3. Return control to the user after startup checking. Do not keep the Main
   Agent turn active by repeatedly polling, waiting for the whole run, or
   running `watch`. The user may discuss other work; the same checkout still
   has only one business-file writer while Ralph is running.
4. Use native completion notifications when the host provides them. When
   the completion result reaches the Main Agent, read that run's
   `.ralph/runs/<run_id>/result.json` and terminal summary, and report the
   outcome using the Evidence rules below. Do not substitute a newer run's
   status; if terminal evidence is missing, report it as unconfirmed. If the
   host cannot resume the Main Agent on completion, explain at startup that
   the user must request status or inspect it manually. Do not add scheduled
   checks, a hook wakeup workaround, or an external relay to fill that gap
   without a separate user request.

A missing running indicator or lost handle does not prove completion. Check
the existing run when asked; do not automatically restart it. Completion
reporting does not trigger acceptance, checkpoint, handoff, or postmortem.

# Observe

Use these instead of starting a second run:

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph status --json
./.ralph/bin/ralph watch
./.ralph/bin/ralph watch --details
```

`watch` exits with `Ctrl+C` without stopping the active run. If Ralph reports
`locked`, inspect the existing run with `status` or `watch`.
Use `watch --details` for scrolling AI messages, tool operations and results.
It replays the current round first; on a TTY it follows until the run finishes,
while a pipe receives one current-round snapshot. Thinking is visible only
when the provider includes it in live events.

# Evidence

After a run, report only decisive facts:

- command run and exit code;
- `run_id`, `exit_reason`, and task progress from Ralph status/result files;
- key error type or blocker, if any;
- artifact path only when useful, such as `.ralph/runs/<run_id>/exit-message.txt`.

Do not treat provider stdout, provider session text, or exit code alone as task
completion evidence. Use Ralph's run summary and task state.

# Boundaries

- Treat `.ralph/PROMPT.md`, `bin/` and `lib/` as versioned tool controls.
  Ordinary project work must not rewrite them to pass user constraints to
  oneshots. Put durable rules in project `AGENTS.md` and work-package constraints
  in `.ralph/TASKS.md` and its referenced requirements/solution.
- Follow the user's staging/commit/push authorization. A no-commit instruction
  does not require changing the execution protocol.
- If startup rejects the protocol or a run reports `protocol_changed`, report
  the mismatch and preserve the worktree. Do not automatically restore files
  or restart. Tool maintenance/upgrades require explicit authorization, a
  stopped run and a matching version package.
- Do not manually execute the task loop when the user asked to run Ralph.
- Do not create another task source.
- Do not edit Ralph's task source unless the user explicitly asks for task
  editing rather than running Ralph.
- Do not run checkpoint, handoff, or postmortem workflows just because a Ralph
  run completed.
