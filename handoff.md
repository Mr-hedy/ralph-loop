# 当前目标与约束

- T1 已完成并入库，工作区干净。下一目标：按 `docs/roadmap.md` 推进 T2（Claude adapter）。
- 约束：事实源以 `docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-016）、`docs/architecture/overview.md`（adapter 契约、退出原因 7 种）、`docs/architecture/integrations.md`（Claude 集成细节）、`docs/architecture/security.md`（approval/sandbox 边界）为准；`task.md` 为当前开发任务事实源（T1 已勾，T2 尚未写入）。

# 当前阶段与范围

- 阶段：T1 完成，T2 未开始；工作区干净，无未提交变更。
- 影响模块（T1 已入库）：`.ralph/bin/ralph` / `.ralph/lib/{common,tasks,session,adapter-fake,run}.sh` / `scripts/{check,integration-test}.sh` / `task.md` / `.agents/skills/task-loop/SKILL.md` / `docs/collaboration/rules/TASK.md`
- 变更类型：下一轮为代码（T2 Claude adapter）。

# 稳定决策

- **Adapter 契约（冻结）**：三函数（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`）+ 全局 `RALPH_PROVIDER_CLI`；adapter source 时设定，run.sh 用于 `command -v` 校验。
- **退出原因 7 种**：`done`(0) / `provider_failed`(2) / `timeout`(3) / `max_iterations`(4) / `stagnated`(5) / `locked`(6) / `interrupted`(130)。
- **Claude adapter 已知约束**（来自 `docs/architecture/integrations.md` + `security.md`）：CLI = `claude`；必须加 `--dangerously-skip-permissions`；approval 白名单固定 `Bash,Read,Edit,Write,Glob,Grep`；session 文件路径由 `--output-dir` 指定；sandbox 写死不开放。
- **macOS 兼容决策（PM-0001）**：`flock` 不可用用 noclobber+PID；`date *1000`；`printf '%s\n'`；信号处理 INT+TERM 并行 trap。新 shell 代码必须遵守，且完成后在 macOS 上运行 `bash scripts/integration-test.sh` PASS=14 才算验收通过。
- **`set -euo pipefail` 防御**：adapter 调用统一 `rc=0; ... || rc=$?`；管道末尾空输出路径加 `|| true` 或变量捕获。
- 启动校验顺序、stagnation 逻辑、per-workspace 部署、每轮 fresh oneshot 等决策继承自 checkpoint 03，不再重述。

# 已完成工作

- **T1 全量**（`889977b`）：ralph run 主循环 + fake adapter 五场景 + 14 个集成测试全绿；两轮 adversarial review 修复 9 个问题；postmortem PM-0001 已建；checkpoint 03 已入库。
- **工作区清理**（`ccc03ac`）：`.agents/skills/task-loop/SKILL.md` 和 `docs/collaboration/rules/TASK.md` 提交入库；`.claude/worktrees/romantic-blackwell` worktree 及分支已删除。

# 最新验证

- 命令：`bash scripts/check.sh && bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`check.sh` → `ralph-loop check passed`；`integration-test.sh` → PASS=14 FAIL=0

# 已验证与未验证

- 已验证：14 个集成用例（7 退出原因 + 6 启动校验 + api-error 变体）；`bash -n` 全 lib 文件；macOS 兼容性（所有已知 pitfall 已修复）。
- 未验证：Claude adapter（T2，尚未实现）；Codex adapter（T3）；Gemini adapter（T4）；`status` / `watch` 子命令（T5）；lock 前 `interrupted` 竞争窗口（可观察风险，接受）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：`889977b` / `docs/checkpoints/2026-04-24-03-t1-done.md`（T1 完成锚点）。
- Postmortem：PM-0001 已新增 `docs/postmortems/pm-shell-macos-compat.md`（macOS shell 兼容性重复 bug 模式）。

# 工作区状态

- 分支：`main`，工作区干净，无未提交变更，无额外 worktree。
- 最近 commit：`ccc03ac Add task-loop skill and collaboration task protocol`。

# 建议下一步

1. 读 `docs/roadmap.md` T2 段 + `docs/architecture/integrations.md` Claude 节，确认 T2 范围边界。
2. 在 `task.md` 中写入 T2 当前任务条目（含实施步骤、验证计划、范围说明）。
3. 创建 T2 开始 checkpoint 作为回滚锚点，然后开始实现 `adapter-claude.sh`。

# 交接摘要

T1 已 100% 完成并入库，工作区干净；下一步是 T2（Claude adapter），**开工前先把 T2 任务写入 `task.md` 并创建开始 checkpoint**，不要直接动代码。
