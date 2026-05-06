# 当前目标与约束

- 本轮目标：完成 I5 设计方案对齐 + PLAN 任务拆分；I5 主题是 run/watch sticky 输出 + per-task round + env 重组；全量术语对齐到 round/stall（PoC 已是事实源）。
- 硬约束：中文回复；当前开发任务事实源是 `.ralph/TASKS.md`；root `task.md` 已封版；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 不入仓；I5 实施时 `.ralph/.gitignore` 自包含会替换工程根 `.gitignore` 中 ralph 相关行。
- 用户明确要求：I5 是 dev 阶段广泛 breaking change，**不留兼容 alias**（iter→round 改名 + stagnation→stall + env 分组重命名 + 删除 RALPH_MAX_ITER 等）；agent 友好是 `ralph run` 默认 plain 模式的核心目标；root PoC 脚本 `ralph-sticky-poc.sh` 和 `ralph-plain-poc.sh` 是视觉契约活文档，commit 进根目录；未来想看视觉效果直接跑 PoC，sticky 由 codex 改完用户已视觉确认。

# 当前阶段与范围

- 阶段：I5 设计已对齐 + PLAN 已拆分 + PoC 视觉契约已确认；待按 PLAN 执行 DEV/QA/REVIEW（18 个任务，2 REQ + 9 DEV + 6 QA + 1 REVIEW）。
- 影响模块：`.ralph/lib/`（新增 sticky.sh + 改造 run.sh / watch.sh）、`.ralph/bin/ralph`、`.ralph/.gitignore` 新建、`.ralph/README.md` 重写、`docs/requirements/ralph-loop/{requirements,I5-design}.md`、`docs/architecture/{overview,integrations,security,testing}.md`、`docs/roadmap.md`、工程根 `.gitignore` 删 ralph 行、`scripts/integration-test.sh` 扩展、`tests/fixtures/` 新增 sticky/stall mock。
- 变更类型：设计文档 + PLAN 拆分 + PoC 视觉契约（本轮）；后续是代码大改造（DEV）+ 测试扩展（QA）+ 对抗审查（REVIEW）。

# 稳定决策

- I5 设计方案落 `docs/requirements/ralph-loop/I5-design.md`（13 项关键决策）。
- 命令矩阵：`ralph run` plain（默认，agent 友好），`ralph run -v` sticky 三段式 10 行（人类），`ralph watch` sticky（与 run -v 共用 renderer），删除 `ralph watch -v`。
- sticky 实现：纯 append + cursor_up 重绘（不用 ANSI scroll region）；10 行紧凑块（顶栏 + 横线 + 6 行事件区 + 横线 + 底栏）；不接管全屏，shell prompt 在 sticky 块下方继续；`stty -echo -icanon` + trap INT/TERM/EXIT 严格还原。
- plain 模式：只打 ralph 自己的 marker（启动 banner / round 启停 / 60s heartbeat / 退出总结），**不打 agent 内部事件**；agent 排障时按需 `grep` `provider.stdout.log`；典型 4 round / 9 分钟 run ≈ 15 行输出。
- 顶栏：`[HH:MM:SS] ralph 0.2 · tasks N/M · round 12 · provider claude · elapsed H:MM:SS`（round 是全局总数，无上限）。
- 底栏：`● round N/∞ · stall N/M · ⠹ HH:MM:SS · → 任务名（动态截断 ...）`（round 是 per-task 已用次数 / 上限；stall 是 per-task 连续无进展次数 / 上限；接近上限 AMBER，触发 RED）。
- 健康灯三态：●绿（60s 内 stdout 字节有变化）/ ●黄 idle（60-300s 无变化，与底栏 stall 字段区分）/ ●红 critical（300s+ 无变化）；只测 `provider.stdout.log` 字节增长，不依赖 stream-json 解析。
- per-task 防死循环双保险：`RALPH_LOOP_MAX_ROUND`（默认 0=无限）+ `RALPH_LOOP_STALL_LIMIT`（默认 5），任一触发 → 自动在当前 task 前插入 HUMAN-N（短 name + 缩进结构化字段）→ exit `blocked_by_human`；stall 改 per-task 判断（task 切换归零）；删除 `max_iterations` exit_reason。
- 改名 breaking 范围：iter→round（含 CLI flag `--max-round` / `--round-timeout` / `--stall-limit`、status.json 字段 `round` / `rounds`、文件路径 `runs/<run_id>/rounds/round-NNN/`）+ stagnation→stall + env 分组重命名（provider_/loop_/ui_/internal）+ 删除 `RALPH_MAX_ITER`（全局 max 取消）；不留 alias。
- `RALPH_VERBOSE` 保留作 CLI → lib 内部传值机制，文档不宣传；用户接口只暴露 flag。
- `.ralph/.gitignore` 自包含：runs/ + lock + status.json + .env，cp -r 时跟随生效。

# 已完成工作

