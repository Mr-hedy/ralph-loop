---
name: ralph
description: Coordinate authorized Ralph task execution, recovery, and independent review. Default to foreground supervision with evidence-based task adjustments; support managed background execution when explicitly requested or supported by a proven execution and validation path. Also use for Ralph status and diagnostics, without treating inspection as permission to start or change work. Exclude standalone requirements discussion and planning without Ralph execution.
---

# Ralph

Use the Ralph CLI provided by the current project. Ralph handles implementation, testing, and oneshot scheduling; the Main Agent maintains requirements and tasks, manages execution, and performs independent review. This skill defines the collaboration workflow; it does not rewrite Ralph's control program.

## Identify the request first

- **Execute or continue a work package**: By default, this includes execution, necessary task adjustments, independent review, and defect repairs within the current authorization. If the user asks only to start a run, limits the number of rounds, or excludes review, honor that narrower scope.
- **Status or diagnostics only**: Read the existing run and evidence. This request alone does not authorize starting or restarting a run, changing tasks, or declaring product acceptance.
- Progress questions or additional conditions during execution preserve the original objective; they do not automatically revoke existing authorization for the full workflow. Honor an explicit pause, stop, or reduction in scope. Do not treat a user-requested pause as an ordinary interruption to resume automatically.
- The objective, success criteria, and permission boundaries must be clear; later implementation choices may be refined as evidence emerges. Each task about to be handed to Ralph must still be executable and verifiable. Resolve missing critical product decisions first rather than handing guesses to the loop.
- Loading this skill does not grant execution authorization. Do not repeatedly seek confirmation for repairs already authorized within scope. New objectives, changes to critical contracts, or additional permissions or budget remain user decisions. Execution or review does not automatically authorize commits, pushes, deployments, archival, or new scheduled tasks.

## Select a mode and read it on demand

1. The user's explicit mode choice and currently applicable constraints take precedence.
2. Otherwise, default to **foreground**. Use foreground for new feature work packages, unproven implementation paths, acceptance that requires ongoing judgment, and tasks whose suitability for background execution is uncertain. A complete task breakdown, a small diff, or existing tests alone does not establish suitability for background execution.
3. Choose background on your own only when the execution path has been validated, scope is fixed, results can be reliably checked, and ongoing independent judgment is unnecessary; briefly explain the evidence. An explicit user request is also sufficient to select background, while making clear that it does not provide continuous Main Agent supervision.
4. State the mode and reason before launch; do not switch silently during execution. If the user explicitly chose background and ongoing intervention becomes necessary, recommend foreground and wait for the mode-change decision. This does not prevent necessary protective action already authorized by the user.

Read only the selected mode's workflow:

- [Foreground: continuous observation and evidence-based task adjustments](references/foreground.md)
- [Background: managed execution and independent review after completion](references/background.md)

Foreground and background describe how the Main Agent manages and participates in execution. They do not select a provider or introduce new Ralph CLI flags. Ordinary status requests do not require loading both mode references.

## Launch and run identity

Read the applicable project entrypoint, the sole task source, and relevant specifications. Verify the explicit working directory, branch, Git status, and existing runs. Preserve user changes; do not create or switch worktrees merely because the default directory differs. Follow the project's task rules when adjusting tasks.

Use the command specified by the user and project. If neither provides a more specific command, run this explicitly in the verified workspace:

```bash
./.ralph/bin/ralph run --verbose
```

Keep the configured provider/model/effort. Do not override the provider because the host is Codex, or read or print the entire `.env`. If no provider is configured and no choice has been established, clarify rather than selecting another provider yourself. Business-model call budgets are separate from Ralph's implementation provider. Preserve cumulative consumption across processes and restarts; conservatively count requests whose dispatch is uncertain against the budget, and stop new calls when the remaining budget is unknown or insufficient.

Use the host's native execution facility and retain a command handle that supports inspection and stopping. Perform a bounded startup check, correlating the handle with the actual workspace, `run_id`, and launch command. If the command exits immediately, check its terminal result directly. A stale status.json does not prove that this launch succeeded.

Record the mode, worktree/branch, handle, run_id, and next checkpoint. Preserve exact identifiers in context handoffs. A lost handle, an interrupted conversation, or temporarily quiet logs does not prove that Ralph has stopped. On resumption, verify the existing process and run state first. If the run is `locked`, do not start another instance or remove the lock on your own.

## Shared boundaries for task adjustments and recovery

- Keep one task source and one implementation writer. While Ralph is running, the Main Agent observes read-only: do not concurrently edit tasks, specifications, or code, or start builds that modify the same artifacts. Let Ralph handle normal implementation problems through its own checks.
- Before adjusting tasks, gracefully stop that run through its native handle. If necessary, send an interrupt signal only to the launcher process confirmed to belong to that workspace/run. Confirm that Ralph, the provider, and related writing processes have exited and the lock has been released before editing tasks. Stopping watch or losing a handle does not stop the run. If termination is uncertain, diagnose first and preserve the current state.
- Record the concrete finding, evidence, impact, and revised acceptance checks in the original task source. Within authorization, refine unfinished tasks, fill omissions, or append repair tasks while following the project's history-preservation rules. Do not rewrite completed-task history or mark work complete without evidence. Ralph still implements code and test repairs.
- Before restarting, check partial changes, completed tasks, evidence, budget, and the previous exit reason. Preserve progress and counters. Do not blindly rerun the entire acceptance suite or use restarts to bypass user-specified round, time, or call limits. Diagnose environment or provider failures without weakening the product contract.
- When the same failure recurs without new evidence, or budget, permissions, or critical decisions are missing, stop blind retries and explain the cause and the smallest outstanding decision. Preserve the current state on `protocol_changed` or a control-protocol mismatch; do not automatically repair tool files.

## Independent review and completion

For a full work package, the default workflow includes Main Agent review after execution. Compare requirements and success criteria against the actual diff, code, the conditions exercised by tests, persisted state or generated artifacts, and necessary end-to-end behavior. Ralph's `[x]`, `done`, and test exit codes prove only their respective scope; they do not replace independent acceptance. Apply the project's adversarial-review rules to high-impact boundaries. When the user requests an overall adversarial-review, cover the entire authorized work package.

For a real defect, explain the evidence, update the task source under the boundaries above, and continue Ralph repairs and review within the original authorization and selected mode. Do not repeatedly seek permission for the same scope. Do not turn style preferences, future capabilities, or repeated tests into new acceptance gates; reuse evidence for an unchanged, already-validated version. If authorization covers only startup or status, or the user explicitly defers review, report the actual execution state and state that acceptance review has not been performed; do not expand the workflow.

Report these separately:

- **Execution result**: Native exit code, `result.json`/terminal summary for the same `run_id`, and task progress. Mark missing evidence as unconfirmed; do not substitute another run's result.
- **Acceptance result**: Specific grounds for passing, requiring changes, or being blocked; behavior actually verified, unverified scope, and remaining budget. Do not declare completion while blocking issues remain open.

## Inspection and tool boundaries

```bash
./.ralph/bin/ralph status --json
./.ralph/bin/ralph watch --details
```

`watch` is an observation interface; Ctrl+C only exits observation. Read tool steps, errors, and validation output as needed. Do not replay entire provider logs, reasoning text, full process arguments, or credentials.

`.ralph/PROMPT.md`, `.ralph/bin/`, and `.ralph/lib/` are versioned control files. This skill does not authorize modifying them or `.env`. Tool upgrades require separate explicit authorization and a stopped run. Put stable project conventions in the project entrypoint, and work-package constraints in the sole task source and its source-of-truth documents. Do not create another execution loop or parallel task board.
