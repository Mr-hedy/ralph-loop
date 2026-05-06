# Roadmap

> Ralph Loop 专项开发阶段目标、优先级、验收口径和风险。
> 权威需求：`docs/requirements/ralph-loop/requirements.md`。

## 编号约定（2026-04-30 起生效）

- **T0–T7 是 v0.1 历史 phase 命名**（已发布 release 范围内的阶段），保留不动作为历史。
- **新阶段统一用 `I` 前缀**（Iteration）：`I1` / `I2` / `I3` ...，每个 iteration 对应一次完整迭代闭环（设计 → 实施 → 验证 → 归档）。
- **第一个新 iteration 是 I1**（dogfood T5），不延续 T0-T7 编号。
- 命名映射：
  - v0.1 release = T0+T1+T2+T6 历史集合（已完成）
  - v0.1.x / v0.2+ release = I1+I2+... 新 iteration 集合（dogfood 模式推进）
- **未实施的历史 phase（T3 / T4 / T5 / T7）后续作为新 iteration 推进，编号与 T 不绑定**：
  - I1 = dogfood T5（status + watch 真实功能）+ HUMAN-N 阻塞机制 + 任务类型路由（已完成，归档见 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`）
  - I2 = T3（Codex adapter）（已完成，归档见 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`）
  - I3 = watch/status 观察面 bugfix（已完成，归档见 `docs/requirements/ralph-loop/I3-FINAL-TASK.md`）
  - I4 = T4（Gemini adapter）（已完成，归档见 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`；设计见 `docs/requirements/ralph-loop/I4-design.md`）
  - I5 = run/watch sticky 输出 + per-task round + env 重组（已完成，归档见 `docs/requirements/ralph-loop/I5-FINAL-TASK.md`；设计见 `docs/requirements/ralph-loop/I5-design.md`）
  - I6 等 = T7 或新议题，由用户在下一轮启动前排序
  - 历史 T 编号仅作为"该 iteration 关联的 v0.1 规划项"出现在 iteration 主题里，不再是 phase 单位

## Current State

- **v0.1 已发布（2026-04-28）**。T6 全部子任务闭环，版本号 `0.1.0`。
- **进入 dogfood 模式（2026-04-30）**：本仓库切换到 `.ralph/TASKS.md` 作为开发任务事实源；root `task.md` 已封版作为 v0.1 历史归档。
- **I1 已完成（2026-05-03）**：dogfood T5（status + watch 真实功能），归档见 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`。
- **I2 已完成（2026-05-04）**：T3（Codex adapter），归档见 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`；设计方案见 `docs/requirements/ralph-loop/I2-design.md`。
- **I3 已完成（2026-05-04）**：watch/status 观察面修复，归档见 `docs/requirements/ralph-loop/I3-FINAL-TASK.md`；checkpoint 为 `2641605 checkpoint: watch status surface fix`。
- **I4 已完成（2026-05-04）**：T4（Gemini adapter），归档见 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`；设计方案见 `docs/requirements/ralph-loop/I4-design.md`。
- **I5 已完成（2026-05-06）**：run/watch sticky 输出 + per-task round + env 重组，归档见 `docs/requirements/ralph-loop/I5-FINAL-TASK.md`；设计方案见 `docs/requirements/ralph-loop/I5-design.md`。
- 协作壳已初始化，`.spec/`、`docs/` 结构稳定。
- Ralph v0.1 需求已收敛为 22 条决策，沉淀在 `requirements.md`（REQ-001 ~ REQ-016）。
- 架构和稳定契约沉淀在 `docs/architecture/overview.md`；provider 集成细节沉淀在 `docs/architecture/integrations.md`；安全边界沉淀在 `docs/architecture/security.md`。
- 工具代码：`.ralph/bin/ralph` + `.ralph/lib/{common,run,session,tasks,adapter-fake,adapter-claude,adapter-codex,adapter-gemini}.sh`；部署单元 `.ralph/PROMPT.md` + `.ralph/TASKS.md`（dogfood 任务源）+ `.ralph/TASKS.bak`（hello world 样例）。
- T1（fake 闭环）、T2（Claude adapter + 单轮真实 smoke）、T6（v0.1 闭环 + 使用指南）均已完成。

## Phased Delivery

