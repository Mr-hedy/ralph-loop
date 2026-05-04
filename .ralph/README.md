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
├── bin/
│   └── ralph              ← CLI 入口
├── lib/
│   ├── common.sh          ← 通用函数（lock / uuid / 时间戳 / .env 加载）
│   ├── run.sh             ← ralph run 主循环
│   ├── status.sh          ← ralph status 渲染
│   ├── watch.sh           ← ralph watch sticky bar + optional tail
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

## 三个子命令

### `ralph run`

主循环：反复调 provider CLI fresh oneshot，每轮处理一个任务。

```bash
.ralph/bin/ralph run                          # 用 .env 配置启动
.ralph/bin/ralph run --provider claude        # CLI 覆盖 RALPH_PROVIDER
.ralph/bin/ralph run --provider codex         # 使用 Codex adapter
.ralph/bin/ralph run --provider gemini        # 使用 Gemini adapter
.ralph/bin/ralph run --max-iter 10            # 限制最多 10 轮
.ralph/bin/ralph run --timeout 600            # 单轮 600 秒超时
.ralph/bin/ralph run --effort high            # 高 reasoning effort
.ralph/bin/ralph run --stagnation-limit 3     # 连续 3 轮无进展退出
.ralph/bin/ralph run -v                       # 启用 live tail（agent 行为实时打到 stderr）
.ralph/bin/ralph help run                     # 完整帮助
```

**默认输出（无 `-v`，stderr）**：

```
[09:10:00] ralph 0.1.1-dev | run 20260502-091000-abc1234 | I1 | tasks 0/13 done | provider claude
[09:10:00] iter 1/∞ → DEV-1: 实现 ralph status plain text 输出
[09:11:00] iter 1/∞ still running | elapsed 60s | provider log 43821 bytes/12 lines | tail -f .ralph/runs/20260502-091000-abc1234/iterations/iter-001/provider.stdout.log
[09:28:54] iter 1/∞ ✓ done | tasks 1/13 | iter 18m54s | run 18m54s
[09:28:54] iter 2/∞ → DEV-2: 实现 ralph status --json 透传
...
```

**`-v` 模式额外输出**：每轮 oneshot 期间，stream-json events 实时过滤打印。Claude：`💭 thinking` / `💬 text` / `🔧 tool_use` / `⏎ result` / `❌ error`；Codex：`💬 text` / `🔧 tool_use` / `⏎ result` / `❌ error`；Gemini：`⚙ init` / `💬 message` / `🔧 tool_use` / `⏎ result` / `❌ error`。

退出时打印 `exit-message.txt` 内容（含 `Ralph Run Complete` banner + 接力提示），同时落到 `runs/<run_id>/exit-message.txt`。

### `ralph status`

一次性快照，不刷新。

```bash
.ralph/bin/ralph status                      # plain text，默认
.ralph/bin/ralph status --json               # 字节透传 status.json
```

无活跃 run 时输出"无运行中/已结束的 run"，exit 0。

### `ralph watch`

持续刷新（固定 2 秒间隔），仅 Ctrl-C 退出。

```bash
.ralph/bin/ralph watch                       # 仅 sticky bar
.ralph/bin/ralph watch -v                    # sticky bar + 上方 iter log live tail
.ralph/bin/ralph watch | cat                 # 非 TTY 输出一次 one-line watch bar
```

行为：
- run 自然结束（`state=finished`）后**不自动退出**，最后一帧持续刷新
- 启用 `-v` 时，status.json `run_id` 变化触发 separator + 切换 tail 目标
- 终端窄度 < 80 列时 sticky bar 字段截断（如 `run_id` 显前 12 位）
- 彩色按 `isatty(stdout) && [ -z "$NO_COLOR" ]` 自动检测

## `.env` 格式

`.ralph/.env` 是私有配置（gitignored），ralph 启动时按行解析，仅识别 `RALPH_*` 前缀。

```bash
# 必需
RALPH_PROVIDER=claude              # claude / codex / gemini

# 可选（留空或注释 = 不传 flag，provider 走自身默认）
RALPH_MODEL=                       # 覆盖 provider 默认模型
RALPH_EFFORT=                      # low / medium / high / none
RALPH_MAX_ITER=                    # 0 = 无限（默认）
RALPH_TIMEOUT=                     # 单轮超时秒数；0 = 无限（默认）
RALPH_STAGNATION_LIMIT=5           # 连续无进展轮数（默认 5）

# Provider 配置目录隔离（中立抽象，REQ-022）
# adapter 在 source 时翻译为 provider 原生变量：
#   Claude → CLAUDE_CONFIG_DIR
#   Codex → CODEX_HOME
#   Gemini → GEMINI_CLI_HOME
RALPH_PROVIDER_CONFIG_DIR=~/.claude-glm    # tilde 自动展开为 $HOME

# 调试
# RALPH_VERBOSE=1                  # 等同于 ralph run -v；默认未设
# RALPH_PROGRESS_HEARTBEAT_SEC=60  # 默认 heartbeat；0 = 关闭
```

