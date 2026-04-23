# ralph-loop

`ralph-loop` 是一个 shell-first CLI harness，用 provider CLI 的 fresh oneshot 能力驱动长任务循环执行。它把任务状态、运行日志、退出原因和 provider 原生 session 证据保存在使用者 workspace 的 `.ralph/runs/` 下，让长任务可观察、可恢复、可复盘。

## 定位

- 做什么：提供 `ralph run`、`ralph status`、`ralph watch` 等 CLI 能力，围绕使用者 workspace 的 `.ralph/TASKS.md` 组织多轮 agent oneshot 执行。
- 不做什么：不实现自有 agent 推理、任务规划或代码生成能力；不把 provider session 当作任务完成事实源；不默认 resume provider session；不提供 `ralph init` 或模板生成。
- 谁在用：维护者和 agent 协作者，用于在真实 workspace 中执行长期或多步骤开发任务。

## 当前状态

- 阶段：需求澄清 + 工具骨架重建
- 当前开发任务：`task.md`
- 续接状态：`handoff.md`
- 工具入口：`.ralph/bin/ralph`

## 入口地图

| 想做什么 | 从哪里开始 |
|---|---|
| 查看协作与规格规范 | `.spec/README.md` |
| 查看当前开发任务 | `task.md` |
| 查看项目文档地图 | `docs/README.md` |
| 查看项目级需求 | `docs/requirements.md` |
| 查看 Ralph 需求 | `docs/requirements/ralph-loop/requirements.md` |
| 查看 Ralph 架构 | `docs/architecture/overview.md` |
| 查看 Provider 集成 | `docs/architecture/integrations.md` |
| 查看安全边界 | `docs/architecture/security.md` |
| 运行 Ralph CLI | `.ralph/bin/ralph` |
| 查看 checkpoint | `docs/checkpoints/` |
| 查看 postmortem | `docs/postmortems/` |
| 查看 roadmap | `docs/roadmap.md` |

## 项目边界

- 本仓库是 ralph-loop 工具的**开发工程**，不自用 ralph 驱动自身开发。
- 工具代码位于 `.ralph/bin/`、`.ralph/lib/`；使用者 workspace 的 `.ralph/PROMPT.md` / `.ralph/TASKS.md` / `.ralph/runs/` 是运行态，由使用者自行创建或由运行期生成，不进入本仓库。
- Ralph 需求沉淀在 `docs/requirements.md`（项目级）和 `docs/requirements/ralph-loop/requirements.md`（模块级）；架构和外部集成沉淀在 `docs/architecture/`。
- 当前开发任务写入 `task.md`；长期事实写入 `README.md` 或 `docs/`。
- 新增、移动、重命名或删除项目文档时，同步更新 `docs/README.md` 和本入口。
