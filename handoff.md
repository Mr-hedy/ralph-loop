# 当前目标与约束

- 本轮目标：完成 I1 归档并启动 I2 任务源；I2 由用户确认执行历史 T3（Codex adapter）。
- 硬约束：中文回复；root `task.md` 已封版，不再更新；当前开发任务事实源是 `.ralph/TASKS.md`；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 不入仓。
- 真实 Codex smoke 会调用外部 provider；执行前必须确认 Codex CLI auth/config 和用户允许范围，不能把 mock 通过伪装成 T3 完成。

# 当前阶段与范围

- 阶段：I2 启动，主题为 dogfood T3 — Codex adapter。
- I1 状态：已完成，归档为 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；上一个稳定 checkpoint/commit 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2 设计锚点：`docs/requirements/ralph-loop/I2-design.md`。
- I2 当前任务源：`.ralph/TASKS.md`，首个任务是 `DEV-1: 校准 Codex CLI 集成契约`。

# 稳定决策

- I2 目标是接入 Codex adapter，不重做 run loop、TASKS 协议、status/watch 或 Claude adapter。
- Codex adapter 必须遵守三函数契约：`provider_oneshot` / `provider_collect_session` / `provider_diagnose`。
- 每轮 iter 证据契约保持 4 文件：`meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`。
- `docs/architecture/integrations.md` 的 Codex 小节基线来自 2026-04-20，且仍有配置目录变量待查、`session.codex.stdout.jsonl` 与 4 文件契约潜在冲突；I2 DEV-1 必须先校准当前 Codex CLI 契约，再改 runtime。

# 已完成工作

- 复制 `.ralph/TASKS.md` 为 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`，保留 I1 完整任务快照。
- 新建 `docs/requirements/ralph-loop/I2-design.md`，记录 I2=T3 的目标、范围、非范围、风险和验收口径。
- 重写 `.ralph/TASKS.md` 为 I2 当前任务源，包含 DEV-1 ~ DEV-5、QA-1/QA-2、REVIEW-1。
- 更新 `docs/roadmap.md`，将 I1 标为完成并将 I2 标为当前 T3。
- 更新 `README.md` 和 `docs/README.md` 的当前状态、设计入口和文档地图。

# 最新验证

- 命令：`git diff --check`
- 结果：通过，无 whitespace error。
- 命令：`bash scripts/check.sh`
- 结果：通过，`ralph-loop check passed`。
- 命令：`bash scripts/integration-test.sh`
- 结果：通过，`PASS=59 FAIL=0`。

# 已验证与未验证

- 已验证：I1 checkpoint `bd85a2d` 存在；进入本轮前工作区 clean；I1 归档/I2 启动文档变更通过项目检查和完整集成测试。
- 未验证：未开始 Codex CLI 契约校准；未实现或验证 Codex adapter。

# Checkpoint 与 Postmortem 状态

- 当前无需新 checkpoint；本轮只是 iteration 归档与 I2 启动准备。
- 当前未触发新的失败、回归、重复错误或预防机制失效；无需新增 postmortem。

# 工作区状态

- 分支：`main`
- 本轮提交 scope：I1 归档文件、I2 设计文件、`.ralph/TASKS.md`、`docs/roadmap.md`、`README.md`、`docs/README.md`、`handoff.md`。
- 本轮开始前提交：`bd85a2d checkpoint: I1 observability review fixes`；提交后以最新 git commit 为准。

# 建议下一步

- 真正开始 I2 时，从 `.ralph/TASKS.md` 的 `DEV-1: 校准 Codex CLI 集成契约` 入手。

# 交接摘要

- I1 已从当前任务源移出并归档；I2 已按用户要求定位为 T3 Codex adapter。当前不能直接写 Codex runtime：先做 DEV-1，解决当前 Codex CLI 文档/本机行为和 4 文件契约的差异，再进入 adapter 实现。