加载规则：
- 路径写死 `.ralph/.env`（相对 ralph 脚本位置）
- 不执行 shell 语句（不 `source`，行级解析），避免 `.env` 变成 RCE 入口
- 仅 export `RALPH_*` 前缀的 key
- 注释 `#` 和空行忽略
- 字符串值两端自动剥离单/双引号
- `~/` 开头的值自动展开为 `${HOME}/...`
- 优先级：CLI flag > 进程环境变量 > `.env` > adapter 内置默认

## iter 目录结构（4 文件契约）

每轮 oneshot 在 `.ralph/runs/<run_id>/iterations/iter-NNN/` 产出 4 个文件：

| 文件 | 内容 |
|---|---|
| `meta.json` | 元数据（session_id / provider_started_at / runtime_block / capture_status / error / 任务进度 / changed_files / stagnation_count） |
| `provider.stdout.log` | provider CLI stdout + stderr 合流（Claude stream-json events / Codex JSONL events / Gemini stream-json events） |
| `session.<provider>.jsonl` | provider 原生 session 副本（Claude `~/.claude/projects/...` / Codex `~/.codex/sessions/...`），保留 30 天后过期 + 派生 bug 回滚 anchor；Gemini 为 `session.gemini.json`（JSON 格式，非 JSONL） |
| `session.history.log` | 跨 provider 人话视图（Claude 含 user / assistant / thinking / tool_use / tool_result；Codex 含 assistant / tool_use / tool_result；Gemini 含 assistant / tool_use / tool_result），Claude 从 `session.claude.jsonl` 派生，Codex 从 `provider.stdout.log` 派生，Gemini 从 `provider.stdout.log` 派生 |

**复盘建议**：
- 看 agent 在做什么 → `cat session.history.log`
- 看 provider CLI 错误 → `cat provider.stdout.log`
- 看完整事件流 → `cat session.<provider>.jsonl | jq -c .`
- 看 iter 元数据 → `cat meta.json | jq`

## 退出原因（8 种）

每次 `ralph run` 退出会写明 `exit_reason`，对应 exit code：

| exit_reason | exit code | 触发条件 | 接力建议 |
|---|---|---|---|
| `done` | 0 | TASKS.md 全部 `[x]` | 归档 iteration |
| `provider_failed` | 2 | provider CLI 退出码非 0 或 is_error=true | 看 `result.json.last_error` 诊断 |
| `timeout` | 3 | 单轮 oneshot 超 `--timeout` 秒 | 拆任务 / 调超时 / 排查 provider 性能 |
| `max_iterations` | 4 | 总轮次超 `--max-iter` | 评估剩余任务 / 提高 max-iter 重跑 |
| `stagnated` | 5 | 连续 N 轮无文件变更且无任务勾选 | 检查任务描述 / agent 行为 / PROMPT 协议 |
| `locked` | 6 | 同 workspace 已有 run 在跑 | 等待或清理 stale lock |
| `blocked_by_human` | 7 | 第一个未勾选任务前缀是 `HUMAN-` | 在 main agent 对话里和人类协作回答，勾掉 HUMAN-N，重跑 |
| `interrupted` | 130 | SIGINT / SIGTERM | 直接重跑 |
| `startup_failed` | 1 | 启动校验失败（含前缀格式错误） | 修 workspace 文件 / 前缀全大写 |

`locked` 和 `startup_failed` **不产生** run 目录；其他都会写 `runs/<run_id>/result.json`。

## 启动校验（快速失败）

ralph 启动时检查（任一失败立即 exit 1，不创建 run 目录）：

1. `.ralph/PROMPT.md` 存在
2. `.ralph/TASKS.md` 存在
3. `.ralph/.env` 存在 + `RALPH_PROVIDER` 非空
4. workspace 是 git 仓库（`.git/` 目录存在）
5. provider CLI 在 PATH 中可执行
6. TASKS.md 任务前缀全大写（违反 `^[A-Z]+-[0-9]+:` 视为 startup_failed）
7. Claude provider 时额外校验 UUID 生成器可用（`uuidgen` / `/proc/sys/kernel/random/uuid` / `python3 -c uuid.uuid4()` 三路至少一路）

## Provider 配置目录隔离（dogfood 推荐）

**场景**：本仓库 dogfood 时跑 ralph，可用独立 provider config dir，避免占用 main agent 的 provider 登录态或 usage limit。

```bash
# 一次性准备：登录独立账号（OAuth）
CLAUDE_CONFIG_DIR=~/.claude-glm claude /login

# 在 .ralph/.env 加：
echo 'RALPH_PROVIDER_CONFIG_DIR=~/.claude-glm' >> .ralph/.env

# 后续 ralph run 自动用独立账号
.ralph/bin/ralph run
```

session 文件落到 `~/.claude-glm/projects/...`，main agent 的 `~/.claude/projects/` 不受影响。adapter 自动从该路径采集 session（REQ-022 / SC-022-3）。

Codex 同一抽象会翻译为 `CODEX_HOME`：

