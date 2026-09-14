# `.ralph/` 新手使用手册

`.ralph/` 是 ralph-loop 的完整部署单元。你把这个目录复制到自己的 git
workspace 里，就可以让 Claude / Codex CLI 按 `.ralph/TASKS.md`
里的任务一轮一轮工作。

> 当前正式支持的 provider 只有 Claude Code 和 Codex CLI。Gemini adapter 暂时保留但公共入口已禁用，文中相关段落仅作历史参考。

最短路径：

```bash
cp -r .ralph/ /path/to/your/workspace/.ralph/
cd /path/to/your/workspace
./.ralph/bin/ralph run --provider claude
```

## Ralph 是做什么的

Ralph 只做一件事：反复启动 provider CLI 的 fresh oneshot，让 agent 每轮完成
`.ralph/TASKS.md` 里的一个未完成任务，完成后提交 commit，然后退出本轮。

- `run`: 真正执行任务循环。
- `status`: 看当前或最近一次 run 的状态快照。
- `watch`: 人类盯进度用的 sticky 观察界面。

几个关键词先记住：

- **workspace**: 你的项目根目录，必须是 git repo。
- **run**: 一次完整执行，从启动到完成、失败、超时或阻塞。
- **round**: run 里面的一次 provider oneshot 调用。
- **task**: `.ralph/TASKS.md` 里顶层的 `- [ ]` 或 `- [x]` 条目。

安全边界也要先知道：

- Provider CLI 会读取你的 workspace，并按任务修改文件。
- Ralph 协议要求 agent 每轮完成后执行 `git add -A && git commit`。
- Codex adapter 为了允许 `.git/` 写入，会使用 `--sandbox danger-full-access`。
- 不要在含有未提交秘密、生产凭据或不想让 AI 读取的目录里直接运行 Ralph。

## 目录里有什么

```text
.ralph/
├── README.md              # 本文件
├── PROMPT.md              # 每轮发给 provider 的工作协议
├── TASKS.md               # 任务清单，使用时主要改这个文件
├── TASKS.bak              # hello world 样例备份，不会被 ralph 读取
├── .env                   # 私有配置，自己创建，gitignored
├── .gitignore             # 忽略 runs/、lock、status.json、.env
├── bin/
│   └── ralph              # CLI 入口
├── lib/                   # Ralph 内部脚本
├── runs/                  # 每次 run 的日志和结果，运行后生成，gitignored
├── status.json            # 当前或最近 run 的状态，运行后生成，gitignored
└── lock                   # 并发运行锁，运行时生成，gitignored
```

## 第一次使用：一步一步来

### 1. 进入你的项目目录

Ralph 需要在 git workspace 里运行。先确认：

```bash
cd /path/to/your/workspace
git status
```

如果提示 `not a git repository`，先初始化：

```bash
git init
git status
```

### 2. 复制 `.ralph/`

从 ralph-loop 仓库复制：

```bash
cp -r /path/to/ralph-loop/.ralph/ ./.ralph/
```

如果你是从一个已经跑过 Ralph 的开发工作区复制，而不是从干净 release 包复制，
不要把这些本地运行产物带过去：`.ralph/runs/`、`.ralph/status.json`、
`.ralph/lock`、`.ralph/.env`。复制后可以检查：

```bash
ls .ralph/runs .ralph/status.json .ralph/lock .ralph/.env 2>/dev/null
```

如果这些文件存在，说明你复制到了本地运行产物；新 workspace 首跑前应移走它们。

确认 CLI 能跑：

```bash
./.ralph/bin/ralph --version
./.ralph/bin/ralph --help
```

### 3. 准备 provider CLI

你至少需要装好并登录一个 provider CLI。

```bash
claude --version
codex --version
gemini --version
```

只用其中一个也可以。你打算用哪个 provider，就保证哪个命令能在当前终端正常
运行。

Provider 认证提示：

- Claude: 先按 Claude Code CLI 自己的方式登录。
- Codex: 先按 Codex CLI 自己的方式登录，或在 CI 里配置 `CODEX_API_KEY`。
- Gemini: 需要 `~/.gemini/settings.json` 里有 auth method，或配置
  `GEMINI_API_KEY` / `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA`。

### 4. 创建 `.ralph/.env`

`.ralph/.env` 不是必须的，但新手建议创建，避免每次敲很多参数。
下面的命令会覆盖 `.ralph/.env`。如果你已经在里面写了私有配置，先手动编辑，
不要直接粘贴覆盖。

Claude 示例：

```bash
cat > .ralph/.env <<'EOF'
RALPH_PROVIDER=claude
RALPH_LOOP_MAX_ROUND=0
RALPH_LOOP_ROUND_TIMEOUT=0
RALPH_LOOP_STALL_LIMIT=5
RALPH_LOOP_MAX_RETRY=3
RALPH_LOOP_RETRY_SCHEDULE=60 120 300
EOF
```

