# Tasks

> 当前迭代: I1
> 主题: dogfood T5 — Status + Watch 真实功能
> 关联 roadmap: T5
> 起始: 2026-04-30
> 设计方案: `docs/requirements/ralph-loop/I1-design.md`

## 当前有效结论

- 本仓库从 v0.1 发布后切换到 `.ralph/TASKS.md` 作为开发任务事实源；root `task.md` 已封版作为 v0.1 历史归档。
- I1 启动前置准备：PROMPT.md 重构 + TASKS.md 四段结构 + ralph 内核加 HUMAN-N 阻塞 + iteration 归档约定（详见 `I1-design.md`）。
- 任务前缀体系：REQ / SOL / PLAN / TASK / DEV / QA / REVIEW / HUMAN（详见 `.ralph/PROMPT.md`）。
- I1 完成动作：`cp .ralph/TASKS.md docs/requirements/ralph-loop/I1-FINAL-TASK.md`，清空当前任务段，"当前迭代"改为下一个。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
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

> 当前迭代待启动。本段在 I1 启动前置 7 步实施完成、T5 任务拆解定稿后填入；详见 `I1-design.md`「实施路径」段。
