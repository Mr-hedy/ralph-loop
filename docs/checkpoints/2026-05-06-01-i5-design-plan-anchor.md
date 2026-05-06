# 目标与约束

- 这个 checkpoint 保留 I5 启动前的可回滚锚点：I5 设计方案 + PLAN 任务拆分 + 两个 PoC 视觉契约 + handoff 全部对齐到 round/stall 命名后的稳定状态。
- 后续 I5 实施（DEV-1~9 / QA-1~6 / REVIEW-1）是**广泛 breaking change**（iter→round + stagnation→stall + env 分组重命名 + 删除 RALPH_MAX_ITER + .gitignore 自包含），如有方向性问题需要回滚，回到本 checkpoint 即可重新拆分 PLAN 而无需重做设计对齐。

# 范围

- 设计文档：`docs/requirements/ralph-loop/I5-design.md`（13 项关键决策）
- PLAN 任务清单：`.ralph/TASKS.md`（18 个任务，2 REQ + 9 DEV + 6 QA + 1 REVIEW）
- 视觉契约 PoC：`ralph-sticky-poc.sh`（sticky 模式，codex 改进版用户已视觉确认） + `ralph-plain-poc.sh`（plain 模式方案 A 粗反馈）
- 协作交接：`handoff.md`
- 不动 lib / .ralph/README.md / docs/architecture / requirements.md（这些都是 I5 DEV 阶段的工作，本 checkpoint 故意不预改避免 scope 蔓延）

# 核心变更

- 与用户对齐 I5 设计的 13 项关键决策：三段式 sticky 总布局 / 命令矩阵（run/run -v/watch）/ plain 模式（方案 A 粗反馈，agent 友好）/ 顶栏与底栏字段定义 / 健康灯三态 / per-task round 计数 / 防死循环双保险 + HUMAN 自动插入 / iter→round 全量改名 / env 分组重命名 / flag-only 接口 / -v 实现层次 / .ralph/.gitignore 自包含 / cursor_up + stty + trap 实现技术。
- 把所有用户拍板的决策固化到 `I5-design.md` 关键决策小节（结构化 13 子节，便于 DEV 阶段直接对照实施）；同步影响 REQ/文档清单、范围、非范围、关键风险、验收口径、待解决/未决（含 PoC 健康灯阈值差异 60/180 vs 决策 60/300，PLAN DEV-3 时按决策值对齐）。
- 拆 18 个 PLAN 任务（每个含预期/输入/范围/验证计划四字段 + 任务依赖标注），按 REQ → DEV-1/2 改名打底 → DEV-3 sticky.sh → DEV-4/5 接入 run/watch → DEV-6 防死循环 → DEV-7/8/9 配置文档 → QA-1~6 → REVIEW-1 顺序排列。
- 落地 codex 改进版 `ralph-sticky-poc.sh`（含 round + stall 字段、AMBER 接近上限色、任务名按可见列宽动态截断含中文字符宽度处理、stty noecho + trap INT/TERM/EXIT 还原），更新 `ralph-plain-poc.sh` 同步 round 用词。
- 全量术语对齐 round/stall：3 个文档 + 2 个 PoC 共 5 个文件用 perl 批量替换 + 边角手工修复（`ONESHOT_TIMEOUT` → `ROUND_TIMEOUT`、健康灯黄色含义改为 `idle` 避免与底栏 stall 字段歧义、env 改名表的旧名列保留 `RALPH_STAGNATION_LIMIT` 以便 DEV grep 残留）。

# 影响文件或模块

- `docs/requirements/ralph-loop/I5-design.md`（新增，约 380 行）
- `.ralph/TASKS.md`（修改，写入 18 个 I5 任务）
- `ralph-sticky-poc.sh`（新增，codex 改进版 358 行）
- `ralph-plain-poc.sh`（新增，方案 A 粗反馈 67 行）
- `handoff.md`（修改，反映 I5 设计 + PLAN + PoC 全部对齐状态）
- 不修改：`.ralph/lib/`、`.ralph/bin/`、`.ralph/README.md`、`docs/architecture/`、`docs/requirements/ralph-loop/requirements.md`、`docs/roadmap.md`、`scripts/`、`tests/fixtures/`、工程根 `.gitignore`

# 稳定决策