| Phase | 目标 | 主要交付 | 验收口径 |
|---|---|---|---|
| T0 Bootstrap | 协作规范、需求、设计、入口文档就位 | `.spec/`、`docs/requirements.md`、`docs/requirements/`、`docs/architecture/`、`scripts/check.sh` | `bash scripts/check.sh` 通过 |
| **T1 Run 骨架 + Adapter 契约 + Fake 实现** | ralph run 主循环 + adapter 三函数契约 + fake adapter 跑通最小闭环 | `.ralph/lib/run.sh` / `tasks.sh` / `session.sh` / `adapter-fake.sh` | fake provider smoke：预置 TASKS，跑到 `exit_reason=done`；stall 和 locked 各有集成测试 |
| T2 Claude Adapter | 把 fake 替换为真实 Claude adapter 实现 | `.ralph/lib/adapter-claude.sh`、chat/tools 派生视图 | 真实 workspace 跑一轮 `--provider=claude`，产生 session + 派生视图 |
| **T6 v0.1 闭环验证 + 使用指南**（提前到 T2 之后）| 用 Claude 单 provider 把多任务长链路、stall、TASKS.md self-mutation、样板/使用指南**整体闭环**；暴露内核未验证假设并就地补丁 | `.ralph/PROMPT.md` + `.ralph/TASKS.md`（部署单元内入仓样板）、`docs/usage.md`、3+ 条 task 真实 smoke、内核 bug fix patches | 真实 multi-task workspace 跑到 `exit_reason=done`；stall / max_round / round_timeout 兜底在真实 Claude 下各触发一次 |
| T3 Codex Adapter（I2 已完成）| 在已闭环的内核上接入 Codex 真实 adapter | `.ralph/lib/adapter-codex.sh` | 真实 workspace 跑一轮 `--provider=codex` |
| T4 Gemini Adapter | 同上，Gemini 实现 | `.ralph/lib/adapter-gemini.sh` | 真实 workspace 跑一轮 `--provider=gemini` |
| T5 Status + Watch（I1 已完成） | 观察性子命令 | `.ralph/lib/status.sh` / `watch.sh` | `ralph status` 一次性输出；`ralph watch` 2 秒刷新 sticky bar |
| T7 Skill 封装（post-v0.1） | `ralph-loop` skill | `.agents/skills/ralph-loop/` | skill 能在空 workspace 引导生成 `.ralph/` 结构 |

### 阶段重排序决策（2026-04-28）

原顺序 T2 → T3 → T4 → T5 → T6 → T7。**用户决策（2026-04-28）**：T2 完成后**优先做 T6（闭环 + 使用指南）**，再回头做 T3/T4/T5。理由：
- 内核（loop / stall / TASKS 解析 / changed_files / done 检测）只在 T1 fake 路径下验过；多 provider 真实接入前先用 Claude 单路径把内核长链路打通，能尽早暴露 adapter 契约不足、PROMPT 协议歧义、stall 误判等系统级问题。
- 若先做 T3/T4 再做 T6，万一闭环暴露 adapter 契约要改，三个 adapter 都得回炉；先 T6 后 T3/T4 一次回炉只动 Claude 一家，成本更低。
- T5（status/watch）暂可由直接读 `.ralph/status.json` 替代；闭环过程中也会逼出 status 真正需要哪些字段，再补 T5 更准。

## Provider Adapter Scope（T2 / T3 / T4）

每个 T 的共同交付：

- 实现 `provider_oneshot` / `provider_collect_session` / `provider_diagnose` 三函数
- 按 `docs/architecture/integrations.md` 构造 oneshot 命令
- 按 provider 协议采集 native session、派生 `session.history.log`
- 按错误诊断矩阵识别 `auth` / `quota` / `rate_limit` / `network` / `api` / `concurrency`（仅 Claude）
- 至少一次真实 workspace 单轮 smoke 验证

## Known Decisions（摘要）

完整 22 条决策在 `requirements/ralph-loop/requirements.md` 的"澄清记录 / 澄清结论"段落。与 roadmap 直接相关的：

- Per-workspace 部署（TC-STK-002）
- `.env` 路径写死 `.ralph/.env`（TC-STK-003）
- 不接受 `--cwd`（TC-STK-004）
- 不默认 resume；每轮 fresh oneshot（SC-001-2）
- 默认值：`max_round=0`、`round_timeout=0`、`stall_limit=5`
- approval/sandbox 写死在 adapter（NFR-SEC-002）
- `--effort=low\|medium\|high\|none` 抽象（REQ-014）

## T6 范围（提前的当前阶段）

**目标**：用 Claude 单 provider 把 v0.1 内核的多任务长链路、stall 真触发、TASKS.md self-mutation、PROMPT 协议参考模板、使用指南整体闭环。**不引入新内核能力**——T6 是"暴露未验证假设并就地补丁"的阶段。

### 覆盖的需求

