# 目标与约束

- 保留 I1 watch / run observability 在 adversarial review 后闭环的稳定状态，作为后续归档或继续 dogfood 前的 rollback anchor。
- 本 checkpoint 覆盖 M1/M2/O2/O3/O4 和 HUMAN-1 的修复/验证，不处理用户已接受后置到 `agent-collab-kit` 的 O1。
- 约束：`.ralph/` runtime artifacts 不入仓；root `task.md` 仍封版；当前任务事实源保持 `.ralph/TASKS.md`。

# 范围

- Runtime：`.ralph/lib/run.sh`、`.ralph/lib/watch.sh`、`.ralph/lib/adapter-claude.sh`
- 测试：`scripts/integration-test.sh`、`tests/fixtures/mock-claude`
- 文档与事实源：`.ralph/README.md`、`.ralph/TASKS.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/{overview,integrations,testing}.md`
- 续接与流程：`handoff.md`、`docs/postmortems/pm-task-closure-req-traceability.md`

# 核心变更

- `ralph run -v` live tail 增加 happy/error 两条 stream-json marker 回归测试，防止 redirection 顺序导致 stderr 全静默的回归再次漏检。
- `run -v` tail 生命周期改为全局状态 + `_ralph_stop_verbose_tail`，由 `_ralph_finish` 覆盖 normal / provider_failed / timeout / interrupted 清理路径。
- Claude `session.history.log` 对长 tool_use input 做摘要，保留开头和尾部，并明确指向 `session.claude.jsonl` 作为完整复盘事实源。
- `watch` sticky bar 显示 `iteration_name`；Ctrl-C cleanup 改为对 sleep 发送 `INT`，避免 macOS bash 打印 killed sleep 噪声。
- REQ-025/REQ-026 补 SC 和追踪矩阵；默认 run progress marker、status 本地时间格式、`run -v` marker、history truncation 均有集成测试证据。
- HUMAN-1 已由 main agent 在普通对话内完成并勾选，任务条目记录 PTY 验证结论和未做真实 side-by-side 录屏的边界。

# 影响文件或模块

- `.ralph/lib/run.sh`：live tail PID/FIFO 全局管理和统一清理。
- `.ralph/lib/watch.sh`：sticky bar `iter_name` + Ctrl-C cleanup 噪声修复。
- `.ralph/lib/adapter-claude.sh`：tool_use input 摘要化。
- `scripts/integration-test.sh`：M1/O2/O3/O4 相关断言补强，当前总数保持 `PASS=59`。
- `tests/fixtures/mock-claude`：补 assistant/tool_use/tool_result stream events 和长 tool input fixture。
- `docs/postmortems/pm-task-closure-req-traceability.md`：记录 2026-05-02 `run -v` 无回归测试再次命中 PM-0003。

# 稳定决策

- 用户可见观测链路不能只靠人工验证；涉及 progress marker、live tail、status/watch、session history 的主路径至少要有集成测试或进程探针。
- `session.history.log` 不承担完整 payload 归档职责；完整 provider 原生内容由 `session.<provider>.jsonl` 承担。
- SC-025-3 目前仍允许手工/进程探针验证，不强行引入复杂信号自动化测试。
- O1 暂不修：未来合并到 `agent-collab-kit` 时再处理 `.spec/` 路由与部署单元边界。

# 验证结果

- 命令：`bash -n scripts/integration-test.sh .ralph/lib/run.sh .ralph/lib/watch.sh .ralph/lib/adapter-claude.sh tests/fixtures/mock-claude`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=59 FAIL=0`。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`。

- 命令：`ps -axo pid=,command= | grep 'ralph/bin/ralph\|tail -f .*provider.stdout.log' | grep -v grep || true`
- 结果：通过
- 诊断：无输出，未发现残留 ralph 或 live tail 进程。

# Postmortem Sweep

- 结果：已更新既有条目
- 关联：`docs/postmortems/pm-task-closure-req-traceability.md`
- 说明：M1 属于 PM-0003 的再次命中：用户可见观测链路缺少最小自动化断言，导致 redirection 静默 bug 只能靠人工完整验证发现。本轮已补集成测试和 SC traceability，无需新增并行 postmortem。PM-0001（shell/macOS 兼容）对 Ctrl-C/sleep 噪声有相关背景，但本轮不需要更新。

# 未验证范围与风险

- 未执行真实 Claude provider 的 side-by-side 录屏；HUMAN-1 记录为 PTY/临时 workspace 等价验证。
- `run -v` 在真实长任务最后 1 秒事件的人眼观感未单独验证；A3（BSD tail polling 延迟）仍按接受风险处理。
- SC-025-3 未转成自动化信号测试，靠进程探针和手工验证；未来若 tail 生命周期再改，应优先补更强自动化。
- O1 保持接受状态：`.spec/` 路由的部署单元问题留给未来 `agent-collab-kit` 完整工程。

# 下一步

- 若继续 I1，优先整理并归档当前 `.ralph/TASKS.md` 到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`，再按 iteration 归档约定推进下一个迭代。
- 若继续强化 observability，可把 SC-025-3 的进程探针收敛为自动化测试，但不作为本 checkpoint 的阻塞项。
