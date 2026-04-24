# Roadmap

> Ralph Loop 专项开发阶段目标、优先级、验收口径和风险。
> 权威需求：`docs/requirements/ralph-loop/requirements.md`。

## Current State

- 协作壳已初始化，`.spec/`、`docs/` 结构稳定。
- Ralph v0.1 需求已收敛为 22 条决策，沉淀在 `requirements.md`（REQ-001 ~ REQ-016）。
- 架构和稳定契约沉淀在 `docs/architecture/overview.md`；provider 集成细节沉淀在 `docs/architecture/integrations.md`；安全边界沉淀在 `docs/architecture/security.md`。
- 工具代码骨架：`.ralph/bin/ralph` + `.ralph/lib/common.sh`，`run` / `status` / `watch` 尚未实现。
- `task.md` 是开发任务事实源；当前只排 T1。

## Phased Delivery

| Phase | 目标 | 主要交付 | 验收口径 |
|---|---|---|---|
| T0 Bootstrap | 协作规范、需求、设计、入口文档就位 | `.spec/`、`docs/requirements.md`、`docs/requirements/`、`docs/architecture/`、`scripts/check.sh` | `bash scripts/check.sh` 通过 |
| **T1 Run 骨架 + Adapter 契约 + Fake 实现** | ralph run 主循环 + adapter 三函数契约 + fake adapter 跑通最小闭环 | `.ralph/lib/run.sh` / `tasks.sh` / `session.sh` / `adapter-fake.sh` | fake provider smoke：预置 TASKS，跑到 `exit_reason=done`；stagnation 和 locked 各有集成测试 |
| T2 Claude Adapter | 把 fake 替换为真实 Claude adapter 实现 | `.ralph/lib/adapter-claude.sh`、chat/tools 派生视图 | 真实 workspace 跑一轮 `--provider=claude`，产生 session + 派生视图 |
| T3 Codex Adapter | 同上，Codex 实现 | `.ralph/lib/adapter-codex.sh` | 真实 workspace 跑一轮 `--provider=codex` |
| T4 Gemini Adapter | 同上，Gemini 实现 | `.ralph/lib/adapter-gemini.sh` | 真实 workspace 跑一轮 `--provider=gemini` |
| T5 Status + Watch | 观察性子命令 | `.ralph/lib/status.sh` / `watch.sh` | `ralph status` 一次性输出；`ralph watch` 2 秒刷新 sticky bar |
| T6 v0.1 Release | 对 v0.1 做端到端整合验证 | release notes、使用指南 | 真实 workspace 跑完一个 3+ 条 task 的 TASKS.md |
| T7 Skill 封装（post-v0.1） | `ralph-loop` skill | `.agents/skills/ralph-loop/` | skill 能在空 workspace 引导生成 `.ralph/` 结构 |

## T1 范围（当前阶段）

**目标**：实现 ralph run 主循环和 adapter 接口契约，用 fake adapter 跑通最小闭环；不绑任何真实 provider。

### 覆盖的需求

- REQ-001（循环）、REQ-002（TASKS 解析）、REQ-005（adapter 抽象）、REQ-006（证据沉淀）、REQ-008（per-workspace）、REQ-009（.env）、REQ-010（cwd 自定位）、REQ-011（快速失败）、REQ-012（退出原因）、REQ-013（stagnation）、REQ-015（provider 绑定）。

### 具体交付

- `.ralph/lib/run.sh`：`ralph run` 主循环（伪代码见 `docs/architecture/overview.md#运行时伪代码`）
- `.ralph/lib/tasks.sh`：TASKS.md 解析（parse_tasks、count_checked）
- `.ralph/lib/session.sh`：session 采集通用入口、派生视图基础设施
- `.ralph/lib/adapter-fake.sh`：三函数契约 + `RALPH_PROVIDER_CLI` 变量，`RALPH_FAKE_SCENARIO` 五场景：
  - `happy` → 勾第 1 条未勾选任务，`exit=0`（驱动 `done` / `max_iterations`）
  - `stagnation` → 不改 TASKS、不改 git，`exit=0`（驱动 `stagnated`）
  - `crash` → `exit=非零`，诊断为 `unknown`（驱动 `provider_failed`）
  - `api-error` → `exit=非零` + stderr 含 api 错误关键字，诊断为 `api`（驱动 `provider_failed` + `last_error.type=api`）
  - `slow` → `sleep` 远超 `--timeout`（驱动 `timeout`）
- `.ralph/bin/ralph` 增加 `run` 路由（当前只有 `help`）
- `.ralph/lib/common.sh`：扩展 `.env` 解析、uuid 生成、锁获取、git diff 收集
- 集成测试脚本：覆盖 7 个退出原因 + 6 个启动校验失败用例 = 13 个用例（清单见 `task.md` T1 范围段）

### 退出条件

- `bash scripts/check.sh` 通过
- fake provider 集成测试全部通过
- `docs/requirements/ralph-loop/requirements.md` 和 `docs/architecture/overview.md` 无需重写（只做补丁级更新）

### 非 T1 范围

- 不实现 Claude / Codex / Gemini 任何一个真实 adapter（T2-T4）
- 不实现 `status` / `watch`（T5）
- 不写 PROMPT.md / TASKS.md 模板（无 init）
- 不涉及 skill 封装（T7）

## Provider Adapter Scope（T2 / T3 / T4）

每个 T 的共同交付：

- 实现 `provider_oneshot` / `provider_collect_session` / `provider_diagnose` 三函数
- 按 `docs/architecture/integrations.md` 构造 oneshot 命令
- 按 provider 协议采集 session、派生 `chat.log` / `tools.log`
- 按错误诊断矩阵识别 `auth` / `quota` / `rate_limit` / `network` / `api` / `concurrency`（仅 Claude）
- 至少一次真实 workspace 单轮 smoke 验证

## Known Decisions（摘要）

完整 22 条决策在 `requirements/ralph-loop/requirements.md` 的"澄清记录 / 澄清结论"段落。与 roadmap 直接相关的：

- Per-workspace 部署（TC-STK-002）
- `.env` 路径写死 `.ralph/.env`（TC-STK-003）
- 不接受 `--cwd`（TC-STK-004）
- 不默认 resume；每轮 fresh oneshot（SC-001-2）
- 默认值：`max_iter=0`、`timeout=0`、`stagnation_limit=5`
- approval/sandbox 写死在 adapter（NFR-SEC-002）
- `--effort=low\|medium\|high\|none` 抽象（REQ-014）

## Known Risks

| 风险 | 影响 | 缓解 |
|---|---|---|
| Claude `~/.claude/projects/` cwd 哈希规则随版本变 | T2 session 采集失败 | fallback 按 mtime 扫描，记录 warning；在 session capture 测试中锁版本 |
| Gemini `-p` 模式输出不稳定含 session id | T4 session 采集退化 | `architecture/integrations.md` 已定退化规则 |
| Codex `--json` 事件 schema 变动 | T3 错误诊断失准 | 锁 0.121.0 基线，事件 schema 写进 `architecture/integrations.md` 随更新 |
| 三家 provider 同时使 `--allowedTools` / `--sandbox` 语义漂移 | 安全边界失效 | 每次 T2-T4 完成前重新读 provider CLI help，写进 PR 描述 |
| stagnation 误判（agent 改了注释但没改勾选状态） | 提前 `stagnated` | changed_files 并集规则覆盖未提交变更；阈值 5 有冗余 |
| Per-workspace 部署导致多 workspace 升级繁琐 | 使用负担 | T7 skill 封装负责升级/同步，优先级 post-v0.1 |
