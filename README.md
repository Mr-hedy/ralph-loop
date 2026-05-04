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
| Claude CLI (`claude`) | Claude provider CLI —— 参考 [安装文档](https://docs.anthropic.com/en/docs/claude-code) |
| Codex CLI (`codex`) | Codex provider CLI（I2 / T3 已落地） |

### 1. 部署到 workspace

```bash
cp -r <ralph-loop-repo>/.ralph/ <your-workspace>/.ralph/
```

一次性带走 `bin/` + `lib/`（工具代码）+ `PROMPT.md` + `TASKS.md`（参考样板，可裁剪）。

### 2. 配置 workspace

在 workspace 根创建 `.ralph/.env`（最小配置）：

```bash
RALPH_PROVIDER=claude                         # claude / codex
# 可选：
# RALPH_EFFORT=low                       # low / medium / high / none（默认不传）
# RALPH_MAX_ITER=20                      # 最大轮数，0 = 无限（默认 0）
# RALPH_TIMEOUT=3600                     # 超时秒数，0 = 无限（默认 0）
# RALPH_STAGNATION_LIMIT=5               # 连续无进展轮数（默认 5）
# RALPH_MODEL=<name>                     # 覆盖 provider 默认模型
# RALPH_PROVIDER_CONFIG_DIR=~/.claude-x  # 用独立账号 / API 配置跑 ralph
                                         # ralph 自动翻译为 provider 原生变量：
                                         # Claude → CLAUDE_CONFIG_DIR；Codex → CODEX_HOME
                                         # 该目录必须已包含对应 provider 登录态 / 配置
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

### 4. 观察运行

```bash
ralph status                  # plain text：run_id / iter / tasks 进度 / state / exit_reason 等
ralph status --json           # 透传 .ralph/status.json 原始 JSON
ralph watch                   # 实时监控：底部 sticky bar + 上方 iter log tail（2 秒刷新，Ctrl-C 退出）
ralph run -v                  # 重跑时直接把 provider stream 过滤到 stderr
```

无 `-v` 的 `ralph run` 默认仍保持 stdout silent；stderr 会打印 iter 启停 marker。长 provider oneshot 未返回时，每 60 秒打印 heartbeat，包含 elapsed、当前 `provider.stdout.log` 大小和可直接 `tail -f` 的路径。

`ralph watch -v` 通过 `.ralph/status.json` 的当前 `run_id` / `iteration` tail 对应 `provider.stdout.log`；v0.1.1 起 run 会在 provider oneshot 启动前更新 status 到当前 iter，避免 watch 盯到 `iter-000` 或上一轮。

底层文件仍可直接读取：

```bash
cat .ralph/runs/<run_id>/result.json            # 运行总结
ls  .ralph/runs/<run_id>/iterations/            # 每轮明细
cat .ralph/runs/<run_id>/iterations/iter-001/meta.json
```

### 退出原因速查

| exit_reason | exit code | 含义 |
|---|---|---|
| `done` | 0 | 全部任务完成 |
| `provider_failed` | 2 | provider CLI 报错或崩溃 |
| `timeout` | 3 | 单轮执行超时 |
| `max_iterations` | 4 | 达到最大轮数 |
| `stagnated` | 5 | 连续 N 轮无进展 |
| `locked` | 6 | workspace 已有 ralph 在跑（lock） |
| `blocked_by_human` | 7 | 第一个未勾选任务前缀是 `HUMAN-`（等人类决策；不调 provider） |
| `interrupted` | 130 | SIGINT 中断 |
| `startup_failed` | 1 | 依赖缺失或初始化失败 |

退出时 ralph 会向 stderr 打印格式化总结（含 exit_reason / iteration / 完成任务 / 阻塞点 / 接力提示），同时落到 `.ralph/runs/<run_id>/exit-message.txt` 方便复制粘贴给 main agent。

### v0.1 行为说明

- `provider_failed` 一次即终止整 run，不自动重试。transient API 抖动建议重新跑 `ralph run`（lock 已自动释放）。
- 详细架构见 `docs/architecture/overview.md`；provider 集成见 `docs/architecture/integrations.md`。

## 当前状态

- 版本：v0.1.1-dev（v0.1.0 已发布于 2026-04-28；I1/I2 已完成，I3 待启动）
- 当前开发任务：`.ralph/TASKS.md`（dogfood 模式，root `task.md` 已封版）
- 当前 iteration 设计方案：待定（上一轮 I2 设计为 `docs/requirements/ralph-loop/I2-design.md`，归档为 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`）
- 续接状态：`handoff.md`
- 工具入口：`.ralph/bin/ralph`

## 入口地图

| 想做什么 | 从哪里开始 |
|---|---|
| 查看协作与规格规范 | `.spec/README.md` |
| 查看当前开发任务（dogfood） | `.ralph/TASKS.md` |
| 查看 v0.1 历史任务 | `task.md`（已封版） |
| 查看当前 iteration 设计方案 | `docs/requirements/ralph-loop/I<N>-design.md` |
| 查看 iteration 完成归档 | `docs/requirements/ralph-loop/I<N>-FINAL-TASK.md` |
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

- 本仓库是 ralph-loop 工具的**开发工程**。**v0.1 后切换为 dogfood 模式** — 自用 ralph 驱动后续开发；`.ralph/TASKS.md` 是当前任务源（按 iteration 推进）。
- 工具代码位于 `.ralph/bin/`、`.ralph/lib/`；`.ralph/PROMPT.md` + `.ralph/TASKS.md` + `.ralph/TASKS.bak` 入仓；运行时产物 `.ralph/runs/` + `.ralph/lock` + `.ralph/status.json` + `.ralph/.env` gitignore。
- Ralph 需求沉淀在 `docs/requirements.md`（项目级）和 `docs/requirements/ralph-loop/requirements.md`（模块级）；架构和外部集成沉淀在 `docs/architecture/`。
- 当前 iteration 设计方案放 `docs/requirements/ralph-loop/I<N>-design.md`；完成后归档为 `I<N>-FINAL-TASK.md`（cp 自 `.ralph/TASKS.md`）。
- 长期事实写入 `README.md` 或 `docs/`。
- 新增、移动、重命名或删除项目文档时，同步更新 `docs/README.md` 和本入口。
