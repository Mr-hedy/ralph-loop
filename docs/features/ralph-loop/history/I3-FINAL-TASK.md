# Tasks

> 当前迭代: I3
> 主题: watch/status 观察面修复
> 关联 roadmap: I3-bugfix
> 起始: 2026-05-04
> 设计方案: 无独立设计文档（用户反馈驱动 bugfix）

## 当前有效结论

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；checkpoint 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2（dogfood T3 — Codex adapter）已完成并归档到 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`；最终修复 commit 包括 `7385981 fix(run): clean provider tree on interrupted runs` 和 `b004a28 docs(test): clarify slow_child interrupt coverage`。
- I2 稳定验收口径已关闭：`RALPH_PROVIDER=codex` 能在真实 workspace 跑到 `exit_reason=done`，并产出统一 iter 证据契约：`meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`。
- I3 以用户反馈的 watch/status 输出契约漂移为 bugfix 主题：`ralph status` 保持详细 15 字段快照；`ralph watch` 默认只暴露紧凑 sticky 监控面，`-v` 才展示 iter log tail。

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

- [x] DEV-1: 修复 `ralph watch` 非 TTY fallback 与 status 输出契约混淆
  - 预期结果：`ralph watch | cat` 输出一次 one-line watch bar，不打印 `workspace:` / `run_dir:` / `last_error:` 等 `ralph status` 详情字段；TTY 默认仍只显示 sticky bar，`-v` 才 tail 当前 iter log。
  - 输入：用户反馈“watch 的实现有很大问题，所有细节内容都刷出来了”；requirements/overview/README/help 与 integration test 的 SC-024 漂移。
  - 范围：`.ralph/bin/ralph`、`.ralph/lib/watch.sh`、`scripts/integration-test.sh`、README / `.ralph/README.md` / requirements / overview / testing docs、postmortem 预防规则。
  - 验证计划：`bash -n` 相关脚本；直接运行 `bash .ralph/bin/ralph watch | cat`；`git diff --check`；`bash scripts/check.sh`；`bash scripts/integration-test.sh`；自做 adversarial-review 检查当前 docs/test/code 是否仍保留“watch 非 TTY = status”契约。
  - 完成：新增 `ralph_watch_once`，`watch` 非 TTY fallback 改为 one-line watch bar；`status` 继续保留详细 15 字段快照；同步 CLI help、README、requirements、overview、testing docs，并补 postmortem 预防规则。
  - 验证：`bash -n .ralph/bin/ralph .ralph/lib/watch.sh scripts/integration-test.sh`；`bash .ralph/bin/ralph watch | cat` 输出一行 watch bar；`git diff --check`；`bash scripts/check.sh`；`bash scripts/integration-test.sh` → PASS=83 FAIL=0；自审 grep 未发现当前代码/docs/test 仍保留“watch 非 TTY = status”旧契约。
  - 未验证：未重跑真实 TTY 视觉录屏；本次变更的自动覆盖集中在非 TTY fallback、help/docs 与既有 watch helper 行为。