Codex 示例：

```bash
cat > .ralph/.env <<'EOF'
RALPH_PROVIDER=codex
RALPH_LOOP_MAX_ROUND=0
RALPH_LOOP_ROUND_TIMEOUT=0
RALPH_LOOP_STALL_LIMIT=5
EOF
```

Gemini 示例：

```bash
cat > .ralph/.env <<'EOF'
RALPH_PROVIDER=gemini
RALPH_LOOP_MAX_ROUND=0
RALPH_LOOP_ROUND_TIMEOUT=0
RALPH_LOOP_STALL_LIMIT=5
EOF
```

Fake 示例，只用于测试 Ralph 本身，不会调用真实 AI：

```bash
cat > .ralph/.env <<'EOF'
RALPH_PROVIDER=fake
EOF
```

Fake provider 只适合检查 Ralph 的循环和状态文件，不代表 Claude / Codex /
Gemini 真实可用。准备 release 或验证真实项目时，必须跑真实 provider。

`.env` 规则：

- 只读取 `RALPH_*` 变量。
- 不会执行 shell 代码，不要写 `$(...)`。
- 可以写引号，Ralph 会去掉最外层单引号或双引号。
- 路径值以 `~/` 开头时会展开成你的 home 目录。
- 优先级：CLI flag > 当前终端 env > `.ralph/.env` > 默认值。

### 5. 写 `.ralph/TASKS.md`

Ralph 只识别顶层 checkbox：

```markdown
# Tasks

- [ ] DEV-1: 创建 hello.txt，内容严格为 `hello ralph`，完成后 commit。
  - 文件路径：hello.txt
  - 完成后：`git add -A && git commit -m "add hello.txt"`

- [ ] DEV-2: 在 README.md 末尾追加 `<!-- setup complete -->`，完成后 commit。
```

注意：

- 顶层 `- [ ]` 是未完成任务。
- 顶层 `- [x]` 是已完成任务。
- 子 bullet 只是说明，Ralph 不会把它当成任务。
- 一轮只做一个顶层任务。
- 没有前缀的任务会按 DEV 处理。
- 有前缀时必须像 `DEV-1:`、`QA-2:`、`HUMAN-3:` 这样全大写、带数字、带冒号。

常用前缀：

| 前缀 | 用途 |
|---|---|
| `DEV-N` | 写代码、改文档、做具体交付，最常用 |
| `QA-N` | 写测试或做验证 |
| `REQ-N` | 梳理需求 |
| `SOL-N` | 方案设计 |
| `PLAN-N` | 拆任务 |
| `REVIEW-N` | 审查 |
| `HUMAN-N` | 必须人类决策，Ralph 会停下 |

如果你的项目没有 `.spec/` 规范文件，第一次使用建议只写无前缀任务或 `DEV-N`
任务，并在项目根目录放一个 `AGENTS.md` 或 `CLAUDE.md` 写清楚项目规则。

### 6. 启动 run

使用 `.env` 里的 provider：

```bash
./.ralph/bin/ralph run
```

临时指定 provider：

```bash
./.ralph/bin/ralph run --provider claude
./.ralph/bin/ralph run --provider codex
./.ralph/bin/ralph run --provider gemini
```

启动后不要急着改 `.ralph/TASKS.md`。等当前 round 结束，再看结果。

### 7. 观察进度

开两个终端最清楚。

终端 A 执行：

```bash
./.ralph/bin/ralph run --provider claude
```

