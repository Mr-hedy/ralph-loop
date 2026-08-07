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
./.ralph/bin/ralph run --provider gemini
```

Useful controls:

- `--max-round <n>`: cap rounds per task.
- `--round-timeout <sec>`: cap a provider oneshot.
- `--stall-limit <n>`: stop after repeated no-progress rounds.
- `--verbose` / `-v`: show live provider events when attached to a TTY.

# Observe

Use these instead of starting a second run:

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph status --json
./.ralph/bin/ralph watch
```

`watch` exits with `Ctrl+C` without stopping the active run. If Ralph reports
`locked`, inspect the existing run with `status` or `watch`.

# Evidence

After a run, report only decisive facts:

- command run and exit code;
- `run_id`, `exit_reason`, and task progress from Ralph status/result files;
- key error type or blocker, if any;
- artifact path only when useful, such as `.ralph/runs/<run_id>/exit-message.txt`.

Do not treat provider stdout, provider session text, or exit code alone as task
completion evidence. Use Ralph's run summary and task state.

# Boundaries

- Do not manually execute the task loop when the user asked to run Ralph.
- Do not create another task source.
- Do not edit Ralph's task source unless the user explicitly asks for task
  editing rather than running Ralph.
- Do not run checkpoint, handoff, or postmortem workflows just because a Ralph
  run completed.