- 重写 `docs/requirements/ralph-loop/I5-design.md`：13 项关键决策、影响 REQ/文档清单、范围/非范围、关键风险、验收口径、待解决/未决；全量 round/stall 命名。
- 拆 `.ralph/TASKS.md` PLAN：18 个任务（REQ-1/2、DEV-1~9、QA-1~6、REVIEW-1），每个含预期/输入/范围/验证计划四字段 + 任务依赖标注。
- 落地两个 PoC 视觉契约：`ralph-sticky-poc.sh`（sticky 模式，含 round + stall + AMBER 颜色 + 任务名动态截断 + char_width 中文支持，codex 改进版用户已视觉确认）、`ralph-plain-poc.sh`（plain 模式，方案 A 粗反馈，已对齐 round 用词）。
- 全量术语对齐：oneshot→round / stagnation→stall / env 名 / CLI flag / 文件路径 / status.json 字段，仅在"旧名→新名映射"位置保留旧名以便 grep 残留检查。
- I5-design 头部 status 字段从"草稿"改为"已确认，待实施"。

# 最新验证

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash -n ralph-sticky-poc.sh ralph-plain-poc.sh`
- 结果：通过
- 诊断：两个 PoC 脚本语法正确（codex 改 sticky 版用户已视觉确认；plain 版本设计阶段已确认形态）。

- 命令：`grep -cE "^- \[ \]" .ralph/TASKS.md`
- 结果：18
- 诊断：18 个任务，分布 9 DEV / 6 QA / 2 REQ / 1 REVIEW，符合 PLAN 设计。

- 命令：`grep -nE "oneshot|stagnat" docs/requirements/ralph-loop/I5-design.md .ralph/TASKS.md ralph-plain-poc.sh handoff.md`
- 结果：3 处命中
- 诊断：3 处均是"旧名→新名映射关系描述"（`RALPH_STAGNATION_LIMIT → RALPH_LOOP_STALL_LIMIT` 和 breaking 范围说明），有意保留，不是漏改。

# 已验证与未验证

- 已验证：I5-design 13 项关键决策与 PoC 视觉锚点用户已确认；PLAN 任务总数 / 前缀分布 / 依赖关系一致；全量术语对齐 round/stall；`git diff --check` 通过；I5-design 文档结构 / 字段命名内部自洽。
- 未验证：实际代码改造（DEV-1~9 全部待执行）；集成测试（QA-1~6 全部待执行）；tmux/screen 兼容性（QA-5）；真实 provider smoke（QA-6）；adversarial review（REVIEW-1）；sticky PoC 当前健康灯阈值 60/180，I5 决策 60/300，DEV-3 实施 sticky.sh 时按决策值对齐。

# Checkpoint 与 Postmortem 状态

- Checkpoint：本轮无新建 checkpoint；最近稳定 checkpoint 是 `docs/checkpoints/2026-05-05-01-i4-gemini-closeout.md`，commit `309423b checkpoint: I4 Gemini closeout`。下一步用户要求执行 `/checkpoint` 创建 I5 启动 anchor。
- Postmortem：本轮无新增 / 命中。

# 工作区状态

- 分支：`main`
- 最近提交：`878edaf docs: refresh handoff after I4 checkpoint`
- 当前 dirty 范围：
  - `M .ralph/TASKS.md`（I5 PLAN 写入）
  - `M handoff.md`（本轮刷新）
  - `?? docs/requirements/ralph-loop/I5-design.md`（I5 设计方案）
  - `?? ralph-sticky-poc.sh` + `?? ralph-plain-poc.sh`（视觉契约 PoC，commit 进根目录作为设计活文档）
- 不存在需要保留的运行中后台任务。

# 建议下一步

- 执行 `/checkpoint`：创建 I5 启动 anchor checkpoint，commit 本轮 5 个产出（建议拆 commit：① 设计文档 + PLAN ② PoC 视觉契约 ③ handoff + checkpoint note），让 I5 实施有干净起点。
- 然后按 PLAN 任务从上至下执行：先 REQ-1/REQ-2（修订 requirements.md），再 DEV-1（iter→round 改名打底）+ DEV-2（env 重命名），后续 DEV-3~9 + QA-1~6 + REVIEW-1。
- 第一轮 ralph 长任务建议跑完 REQ-1/REQ-2 + DEV-1 后人工 checkpoint，验证 breaking change 范围可控再继续。

# 交接摘要

- I5 设计方案 + PLAN 已对齐落档（I5-design 13 决策 + TASKS.md 18 任务 + 两个 PoC 视觉契约），下一位 agent 直接按 `.ralph/TASKS.md` 顺序执行 DEV/QA/REVIEW；sticky/plain 视觉已被用户确认；最大注意点是 I5 是无 alias 的 breaking change（iter→round + stagnation→stall + env 重命名 + 删除 RALPH_MAX_ITER + .gitignore 自包含），DEV-1/DEV-2 必须严格 grep 残留旧名。
