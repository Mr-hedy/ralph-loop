# 当前目标与约束

- 目标：I5 已经实施完毕（含 REVIEW-1 / REVIEW-2 / DEV-12 / CHORE-1 后续修订），整套 sticky / per-task / retry / iter→round / env 重组都落地；当前 main 干净，下一步是归档 I5（cp `.ralph/TASKS.md` → `docs/requirements/ralph-loop/I5-FINAL-TASK.md` + 清空 `.ralph/TASKS.md` + commit）或开 I6。
- 硬约束：中文回复；当前开发任务事实源是 `.ralph/TASKS.md`；项目最终产物是 `.ralph/` 整个目录（用户 cp -r 部署）；`.ralph/.gitignore` 自包含。
- 用户偏好（本会话累积）：sticky UI 偏好极简——`( CTRL+C to exit )` 紧凑（无空格）+ "all tasks done" 用 `_SGRAY`/提示用 `_SDIM`/状态结论比提示更亮；视觉契约要在 design 文档同步（不接受 design vs 实现漂移）；后台任务必须用 waiter 显式等而不能轮询。

# 当前阶段与范围

- 阶段：I5 实施完成 + 第二轮 adversarial review 后续修复全部 landed + doc-drift 同步完成。
- 影响模块（本轮）：`.ralph/lib/run.sh` / `.ralph/lib/sticky.sh` / `.ralph/lib/watch.sh` / `scripts/integration-test.sh` / `.ralph/README.md` / `docs/requirements/ralph-loop/I5-design.md` / `ralph-sticky-poc.sh` / `.ralph/TASKS.md` / `.gitignore`。
- 变更类型：代码 fix（P1 retry × TRY 灌水 / watch 时钟冻结）+ UX 升级（live hint 行 / frozen 后缀 / `( CTRL+C to exit )` 文本与颜色）+ 测试修复（diagnose retry hang / pty stty size / ANSI grep / 删 4 个失效 -v live tail 测试）+ 文档同步（I5-design §0 ChangeLog / .ralph/README / PoC 注释）+ 工作树清理。

# 稳定决策

- **I5-design.md §0 ChangeLog 是当前 sticky 契约事实源**，§1-§13 保留作启动初版决议但与 §0 冲突时以 §0 为准。
- Sticky 高度按模式变化：live = `EVENT_WINDOW + 5`（默认 11，含 `( CTRL+C to exit )` 提示行）；frozen = `EVENT_WINDOW + 4`（默认 10，不带提示行，提示走底栏后缀）。
- Frozen 视觉触发：watch 检测 state=finished 时从 status.json `updated_at` 写入 `_RALPH_STICKY_FROZEN_NOW`；run -v 在 `_ralph_finish` 前 `_RALPH_STICKY_FROZEN_NOW=$(date +%s)`，让 run -v 退出最终帧与 watch attach 已 finished run 视觉完全一致。
- Frozen 顶栏 `finished Xago · duration H:MM:SS` 替代 `elapsed H:MM:SS`；起始时间戳 `[HH:MM:SS]` 整体删除（live/frozen 都不显示）。
- Frozen + exit_reason=done 底栏简化为 `✓ all tasks done · ( CTRL+C to exit )`；其它 frozen 退出态在原底栏末尾追加 ` · ( CTRL+C to exit )` 后缀（task 名 `_struncate_cols` 按 `frozen_suffix_w=24` 让出空间）。
- 颜色：状态结论 `all tasks done` 用 `_SGRAY`；提示 `( CTRL+C to exit )` 用 `_SDIM`（提示弱化，状态主级）。
- Spinner 节奏 200ms → 100ms（10fps）；run.sh sticky polling + watch.sh main loop 都改 sleep 0.1。
- per-task TRY 计数与 round 同源：必须包入 `if [[ "$retry_count" -eq 0 ]]; then ... fi` 守门，retry 不增 TRY。
- `.ralph/scheduled_tasks.lock` / `.claude/worktrees/` / `.claude/settings.local.json` 进 root `.gitignore`，不再污染 git status。
- REVIEW-1 P2 三项（watch SIGTERM trap / run.sh × watch.sh 事件过滤 jq 重复 / `ralph_sticky_install_traps` 死代码）+ P3 几项（plain retry round-marker 重打 / CJK locale）保留至 I6，本轮不改。

# 已完成工作（commit 链 17ee6e2 → c3d79b8）

- `17ee6e2` task_try 字段写入 status.json（DEV-11，REVIEW-1 P1 修）
- `df1206d` REVIEW-1 adversarial review（1 P1 + 3 P2 + 4 P3）
- `402aa3c` REVIEW-2 + DEV-12 + CHORE-1：retry × TRY 守门 + watch 时钟冻结 + spinner 提速 + 删 4 个 -v live tail 失效测试 + 工作树残渣清理 + diagnose retry hang 修
- `0668b6a` 顶栏 frozen 用 `finished Xago · ran H:MM:SS`
- `778f09a` 顶栏精简（删 `[HH:MM:SS]`）+ 底栏 done 简化为 `✓ all tasks done` + diagnose hang `--max-retry 0` + pty `stty rows 24 cols 80` + sticky `tasks 0/1` 断言改为先 strip ANSI 再 grep —— integration test 首次 145/0 全通过
- `7bacc16` live 加 `( ctrl + c )` 提示行 + frozen 底栏后缀 + `_RALPH_STICKY_FROZEN_NOW` 变高 cursor 管理
- `c3d79b8` 文本 `(ctrl + c) to exit` → `( CTRL+C to exit )`（后续用户改成无空格紧凑形）+ 颜色互换（dim/gray 互换）
- 本次未提交（待 commit）：I5-design §0 ChangeLog、.ralph/README 同步、ralph-sticky-poc.sh PoC v1 注释、`.gitignore` 加 `.claude/` 系列条目

