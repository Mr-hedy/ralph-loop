# Tasks

> 当前迭代: I5
> 主题: run/watch sticky 输出 + per-task round + env 重组
> 关联 roadmap: 新议题（用户体验 / 接口重构）
> 起始: 2026-05-05
> 设计方案: `docs/requirements/ralph-loop/I5-design.md`

## 当前有效结论

- I5 设计方案已对齐并落到 `docs/requirements/ralph-loop/I5-design.md`（13 项关键决策，含三段式 sticky / 命令矩阵 / per-task round / HUMAN 自动插入 / iter→round 改名 / env 分组）
- 视觉契约 PoC 锚点在仓库根目录：`ralph-sticky-poc.sh`（sticky 模式 = `ralph run -v` / `ralph watch`）和 `ralph-plain-poc.sh`（plain 模式 = `ralph run` 默认）
- I5 是**广泛 breaking change**，dev 阶段**不留兼容 alias**：iter→round 改名、env 分组重命名、删除 `RALPH_MAX_ITER`（全局 max）替换为 `RALPH_LOOP_MAX_ROUND`（per-task）
- 防死循环改 per-task：单 task max_round 触发 / 单 task stall 触发 → 自动在 TASKS.md 插入 HUMAN-N → exit `blocked_by_human`
- 命令矩阵：`ralph run` plain（默认，agent 友好），`ralph run -v` sticky，`ralph watch` sticky；删除 `ralph watch -v`
- I4（T4 Gemini adapter）已完成并归档到 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- I2 归档：`docs/requirements/ralph-loop/I2-FINAL-TASK.md`
- I3 归档：`docs/requirements/ralph-loop/I3-FINAL-TASK.md`
- I4 归档：`docs/requirements/ralph-loop/I4-FINAL-TASK.md`
- I5 设计方案：`docs/requirements/ralph-loop/I5-design.md`
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
- HUMAN-N 任务在 ralph round 内不可勾选（人类在 Claude Code 对话里勾）。
- 不创建根 `task.md` 或其他并行任务板。
- 历史完成细节进入 checkpoint；本文件只保留当前有效结论、历史索引和当前迭代任务。

## 当前任务

- [x] REQ-1: 修订 REQ-024 / REQ-025 / REQ-026 输出契约
  - 预期：requirements.md 中 watch / run 的输出契约和命令矩阵与 I5-design §1-§5 完全一致；删除"双区域 -v / 2 秒固定刷新 interval / verbose live tail"等已废弃描述；用户读 requirements 即可了解三种调用形态（`ralph run` plain / `ralph run -v` sticky / `ralph watch` sticky）。
  - 输入：`docs/requirements/ralph-loop/I5-design.md` §1-§5 / §10 / §11；现有 `docs/requirements/ralph-loop/requirements.md` REQ-024 / REQ-025 / REQ-026 段。
  - 范围：只动 `docs/requirements/ralph-loop/requirements.md` 的 REQ-024 / REQ-025 / REQ-026 描述和对应 SC-024-* / SC-025-* 验收口径；同步追溯矩阵；不动 architecture / README。
  - 验证计划：`grep -nE "RALPH_VERBOSE|RALPH_MAX_ITER|双区域|2 秒固定刷新|fork tail" docs/requirements/ralph-loop/requirements.md` 无遗漏旧描述；REQ-024/025/026 的 SC 项 grep 出来逐条对照 I5-design 字段；`bash -n` 不适用，`git diff --check` 通过。
  - 完成：REQ-024 删除 `-v` flag / "2 秒固定刷新" / "双区域"，改为三段式 sticky + 健康灯三态 + `RALPH_UI_*` 环境变量；REQ-025 重定义 plain + sticky 双模式 + TTY fallback + per-task round；REQ-026 `iter-NNN` → `round-NNN`；SC-024-* / SC-025-* 全部对齐，新增 SC-025-4（TTY fallback）和 SC-025-5（per-task round）；追溯矩阵同步。
  - 验证：`git diff --check` 通过；grep 命中均在范围外（SC-009-1 / FR-001 / FR-003，属 DEV-2/DEV-9）；REQ-024/025/026 + SC-024-*/SC-025-* 内无旧描述残留。
  - 未验证：FR-001 / FR-003 中仍含旧 `iter` / `RALPH_MAX_ITER` / `双区域` 描述（DEV-2 / DEV-9 范围）；I5 新增 REQ-027（per-task 防死循环）待 REQ-2 独立新增。

