# I1 启动锚点（REQ + PLAN 闭环，待启动 dogfood 第一次 ralph run）

**日期**：2026-05-01
**版本**：`0.1.1-dev`
**Slug**：`i1-launch-ready`
**锚定 commit**：`8352a36`（含本 checkpoint note）
**前置 checkpoint**：`2026-05-01-01-i1-prep.md`（锁 `1f9ae1b`）

# 目标与约束

- 在启动 dogfood 第一次 `ralph run` 之前固化稳定锚点，便于真实 run 跑出问题时回滚到 REQ + PLAN 全部就绪、未被 dogfood 输出污染的状态。
- 验证 PROMPT 协议 + HUMAN-N 阻塞 + iteration 命名 + Provider 配置目录隔离四件套，在真实 dogfood 长任务下是否符合 I1 prep 阶段的设计预期。
- 不动 v0.1.0 已发布的稳定契约（exit reason 8 种 / adapter 三函数 / TASKS.md 协议）。

# 范围

- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 任务事实源：`.ralph/TASKS.md`
- 命名对齐（业界 PLAN/ROADMAP 同义）：`.ralph/PROMPT.md`、`.ralph/lib/tasks.sh`、`scripts/integration-test.sh`、若干文档

# 核心变更（前置 checkpoint 之后）

| Commit | 主题 | 内容 |
|---|---|---|
| `9bb8fa7` | 命名对齐 | `PLAN-N` → `ROADMAP-N`（roadmap 阶段规划）+ `TASK-N` → `PLAN-N`（任务列表规划，与 trantor PLAN / 业界 sprint planning 同义）。改动 PROMPT.md / tasks.sh / integration-test.sh + 多份文档 |
| `2bb6001` | I1 REQ：status/watch 需求收敛 | 改写 REQ-007（入口需求，详细见 023/024）；新增 REQ-023（status 边界）+ REQ-024（watch 边界，含彩色 + 固定 2s + run_id 切换 separator）；新增 SC-023-1/2/3 + SC-024-1/2/3/4/5（含 8 类 exit_reason 颜色映射验收）；改写 FR-002（status：默认 plain text + `--json`）+ FR-003（watch：双区域布局 + Ctrl-C only + 非 TTY 退化 + 空白等待） |
| `8352a36` | I1 PLAN：status/watch 任务拆解（13 条） | `.ralph/TASKS.md` 当前任务段填入 13 条：DEV-1/2 + QA-1（status）+ DEV-3/4/5/6/7/8 + QA-2（watch）+ DEV-9/10（文档同步）+ HUMAN-1（手工验证 watch UX 类 SC） |

# 影响文件或模块

需求层：`docs/requirements/ralph-loop/requirements.md`（+54 / -18，REQ-007 改写 + REQ-023/024 + 8 SC + FR-002/003 重写 + 待澄清整合 + 追踪矩阵补全）
任务层：`.ralph/TASKS.md`（+71 / -1，13 条 I1 任务）
命名对齐（前置 commit）：`.ralph/PROMPT.md`、`.ralph/lib/tasks.sh`、`scripts/integration-test.sh`、`CLAUDE.md` / `AGENTS.md` / `docs/requirements/ralph-loop/I1-design.md` / `docs/requirements/ralph-loop/requirements.md`

# 稳定决策

- **status 是一次性快照命令**（默认 plain text + `--json` flag），仅看 `.ralph/status.json` 活跃指针；不支持 `--run <id>` 历史浏览（已结束 run 由用户读 `runs/<id>/result.json`）。
- **watch 是人类专用持续刷新工具**（agent oneshot 不调用，PROMPT.md 不引导），双区域布局：上方 tail 当前 iter log + 下方 sticky bar；run 自然结束不自动退出，仅 Ctrl-C 退出；status.json `run_id` 变化时插入 separator 切换 tail 目标。
- **刷新频率固定 2 秒**，不暴露 `--interval` flag（`flag 不是凭空加的`：dogfood 触发实际场景再升级 REQ）。
- **彩色按 isatty + NO_COLOR 自适应**，sticky bar 状态字段按 8 类 exit_reason 上 3 色（绿/红/黄）；非 TTY 退化为 status 单次打印。
- **HUMAN-1 放任务列表最末**：自动化 SC（023-1/2/3 + 024-2/4）由 QA-1/2 集成测试覆盖；纯 UX 类 SC（024-1/3/5）必须人眼录屏验证，agent 验不了，故走 HUMAN-N 阻塞 + 退出 7 + 人类验收勾选后归档。
- **粒度选择**：watch 拆 6 条 DEV（sticky bar / iter log tail / 主循环 + dispatcher / run_id separator / 彩色 / 非 TTY 退化）降低 stagnation 风险；status 拆 2 条 DEV（plain text / `--json`）+ 1 条 QA。
- **PLAN-N 命名定型**：与 trantor PLAN 和业界 sprint planning 同义（任务列表规划）；ROADMAP-N 是 roadmap 阶段规划。本仓库 `.spec/` + `.ralph/PROMPT.md` 已对齐。