# 最新验证

- 命令：`bash scripts/integration-test.sh`
- 结果：**148 PASS / 0 FAIL** 完整通过（首次）
- 诊断：之前的 100 PASS / 3 FAIL 中 3 个 -v live tail 已删除；65 PASS 截断点（Codex diagnose retry hang）已通过 `--max-retry 0` 修复。

- 命令：`bash -n .ralph/lib/{run,sticky,watch}.sh scripts/integration-test.sh ralph-sticky-poc.sh`
- 结果：通过
- 诊断：所有改动 shell 文件语法 OK。

- 命令：`bash scripts/check.sh`
- 结果：通过

- 命令：`git worktree list`
- 结果：仅 main 一个工作树
- 诊断：`.claude/worktrees/blissful-satoshi-0538ef`（早先 Agent isolation 残留）已 `git worktree remove` + `git branch -D claude/blissful-satoshi-0538ef`。

- 命令：unit visual test（live / frozen+done / frozen+blocked 三模式 _sdraw_top + _sdraw_bottom + _sdraw_hint）
- 结果：三模式视觉与 design §0 ChangeLog 描述一致；spinner live mode 0→1→2 递增、frozen mode 不前进；frozen 后缀含 `( CTRL+C to exit )`；done 终态底栏简化。

- 未运行：TTY 真实终端下的 spinner 100ms 视觉、watch attach finished run 时钟冻结视觉、live↔frozen 收缩切换的实际终端展现。需人工冒烟（QA-5/QA-6 范围）。

# 已验证与未验证

- 已验证：DEV-12 retry × TRY 不灌水（`task_try=1` 而非旧 6）、retry × max_round=2 不假阳性触发 HUMAN-N、QA-1 sticky 11 unit + 2 stty + 2 e2e、所有 diagnose case error.type 分类、所有 plain 模式 retry marker 格式、所有 per-task max_round / stall HUMAN 自动插入、iter→round 改名一致性。
- 未验证：TTY 视觉冒烟（spinner / watch 时钟冻结 / live↔frozen 切换）；需真实终端人工对比 `ralph-sticky-poc.sh` 与实际 `ralph run -v`（PoC 已标注 v1 contract，新合约见 design §0 ChangeLog）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：本轮无新建。最近一个相关 checkpoint 是 `docs/checkpoints/2026-05-07-01-i5-qa6-smoke.md`（QA-6 真实 claude smoke）。当前 main `c3d79b8` 视为隐式稳定锚点。
- Postmortem：本轮无新增。考虑下次开 I6 前补一条 PM 关于"refactor 后 pre-existing 测试未回归审查"——本轮 `round → oneshots` 断言 / 4 个 -v live tail 测试 / sticky 顶栏 `tasks 0/1` ANSI grep / pty stty size 都是 I3-I5 期间累积的同类盲区，集中在 REVIEW-2 后续才被发现。

# 工作区状态

- 分支：main，HEAD = `c3d79b8`
- dirty 文件（待提交，本节末尾的"建议下一步"会处理）：
  - `M .gitignore`（加 `.claude/scheduled_tasks.lock` / `.claude/worktrees/` / `.claude/settings.local.json`）
  - `M .ralph/README.md`（11 行 / frozen 模式 / 100ms 三处描述同步）
  - `M .ralph/lib/sticky.sh`（用户改 `CTRL + C` → `CTRL+C` 紧凑形）
  - `M docs/requirements/ralph-loop/I5-design.md`（新增 §0 ChangeLog 6 项）
  - `M ralph-sticky-poc.sh`（注明 v1 contract，指向 design §0）
  - `M scripts/integration-test.sh`（同步 `CTRL+C` 紧凑形 + 新增 frozen line count 测试）
- 外部参考：commit `c3d79b8` 含完整提示文本/颜色互换；`docs/requirements/ralph-loop/I5-design.md` §0 ChangeLog 是 sticky 契约事实源。

# 建议下一步

1. **commit 当前 dirty 文件**：一个 commit 把 doc-drift 同步收掉（"docs(I5): sync sticky contract drift after REVIEW-2 — design §0 ChangeLog + README + PoC v1 marker + .gitignore"）。
2. **归档 I5**（按 CLAUDE.md iteration 协议）：
   - `cp .ralph/TASKS.md docs/requirements/ralph-loop/I5-FINAL-TASK.md`
   - 清空 `.ralph/TASKS.md` 当前任务段，"当前迭代"改为下一个（如 I6）
   - `docs/roadmap.md` 添加 I5 完成行 + 引用归档文件
   - commit
3. **可选 I6 启动议题**（用户决定主题；当前 backlog 候选）：
   - REVIEW-1 P2 三项遗留收尾（watch SIGTERM trap / 事件过滤代码抽 `lib/events.sh` / 删 `ralph_sticky_install_traps` 死代码）
   - P3 收尾：plain retry round-start marker 不重打、CJK locale 字宽
   - 新议题：用户 onboarding 文档？token cost 追踪？跨 run iteration-cumulative 统计？
4. **Postmortem 记录**："I3-I5 累积的 refactor 后测试未回归审查盲区"（多次发现同类问题，值得固化为流程检查点）。

# 交接摘要

I5 + REVIEW-2 后续全部 landed，integration test 首次 148/0 全通过；当前 dirty 是 doc-drift 同步（5 个文件）+ `.gitignore` 收尾，**先 commit 再按 CLAUDE.md 协议归档 I5**。Sticky 契约现在以 `docs/requirements/ralph-loop/I5-design.md` §0 ChangeLog 为准，§1-§13 是历史。