```bash
# 一次性准备：让该目录拥有 Codex 登录态 / auth 配置
CODEX_HOME=~/.codex-ralph codex login

# 在 .ralph/.env 加：
echo 'RALPH_PROVIDER=codex' > .ralph/.env
echo 'RALPH_PROVIDER_CONFIG_DIR=~/.codex-ralph' >> .ralph/.env

# 后续 ralph run 自动用 CODEX_HOME=~/.codex-ralph
.ralph/bin/ralph run
```

Codex session 文件落到 `~/.codex-ralph/sessions/...`，adapter 自动从该路径采集 rollout 文件（REQ-022 / SC-022-5）。

Gemini 同一抽象会翻译为 `GEMINI_CLI_HOME`：

```bash
# 一次性准备：让该目录拥有 Gemini 登录态 / auth 配置
# Gemini CLI 会在该目录下创建 .gemini/ 子目录
GEMINI_CLI_HOME=~/.gemini-ralph gemini auth login

# 在 .ralph/.env 加：
echo 'RALPH_PROVIDER=gemini' > .ralph/.env
echo 'RALPH_PROVIDER_CONFIG_DIR=~/.gemini-ralph' >> .ralph/.env

# 后续 ralph run 自动用 GEMINI_CLI_HOME=~/.gemini-ralph
.ralph/bin/ralph run
```

Gemini session 文件落到 `~/.gemini-ralph/.gemini/tmp/...`，adapter 自动从该路径采集 session（REQ-022）。

## 任务前缀（8 类）

详见 `.spec/rules/tasks.md`。速查：

| 前缀 | mindset |
|---|---|
| `REQ-N` | 需求澄清 |
| `SOL-N` | 方案决策（存在真实取舍时） |
| `ROADMAP-N` | Roadmap 阶段规划 |
| `PLAN-N` | 任务列表规划（产出 TASKS.md 当前迭代任务列表） |
| `DEV-N`（或无前缀） | 开发实施（默认） |
| `QA-N` | 测试设计与实施 |
| `REVIEW-N` | 审查（`| review` / `| adversarial-review` 后缀，或 `[blocked-by]` escalation） |
| `HUMAN-N` | 等人类决策（ralph oneshot 内不可勾选不可执行） |

前缀必须全大写英文。

## 常见问题

**Q：ralph run 卡住了，看不到任何输出**
A：默认 silent + 进度 marker（stderr）。长 oneshot 会每 60 秒输出 heartbeat，里面带 `provider.stdout.log` 路径。实时看 agent 事件用 `tail -f .ralph/runs/<run_id>/iterations/iter-NNN/provider.stdout.log`，或重新启动加 `-v` flag。

**Q：ralph watch -v 没有 tail 输出**
A：`watch -v` 依赖 `.ralph/status.json` 的 `run_id` / `iteration` 定位当前 iter log。v0.1.1 起 `ralph run` 会在 provider oneshot 启动前更新到当前 iter 并创建 `provider.stdout.log`；旧 run 产物若 status 指向不存在的 iter，可直接 tail 实际存在的 `iterations/iter-NNN/provider.stdout.log`。

**Q：session.<provider>.jsonl 没采集到（meta.json `capture_status: warning`）**
A：检查 provider 配置目录是否正确。Claude 使用 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd_hash>/<session_id>.jsonl`；Codex 使用 `${CODEX_HOME:-$HOME/.codex}/sessions/` 下的 `rollout-*-<thread_id>.jsonl`；Gemini 使用 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/*.json`。

**Q：HUMAN-N 任务被 agent 勾掉了**
A：违反 PROMPT.md 强约束。重跑前手动改回 `[ ]`；可能 agent 误判，需要在 PROMPT.md 加强约束或在任务描述明示。

**Q：iter dir 里没有 `chat.log` / `tools.log`**
A：v0.1.1 起合并为 `session.history.log`。Claude 的完整 input 见 `session.claude.jsonl`；Codex 的完整 command input 见 `provider.stdout.log`。

**Q：时间戳为什么是 +0800？**
A：人类终端输出（status / watch / 进度 marker / exit-message）渲染本地时间；JSON 文件（`status.json` / `result.json` / `meta.json`）保留 ISO 8601 UTC 用于机器解析（REQ-026 双层时间格式）。

**Q：可以同时跑两个 ralph run 吗？**
A：不能。每个 workspace `.ralph/lock` 互斥，第二次会以 `locked` exit 6 退出。

## 相关文档

- 协议规范：`.spec/rules/`（requirements / solution / roadmap / tasks / testing / review / adversarial-review）
- 项目入口：`README.md` / `AGENTS.md`（本仓库根）
- 架构：`docs/architecture/{overview,integrations,security}.md`
- 需求：`docs/requirements/ralph-loop/requirements.md`
- 路线：`docs/roadmap.md`
- Iteration 设计方案：`docs/requirements/ralph-loop/I<N>-design.md`
- Iteration 完成归档：`docs/requirements/ralph-loop/I<N>-FINAL-TASK.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`