- REQ-001 ~ REQ-013（闭环验证全部 P0 需求在真实 Claude 下落地）。
- REQ-016 / SC-001-1（多任务 smoke 端到端）。
- 样板与使用指南（requirements §非目标 line 23 约束 ralph 工具运行时不 init / 不生成模板；REQ-017 明确 `.ralph/` 部署单元含 PROMPT/TASKS 样板入仓由 `cp -r` 部署，由人工维护，不是工具 init 路径）。

### 具体交付

- `.ralph/PROMPT.md` + `.ralph/TASKS.md`：作为部署单元 `.ralph/` 的一部分入仓的参考样板。PROMPT.md 是 provider-agnostic 循环协议，承载"一个 task 一个 oneshot"硬约束、TASKS self-mutation 规则（append-only / 不删 / 不伪 `[x]`）、agent 身份澄清（不 schedule 自己 / 不 spawn 例行 subagent）、退出语义说明；**不**烧入 role 系统 / questions hard-block / conductor 概念（属用户业务域扩展，最多注释引用 trantor PROMPT.md 作为外部例子）。TASKS.md 是 ≤20 行 hello-world 起手示例。使用者部署 ralph 时通过 `cp -r .ralph/ <workspace>/.ralph/` 一并带走，按需裁剪。
- `docs/usage.md`（或 `README.md` quickstart 节）：用户 workspace 三件套准备步骤、模板 copy 路径、首跑期望。
- 真实 multi-task smoke：3+ 条独立小任务（每条产生真实 file diff）的 TASKS.md，Claude 全程跑通到 `exit_reason=done`。
- 边界场景真实验证：stall 真触发（agent 一轮不动）、max_round 兜底、round_timeout 兜底——T1 fake 验过的兜底逻辑在 Claude 真实长链路下重新验一次。
- 内核 bug fix patches（如 T6 暴露假设不成立则就地修，不预先扩功能）。

### 退出条件

- `bash scripts/check.sh && bash scripts/integration-test.sh` 通过。
- 真实 multi-task smoke `exit_reason=done`，证据贴 `task.md`。
- stall / max_round / round_timeout 在 Claude 真实环境各触发一次并记录证据。
- `docs/usage.md` 可让一个新使用者照着把 workspace 准备好并跑通首轮。

### 非 T6 范围

- 当时不实现 Codex / Gemini adapter（已后续由 I2 / I4 完成）。
- 当时不实现 `status` / `watch` 子命令（已后续由 I1 完成）。
- 不做 ralph init / 不让 ralph 工具运行时写 PROMPT.md 或 TASKS.md（requirements §非目标 line 23；样板入仓属交付配置，由 REQ-017 管辖，与 init 不冲突）。
- 不引入 conductor / STATUS.md / role 系统等业务域扩展。

## Deferred (post-v0.1)

- `ralph doctor` 子命令 + provider 版本兼容性矩阵：T2.0 引入的依赖校验框架（`ralph_require_cmd`）已预留 `min_version` 参数位，doctor 实现按需补充，不需要重构现有调用。后置到 v0.2 或并入 T7 skill 封装。

## Known Risks

| 风险 | 影响 | 缓解 |
|---|---|---|
| Claude `~/.claude/projects/` cwd 哈希规则随版本变 | T2 session 采集失败 | fallback 按 mtime 扫描，记录 warning；在 session capture 测试中锁版本 |
| Gemini `-p` 模式输出不稳定含 session id | T4 session 采集退化 | `architecture/integrations.md` 已定退化规则；I4 DEV-1 先用 Gemini CLI 0.39.1 + 官方 docs 重新校准 |
| Gemini CLI flag 漂移（`--yolo` deprecated、effort 映射未确认） | T4 命令构造或 docs 误导用户 | I4 DEV-1 必须先同步 requirements / integrations / overview，再写 adapter |
| Codex `--json` 事件 schema 变动 | Codex 错误诊断失准 | I2 已按本机 Codex CLI `0.125.0` 校准，事件 schema 写进 `architecture/integrations.md` 随更新 |
| 三家 provider 同时使 `--allowedTools` / `--sandbox` 语义漂移 | 安全边界失效 | 每次 T2-T4 完成前重新读 provider CLI help，写进 PR 描述 |
| stall 误判（agent 改了注释但没改勾选状态） | 提前 `blocked_by_human` | changed_files 并集规则覆盖未提交变更；阈值 5 有冗余 |
| Per-workspace 部署导致多 workspace 升级繁琐 | 使用负担 | T7 skill 封装负责升级/同步，优先级 post-v0.1 |
