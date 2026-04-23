# ralph-loop 项目级需求

> 项目级全局目标、全局边界和模块索引。模块内部 `REQ-*` / `SC-*` / `BPF-*` / `FR-*` 追踪链落在各自模块需求文档中。

## 项目定位

`ralph-loop` 是一个 shell-first CLI harness 工具项目。它为使用者 workspace 提供一组 shell 命令（`ralph run` / `ralph status` / `ralph watch`），用 provider CLI 的 fresh oneshot 循环驱动长任务执行，把任务状态、运行日志、退出原因和 provider 原生 session 证据沉淀到使用者 workspace 的 `.ralph/` 目录下。

本仓库是 ralph-loop 工具**本身**的开发工程，**不**使用 ralph 驱动自身开发。

## 全局目标

- 提供一个可被 coding agent 或维护者调用的 shell 工具，让长任务在多轮 fresh oneshot 中可观察、可恢复、可复盘。
- 覆盖 Claude Code、Codex CLI、Gemini CLI 三家 provider，通过统一 adapter 抽象解耦 provider 差异。
- 工具本身以 shell 实现,降低部署和运行环境成本；不引入包管理器、编译步骤或额外 runtime。
- 项目文档、方案取舍和实现任务按 `.spec/` 规范沉淀，让后续迭代有稳定事实源。

## 全局非目标

- 不实现自有 agent 推理、任务规划或代码生成能力；ralph 只是 harness，不是 agent。
- 不提供任何项目脚手架或模板生成（无 `ralph init`）；使用者自行创建 workspace 内的 `.ralph/PROMPT.md` / `.ralph/TASKS.md` / `.ralph/.env`。
- 不支持全局 `ralph` 命令；工具以 per-workspace 方式分发，每个 workspace 自带 `.ralph/bin/ralph` + `.ralph/lib/*`。
- 不在本仓库内自举（不用 ralph 驱动 ralph-loop 的开发）。
- 不把 provider 原生 session 当作任务完成事实源。
- 不默认 resume provider session；每轮都是 fresh oneshot。
- 不引入数据库，不依赖完整 Markdown parser，不做复杂 TUI。

## 全局角色

- **维护者**：直接在使用者 workspace 手动跑 `ralph run`，并据产物复盘。
- **coding agent 协作者**：通过 Bash 工具调用 `ralph run` 驱动长任务。
- **ralph 工具开发者**（本仓库）：按项目事实源迭代工具本身。

## 跨模块约束

以下约束适用于整个项目，所有模块必须遵守：

- **Shell-first**：工具代码全部用 Bash 实现；不得引入 Node.js、Python、Go 等额外 runtime 作为运行期依赖。
- **Per-workspace 部署**：工具以 `.ralph/bin/` + `.ralph/lib/` 方式随 workspace 分发；不维护全局安装入口。
- **Workspace 根由脚本路径决定**：ralph 脚本启动时通过 `${BASH_SOURCE[0]}` 解析 workspace 根，内部 `cd` 到该目录；不接受 `--cwd` 参数。
- **`.env` 路径写死**：`.ralph/.env` 是唯一配置来源，只读 `RALPH_*` 前缀字段。
- **本仓库不自举**：本仓库是开发工程，不创建 `.ralph/PROMPT.md` / `.ralph/TASKS.md`，不用 ralph 跑自身。
- **协作规范与项目事实分离**：协作方法与文档结构在 `.spec/`，项目事实在 `README.md` / `docs/` / 代码。
- **敏感信息不入仓**：secrets、完整凭据、会话 transcript 不写入 `docs/` / `handoff.md` / checkpoint / postmortem / 任务源。

## 模块索引

| 模块 | 角色 | 需求 | 业务结构 | 状态 |
|---|---|---|---|---|
| Ralph harness | 当前唯一核心模块；提供 `ralph run/status/watch` 和 provider adapter | [`requirements/ralph-loop/requirements.md`](./requirements/ralph-loop/requirements.md) | 当前不适用（命令行工具，无持久化业务实体） | 已确认 |

## 全局验收口径

项目级验收由模块验收汇总构成，当前：

- Ralph harness 模块的 `SC-*` 全部通过 → 项目当前阶段（v0.1）验收达成。
- 模块之外的跨模块端到端验证入口：`bash scripts/check.sh`（结构性回归）+ 各模块声明的集成测试。

## 架构与专题

- 系统总体架构与稳定契约：[`architecture/overview.md`](./architecture/overview.md)。
- 外部系统集成（Claude / Codex / Gemini session 采集）：[`architecture/integrations.md`](./architecture/integrations.md)。
- 安全边界（approval / sandbox 策略）：[`architecture/security.md`](./architecture/security.md)。
- 阶段规划：[`roadmap.md`](./roadmap.md)。

## 变更影响

项目级需求变化时必须同步检查：

- 各模块需求文档（`requirements/<module>/requirements.md`）——是否触发 `REQ-*` 增删或状态变化。
- `docs/architecture/**`——是否触发稳定契约调整。
- `docs/roadmap.md`——是否触发阶段或优先级变化。
- `README.md` / `docs/README.md`——文档地图是否需要刷新。
- 根 `task.md`——当前开发任务是否需要调整。
