# `.ralph/` 部署单元使用指南

`.ralph/` 是 ralph-loop 工具的**完整部署单元**——使用者通过 `cp -r .ralph/ <workspace>/.ralph/` 一次性带走所有内容到自己的 workspace，按需裁剪 `.ralph/TASKS.md` 和补 `.ralph/.env` 即可使用。

> 本仓库自身也用 `.ralph/` 驱动开发（dogfood 模式）。

## 目录结构

```
.ralph/
├── README.md              ← 本文件
├── PROMPT.md              ← 循环协议（每轮发给 provider 的 system prompt 主体）
├── TASKS.md               ← 任务事实源（按 .spec/rules/tasks.md 结构）
├── TASKS.bak              ← hello world 部署样例参考（不被 ralph 识别）
├── .env                   ← 私有配置（gitignored）
├── .gitignore             ← 自包含规则（cp -r 时跟随生效）
├── bin/
│   └── ralph              ← CLI 入口
├── lib/
│   ├── common.sh          ← 通用函数（lock / uuid / 时间戳 / .env 加载）
│   ├── run.sh             ← ralph run 主循环
│   ├── status.sh          ← ralph status 渲染
│   ├── watch.sh           ← ralph watch sticky 模式入口
│   ├── sticky.sh          ← 三段式 sticky renderer（run -v / watch 共用）
│   ├── tasks.sh           ← TASKS.md 解析 + HUMAN-N 扫描
│   ├── session.sh         ← meta.json 读写骨架
│   ├── adapter-claude.sh  ← Claude provider adapter
│   ├── adapter-codex.sh   ← Codex provider adapter
│   ├── adapter-gemini.sh  ← Gemini provider adapter
│   └── adapter-fake.sh    ← fake adapter（测试用）
├── runs/                  ← 运行期产物（gitignored）
│   └── <run_id>/...
├── status.json            ← 当前活跃 run 指针（gitignored）
└── lock                   ← 运行时锁（gitignored）
```

## Ralph loop 与 round

- **Loop (Run)**: 一个完整的任务序列执行过程，从 `ralph run` 启动到所有任务完成或中断。
- **Round**: Loop 的一次物理迭代（Provider 的一次 Oneshot 调用）。
- **关系**: 一个 Task 可能需要多个 Round 才能完成。Ralph 会跟踪 **per-task round** 计数（try），并在 TUI 底栏或进度 marker 中显示（如 `round 2/∞`）。

## 三个子命令

### `ralph run`

主循环：反复调 provider CLI fresh oneshot，每轮处理一个任务。

```bash
.ralph/bin/ralph run                          # 默认 plain 模式（agent/CI 友好）
.ralph/bin/ralph run -v                       # 启用 sticky TUI（人类友好，10 行 sticky 块）
.ralph/bin/ralph run --provider claude        # CLI 覆盖 RALPH_PROVIDER
.ralph/bin/ralph run --max-round 10           # 限制单任务最多 10 轮
.ralph/bin/ralph run --round-timeout 600      # 单轮 600 秒超时
.ralph/bin/ralph run --stall-limit 3          # 连续 3 轮无进展自动插 HUMAN
.ralph/bin/ralph run --max-retry 3            # Provider 暂时性错误自动重试次数
.ralph/bin/ralph help run                     # 完整帮助
```

**默认输出（plain 模式，stderr）**：
追加式纯文本，无 ANSI 控制码，每行独立可 grep。仅打印 ralph 核心 marker（启动 banner、round 启停、60s heartbeat、退出总结）。

**Sticky 模式（`-v`，仅 TTY）**：
10 行紧凑 sticky 块，包含顶栏（任务进度/全局 round/elapsed）、事件区（最近 6 条 tool/chat 事件流）、底栏（健康灯/per-task round/stall 计数/当前任务名）。

### `ralph status`

一次性快照，不刷新。

```bash
.ralph/bin/ralph status                      # plain text，默认
.ralph/bin/ralph status --json               # 字节透传 status.json
```

### `ralph watch`

持续刷新（200ms 间隔），始终使用 sticky TUI（仅 TTY）。

```bash
.ralph/bin/ralph watch                       # 观察当前活跃 run
.ralph/bin/ralph watch --help                # 完整帮助
```

## 防死循环机制（双保险 + 自动插 HUMAN）

为了防止 Agent 在死胡同里空转，Ralph 实现了 per-task 的防死循环保护：