终端 B 观察：

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph watch
```

`watch` 里按 `Ctrl+C` 只会退出观察界面，不会停止终端 A 里的 run。

### 8. 看结果

run 结束后看摘要：

```bash
./.ralph/bin/ralph status
cat .ralph/runs/<run_id>/result.json
cat .ralph/runs/<run_id>/exit-message.txt
```

看每轮日志：

```bash
ls .ralph/runs/<run_id>/rounds/
cat .ralph/runs/<run_id>/rounds/round-001/provider.stdout.log
cat .ralph/runs/<run_id>/rounds/round-001/session.history.log
```

## 所有命令和示例

### `./.ralph/bin/ralph --version`

查看版本。

```bash
./.ralph/bin/ralph --version
```

### `./.ralph/bin/ralph --help`

查看总帮助。

```bash
./.ralph/bin/ralph --help
```

### `./.ralph/bin/ralph help`

和 `--help` 等价。

```bash
./.ralph/bin/ralph help
```

### `./.ralph/bin/ralph help run`

查看 `run` 的完整参数。

```bash
./.ralph/bin/ralph help run
./.ralph/bin/ralph run --help
```

### `./.ralph/bin/ralph help status`

查看 `status` 的参数。

```bash
./.ralph/bin/ralph help status
./.ralph/bin/ralph status --help
```

### `./.ralph/bin/ralph help watch`

查看 `watch` 的参数。

```bash
./.ralph/bin/ralph help watch
./.ralph/bin/ralph watch --help
```

### `./.ralph/bin/ralph run`

启动任务循环。

```bash
./.ralph/bin/ralph run
```

常见写法：

```bash
./.ralph/bin/ralph run --provider claude
./.ralph/bin/ralph run --provider codex
./.ralph/bin/ralph run --provider gemini
./.ralph/bin/ralph run --provider fake
```

带模型：

```bash
./.ralph/bin/ralph run --provider claude --model sonnet
./.ralph/bin/ralph run --provider codex --model gpt-5.2
./.ralph/bin/ralph run --provider gemini --model gemini-2.5-pro
```

带推理强度：

```bash
./.ralph/bin/ralph run --provider claude --effort low
./.ralph/bin/ralph run --provider codex --effort medium
./.ralph/bin/ralph run --provider claude --effort none
```

限制单个任务最多跑 3 个 round：

```bash
./.ralph/bin/ralph run --provider claude --max-round 3
```

限制每个 round 最多 10 分钟：

```bash
./.ralph/bin/ralph run --provider claude --round-timeout 600
```

连续 2 轮没有进展就停下来交给人：

```bash
./.ralph/bin/ralph run --provider claude --stall-limit 2
```

provider 临时失败时最多重试 5 次：

```bash
./.ralph/bin/ralph run --provider claude --max-retry 5
```

自定义重试等待时间，单位是秒：

```bash
./.ralph/bin/ralph run --provider claude --retry-schedule "10 30 60 120"
```

打开 sticky 事件界面：

```bash
./.ralph/bin/ralph run --provider claude --verbose
./.ralph/bin/ralph run --provider claude -v
```

如果 stdout 不是 TTY，`run -v` 会自动退回普通文本输出，避免日志文件混入控制字符。

### `./.ralph/bin/ralph status`

一次性打印状态，不刷新。

```bash
./.ralph/bin/ralph status
```

输出原始 JSON：

```bash
./.ralph/bin/ralph status --json
```

常用排查：

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph status --json | jq .
```

如果没有 run，status 会打印 `无运行中/已结束的 run` 并返回 0。

### `./.ralph/bin/ralph watch`

持续观察当前或最近 run。

```bash
./.ralph/bin/ralph watch
```

注意：

- `watch` 在 TTY 里是 sticky 界面。
- `watch` 没有 `-v` 参数。
- 非 TTY 下只输出一行状态快照，然后退出。
- `Ctrl+C` 只退出 watch，不会停止正在运行的 `ralph run`。

非 TTY 示例：

```bash
./.ralph/bin/ralph watch | cat
```

## `run` 参数速查

| 参数 | `.env` 变量 | 默认 | 说明 |
|---|---|---|---|
| `--provider <name>` | `RALPH_PROVIDER` | 无 | 必填，`claude` / `codex` / `fake`；Gemini 暂停支持 |
| `--model <name>` | `RALPH_PROVIDER_MODEL` | 无 | 传给 provider 的模型名 |
| `--effort <level>` | `RALPH_PROVIDER_EFFORT` | 无 | `low` / `medium` / `high` / `none` |
| `--max-round <n>` | `RALPH_LOOP_MAX_ROUND` | `0` | 单个 task 最多 round 数，0 表示无限 |
| `--round-timeout <sec>` | `RALPH_LOOP_ROUND_TIMEOUT` | `0` | 单个 round 超时秒数，0 表示无限 |
| `--stall-limit <n>` | `RALPH_LOOP_STALL_LIMIT` | `5` | 单个 task 连续无进展 round 上限 |
| `--max-retry <n>` | `RALPH_LOOP_MAX_RETRY` | `3` | rate limit / network 这类临时错误的重试次数 |
| `--retry-schedule "<s...>"` | `RALPH_LOOP_RETRY_SCHEDULE` | `60 120 300` | 重试等待秒数序列 |
| `--verbose` / `-v` | `RALPH_VERBOSE=1` | 关闭 | run 时显示 sticky 事件界面 |
| `--help` | 无 | 无 | 查看帮助 |

其他常用变量：

