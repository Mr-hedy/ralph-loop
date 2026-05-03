# ralph-loop 文档地图

## 权威事实源

| 主题 | 文档 | 状态 | 说明 |
|---|---|---|---|
| 项目入口 | `../README.md` | 已确认 | 项目定位、入口地图和项目边界 |
| 协作规范 | `../.spec/README.md` | 已确认 | 协作模型、阶段和事实源边界 |
| 当前开发任务 | `../.ralph/TASKS.md` | 已确认 | 当前工程的开发任务事实源（dogfood 模式，按 iteration 推进） |
| v0.1 历史任务 | `../task.md` | 已封版 | T0–T6 历史任务史 + 22 条决策追溯（v0.1.0 发布于 2026-04-28） |
| 当前 iteration 设计 | `requirements/ralph-loop/I2-design.md` | 进行中 | I2（T3 Codex adapter）的启动前方案锚点 |
| Iteration 归档 | `requirements/ralph-loop/I1-FINAL-TASK.md` / `requirements/ralph-loop/I<N>-FINAL-TASK.md` | 历史 | iteration 完成后的不可变任务快照（cp 自 `.ralph/TASKS.md`） |
| 项目级需求 | `requirements.md` | 已确认 | 项目全局目标、跨模块边界和模块索引 |
| 模块需求 | `requirements/ralph-loop/requirements.md` | 已确认 | Ralph harness 模块 REQ-001 ~ REQ-026，22 条决策和 I1 扩展需求完整追踪 |
| 架构 Overview | `architecture/overview.md` | 已确认 | 系统上下文、CLI 契约、运行目录 schema、adapter 函数签名、退出原因、stagnation、lock、错误诊断类别 |
| 架构 Integrations | `architecture/integrations.md` | 已确认 | Claude / Codex / Gemini 原生 session 路径、采集命令、退化策略、UUID 依赖 |
| 架构 Security | `architecture/security.md` | 已确认 | approval/sandbox 固定策略、`.env` 解析约束、secrets 禁入规则、攻击面 |
| Roadmap | `roadmap.md` | 已确认 | T1→T7 阶段目标、验收口径和风险 |
| 部署单元 | `../.ralph/PROMPT.md` / `../.ralph/TASKS.md` / `../.ralph/TASKS.bak` | 已确认 | 部署单元 `.ralph/`（bin/ + lib/ + PROMPT.md + TASKS.md + TASKS.bak）通过 `cp -r .ralph/ <workspace>/.ralph/` 一次性部署；TASKS.bak 是 hello world 样例参考 |
| 使用指南 | `../README.md#快速开始` | 已确认 | 前置依赖、部署、.env 配置、首跑、结果查看、退出原因速查、v0.1 行为说明 |

## 模块索引

| 模块 | 需求 | 业务结构 | 状态 |
|---|---|---|---|
| Ralph harness | `requirements/ralph-loop/requirements.md` | 当前不适用 | 已确认 |

## 架构索引

| 领域 | 文档 | 状态 | 说明 |
|---|---|---|---|
| Overview | `architecture/overview.md` | 已确认 | 系统上下文、稳定契约和架构文档索引 |
| API | `architecture/api.md` | 当前不适用 | Ralph 是 CLI 工具，无 HTTP/RPC API |
| Backend | `architecture/backend.md` | 当前不适用 | Bash 模块结构在 `overview.md#运行目录` 覆盖 |
| Frontend | `architecture/frontend.md` | 当前不适用 | 无前端 |
| Database | `architecture/database.md` | 当前不适用 | 无持久化业务实体；运行期状态在 `.ralph/runs/` |
| UI | `architecture/ui.md` | 当前不适用 | 仅 `ralph watch` 的终端 UI，细节已由 REQ-024 与 `architecture/overview.md` 覆盖 |
| Security | `architecture/security.md` | 已确认 | approval / sandbox、secrets、allowedTools 白名单 |
| Testing | `architecture/testing.md` | 已建立（I1 阶段持续扩展） | 测试入口、基础设施、隔离规则、单一来源、运行平台、当前覆盖范围 |
| Deployment | `architecture/deployment.md` | 当前不适用 | per-workspace 部署在 `overview.md#部署形态` 覆盖 |
| Integrations | `architecture/integrations.md` | 已确认 | Provider CLI 原生 session、oneshot 命令、错误诊断关键字 |

## 运行过程文档

| 类型 | 路径 | 用途 |
|---|---|---|
| Checkpoints | `checkpoints/` | 可回滚、可比较的稳定点记录；不是当前任务事实源 |
| Postmortems | `postmortems/` | 可复用失败模式；不是需求或架构事实源 |

## 阅读入口

| 想了解什么 | 先读 |
|---|---|
| 项目是什么、当前状态 | `../README.md` |
| 当前协作规范和文档结构 | `../.spec/README.md` |
| 当前要执行什么 | `../.ralph/TASKS.md`（dogfood 任务源） |
| 当前 iteration 设计方案 | `requirements/ralph-loop/I2-design.md` |
| v0.1 历史任务 | `../task.md`（已封版） |
| 项目级需求和跨模块约束 | `requirements.md` |
| Ralph harness 模块需求 | `requirements/ralph-loop/requirements.md` |
| Ralph 架构和稳定契约 | `architecture/overview.md` |
| Provider 集成细节 | `architecture/integrations.md` |
| 安全边界 | `architecture/security.md` |
| 阶段规划 | `roadmap.md` |
| 已知失败模式 | `postmortems/README.md` |
| 稳定 checkpoint | `checkpoints/README.md` |

## 维护规则

- 本文件是 `docs/` 唯一文档地图。
- 新增、移动、重命名、废弃或删除 `docs/` 文档时必须同步更新。
- 未确认内容必须标为"待补齐""草案"或"当前不适用"，不能写成已确认事实。
- 需求正文、架构正文、任务计划、review 报告、checkpoint 正文和 postmortem 正文不写在本文件。
