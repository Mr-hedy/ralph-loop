# Foreground execution

Read this file only when foreground mode is selected. [SKILL.md](../SKILL.md) defines authorization, launch identity, stopping conditions, and review standards.

## Launch and remain engaged

- Start Ralph with a resumable native command handle. For a full work package, the Main Agent stays active through execution, necessary repairs, and review. For startup-only or otherwise limited requests, honor the narrower authorization defined in the entrypoint. A host call returning a handle means execution can be inspected again; it does not mean delivery has switched to background mode.
- After startup checks, alternate bounded waits with inspecting new events and actual artifacts. Choose waiting intervals according to activity and the next critical checkpoint. Compressing output must not reduce inspection coverage or delay checks. Back off only while state is unchanged and no relevant unread events remain; resume normal checks when activity resumes. Do not busy-poll or block so long that you cannot respond to the user.
- Progress updates should focus on new findings, current uncertainty, and the next checkpoint; do not narrate every log entry. When the user asks for status or adds conditions during execution, respond briefly and continue the existing task. Handle explicit pause/stop requests as directed.

## Incremental monitoring

Apply the shared [bounded inspection output](../SKILL.md#bounded-inspection-output) rules on every monitoring call.

- Retain the run_id, round/log identity, last complete byte offset (or the provider's native cursor), and the last surfaced version of each relevant event. Keep this compact state in the active session; if persistence is needed, use a run-owned evidence location, never Ralph control files or secrets. The original log remains the evidence source.
- Read only appended complete records. Carry an unfinished JSONL/UTF-8 tail to the next read; do not advance past it or report an incomplete record as a provider failure. If a file is replaced, truncated, or a new round starts, establish a cursor for that file identity and avoid replaying previously accounted-for history.
- De-duplicate by run/round plus tool-call ID or step index **and state/result version**. Suppress identical repeats, but surface a running-to-completed/failed transition and a materially changed result from the same call. Correlate tool results with their action; a result's different JSON envelope is not a new tool invocation.
- Process new events locally and collapse repetitive progress. Use the shared reference budgets for concise summaries, expanding the relevant event or log range when a decision needs more evidence. Keep a coherent error or action sequence together rather than splitting it to meet a character target. Retain the position of relevant events deferred from the summary and disclose the remaining coverage. Review deferred critical events before the next checkpoint or any all-clear/completion claim; disclose any unresolved coverage gap. Do not jump to the end of the file or repeatedly return its last few events as a substitute for incremental coverage.
- A native foreground poll may collect a large TUI redraw. Consume it locally and emit only exit/session metadata or the bounded event summary. Use bounded waits and back off when unchanged; do not add rapid polling or a separate execution loop just to watch a quiet run.
- After a lost cursor or conversation recovery, first verify the same run and handle, then use one bounded recent window to re-establish position. State any unobserved interval; inspect it selectively when needed for a decision or acceptance, rather than automatically loading the full transcript.

## What to observe and when to intervene

Prioritize points where actual results affect later decisions: the first real integration, migration or persistence boundaries, budget checks before external calls, critical tests, and claims that tasks are complete. Source code that is still changing provides leads only. Inspect stable artifacts or pause before confirming a finding; do not declare a defect from a transient inconsistency. Monitoring observes actions; it is not a guaranteed pre-execution barrier. If a known action must wait for review, encode that checkpoint in the task before launch rather than relying on polling to intercept it.

Intervene when concrete evidence shows:

- The implementation deviates from the confirmed objective, hard constraints, or critical contracts.
- New facts invalidate a task's technical assumptions, and continuing would increase rework.
- Tests do not exercise the target behavior, assertions may pass incorrectly, or cleanup will destroy essential original evidence.
- Authorized resources or call budgets are about to be incorrectly reset or exceeded, or there is a concrete data or permission risk.

A normal failing test, an implementation error still under investigation, temporarily quiet logs, or a style difference alone does not justify pausing. Let Ralph complete its normal checks and repairs; do not turn every output line into a new instruction.

## Pause, revise, and continue

1. Briefly explain the finding and impact to the user. Proceed when the action is already authorized; wait for the user only when a decision changes the objective, critical contracts, permissions, or budget.
2. Follow the entrypoint's stopping rules to confirm that the old run and its writers have exited, then inspect that run's terminal state and uncommitted changes. Preserve failure evidence; do not roll back or discard partial work merely to revise the task breakdown.
3. Record the verifiable finding and rationale in the sole task source. Refine later tasks or add repair tasks under the project's rules, with explicit scope and acceptance checks for each. Update related source-of-truth documents when necessary; do not leave corrections only in logs or chat.
4. Check remaining authorization, existing progress, and the validated version before rerunning with the original configuration. Associate the new handle/run_id with the previous interruption reason. Do not repeat an entire paid acceptance suite for which sufficient evidence already exists.

When a run ends, first verify its exit reason and completed scope. If implementation is incomplete, use the available evidence to decide whether work can continue under the original authorization; do not bypass a user pause, authorization limits, or a human-decision blocker. When implementation is complete and review is authorized, perform the independent review defined in the entrypoint. Add repairs only for real defects, and finish once verification passes and no blocking issues remain open. Stop blind restarts when the same failure recurs without new diagnostic evidence. Report the specific blocker instead of substituting an endless loop for judgment.

## Acceptance evidence

Key conclusions must match actual behavior and final artifacts: for example, public responses and persisted state, actual tool termination and session release, or generated files and expected content. Ralph's summary alone is insufficient. Check existing evidence for the same version before running necessary supplemental validation. Any additional external calls remain subject to existing authorization and cumulative budgets.

By default, report high-signal findings in the conversation and update existing sources of truth. A run ending does not automatically trigger new review reports, checkpoints, archival, or commits.
