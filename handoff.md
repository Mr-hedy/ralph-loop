# 当前目标与约束

- **v0.1 已发布**（2026-04-28）。T6 全部子任务闭环，版本号 `0.1.0`。
- 下一步等待用户决策：T3（Codex adapter）/ T4（Gemini adapter）/ T5（status/watch 真实功能）/ T7（skill 封装）。

# 当前阶段

**T6 — v0.1 闭环验证 + 使用指南（已完成）**

所有 T6 子任务（T6.0–T6.7）均已闭环：

| 子任务 | commit 状态 | 核心交付 |
|--------|------------|----------|
| T6.0 模板 | 已落地 | `.ralph/PROMPT.md` + `.ralph/TASKS.md` 入仓 |
| T6.1 stagnation 修正 | 已落地 | fingerprint per-iter；`changed_files_iter`/`changed_files_total`；`--stagnation-limit` |
| T6.2 effort 接入 | 已落地 | `--effort` 直通；SC-014-1 集成测试 4 用例 |
| T6.3 多轮 smoke | 已落地 | 3 条任务 4 轮 done（run_id `20260428-080709-a17ef14`）|
| T6.4 边界复验 | 已落地 | stagnation/max_iter/timeout 各触发；fingerprint bug T6.7.1 修复 |
| T6.5 使用指南 | 已落地 | `README.md ## 快速开始`（80 行）|
| T6.6 closure | 已落地 | 版本 0.1.0；roadmap 更新；checkpoint 06 |
| T6.7.1 fingerprint bug | 已落地 | `common.sh` 双路过滤 `.ralph/` 路径 |

工作区状态：**有未提交改动**（T6.4–T6.6 本会话所有变更，待下次 `/checkpoint` 落仓）。

# 稳定决策

本轮新增（T6.1/T6.2/T6.4，2026-04-28）：

- **stagnation 比对 = 方案 B**：per-iter fingerprint（`git ls-files -s` + `git status -z`，过滤 `.ralph/`）。不写 `.git/refs/`，不创建 git 对象。
- **`--effort` 直通**：Claude CLI v2.1.114+ 原生 `--effort low/medium/high/xhigh/max`；`none`/空不拼。**不再**翻译为 `--thinking-budget`（原 requirements 文档已更正）。
- **T6.7.1 fingerprint bug**：`git status -z` 输出含 `.ralph/runs/iter-NNN/` 未追踪目录，每轮新增导致指纹每轮变。修复：`grep -v '\.ralph/'`（status-z 输出）+ `grep -v $'\t\.ralph/'`（ls-files-s 输出）。

继承自 T2 / T6 prep 的稳定决策：adapter 三函数契约、退出原因 7 种、macOS 兼容（PM-0001）、`set -euo pipefail`、approval/sandbox 写死、每轮 fresh oneshot、依赖校验框架、Session 文件命名约定、cwd_hash 严格 realpath→hash 顺序、Claude JSONL tool_result schema、5xx 正则 word-boundary、ARG_MAX 900KB 防护、REQ-017 `cp -r .ralph/` 一次性部署。

# 已完成工作（本会话）

- `common.sh` fingerprint 函数双路过滤 `.ralph/` 路径（T6.7.1 bug 修复）
- `adapter-claude.sh` `--effort` 直通（T6.2）
- `integration-test.sh` 41 用例 PASS（含 SC-014-1 × 4 + stagnation per-iter × 2）
- `.ralph/PROMPT.md` + `.ralph/TASKS.md` 入仓（T6.0）
- T6.3 多轮 smoke：run_id `20260428-080709-a17ef14`，3 条任务 4 轮 done
- T6.4 边界复验：stagnation `20260428-082455-b147582`、max_iter `20260428-082801-5b19f40`、timeout `20260428-082909-5af11ee`
- `README.md ## 快速开始` 新增（T6.5）
- `.ralph/bin/ralph` 版本号 `0.1.0-dev` → `0.1.0`（T6.6）
- `docs/roadmap.md` Current State 更新（v0.1 已发布）
- Checkpoint 03/04/05/06 入仓

# 最新验证

- `bash scripts/check.sh` PASS
- `bash scripts/integration-test.sh` 41/41 PASS
- `ralph --version` → `ralph 0.1.0 (d1fbb69)`

# 工作区状态

- 分支：`main`
- 工作区：有未提交改动（本会话 T6.4–T6.6 全量变更）
- 最近已 commit：`5c7258b T6 prep`

# 建议下一步

1. `/checkpoint` 把本会话全量改动落仓（T6.4 fingerprint fix + T6.5 quickstart + T6.6 版本号 + checkpoints 03–06）。
2. 向用户汇报 v0.1 完成，等待决策 T3/T4/T5/T7 优先级。
