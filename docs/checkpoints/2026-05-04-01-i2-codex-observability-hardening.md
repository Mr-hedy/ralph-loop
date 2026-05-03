# 目标与约束

- 保留 I2 Codex adapter、用户可见 observability、timeout process cleanup 已收敛的稳定状态，作为后续 I2 归档或继续 review 前的 rollback anchor。
- 本 checkpoint 覆盖 I2 DEV-8 ~ DEV-12 以及前序 Codex real smoke 复验，不把 `.ralph/runs/`、provider 原始运行目录、secrets 或本机 auth/config 纳入仓库。
- 约束：当前任务事实源保持 `.ralph/TASKS.md`；root `task.md` 已封版；真实长 provider timeout 不作为本 checkpoint 阻塞项。

# 范围

- Runtime：`.ralph/lib/run.sh`、`.ralph/lib/adapter-fake.sh`、`.ralph/bin/ralph`
- Provider fixture：`tests/fixtures/mock-codex`
- 测试：`scripts/integration-test.sh`
- 文档与任务源：`.ralph/README.md`、`.ralph/TASKS.md`、`README.md`、`docs/README.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/{overview,security,testing}.md`
- 续接与流程：`handoff.md`、`docs/postmortems/pm-task-closure-req-traceability.md`

# 核心变更

- Codex 使用入口和证据契约收敛：README、`.ralph/README.md`、requirements、testing/security/overview docs 均指向 `provider.stdout.log`、`session.codex.jsonl`、`session.history.log`，并说明 `RALPH_PROVIDER=codex` 与 `RALPH_PROVIDER_CONFIG_DIR` → `CODEX_HOME`。
- Codex history 派生和真实 smoke 闭环：`session.history.log` 从真实 `codex exec --json` event stream 派生；复验 run `20260503-145326-3085d11` 自然结束 `exit_reason=done`，iter 4 文件齐全且 history 非空。
- Codex `run -v` live tail 支持真实事件类型：`thread.started`、`agent_message`、`command_execution`、`turn.completed`、`turn.failed`、`error`。
- 默认 provider heartbeat：无 `-v` 的长 oneshot 每 `RALPH_PROGRESS_HEARTBEAT_SEC` 秒输出 still-running marker、elapsed、log bytes/lines 与 `tail -f provider.stdout.log` 路径。
- `watch -v` active iter 定位修复：run loop 在 provider 前更新 `status.json.iteration` 指向当前 iter，避免第一轮盯 `iter-000` 或上一轮。
- timeout process tree cleanup：timeout 时终止 provider oneshot 进程树；fake `slow_child` fixture 断言外部 child pid 被清理。
- 动态追加任务总数修复：run/status/meta/result/summary 在任务被 provider 追加后重新读取 total，避免 `tasks_checked > tasks_total`。
- 测试补强：Codex effort/model 断言改为检查 mock 实收参数；error-event fallback fixture 不再混入 `turn.failed`；新增 heartbeat、watch active iter、timeout child process、watch help、Codex run-v、dynamic task totals 回归。

# 影响文件或模块

- `.ralph/lib/run.sh`：heartbeat、process tree cleanup、active iter status update、dynamic task totals、Codex verbose filter。
- `.ralph/lib/adapter-fake.sh`：`append_task_once`、`slow_child` 等回归 fixture 场景。
- `.ralph/bin/ralph`：run/watch help 对齐实际行为，provider list 与 exit reasons 更新。
- `scripts/integration-test.sh`：当前 PASS 总数 83，覆盖本轮新增回归。
- `tests/fixtures/mock-codex`：真实命令参数回显、Codex event stream fixture 和 error fallback 修正。
- README/docs/requirements/testing/security/overview：Codex 使用入口、timeout 语义、watch-v 行为和 evidence artifact 文案同步。
- `.ralph/TASKS.md`：DEV-8 ~ DEV-12 完成证据与未验证边界。
- `docs/postmortems/pm-task-closure-req-traceability.md`：记录 2026-05-04 再次命中 PM-0003。

# 稳定决策

- 不需要为了 checkpoint 重跑真实 Claude/Codex timeout 长任务：timeout 风险位于 Ralph 的 shell process tree cleanup，fake external child fixture 已覆盖同一关键机制。
- `ralph watch` 默认只显示 sticky bar；只有 `watch -v` 才 tail 当前 iter 的 `provider.stdout.log`。
- 默认 heartbeat 属于 `ralph run` 无 `-v` 的用户反馈机制，不替代 `run -v` live event tail。
- Codex adapter 当前支持 Claude/fake/Codex 三 provider；Gemini 仍是 T4 计划项，不在 I2 范围。

# 验证结果

- 命令：`bash -n .ralph/lib/run.sh .ralph/lib/adapter-fake.sh .ralph/bin/ralph scripts/integration-test.sh tests/fixtures/mock-codex`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`RALPH_FAKE_SCENARIO=slow_child RALPH_FAKE_SLEEP=30 bash <temp>/.ralph/bin/ralph run --provider fake --timeout 2`
- 结果：通过
- 诊断：`exit_reason=timeout`，返回码 3，fixture 记录的 child pid 已退出。

- 命令：`bash .ralph/bin/ralph watch --help`
- 结果：通过
- 诊断：help 中包含 `--verbose, -v` 和 `provider.stdout.log`。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=83 FAIL=0`。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

# Postmortem Sweep

- 结果：已更新既有条目
- 关联：`docs/postmortems/pm-task-closure-req-traceability.md`
- 说明：本轮没有新增失败类型，但 PM-0003 再次命中。用户反馈“无输出/卡住”时，排查先修了相邻路径，最后才精确定位到实际观察面 `ralph watch -v`；timeout 也暴露出 fake 测试未建模外部 child pid 的缺口。本轮已补 PM-0003 的 trigger/failure/prevention，并落地 watch active iter 与 timeout child process 自动化回归。

# 未验证范围与风险

- 未重跑真实 Claude 长任务 + `ralph watch -v` 视觉观察；自动化已覆盖导致空白的 status/log 定位路径。
- 未重跑真实 Claude/Codex timeout 手工进程树验证；fake `slow_child` 使用真实外部 child pid 覆盖 Ralph timeout cleanup 的关键机制。
- 未执行 I2 归档动作；当前 `.ralph/TASKS.md` 仍保留 I2 完整任务与证据，适合下一步 final review 或归档。

# 下一步

- 先完成本 checkpoint commit，再刷新 `handoff.md` 写入 checkpoint commit id。
- 若继续 I2，优先做最终 adversarial review；若无新问题，再按 iteration 归档约定生成 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`，清空 `.ralph/TASKS.md` 当前任务段并更新 roadmap。
