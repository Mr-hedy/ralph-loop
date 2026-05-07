# Tasks

> 当前迭代: I6（待启动）
> 主题: TBD — 候选见下方"I6 候选议题"，由用户在下一轮启动前选定
> 关联 roadmap: 见 `docs/roadmap.md`
> 起始: TBD
> 设计方案: TBD（启动后落到 `docs/requirements/ralph-loop/I6-design.md`）

## 当前有效结论

- I5 已完成（2026-05-07）并归档到 `docs/requirements/ralph-loop/I5-FINAL-TASK.md`，含 REVIEW-2 第二轮审查后续修订（DEV-12 / CHORE-1）+ doc-drift 同步。
- I5 主要产出：sticky 三段式（live 11 行 / frozen 10 行）+ per-task round + env 分组重命名（provider_/loop_/ui_）+ iter→round 全量改名 + retry 自动重试 + HUMAN 自动插入。
- I5 sticky 契约事实源现在是 `docs/requirements/ralph-loop/I5-design.md` §0 ChangeLog（§1-§13 是启动初版决议，与 §0 冲突时以 §0 为准）。
- I5 完成时整套 `bash scripts/integration-test.sh` 首次完整通过：148 PASS / 0 FAIL。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- I2 归档：`docs/requirements/ralph-loop/I2-FINAL-TASK.md`
- I3 归档：`docs/requirements/ralph-loop/I3-FINAL-TASK.md`
- I4 归档：`docs/requirements/ralph-loop/I4-FINAL-TASK.md`
- I5 归档：`docs/requirements/ralph-loop/I5-FINAL-TASK.md`
- I5 设计方案：`docs/requirements/ralph-loop/I5-design.md`
- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
- Provider 集成事实源：`docs/architecture/integrations.md`
- Roadmap：`docs/roadmap.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`

## I6 候选议题（待用户选择）

启动 I6 前由用户从以下 backlog 中选取主题（也可新增）：

- **REVIEW-1 P2 收尾**（lib 层维护性，sticky/watch 路径）：
  - watch.sh 不 trap SIGTERM（进程管理器 kill -TERM 时 stty 还原依赖 EXIT trap，bash 行为不确定）
  - run.sh `_ralph_filter_verbose` 与 watch.sh `_ralph_watch_filter_events` 近 100 行 jq 完全重复 → 抽 `lib/events.sh`
  - `ralph_sticky_install_traps` 是死代码（公共 API 标注但无人调）→ 删除或标注 standalone
- **P3 收尾**（边缘体验问题）：
  - plain 模式 retry 期间每次都重打一行 `[ts] round N/M → task` round-start marker → 收敛为只在 `retry_count==0` 打
  - sticky.sh `_schar_width` CJK 检测的 bash glob `[一-龥]` 依赖 locale，CJK task 名截断在 `LC_ALL=C` 等场景可能不一致
- **新议题**（用户提议或 roadmap 中 T7 / 跨 run 统计 / token cost / onboarding 文档等）

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 子 bullet 是给 agent 读的上下文，不进 ralph 解析（只识别 `^\s*- \[([ xX])\]`）。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `→ BLOCKED by HUMAN-N` 或 `→ BLOCKED by REVIEW-N`。
- HUMAN-N 任务在 ralph round 内不可勾选（人类在 Claude Code 对话里勾）。
- 不创建根 `task.md` 或其他并行任务板。
- 历史完成细节进入 checkpoint；本文件只保留当前有效结论、历史索引和当前迭代任务。

## 当前任务

（I5 已归档；I6 待启动。启动 I6 时按以下顺序：1）选定主题 → 2）写 design → 3）拆 PLAN 任务 → 4）填本节。本段保持空白直到下一轮启动 I6。）