- I5 主题：run/watch sticky 输出 + per-task round + env 重组。
- 命令矩阵：`ralph run` plain（默认，agent 友好）/ `ralph run -v` sticky 三段式 / `ralph watch` sticky（删除 `watch -v`）；`run -v` 与 `watch` 共用 sticky renderer。
- sticky 实现技术：纯 append + cursor_up 重绘（不用 ANSI scroll region）；10 行紧凑块；不接管全屏；`stty -echo -icanon` + trap INT/TERM/EXIT 严格还原；非 TTY 自动降级 plain。
- 顶栏：`[HH:MM:SS] ralph 0.2 · tasks N/M · round 12 · provider claude · elapsed H:MM:SS`（round 是全局总数，无上限）。
- 底栏：`● round N/∞ · stall N/M · ⠹ HH:MM:SS · → 任务名（动态截断 ...）`（per-task 计数；stall 接近上限 AMBER，触发 RED）。
- 健康灯三态：●绿（60s 内 stdout 字节有变化）/ ●黄 idle（60-300s 无变化）/ ●红 critical（300s+ 无变化）；只测 `provider.stdout.log` 字节增长。
- 防死循环：`RALPH_LOOP_MAX_ROUND`（默认 0=无限）+ `RALPH_LOOP_STALL_LIMIT`（默认 5）任一触发 → 自动在当前 task 前插入 HUMAN-N → exit blocked_by_human；删除 `max_iterations` exit_reason。
- 改名 breaking 范围：iter→round + stagnation→stall + env 分组重命名（provider_/loop_/ui_/internal）+ 删除 `RALPH_MAX_ITER`（全局 max 取消）；不留 alias。
- `RALPH_VERBOSE` 保留作 CLI → lib 内部传值机制，文档不宣传；用户接口只暴露 flag。
- `.ralph/.gitignore` 自包含：runs/ + lock + status.json + .env，cp -r 时跟随生效。
- PoC 是视觉契约活文档，commit 进根目录；后续改样式必须先改 PoC 再改 lib。

# 验证结果

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash -n ralph-sticky-poc.sh ralph-plain-poc.sh`
- 结果：通过
- 诊断：两个 PoC 脚本语法正确；用户已视觉确认 sticky 效果。

- 命令：`grep -cE "^- \[ \]" .ralph/TASKS.md`
- 结果：18
- 诊断：18 个任务，分布 9 DEV / 6 QA / 2 REQ / 1 REVIEW。

- 命令：`grep -nE "oneshot|stagnat" docs/requirements/ralph-loop/I5-design.md .ralph/TASKS.md ralph-plain-poc.sh handoff.md`
- 结果：5 处命中
- 诊断：5 处均是有意保留的"旧名→新名映射关系描述"或 grep 命令本身（用于 DEV 阶段残留检查），不是漏改。

# Postmortem Sweep

- 结果：无需要新增
- 关联：无
- 说明：本轮有过一次失误（在与用户讨论 ANSI scroll region 时，未先做最小复现验证就论断"方案 B 鼠标可翻 scrollback"，被用户挑出错误后修正），但已通过 I5-design §"关键约束 — scrollback 行为"小节固化正确事实（region top != 1 时滚出内容不进 scrollback；trantor 之所以可翻是因为没有顶栏 + region top = 1），不会重复影响 I5 DEV 阶段；不构成需要新增 postmortem 的可复用失败模式。已存在的 PM-0001（macOS shell 兼容性）/ PM-0002（跨任务决策沉淀）/ PM-0003（任务收口 traceability）也无新触发。

# 未验证范围与风险

- 实际代码改造（DEV-1~9）：未执行，是 I5 实施的核心工作量。
- 集成测试（QA-1~6）：未执行。
- tmux / screen 兼容性（QA-5）：cursor_up + EL 重绘在嵌套终端复用器下未 smoke 测试。
- 真实 provider smoke（QA-6）：未执行。
- adversarial review（REVIEW-1）：未执行。
- sticky PoC 健康灯阈值 60/180 与 I5 决策 60/300 的差异：DEV-3 实施 sticky.sh 时按决策值对齐。
- iter→round 改名是广泛 breaking change：旧 `runs/<run>/iterations/iter-NNN/` 目录在新版 ralph 下表现未验证（设计上"新版只读 oneshots/，旧目录保留可见但 status 不展示"）。

# 下一步

- 提 commit（本 checkpoint 一个 commit），然后按 `.ralph/TASKS.md` 顺序启动 I5 实施：
  1. REQ-1 / REQ-2：先把 requirements.md 修订掉，让 lib 改造有清晰契约对齐
  2. DEV-1（iter→round 全量改名打底）+ DEV-2（env 分组重命名）：是后续所有 DEV 的依赖
  3. DEV-3（sticky.sh）→ DEV-4（run.sh）→ DEV-5（watch.sh）→ DEV-6（per-task 防死循环 + HUMAN 自动插入）→ DEV-7/8/9（配置/文档/同步）
  4. QA-1~6：覆盖 sticky 渲染 / plain 回归 / per-task 边界 / 改名一致性 / tmux smoke / 真实 provider smoke
  5. REVIEW-1：adversarial review 收口
- 第一轮 ralph 长任务建议跑完 REQ-1/REQ-2 + DEV-1 后人工 checkpoint，验证 breaking change 范围可控再继续 DEV-2 之后。