- [x] REQ-2: 新增 REQ：per-task 防死循环 + HUMAN 自动插入
  - 预期：requirements.md 新增一条 REQ（编号待定，记为 REQ-027）描述"单 task max_round / 单 task stall 任一触发 → 自动在当前 task 前插入 HUMAN-N task → exit `blocked_by_human`"，含触发条件、HUMAN task 模板、人类修复路径、对应 SC 验收。
  - 输入：I5-design §6 §7；现有 `docs/architecture/overview.md` 中 stall 相关描述。
  - 范围：在 `docs/requirements/ralph-loop/requirements.md` 追加 REQ-027 + SC-027-*；同步追溯矩阵；不改 architecture / README。
  - 验证计划：requirements.md 中能找到 REQ-027 完整条目（描述 + SC + 优先级）；SC 验收能映射到具体集成测试场景（QA 阶段会覆盖）；`git diff --check` 通过。
  - 完成：requirements.md 新增 REQ-027（P1-重要 / 功能 / I5-design §6 §7），描述 per-task max_round + per-task stall 双触发 → 自动插 HUMAN-N → exit blocked_by_human；新增 SC-027-1~6 覆盖 max_round 触发 / stall 触发 / task 切换归零 / HUMAN 模板 / exit_reason / 勾掉后继续；追溯矩阵新增 REQ-027 行。
  - 验证：`git diff --check` 通过；`grep -c REQ-027 requirements.md` = 8；`grep -c SC-027- requirements.md` = 7（6 条 SC + 1 条追溯矩阵引用）。
  - 未验证：REQ-012 / REQ-013 / FR-001 中仍含旧 `max_iterations` / `stagnated` / `--max-iter` 描述（DEV-1 / DEV-2 / DEV-6 范围内同步）；REQ-027 未验证与现有 BPF-001 流程的一致性（DEV-6 实施时同步）。

- [ ] DEV-1: iter → round 全量改名（lib + status.json + 文件路径）
  - 预期：ralph 代码内部所有 `iter` / `iteration` 标识改为 `round`；`status.json` / `result.json` / `meta.json` 字段 `iteration` → `round`，`iterations` → `rounds`；运行时目录 `.ralph/runs/<run_id>/iterations/iter-NNN/` → `.ralph/runs/<run_id>/rounds/round-NNN/`；CLI flag `--max-iter` → `--max-round`，`--timeout` → `--round-timeout`；新版 ralph 跑出来的 run 完全使用新命名，旧 run 目录保留可见但 `ralph status` 不展示。
  - 输入：I5-design §8；当前 `.ralph/lib/run.sh` / `.ralph/lib/status.sh` / `.ralph/lib/watch.sh` / `.ralph/lib/common.sh` / `.ralph/bin/ralph` / 各 adapter / 测试 fixture。
  - 范围：`.ralph/lib/*.sh` / `.ralph/bin/ralph` / `tests/fixtures/mock-*` / `scripts/integration-test.sh`；不改 docs（独立任务）；不留 alias。
  - 验证计划：`grep -rnE "iteration|iter-NNN|RALPH_MAX_ITER|--max-iter|--timeout " .ralph/ scripts/ tests/` 无残留旧名（除 `.ralph/runs/` 历史目录）；`bash -n .ralph/bin/ralph .ralph/lib/*.sh`；`bash scripts/check.sh`；`bash scripts/integration-test.sh` 通过（fixture 测试已同步）。