1. **Max Round**: 同一个任务尝试次数超过 `RALPH_LOOP_MAX_ROUND`（默认 0=无限）。
2. **Stall Limit**: 同一个任务连续 `RALPH_LOOP_STALL_LIMIT`（默认 5）次 round 既没勾掉任务也没改动代码。

**触发后果**:
Ralph 会自动在 `.ralph/TASKS.md` 当前任务**之前**插入一个 `HUMAN-N` 任务，并以 `blocked_by_human` 退出。人类在对话中修复问题（如修改任务描述）并勾掉 HUMAN 任务后，重跑 `ralph run` 即可继续。

## 环境配置 (`.ralph/.env`)

环境变量按功能分为三组。优先推荐使用 CLI flag，但 `.env` 可用于持久化配置。

| 分类 | 变量名 | 默认值 | 说明 |
|------|-------|-------|------|
| **Provider** | `RALPH_PROVIDER` | `claude` | 使用的 adapter (claude/codex/gemini/fake) |
| | `RALPH_PROVIDER_MODEL` | - | 覆盖 provider 默认模型 |
| | `RALPH_PROVIDER_EFFORT` | - | 推理强度 (low/medium/high/none) |
| | `RALPH_PROVIDER_CONFIG_DIR` | - | Provider 配置目录隔离 |
| **Loop** | `RALPH_LOOP_MAX_ROUND` | `0` | 单个任务的最大 round 数 (0=无限) |
| | `RALPH_LOOP_ROUND_TIMEOUT`| `0` | 单个 round 的超时秒数 (0=无限) |
| | `RALPH_LOOP_STALL_LIMIT` | `5` | 单个任务连续无进展轮数上限 |
| | `RALPH_LOOP_MAX_RETRY` | `3` | Provider 暂时性错误 (429/网络) 的重试次数 |
| | `RALPH_LOOP_RETRY_SCHEDULE`| `60 120 300`| 重试等待秒数序列 (秒，空格分隔) |
| **UI** | `RALPH_UI_STICKY_EVENT_LINES`| `6` | Sticky 模式事件区可见行数 |
| | `RALPH_UI_HEALTH_GREEN_SEC` | `60` | 健康灯变黄的静默秒数 |
| | `RALPH_UI_HEALTH_RED_SEC` | `300` | 健康灯变红的静默秒数 |

## Agent 调用最佳实践

- **默认调用**: Agent 应直接执行 `ralph run`。其 plain 模式输出紧凑且易于解析，不会浪费 context 存储 ANSI 控制码。
- **任务定义**: 确保 `.ralph/TASKS.md` 中的任务描述清晰，避免导致 Agent 进入 stall 状态。

## Sticky 模式救援

如果 `ralph run -v` 或 `ralph watch` 异常崩溃（例如被 `kill -9` 或 SSH 断开），终端可能处于 `noecho` 状态（打字不显示）。
**执行以下命令恢复**:
```bash
stty sane
```

## round 目录结构（4 文件契约）

每轮 oneshot 在 `.ralph/runs/<run_id>/rounds/round-NNN/` 产出 4 个文件：

| 文件 | 内容 |
|---|---|
| `meta.json` | 元数据（session_id / runtime_block / tasks_before / tasks_after / changed_files / stall_count / retry_count） |
| `provider.stdout.log` | provider CLI stdout + stderr 合流（原始 stream-json/JSONL 事件） |
| `session.<provider>.json` | provider 原生 session 副本（JSON/JSONL 格式） |
| `session.history.log` | 跨 provider 人话视图（assistant / thinking / tool_use / tool_result） |

## 退出原因

| exit_reason | exit code | 触发条件 |
|---|---|---|
| `done` | 0 | TASKS.md 全部完成 |
| `provider_failed` | 2 | Provider 彻底失败（超重试次数或不可重试错误） |
| `timeout` | 3 | 单轮超时 |
| `blocked_by_human` | 7 | 遇到 HUMAN-N 任务或触发防死循环自动插入 |
| `locked` | 6 | 已有 run 在运行 |
| `interrupted` | 130 | SIGINT / SIGTERM |
| `startup_failed` | 1 | 启动校验失败（配置错误/任务格式错误） |

## 相关文档

- 协议规范：`.spec/rules/`（requirements / solution / roadmap / tasks / testing / review / adversarial-review）
- 架构：`docs/architecture/{overview,integrations,security,testing}.md`
- 需求：`docs/requirements/ralph-loop/requirements.md`
- 路线：`docs/roadmap.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`
