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

- [x] DEV-1: 实现 ralph status plain text 输出（REQ-023 / SC-023-1, SC-023-3）
  - 新建 `.ralph/lib/status.sh`
  - 读 `.ralph/status.json`，渲染 15 字段 plain text（`run_id` / `run_dir` / `workspace` / `provider` / `model` / `effort` / `started_at` / `updated_at` / `iteration` / `iteration_name` / `state` / `tasks_total` / `tasks_checked` / `exit_reason` / `last_error`）
  - 任务进度渲染为 `<checked> / <total> checked`
  - status.json 不存在时 stdout 输出"无运行中/已结束的 run"，exit 0，不创建任何文件
  - 在 `.ralph/bin/ralph` 加 `status` 子命令 dispatcher

- [x] DEV-2: 实现 ralph status --json 透传（SC-023-2）
  - 加 `--json` flag 解析
  - cat `.ralph/status.json` 字节透传（不二次序列化）

- [x] QA-1: status 集成测试（SC-023-1/2/3）
  - `scripts/integration-test.sh` 加 3 用例：
    - SC-023-1: plain text 14 字段标签 + checked 进度格式
    - SC-023-2: `--json` 输出与 status.json diff 完全一致
    - SC-023-3: status.json 缺失时 exit 0 + 提示文案 + 无副作用
  - 验证：3/3 PASS；替换旧占位测试（v0.1 placeholder check）

- [x] DEV-3: 实现 watch sticky bar 渲染（REQ-024 / SC-024-1 部分）
  - 新建 `.ralph/lib/watch.sh`
  - 底部 sticky bar（ANSI 保留底部 1-2 行 + 上方滚动）
  - sticky bar 字段：`run_id`（截断前 12 位 + `...`）/ `iter <N>` / `<checked>/<total> tasks` / `state` / `exit_reason` / `provider`
  - 主循环和 tail 区域暂留空（DEV-4/5 接管）

- [x] DEV-4: 实现 watch iter log tail（REQ-024 / SC-024-1 部分）
  - 上方区域 tail 当前活跃 iter log：路径 = `.ralph/runs/<run_id>/iterations/iter-<NNN>/log`，从 status.json `run_id` + `iteration` 拼接
  - 文件不存在时上方区域留空（无占位文案）
  - iter 切换（status.json `iteration` 变化）时切换 tail 目标

- [x] DEV-5: 实现 watch 主循环 + dispatcher wiring + Ctrl-C 退出清屏
  - 2 秒刷新循环（固定，不暴露 `--interval`）
  - 在 `.ralph/bin/ralph` 加 `watch` 子命令
  - SIGINT 信号处理 + 退出时 `tput clear` 清屏
  - run 自然结束（`state=finished`）后**不自动退出**，最后一帧保留继续刷新

- [x] DEV-6: 实现 watch run_id 切换 separator（SC-024-2）
  - 检测 status.json `run_id` 变化 → 上方区域插入 separator 行 `─── new run: <new_run_id> ───`
  - 切换 tail 目标到新 run 的 iter log

- [x] DEV-7: 实现 watch 彩色支持（SC-024-5）
  - 检测 `isatty(stdout) && [ -z "$NO_COLOR" ]`
  - sticky bar 状态字段按 exit_reason 上色：
    - `state=running` 或 `exit_reason=done` → 绿
    - `exit_reason` ∈ {`provider_failed`, `timeout`, `max_iterations`, `stagnated`} → 红
    - `exit_reason` ∈ {`blocked_by_human`, `locked`, `interrupted`} → 黄
  - sticky bar 字段标签（如 `run:` / `iter` / `tasks`）→ dim 灰
  - 上方 tail 区域不主动上色（透传 provider 输出）

- [x] DEV-8: 实现 watch 非 TTY 退化（SC-024-4）
  - 启动时检测 `isatty(stdout)`，false → 退化为 `ralph status` 单次打印后 exit 0
  - 用例验证：`ralph watch | cat` 不卡死

- [x] QA-2: watch 集成测试（SC-024-2/4 自动化部分）
  - `scripts/integration-test.sh` 加 2 用例：
    - run_id 切换 separator（mock 修改 status.json `run_id` → 验证 separator 行出现 + tail 目标切换；用 timeout + tail -f 自身退出验证）
    - 非 TTY 退化（`ralph watch | cat` → exit 0 + 单次输出）

- [ ] DEV-9: 同步 README + docs/usage.md status/watch 使用示例
  - `README.md` 加 `ralph status` / `ralph watch` 快速入口段（含 `--json` 示例）
  - 如 `docs/usage.md` 不存在则不创建（README 内嵌即可）

- [ ] DEV-10: 同步 docs/architecture/overview.md 状态观察段
  - 加 status/watch 数据流图 + 双区域布局说明
  - 引用 REQ-023 / REQ-024 / SC-023-* / SC-024-*

- [ ] HUMAN-1: 手工验证 watch UX（SC-024-1, SC-024-3, SC-024-5）
  - 双区域布局视觉验证
  - 8 类 exit_reason 颜色映射验证（构造 8 个 status.json 各对应一个 exit_reason，逐个看色彩）
  - Ctrl-C 退出 + 清屏行为
  - run 自然结束（state=finished）后 watch 不自动退出、最后一帧保留刷新
  - 录屏 / 截图作为 I1 验收证据，附在 `I1-FINAL-TASK.md` 归档
  - 答（待）：