- [ ] DEV-2: env 分组重命名（provider_ / loop_ / ui_）
  - 预期：所有用户可见 env 按 `RALPH_PROVIDER_*` / `RALPH_LOOP_*` / `RALPH_UI_*` 三组重命名；`RALPH_MODEL` → `RALPH_PROVIDER_MODEL`，`RALPH_EFFORT` → `RALPH_PROVIDER_EFFORT`，`RALPH_TIMEOUT` → `RALPH_LOOP_ROUND_TIMEOUT`，`RALPH_STAGNATION_LIMIT` → `RALPH_LOOP_STALL_LIMIT`（同时改名 stagnation→stall），新增 `RALPH_LOOP_MAX_ROUND`（替代删除的 `RALPH_MAX_ITER`，语义改 per-task），新增 `RALPH_UI_STICKY_EVENT_LINES` / `RALPH_UI_HEALTH_GREEN_SEC` / `RALPH_UI_HEALTH_RED_SEC`；`RALPH_VERBOSE` 保留作内部传值（lib 仍读这个 env）但文档不宣传；CLI flag 同步 `--max-round` / `--round-timeout` / `--stall-limit` / `--provider` / `--model` / `--effort`。
  - 输入：I5-design §9；DEV-1 完成后；当前 `.ralph/bin/ralph` flag 解析、`.ralph/lib/run.sh` / `.ralph/lib/common.sh` env 读取。
  - 范围：`.ralph/bin/ralph` / `.ralph/lib/*.sh` / `scripts/integration-test.sh` / `tests/fixtures/`；不改 docs（独立任务）；不留 alias。
  - 验证计划：`grep -rnE "RALPH_MODEL[^_]|RALPH_EFFORT[^_]|RALPH_TIMEOUT[^_]|RALPH_STAGNATION_LIMIT|RALPH_MAX_ITER" .ralph/ scripts/ tests/` 无残留；`ralph run --help` 输出新 flag 名；`bash scripts/check.sh`；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-1

- [ ] DEV-3: 新增 .ralph/lib/sticky.sh — 三段式 sticky renderer
  - 预期：新增 `.ralph/lib/sticky.sh`（或类似命名），实现 §1 / §4 / §5 / §13 描述的纯 append + cursor_up 重绘 sticky renderer；提供 `ralph_sticky_enter` / `ralph_sticky_render_frame` / `ralph_sticky_cleanup` 公共函数；事件区高度由 `RALPH_UI_STICKY_EVENT_LINES`（默认 6）控制；健康灯按 `RALPH_UI_HEALTH_GREEN_SEC`（默认 60）/ `RALPH_UI_HEALTH_RED_SEC`（默认 300）三态；`stty -echo -icanon` + trap INT/TERM/EXIT 严格还原；与 `ralph-sticky-poc.sh` 视觉一致。
  - 输入：I5-design §1 / §4 / §5 / §13；`ralph-sticky-poc.sh` 视觉契约。
  - 范围：新增 `.ralph/lib/sticky.sh`；不改 run.sh / watch.sh（接入是后续任务）；可被 `bash -n` 通过。
  - 验证计划：`bash -n .ralph/lib/sticky.sh`；mock 一个 status.json + 简单 log 文件，独立 source sticky.sh + 调用 enter/render/cleanup，视觉与 `ralph-sticky-poc.sh` 一致；trap INT/TERM/EXIT 测试 stty 还原（用 stty -g 对比）；`bash scripts/check.sh` 通过。
  - 依赖：DEV-1, DEV-2

