# Tasks

> 当前迭代: I5
> 主题: 待定
> 关联 roadmap: T7 Skill 封装或新议题（待用户排序）
> 起始: 待定
> 设计方案: 等待 I5 启动

## 当前有效结论

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；checkpoint 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2（dogfood T3 — Codex adapter）已完成并归档到 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`；最终修复 commit 包括 `7385981 fix(run): clean provider tree on interrupted runs` 和 `b004a28 docs(test): clarify slow_child interrupt coverage`。
- I3（watch/status 观察面修复）已完成并归档到 `docs/requirements/ralph-loop/I3-FINAL-TASK.md`；checkpoint 为 `2641605 checkpoint: watch status surface fix`。
- I4（T4 Gemini adapter）已完成并归档到 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`。
- I4 最终状态：`RALPH_PROVIDER=gemini` 支持 fresh oneshot、session capture、`session.history.log` 派生、错误诊断、mock 集成测试矩阵和用户入口文档；真实 Gemini smoke 跑到 `exit_reason=done`。
- I4 最终验证：`git diff --check`、`bash -n .ralph/lib/run.sh .ralph/lib/adapter-gemini.sh tests/fixtures/mock-gemini scripts/integration-test.sh`、`bash scripts/check.sh`、`bash scripts/integration-test.sh` 均通过；完整集成为 `PASS=100 FAIL=0`。
- I4 接受风险：真实 Gemini error event schema 未触发验证；真实 `ralph run -v --provider gemini` 未单独重跑，mock `run -v` 和真实 non-verbose smoke 已覆盖主路径。
- I5 尚未启动；下一步需要用户确认是推进 T7 Skill 封装，还是插入新的 bugfix / provider / 文档议题。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- I2 归档：`docs/requirements/ralph-loop/I2-FINAL-TASK.md`
- I3 归档：`docs/requirements/ralph-loop/I3-FINAL-TASK.md`
- I4 归档：`docs/requirements/ralph-loop/I4-FINAL-TASK.md`
- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
- Provider 集成事实源：`docs/architecture/integrations.md`
- Roadmap：`docs/roadmap.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 子 bullet 是给 agent 读的上下文，不进 ralph 解析（只识别 `^\s*- \[([ xX])\]`）。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `→ BLOCKED by HUMAN-N` 或 `→ BLOCKED by REVIEW-N`。
- HUMAN-N 任务在 ralph oneshot 内不可勾选（人类在 Claude Code 对话里勾）。
- 不创建根 `task.md` 或其他并行任务板。
- 历史完成细节进入 checkpoint；本文件只保留当前有效结论、历史索引和当前迭代任务。

## 当前任务

（暂无；等待用户确认 I5 主题并写入新的任务列表。）
