# 当前目标与约束

- 本轮目标：完成 I1 dogfood observability 修复后的最终 adversarial review，随后按用户要求先更新 handoff，再创建 checkpoint。
- 硬约束：中文回复；root `task.md` 已封版，不再更新；当前开发任务事实源是 `.ralph/TASKS.md`；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 不入仓。
- 用户已明确接受 O1：`.ralph/PROMPT.md` 对 `.spec/rules/tasks.md` 的路由问题等未来合并到 `agent-collab-kit` 再处理，本仓库不阻塞。

# 当前阶段与范围

- 阶段：I1 watch / run observability 收口，修复 review 中 M1/M2/O2/O3/O4，并完成 HUMAN-1 手工验证记录。
- 影响模块：`.ralph/lib/run.sh`、`.ralph/lib/watch.sh`、`.ralph/lib/adapter-claude.sh`、`tests/fixtures/mock-claude`、`scripts/integration-test.sh`、`.ralph/TASKS.md`、`.ralph/README.md`、`docs/architecture/*`、`docs/requirements/ralph-loop/requirements.md`。
- 变更类型：代码 + 测试 + 文档 + 任务事实源更新。

# 稳定决策

- `ralph run -v` live tail 必须有自动回归测试，覆盖 happy marker 和 provider error marker，避免 redirection 顺序问题再次静默。
- `run -v` tail 生命周期改为全局 `_RALPH_TAIL_PID` / `_RALPH_TAIL_FILTER_PID` / `_RALPH_TAIL_FIFO`，由 `_ralph_finish` 统一清理，覆盖 Ctrl-C / timeout / provider_failed / normal exit。
- `session.history.log` 是人类摘要视图：保留 user / assistant / thinking / tool_use 摘要 / tool_result；完整 tool input 仍以 `session.<provider>.jsonl` 作为复盘事实源。
- `watch` sticky bar 显示 `iteration_name`；Ctrl-C cleanup 对 sleep 发送 `INT`，避免 macOS bash 打印 killed sleep 噪声。
- REQ-025/REQ-026 已补 SC，且 SC-025-1 / SC-025-2 / SC-026-1 现在有集成测试证据；SC-025-3 仍按进程探针/手工验证处理。

# 已完成工作

- M1：`scripts/integration-test.sh` 新增 `ralph run -v` happy/error live tail 回归测试；mock Claude 输出 assistant/tool_result 等 stream-json events。
- M2：`.ralph/lib/run.sh` 加 `_ralph_stop_verbose_tail`，trap 路径通过 `_ralph_finish` 清理 live tail 相关进程；进程探针未发现残留 `tail -f provider.stdout.log`。
- O2：`docs/requirements/ralph-loop/requirements.md` 补 SC-025-* / SC-026-*，追踪矩阵更新为完整。
- O3：`.ralph/lib/adapter-claude.sh` 对长 tool_use input 做前段 + 尾段摘要，中间标注 truncation，完整内容保留在 `session.claude.jsonl`；mock fixture 和集成测试覆盖。
- O4：`.ralph/lib/watch.sh` sticky bar 加 `iter_name`，非 TTY watch fallback 测试覆盖 `iteration_name:` 字段。
- HUMAN-1：`.ralph/TASKS.md` 已勾选并记录 PTY 验证结论；真实 side-by-side 录屏未执行，使用临时 workspace / mock status / PTY 覆盖 UX 合约。
- 最终 adversarial review：未发现新的必须修复项；仅保留已接受 O1 和 SC-025-3 的手工/探针验证边界。

# 最新验证

- 命令：`bash -n scripts/integration-test.sh .ralph/lib/run.sh .ralph/lib/watch.sh .ralph/lib/adapter-claude.sh tests/fixtures/mock-claude`
- 结果：通过。
- 命令：`git diff --check`
- 结果：通过。
- 命令：`bash scripts/integration-test.sh`
- 结果：通过，`PASS=59 FAIL=0`。
- 命令：`bash scripts/check.sh`
- 结果：通过，`ralph-loop check passed`。
- 命令：`ps -axo pid=,command= | grep 'ralph/bin/ralph\|tail -f .*provider.stdout.log' | grep -v grep || true`
- 结果：无输出，未发现残留 ralph/tail 进程。

# 已验证与未验证

- 已验证：默认 run progress marker + stdout silent；`run -v` happy/error stream-json marker；Claude session capture + history truncation marker + native jsonl 完整 input；status plain text 本地时间格式；status `--json` 原始 ISO UTC；watch non-TTY fallback 含 `iteration_name`；完整集成测试与项目检查。
- 未验证：真实 Claude provider 的 side-by-side 录屏；真实长任务中 `-v` 最后一秒事件的人眼观感；SC-025-3 尚未转成自动化测试，当前靠进程探针和手工验证。

# Checkpoint 与 Postmortem 状态

- Checkpoint：按用户指定顺序，handoff 已先更新；checkpoint note 已创建为 `docs/checkpoints/2026-05-02-01-i1-observability-review-fixes.md`，待随本轮 coherent scope 一起提交。提交后以最新 git commit 为准。
- Postmortem：checkpoint sweep 命中既有 PM-0003（REQ traceability / 可观察链路缺少自动化证据），已更新 `docs/postmortems/pm-task-closure-req-traceability.md`；无需新增并行 PM。

# 工作区状态

- 分支：`main`
- 当前 dirty scope：13 个 tracked 文件修改 + 1 个 checkpoint note，集中在 `.ralph/` runtime code/docs、requirements/architecture 文档、集成测试、mock fixture、handoff、checkpoint 和 PM-0003。
- 最近提交：`6712934 fix: -v live tail redirection 顺序（>&2 必须在 2>/dev/null 之前）`、`4553070 docs: add .ralph/README.md (usage guide)`、`02b9c3c spec: tasks.md format rules + retrospective for kit sync (Q3)`。

# 建议下一步

- 立即按 checkpoint skill 创建 `docs/checkpoints/YYYY-MM-DD-NN-*.md`，做 postmortem sweep，stage 本轮 coherent scope 并提交。

# 交接摘要

- 本轮核心是把 I1 observability 的审查缺口闭环：`run -v` 有回归测试且 Ctrl-C cleanup 不漏 tail，history 摘要不吞完整复盘数据，watch/status 的新需求有 SC 和验证证据；当前可进入 checkpoint。