- [ ] DEV-4: 改造 .ralph/lib/run.sh — plain 默认 + -v 启动 sticky + per-task round 计数
  - 预期：`ralph run`（无 `-v`）保留 plain 输出契约（启动 banner + round 启停 marker + 60s heartbeat + 退出总结）但全量 iter→round 改名；`ralph run -v` 启动 `sticky.sh` 渲染；TTY 检测自动降级（非 TTY → plain）；plain 模式 60s heartbeat 保留，sticky 模式不需要 heartbeat（健康灯替代）；新增 `_RALPH_CURRENT_TASK_ID` / `_RALPH_CURRENT_TASK_TRY` 变量维护 per-task round 计数（task 切换时 try 归零，相同 task 时 try +=1）；底栏显示 per-task try 数。
  - 输入：I5-design §2 §3 §6；DEV-3 完成后；当前 `.ralph/lib/run.sh` plain marker / verbose tail 逻辑。
  - 范围：`.ralph/lib/run.sh`；不改 watch.sh / sticky.sh；不改 plain 模式输出格式（保持 REQ-025 兼容）。
  - 验证计划：`ralph run` 无 -v 时输出与 `ralph-plain-poc.sh` 形态一致（≤ ~30 行 / 4 round 长 run）；`ralph run -v` 在 TTY 启动 sticky 三段式；`ralph run -v 2> /tmp/log` 走 plain（log 无 ANSI）；per-task round 计数：连续 5 次同 task 时底栏显示 round 5/∞；task 切换时归零；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-1, DEV-2, DEV-3

- [ ] DEV-5: 改造 .ralph/lib/watch.sh — TTY sticky / 非 TTY 一行 bar / 删除 -v
  - 预期：`ralph watch` 在 TTY 调用 `sticky.sh` 渲染（与 run -v 共用 renderer），数据源为 `status.json` + tail `provider.stdout.log`；非 TTY 输出一行 watch bar 后 exit（保留现状）；删除 `-v` flag（不识别，报未知参数错误清晰提示）；run 自然结束（state=finished）后 watch 不自动退出，最后一帧持续刷新等 Ctrl+C；watch attach 时只显示当前一帧，不回放已结束 round 的总结行；Ctrl+C 仅退出 watch（不影响后台 run）。
  - 输入：I5-design §2；DEV-3 完成后；当前 `.ralph/lib/watch.sh`。
  - 范围：`.ralph/lib/watch.sh` / `.ralph/bin/ralph` 中 watch 入口；不改 run.sh / sticky.sh。
  - 验证计划：`ralph watch` TTY 输出三段式 sticky；`ralph watch | cat` 一行 bar 后 exit；`ralph watch -v` 报未知参数（exit 2 + 友好提示）；attach 已 finished 的 run，sticky 显示最终状态不退出；Ctrl+C 干净退出还原终端；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-1, DEV-3

- [ ] DEV-6: per-task round 防死循环 + HUMAN 自动插入
  - 预期：`RALPH_LOOP_MAX_ROUND > 0` 时，同一 task 试了 N 次 → 触发；`RALPH_LOOP_STALL_LIMIT`（默认 5）连续无进展（无勾任务 + worktree fingerprint 不变）→ 触发；任一触发 → ralph 在 `.ralph/TASKS.md` 当前 first_unchecked task **前面**插入一行 HUMAN-N（按 §7 模板，短 name + 缩进结构化字段）→ exit `blocked_by_human`；stall 改 per-task 判断（同一 task 连续 N 次无进展，task 切换时归零）；删除原全局 stall 逻辑；删除 `max_iterations` exit_reason（全局 max 取消）。
  - 输入：I5-design §6 §7；DEV-1 / DEV-4 完成后；当前 `.ralph/lib/run.sh` stall 判断。
  - 范围：`.ralph/lib/run.sh` 主循环 + stall 判断 + TASKS.md 写入；新增 helper 函数（解析 first_unchecked task、生成 HUMAN-N 编号、按模板插入行）。
  - 验证计划:
    - 单 task max_round 触发：mock TASKS.md 只有 1 个 task，agent 完全不勾不改文件，跑 `RALPH_LOOP_MAX_ROUND=3 ralph run` → 3 次 round 后 TASKS.md 出现 HUMAN-1（在原 task 前），exit_reason=blocked_by_human
    - stall 触发：mock TASKS.md，5 次 round 都不勾不改 → HUMAN-1 出现，exit blocked_by_human
    - task 切换归零：mock 第 1 个 task 完成（勾掉），第 2 个 task 开始，per-task try 重置为 1
    - HUMAN-N 模板：name 简短、缩进字段含触发原因 / 已耗时 / 建议 / 修复后操作
    - `bash scripts/integration-test.sh` 通过
  - 依赖：DEV-1, DEV-4

