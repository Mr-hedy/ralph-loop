# 目标与约束

- 保留 I4（T4 Gemini adapter）最终 adversarial-review、归档和 I5 待启动切换后的稳定状态。
- 本 checkpoint 覆盖 Gemini adapter 收口事实源、I4 归档、当前任务源切换、testing docs 更新、handoff 刷新和 postmortem 预防规则。
- 约束：`.ralph/TASKS.md` 是当前任务事实源；root `task.md` 已封版；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 和 provider 原始日志不入仓。

# 范围

- Runtime：`.ralph/lib/run.sh`
- 部署单元与任务源：`.ralph/README.md`、`.ralph/TASKS.md`
- 文档：`docs/README.md`、`docs/roadmap.md`、`docs/architecture/integrations.md`、`docs/architecture/testing.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/requirements/ralph-loop/I4-FINAL-TASK.md`
- 续接与流程：`handoff.md`、`docs/postmortems/pm-task-closure-req-traceability.md`

# 核心变更

- I4 已归档到 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`；`.ralph/TASKS.md` 已清为 I5 待启动状态，当前任务列表为空，等待用户排序 T7 或新议题。
- 修复最终 review 发现的事实源漂移：roadmap 不再写 I4“实施中”，docs/README 不再把当前 design 指向 I4，requirements/integrations/README 不再把 Gemini native session 描述成 `.jsonl`。
- 修复 `ralph run -v` Gemini result marker 小问题：`_ralph_filter_verbose` 先匹配 Gemini `result.text`，再匹配 Claude `result` 分支。
- testing docs 和 I4 归档同步最新验证结果：`bash scripts/integration-test.sh` 为 PASS=100 FAIL=0。
- `handoff.md` 已刷新为 I4 closeout / I5 pending 的续接状态。
- PM-0003 追加“用户要求后台执行但 Ralph run 被前台启动”的失败模式和预防规则。

# 影响文件或模块

- `.ralph/lib/run.sh`：Gemini `result.text` verbose filter 分支。
- `.ralph/TASKS.md`：当前迭代切到 I5，保留 I4 完成结论和未验证风险。
- `docs/requirements/ralph-loop/I4-FINAL-TASK.md`：I4 final task 归档，更新最终验证为 PASS=100 FAIL=0。
- `docs/architecture/integrations.md` / `docs/requirements/ralph-loop/requirements.md` / `.ralph/README.md`：Gemini session 文件扩展名与 history marker 契约同步。
- `docs/architecture/testing.md`：当前覆盖范围更新为 I4 后实际 100 PASS。
- `docs/postmortems/pm-task-closure-req-traceability.md`：新增后台执行控制面预防规则。
- `handoff.md`：下一轮恢复上下文。

# 稳定决策

- 当前 provider surface 是 `claude|codex|gemini|fake`。
- Gemini adapter 命令契约保持：`gemini -p <prompt> --approval-mode=yolo --output-format stream-json`；`--model` 有值才传；`--effort` 暂不传。
- Gemini native session 文件名是 `session.gemini.json`；跨 provider 人话视图是 `session.history.log`，Gemini history 从 `provider.stdout.log` 派生。
- I5 进入前不再继续执行 I4 任务列表；下一轮必须先写入新的 `.ralph/TASKS.md` 任务。
- 后续用户要求后台 Ralph run 时，启动策略本身是硬约束：必须使用后台 wrapper 并回报 log/pid 路径。

# 验证结果

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash -n .ralph/lib/run.sh .ralph/lib/adapter-gemini.sh tests/fixtures/mock-gemini scripts/integration-test.sh`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`printf '%s\n' '{"type":"result","text":"Gemini finished"}' | bash -c 'source .ralph/lib/run.sh; _ralph_filter_verbose'`
- 结果：通过
- 诊断：输出 `✓ result Gemini finished`。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=100 FAIL=0`。

- 命令：`rg` 收口检查旧事实残留
- 结果：通过
- 诊断：未发现 I4“实施中”、Gemini `.jsonl`、`97 PASS / 3 FAIL` 等当前事实源漂移；历史 checkpoint/归档的旧 PASS 数只作为历史记录保留。

# Postmortem Sweep

- 结果：已更新
- 关联：`docs/postmortems/pm-task-closure-req-traceability.md`
- 说明：本轮命中一个可复用 agent 行为问题：用户明确要求后台执行 Ralph run，但 agent 以前台工具会话启动。已在 PM-0003 增加触发条件、失败模式和预防规则；后续长任务启动前必须确认后台/前台策略并回报 log/pid 观察面。

# 未验证范围与风险

- 真实 Gemini error event schema 未验证；QA-2 两次真实 smoke 都成功，未触发真实错误事件。
- 真实 `ralph run -v --provider gemini` 未单独重跑；mock `run -v` 和真实 non-verbose Gemini smoke 已覆盖主路径。
- 后台 wrapper 行为尚未实现为项目内命令或脚本；当前只是 PM 级预防规则。下一次实际后台跑 Ralph 时必须按 PM-0003 人工执行。

# 下一步

- 用户确认 I5 主题：T7 Skill 封装，或新的 bugfix / provider / 文档议题。
- 写入新的 `.ralph/TASKS.md` I5 任务列表后，再按 Ralph loop 执行。
- 若下一轮使用 Ralph 跑长任务，按后台执行规则启动并记录 log/pid 路径。
