# Background execution

Read this file only when background mode is selected. [SKILL.md](../SKILL.md) defines authorization, launch identity, stopping conditions, and review standards.

## Managed execution and startup checks

- Use the host's native managed background-task capability. It must provide a visible running state and handles for reading output, stopping execution, and confirming completion. Host capability is independent of provider selection.
- Do not substitute `nohup`, `disown`, or an unmanaged `&`. If the capability is unavailable or cannot be confirmed, explain the specific limitation before launch and let the user choose foreground or manual execution. Do not silently switch to foreground or claim that a background task has started without evidence.
- Complete the bounded startup check defined in the entrypoint and record the mode, handle, run_id, and workspace. If startup has already ended, check the result directly. If execution is still active, explain how to inspect and stop it.

Return control after startup checks. Do not continuously poll, watch, or wait for the full run in the same turn. Explain that this mode relies on Ralph's own checks and Main Agent review after completion; it does not provide continuous Main Agent supervision while running.

## Boundaries during execution

Ralph implements, checks its work, and handles normal problems under the project's task protocol. While it is running in the background, the Main Agent must not concurrently edit tasks, specifications, or code, or start another build that affects its artifacts.

When the user returns with a question, inspect the existing execution through its original handle and run_id first. A request to check progress does not itself authorize task edits, a restart, or a mode switch. If the user requests task adjustments, or an observed boundary violation requires immediate protective action, follow the entrypoint's rules to stop and confirm termination before proceeding. Background mode does not override a user's stop instruction.

If new circumstances require ongoing judgment, explain the evidence and recommend foreground. Do not change a user-selected background mode without consent. Background execution does not guarantee early detection of acceptance gaps that Ralph itself has not identified.

## Completion notifications and independent review

- If the host supports native completion notifications that can resume the Main Agent, use that mechanism for follow-up.
- If automatic resumption is unavailable, explain at startup that the user must return to request a check. Acceptance review remains pending until the next opportunity to execute. Do not promise a proactive notification or add scheduled tasks, heartbeats, or external message relays on your own.
- On notification or the user's return, verify the original handle's exit status, the same run's `result.json`, and its terminal summary. Distinguish implementation completion, provider failure, a human-decision blocker, and deliberate interruption. Another run's success cannot replace an unknown result for this run.
- With full work-package authorization, the Main Agent then performs independent review under the entrypoint's standards. For real defects, record necessary repairs after the previous execution has stopped. Already-authorized repairs may continue as managed background work, returning control again. Resolve any required mode-change or scope-expansion decision first.
- If authorization covers only startup or status, or the user explicitly defers review, report execution facts and state that acceptance review has not been performed. A completion notification does not expand scope. Progress questions during a full workflow preserve the original objective.

Report the work package complete only after independent acceptance review has been performed and blocking issues are closed. A `done` result alone means execution has ended.
