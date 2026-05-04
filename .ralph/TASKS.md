# Tasks

> 当前迭代: I3
> 主题: 待定 — 等待用户排序
> 关联 roadmap: TBD
> 起始: 待定
> 设计方案: 待定

## 当前有效结论

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；checkpoint 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2（dogfood T3 — Codex adapter）已完成并归档到 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`；最终修复 commit 包括 `7385981 fix(run): clean provider tree on interrupted runs` 和 `b004a28 docs(test): clarify slow_child interrupt coverage`。
- I2 稳定验收口径已关闭：`RALPH_PROVIDER=codex` 能在真实 workspace 跑到 `exit_reason=done`，并产出统一 iter 证据契约：`meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`。
- I3 尚未启动。候选方向：T4（Gemini adapter）/ T7（skill 封装）/ 新议题；等待用户排序后再创建 I3 design 与任务列表。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- I2 归档：`docs/requirements/ralph-loop/I2-FINAL-TASK.md`
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

暂无。等待用户选择 I3 主题后，再创建 `docs/requirements/ralph-loop/I3-design.md` 并生成当前任务列表。