# 验证结果

- 命令：`bash scripts/check.sh`
  结果：通过
  诊断：项目结构 + 文档边界 + 关键文本契约（含命名对齐改动）

- 命令：`bash scripts/integration-test.sh`
  结果：通过（52/52 PASS）
  诊断：v0.1 41 用例 + I1 prep 11 用例（HUMAN-N 阻塞 / 前缀全大写 / tilde 翻译 / 空值鲁棒性）；命名对齐改动未引入新用例（ralph 内核不解析前缀，仅 prompt 层文本契约）

- 命令：`git status --short`
  结果：clean

- 命令：`git log --oneline -4`
  结果：`8352a36` ← `2bb6001` ← `9bb8fa7` ← `1f9ae1b`（线性链）

# Postmortem Sweep

- 结果：无需要新增
- 关联：无
- 说明：本轮（命名对齐 + REQ + PLAN）属规范化和文档收敛工作，无 agent 实施失败、无回归、无重复错误、无预防机制失效。一处发生过的 agent 误判（误读 handoff 快照导致以为 workspace dirty，被用户即时纠正）属于"memory/handoff 快照可能过期，应先验证当前状态"的常识范畴，已被全局 CLAUDE.md 内置规则覆盖（"Memory records can become stale over time. ... Before answering ... verify ... by reading the current state"），无需新增 PM 条目。现有 PM-0001/0002/0003 仍 active 且未被本轮违反。

# 未验证范围与风险

- **PROMPT 协议在 dogfood 真实长任务下的健壮性**：v0.1 hello-world / T6 多任务 smoke 已验，但 I1 13 条任务跨越 status/watch 实现 + ANSI 转义 + 彩色 + 非 TTY 退化等多种实现关注点，agent 是否会误用任务前缀、误勾、stagnate，未实测。
- **HUMAN-1 真实拦截行为**：当 ralph 跑到第 13 条 HUMAN-1 时，是否如期退出 exit 7、exit-message.txt 是否含正确接力提示，未实测（前置 checkpoint 在临时 workspace 验过 RT2 路径，但本仓库 dogfood 路径下 PROMPT 协议 + 真实 13 条历史任务上下文是否触发 agent 误勾，仍是开放问题）。
- **watch 实现**：watch 还未开始实施（DEV-3 ~ DEV-8）；ANSI sticky bar + tail -f 等价循环 + Ctrl-C 信号处理在 bash 实现中的边界情况（如 SIGWINCH / 终端 resize / iter log 文件 rotate）未被 SC 显式覆盖，dogfood 时按需补救。
- **agent-collab-kit 同步**：`I1-design.md` 末尾的同步建议尚未拿去 kit 工程推进，本 checkpoint 不锚定 kit 状态。

# 下一步

1. 启动 dogfood 第一次 `ralph run`，方式 B：`.ralph/.env` 设 `RALPH_PROVIDER_CONFIG_DIR=~/.claude-glm/`（独立账号，避免占用 main agent Claude usage）。
2. 监控前 1-2 轮 oneshot 行为：是否如期 pick DEV-1、是否一轮一勾、是否触发 stagnation / max_iter / blocked_by_human 误判。
3. 跑出问题时回滚到本 checkpoint（`git reset --hard 8352a36`）；正常推进时让 ralph 跑到 HUMAN-1 阻塞退出，再人类介入做 watch UX 手工验证。
4. I1 完成（HUMAN-1 勾掉 + ralph 跑出 `exit_reason=done`）后归档：`cp .ralph/TASKS.md docs/requirements/ralph-loop/I1-FINAL-TASK.md` + 清空 TASKS.md 当前任务段 + roadmap.md 加完成行 + 本仓库 commit。
