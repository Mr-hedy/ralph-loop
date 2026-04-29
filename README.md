# ralph-loop

`ralph-loop` 是一个 shell-first CLI harness，用 provider CLI 的 fresh oneshot 能力驱动长任务循环执行。它把任务状态、运行日志、退出原因和 provider 原生 session 证据保存在使用者 workspace 的 `.ralph/runs/` 下，让长任务可观察、可恢复、可复盘。

## 定位

- 做什么：提供 `ralph run`、`ralph status`、`ralph watch` 等 CLI 能力，围绕使用者 workspace 的 `.ralph/TASKS.md` 组织多轮 agent oneshot 执行。
- 不做什么：不实现自有 agent 推理、任务规划或代码生成能力；不把 provider session 当作任务完成事实源；不默认 resume provider session；不提供 `ralph init` 或模板生成。
- 谁在用：维护者和 agent 协作者，用于在真实 workspace 中执行长期或多步骤开发任务。

## 快速开始

### 前置依赖

| 依赖 | 用途 |
|---|---|
| bash 4+ | 运行 ralph |
| git | workspace 变更追踪 |
| jq | meta.json 写入 |
| Claude CLI (`claude`) | provider CLI（v0.1 仅 Claude）—— 参考 [安装文档](https://docs.anthropic.com/en/docs/claude-code) |

### 1. 部署到 workspace

```bash
cp -r <ralph-loop-repo>/.ralph/ <your-workspace>/.ralph/
```

一次性带走 `bin/` + `lib/`（工具代码）+ `PROMPT.md` + `TASKS.md`（参考样板，可裁剪）。

### 2. 配置 workspace

在 workspace 根创建 `.ralph/.env`（最小配置）：

```bash
RALPH_PROVIDER=claude
# 可选：
# RALPH_EFFORT=low        # low / medium / high / none（默认不传）
# RALPH_MAX_ITER=20       # 最大轮数，0 = 无限（默认 0）
# RALPH_TIMEOUT=3600      # 超时秒数，0 = 无限（默认 0）
# RALPH_STAGNATION_LIMIT=5  # 连续无进展轮数（默认 5）
# RALPH_MODEL=<name>      # 覆盖 provider 默认模型
```

按需裁剪 `.ralph/TASKS.md`（样板含 hello-world 示例；ralph 只识别顶层 `- [ ]` / `- [x]`，子 bullet 供 agent 读）。

按需裁剪 `.ralph/PROMPT.md`（样板含循环协议骨架；ralph 内核不依赖此文件）。

建议在 workspace 的 `.gitignore` 加：

```
.ralph/runs/
.ralph/lock
.ralph/status.json
.ralph/.env
```

### 3. 首跑

```bash
cd <your-workspace>
./.ralph/bin/ralph run
```

### 4. 查看结果

```bash
cat .ralph/status.json                          # 当前运行状态
cat .ralph/runs/<run_id>/result.json            # 运行总结
ls  .ralph/runs/<run_id>/iterations/            # 每轮明细
cat .ralph/runs/<run_id>/iterations/iter-001/meta.json
```

（v0.1 没有 `ralph status` / `ralph watch` 真实功能；直接读文件）

### 退出原因速查

| exit_reason | 含义 |
|---|---|
| `done` | 全部任务完成 |
| `stagnated` | 连续 N 轮无进展 |
| `max_iterations` | 达到最大轮数 |
| `timeout` | 超过总超时 |
| `provider_failed` | provider CLI 报错或崩溃 |
| `locked` | workspace 已有 ralph 在跑（lock） |
| `startup_failed` | 依赖缺失或初始化失败 |

### v0.1 行为说明

- `provider_failed` 一次即终止整 run，不自动重试。transient API 抖动建议重新跑 `ralph run`（lock 已自动释放）。
- 详细架构见 `docs/architecture/overview.md`；provider 集成见 `docs/architecture/integrations.md`。

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
