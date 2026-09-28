# ralph-loop 文档地图

## 权威事实源

| 主题 | 文档 | 状态 | 说明 |
|---|---|---|---|
| 项目入口 | `../README.md` | 已确认 | 项目定位、入口地图和项目边界 |
| 协作规范 | `../.spec/README.md` | 已确认 | 协作模型、阶段和事实源边界 |
| 当前开发任务 | `../.ralph/TASKS.md` | 执行中 | 本仓库 dogfood 的唯一任务事实源；release 构建另生成空模板，不复制这里的任务状态 |
| v0.1 历史任务 | `../task.md` | 已封版 | T0–T6 历史任务史 + 22 条决策追溯（v0.1.0 发布于 2026-04-28） |
| 历史 I<N> 设计与归档 | `features/ralph-loop/history/index.md` | 历史 | I1–I5 启动前设计与已完成任务快照；I<N> 是文档索引，不属于 runtime 契约 |
| 早期任务协议 | `research/task-protocol-legacy-2026-04.md` | 历史 | 仅用于理解早期 `task.md` 协作方式；现行规则见 `.spec/rules/TASKS.md` |
| 项目级需求 | `requirements.md` | 已确认 | 项目全局目标、跨模块边界和模块索引 |
| Vibecoding 协作需求 | `features/vibecoding-collaboration/requirements.md` | 已确认 | Codex Main Agent、Ralph 黑盒执行、用户触发验收、handoff/checkpoint/postmortem 边界，REQ-033 ~ REQ-047 |
| Ralph 模块需求 | `features/ralph-loop/requirements.md` | 已确认 | Ralph harness 模块 REQ-001 ~ REQ-032 及历史决策追踪 |
| 架构 Overview | `architecture.md` | 已确认 | 总体系统入口；Ralph CLI 契约、运行目录 schema、adapter 函数签名、退出原因、stagnation、lock、错误诊断类别 |
| Vibecoding 协作方案 | `features/vibecoding-collaboration/solution.md` | 草案 | Codex Main Agent 控制面、Ralph 后台执行面、用户触发验收和长期协作记忆 |
| 外部集成 | `integrations.md` | 已确认 | Claude / Codex 原生 session 路径、采集命令、退化策略、UUID 依赖（Gemini 段落为暂停接入的历史契约） |
| 安全边界 | `security.md` | 已确认 | approval/sandbox 固定策略、`.env` 解析约束、secrets 禁入规则、攻击面 |
| 测试规范 | `testing.md` | 已建立（持续维护） | 测试入口、基础设施、隔离规则、运行平台和当前覆盖范围 |
| Roadmap | `roadmap.md` | 已确认 | T1→T7 阶段目标、验收口径和风险 |
| 发布包 | `../release/<version>/` | 已确认 | 对外部署使用同一项目版本的生成目录；当前包内容以构建脚本和实际受版本控制文件为准，开发工程运行数据不进入包 |
| 使用指南 | `../README.md#快速开始` | 已确认 | 前置依赖、部署、.env 配置、首跑、结果查看、退出原因速查、v0.1 行为说明 |

## 模块索引

| 模块 | 需求 | 业务结构 | 状态 |
|---|---|---|---|
| Vibecoding collaboration | `features/vibecoding-collaboration/requirements.md` | 流程和状态边界见需求文档 | 已确认 |
| Ralph harness | `features/ralph-loop/requirements.md` | 当前不适用 | 已确认 |

## 架构索引

| 领域 | 文档 | 状态 | 说明 |
|---|---|---|---|
| Overview | `architecture.md` | 已确认 | 系统上下文、稳定契约和架构文档索引 |
| Vibecoding Collaboration | `features/vibecoding-collaboration/solution.md` | 草案 | Main Agent 协作、后台派发、用户触发验收、handoff/checkpoint/postmortem 边界 |
| API | — | 当前不适用 | Ralph 是 CLI 工具，无 HTTP/RPC API |
| Backend | — | 当前不适用 | Bash 模块结构在 `architecture.md#运行目录` 覆盖 |
| Frontend | — | 当前不适用 | 无前端 |
| Database | — | 当前不适用 | 无持久化业务实体；运行期状态在 `.ralph/runs/` |
| UI | — | 当前不适用 | 仅 `ralph watch` 的终端 UI，细节已由 REQ-024 与 `architecture.md` 覆盖 |
| Security | `security.md` | 已确认 | approval / sandbox、secrets、allowedTools 白名单 |
| Testing | `testing.md` | 已建立（持续维护） | 测试入口、基础设施、隔离规则、单一来源、运行平台、当前覆盖范围 |
| Deployment | — | 当前不适用 | per-workspace 部署在 `architecture.md#部署形态` 覆盖 |
| Integrations | `integrations.md` | 已确认 | Provider CLI 原生 session、oneshot 命令、错误诊断关键字 |

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
| 当前要执行什么 | 用户请求、`../handoff.md`、显式任务清单 |
| 当前 dogfood 任务 | `../.ralph/TASKS.md` |
| v0.1 历史任务 | `../task.md`（已封版） |
| 项目级需求和跨模块约束 | `requirements.md` |
| Codex Main Agent vibecoding 协作需求 | `features/vibecoding-collaboration/requirements.md` |
| Ralph harness 模块需求 | `features/ralph-loop/requirements.md` |
| Vibecoding 协作技术方案 | `features/vibecoding-collaboration/solution.md` |
| Ralph 架构和稳定契约 | `architecture.md` |
| Provider 集成细节 | `integrations.md` |
| 安全边界 | `security.md` |
| 阶段规划 | `roadmap.md` |
| 已知失败模式 | `postmortems/README.md` |
| 稳定 checkpoint | `checkpoints/README.md` |

## 维护规则

- 本文件是 `docs/` 唯一文档地图。
- 旧 `requirements/`、`architecture/` 和 `collaboration/` 目录已移除；历史快照中的旧路径仅记录当时状态。现行内容只在本地图列出的路径维护。
- 新增、移动、重命名、废弃或删除 `docs/` 文档时必须同步更新。
- 未确认内容必须标为“待补齐”“草案”或“当前不适用”，不能写成已确认事实。
- 需求正文、架构正文、任务计划、review 报告、checkpoint 正文和 postmortem 正文不写在本文件。