- [ ] DEV-7: 新建 .ralph/.gitignore + 删工程根 .gitignore 中 ralph 行
  - 预期：`.ralph/.gitignore` 自带 `runs/` / `lock` / `status.json` / `.env` 规则；用户 `cp -r .ralph` 时 gitignore 自动跟随；工程根 `.gitignore` 删除 `.ralph/runs/` / `.ralph/lock` / `.ralph/status.json` / `.ralph/.env` 4 行；本仓库验证 `git status` 仍正确忽略这些文件。
  - 输入：I5-design §12；当前工程根 `.gitignore`。
  - 范围：新建 `.ralph/.gitignore`；编辑工程根 `.gitignore`；不改其他文件。
  - 验证计划：`cat .ralph/.gitignore` 含 4 行规则；工程根 `.gitignore` 不含 `.ralph/*` 相关行；`git check-ignore .ralph/runs/test .ralph/lock .ralph/status.json .ralph/.env` 全部命中；`git status --ignored` 验证 `.ralph/runs/` 等仍被忽略；`git diff --check` 通过。

- [ ] DEV-8: 重写 .ralph/README.md
  - 预期：按 I5-design §10 / §影响 REQ-文档 描述重写 `.ralph/README.md`：环境变量按 provider/loop/ui 三组分类（每个变量含默认 / 说明 / 示例）；新增《Ralph loop 与 round》小节解释 round ≠ task 概念；新增《防死循环机制》小节描述 max_round + stall + HUMAN 自动插入；新增《agent 调用 ralph》最佳实践（默认 `ralph run` plain 即 agent 友好）；新增《sticky 模式异常退出救援》（`stty sane`）；删除所有 `RALPH_VERBOSE` / `RALPH_MAX_ITER` / `iter` 旧名宣传；`.ralph/.gitignore` 自包含说明（cp -r 时自动跟随）。
  - 输入：I5-design 全文；DEV-1 / DEV-2 / DEV-7 完成后；当前 `.ralph/README.md`。
  - 范围：`.ralph/README.md`；不改 docs/architecture/。
  - 验证计划：`grep -E "RALPH_VERBOSE|RALPH_MAX_ITER|^- iter " .ralph/README.md` 无残留；环境变量小节有 provider/loop/ui 三组表格；含 round/防死循环/agent 调用/sticky 救援/.gitignore 五个新小节；`git diff --check` 通过。
  - 依赖：DEV-1, DEV-2, DEV-7

- [ ] DEV-9: 同步 docs/architecture/ + docs/roadmap.md
  - 预期：`docs/architecture/overview.md` 同步三种调用形态 + sticky renderer 共用 + per-task round + iter→round 改名；`docs/architecture/integrations.md` 检查并改名所有旧字段引用；`docs/architecture/security.md` 同上；`docs/architecture/testing.md` 补 sticky 渲染测试策略 + plain 模式回归 + per-task 边界测试；`docs/roadmap.md` 加 I5 项的描述。
  - 输入：I5-design 全文；DEV-1 / DEV-2 / DEV-6 完成后；当前 `docs/architecture/*.md` / `docs/roadmap.md`。
  - 范围：`docs/architecture/{overview,integrations,security,testing}.md` / `docs/roadmap.md`；不改 requirements / README。
  - 验证计划：`grep -rnE "iteration|RALPH_MAX_ITER|RALPH_VERBOSE" docs/architecture/` 无残留旧名（说明文字保留历史除外）；overview.md 含三种调用形态描述；testing.md 含 sticky/plain 测试策略章节；`git diff --check` 通过。
  - 依赖：DEV-1, DEV-2, DEV-6