| 变量 | 默认 | 说明 |
|---|---|---|
| `RALPH_PROVIDER_CONFIG_DIR` | 无 | 隔离 provider 配置目录，Claude/Codex adapter 会翻译成对应原生目录 |
| `RALPH_PROGRESS_HEARTBEAT_SEC` | `60` | 普通文本模式 heartbeat 间隔，设成 `0` 关闭 |
| `RALPH_UI_STICKY_EVENT_LINES` | `6` | sticky 事件区行数 |
| `RALPH_UI_HEALTH_GREEN_SEC` | `60` | provider 日志静默超过该秒数后健康灯变黄 |
| `RALPH_UI_HEALTH_RED_SEC` | `300` | provider 日志静默超过该秒数后健康灯变红 |

## 退出原因怎么处理

| exit_reason | exit code | 意思 | 你下一步做什么 |
|---|---:|---|---|
| `done` | 0 | 全部任务完成 | 看 commit、看 `result.json`，准备合并或继续写新任务 |
| `provider_failed` | 2 | provider CLI 报错或认证失败 | 看 `provider.stdout.log` 和 `exit-message.txt`，修 provider 环境后重跑 |
| `timeout` | 3 | 单个 round 超过 `--round-timeout` | 放大 timeout、拆小任务，或人工处理当前任务 |
| `locked` | 6 | 已经有一个 `ralph run` 在跑 | 用 `status` / `watch` 看现有 run，不要并发启动 |
| `blocked_by_human` | 7 | 遇到 `HUMAN-N` 或防死循环触发 | 人类回答问题、更新任务、勾掉 HUMAN 任务后重跑 |
| `interrupted` | 130 | 收到 Ctrl+C / SIGTERM | 看工作区和 run 目录，确认是否需要继续 |
| `startup_failed` | 1 | 启动校验失败 | 修 `.ralph/TASKS.md` 格式、provider 配置或基础环境后重跑 |

## 防死循环机制

Ralph 有两道保护：

1. `--max-round`: 同一个 task 尝试太多轮就停。
2. `--stall-limit`: 同一个 task 连续多轮没有勾任务、也没有改动文件就停。

触发后，Ralph 会在当前任务前插入一个 `HUMAN-N` 任务，并以
`blocked_by_human` 退出。你需要：

1. 打开 `.ralph/TASKS.md`。
2. 阅读自动插入的 `HUMAN-N`。
3. 在普通对话里和 agent 或人类解决问题。
4. 把答案写回任务或项目文档。
5. 把 `HUMAN-N` 改成 `- [x]`。
6. 重新执行 `./.ralph/bin/ralph run`。

## 日志和产物在哪里

每个 run 在 `.ralph/runs/<run_id>/` 下。

```text
.ralph/runs/<run_id>/
├── context.json
├── result.json
├── exit-message.txt
└── rounds/
    └── round-001/
        ├── meta.json
        ├── provider.stdout.log
        ├── session.<provider>.json 或 session.<provider>.jsonl
        └── session.history.log
```

常看这几个：

- `result.json`: 这次 run 的最终结果。
- `exit-message.txt`: 退出摘要和下一步提示。
- `provider.stdout.log`: provider 原始输出，排查失败第一看它。
- `session.history.log`: Ralph 整理过的人类可读历史。

## 常见问题

### 运行前提示 provider 必填

你没有传 `--provider`，也没有在 `.ralph/.env` 写 `RALPH_PROVIDER`。

修法二选一：

```bash
./.ralph/bin/ralph run --provider claude
```

或：

```bash
printf 'RALPH_PROVIDER=claude\n' > .ralph/.env
./.ralph/bin/ralph run
```

### `TASKS.md` 前缀格式错误

错误例子：

```markdown
- [ ] dev-1: 小写不允许
- [ ] Dev-1: 混合大小写不允许
- [ ] DEV1: 少了连字符不允许
- [ ] DEV-1 写代码: 少了冒号不允许
```

正确例子：

```markdown
- [ ] DEV-1: 写代码并提交。
- [ ] 写代码并提交。
```

### Gemini 提示没有 auth method

先配置 Gemini CLI 认证。常见错误会提到：

```text
Please set an Auth method in your ~/.gemini/settings.json
```

修法：按 Gemini CLI 要求写 `~/.gemini/settings.json`，或设置
`GEMINI_API_KEY` / `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA`。

### `watch` 没有详细字段

这是正常的。`watch` 是观察进度的紧凑界面。要看完整字段，用：

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph status --json
```

### 终端打字不显示

如果 `run -v` 或 `watch` 被强杀，终端可能进入 `noecho` 状态。执行：

```bash
stty sane
```

### 想重新跑

先确认没有 run 在运行：

```bash
./.ralph/bin/ralph status
```

如果上次已经结束，直接重跑：

```bash
./.ralph/bin/ralph run
```

如果上次留下未完成代码，先自己处理 git 工作区：

```bash
git status
git diff
```

不要直接删除 `.ralph/runs/` 来“修复”问题。`runs/` 是证据，删掉只会让排查更难。