- [ ] QA-1: TTY mock 测试三段式 sticky 渲染
  - 预期：集成测试覆盖 sticky 模式核心场景：首帧顺序输出 10 行 / cursor_up 重绘不破坏布局 / 健康灯三态颜色映射（绿/黄/红）正确随时间切换 / 事件区 6 行硬限超出从数组 shift / 退出后保留 sticky 块 / Ctrl+C 干净还原 stty。
  - 输入：I5-design §1 §4 §5 §13；DEV-3 / DEV-4 / DEV-5 完成后。
  - 范围：`scripts/integration-test.sh` 新增 sticky 渲染用例；可能新增 `tests/fixtures/mock-sticky/` 辅助；不改 lib。
  - 验证计划：mock TTY 环境（用 `script` / `unbuffer` 等工具）跑 `ralph run -v --provider fake`，断言 stdout 含顶栏字段 / 横线 / 6 行事件区 / 底栏字段；mock log 字节静默 60s+ 后健康灯应变黄；模拟 Ctrl+C 后 `stty -g` 与启动前一致；新增用例计入 PASS=N；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-3, DEV-4, DEV-5

- [ ] QA-2: plain 模式回归（ralph run 默认 / 非 TTY 自动降级）
  - 预期：集成测试覆盖 plain 模式：`ralph run`（无 -v）输出形态 ≈ `ralph-plain-poc.sh`；含启动 banner / 每 round 启停 marker / 60s heartbeat（长 round 用 fake-slow 触发） / 退出总结；`ralph run -v 2> /tmp/log` 在非 TTY stderr 自动降级 plain（无 ANSI）；`ralph run | cat` 同上。
  - 输入：I5-design §3；DEV-4 完成后；现有 REQ-025 集成测试用例。
  - 范围：`scripts/integration-test.sh` 新增/修订 plain 模式回归用例；不改 lib。
  - 验证计划：mock-claude fake provider 跑 `ralph run`，断言每个 round 启停一行 marker / 长 round 触发 heartbeat / 退出 summary 块字段全；`ralph run -v 2> /tmp/log` 后 `grep -P '\\033\\[' /tmp/log` 无 ANSI；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-4

- [ ] QA-3: per-task round 边界 + HUMAN 自动插入测试
  - 预期：集成测试覆盖 §6 / §7 全部场景：单 task max_round 触发自动插 HUMAN / 单 task stall 触发自动插 HUMAN / task 切换时 per-task try 归零 / HUMAN-N 模板正确（短 name + 缩进字段） / exit_reason=blocked_by_human / 用户勾掉 HUMAN-N 重跑 ralph run 能继续做原 task。
  - 输入：I5-design §6 §7；DEV-6 完成后。
  - 范围：`scripts/integration-test.sh` 新增 per-task round 用例；可能新增 `tests/fixtures/mock-stall/`；不改 lib。
  - 验证计划：fake provider 配置成"完全不勾不改文件"模式，跑 `RALPH_LOOP_MAX_ROUND=3 ralph run` → 3 次后 TASKS.md 出现 HUMAN-1，断言行号在原 task 前 + name 简短 + 缩进含 4 个结构化字段；`RALPH_LOOP_STALL_LIMIT=5 ralph run` 5 次无进展同样触发；mock 第 1 个 task 勾完进入第 2 个，per-task try 重置；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-6

- [ ] QA-4: iter → round 改名 + env 重命名一致性回归
  - 预期：集成测试验证全量改名后无残留：所有 status.json / result.json / meta.json 字段为 `round` / `rounds`；运行时目录为 `runs/<run_id>/rounds/round-NNN/`；CLI flag `--max-round` / `--round-timeout` 生效，旧 flag `--max-iter` / `--timeout` 报错；env `RALPH_PROVIDER_MODEL` / `RALPH_LOOP_MAX_ROUND` 等新名生效，旧名不再被读取（除 `RALPH_VERBOSE` 内部传值保留）。
  - 输入：I5-design §8 §9；DEV-1 / DEV-2 完成后；现有集成测试。
  - 范围：`scripts/integration-test.sh` 修订所有现有用例的旧名引用；新增改名一致性断言用例；不改 lib。
  - 验证计划：`grep -rnE "iter-NNN|iteration[^_]|RALPH_MAX_ITER|--max-iter" .ralph/runs/<test_run>/` 无残留新名；`ralph run --max-iter 3` exit 2 报错；`RALPH_MAX_ITER=3 ralph run` 不被 ralph 接受（除非用户在 .env 写）；`bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-1, DEV-2

- [ ] QA-5: tmux / screen 兼容性 smoke
  - 预期：在 tmux 和 screen 嵌套下手工跑 `ralph run -v --provider fake` 长任务，验证 sticky 三段式渲染正常（不闪烁过度 / cursor_up 不错位 / 颜色正确）；Ctrl+C 干净还原 stty。
  - 输入：I5-design §13 / 关键风险段；DEV-3 / DEV-4 完成后。
  - 范围：手工执行 + 截图 / 终端录屏归档；不改 lib（如发现严重 bug 创建 DEV-N 修复任务）；不改自动化测试（tmux 内嵌 mock 难做）。
  - 验证计划：在 tmux 和 screen 各跑一次，截图 / asciinema 录制保存到 `docs/checkpoints/` 或 issue；如视觉正常，本任务 verified；如有问题，记录现象 + 触发条件，新增 DEV 任务；`bash scripts/check.sh` 通过。
  - 依赖：DEV-3, DEV-4

- [ ] QA-6: 真实 provider smoke（claude + plain + sticky）
  - 预期：在临时 workspace 跑两次真实 `ralph run`：① `ralph run --provider claude` plain 模式跑到 `exit_reason=done`（或主动 Ctrl+C），输出 ≈ ralph-plain-poc.sh 形态、main agent 角色 grep 友好；② `ralph run -v --provider claude` sticky 模式手工观察三段式视觉、健康灯、退出后 sticky 块保留；新版 `runs/<run_id>/rounds/round-NNN/` 目录结构正确；`status.json` / `result.json` / `meta.json` 字段名为 `round`。
  - 输入：DEV-1 ~ DEV-6 全部完成后；I5 所有改名 / 行为变化已落地。
  - 范围：手工执行 + 截图归档；不改 lib；如发现 bug 新增 DEV 修复任务。
  - 验证计划：两次 smoke 全程录屏 / 截图，归档到 `docs/checkpoints/2026-MM-DD-i5-smoke.md`；plain 输出行数 ≤ 50（一个中等长 run）；sticky 视觉与 ralph-sticky-poc.sh 一致；`runs/<run_id>/rounds/` 目录结构 + meta.json `round` 字段；本仓库 `bash scripts/check.sh` + `bash scripts/integration-test.sh` 通过。
  - 依赖：DEV-1, DEV-2, DEV-3, DEV-4, DEV-5, DEV-6, DEV-7, DEV-8, DEV-9

- [ ] REVIEW-1: I5 实施完成 adversarial review | adversarial-review
  - 预期：对 I5 的 lib 改造 / 文档同步 / 测试覆盖 做对抗式审查，重点检查：iter→round 改名是否有残留 / per-task round 边界条件（task 全部勾完 / TASKS.md 为空 / 第一个 task 是 HUMAN-）/ HUMAN 自动插入是否会重复触发 / sticky 模式异常退出（kill -9 / 终端关闭）下 stty 还原 / TTY 检测在边缘 CI / sticky 在窄终端的降级 / plain 模式 6 种 exit_reason 输出格式完整性 / `.ralph/.gitignore` 自包含 cp -r 后真的生效。
  - 输入：I5 全部 DEV / QA 完成；I5-design 关键风险段；`.spec/rules/adversarial-review.md`。
  - 范围：审阅代码 + 文档 + 测试 + 实际跑一次 ralph run；产出 findings 列表（在本任务子项追加）；如有 P0/P1 找 bug 新增 DEV 任务修复；不直接改代码。
  - 验证计划：findings 列表完整且每个 finding 有"严重度 / 复现步骤 / 建议修复"三字段；P0/P1 findings 全部转化为 DEV 任务并完成；本仓库 `bash scripts/check.sh` + `bash scripts/integration-test.sh` 通过；归档 review 结果到 checkpoint。
  - 依赖：QA-1, QA-2, QA-3, QA-4, QA-5, QA-6
