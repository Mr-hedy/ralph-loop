# `.ralph/` 新手使用手册

`.ralph/` 是 ralph-loop 的完整部署单元。你把这个目录复制到自己的 git
workspace 里，就可以让 Claude / Codex CLI 按 `.ralph/TASKS.md`
里的任务一轮一轮工作。

> 当前正式支持的 provider 只有 Claude Code 和 Codex CLI（测试另可用 `fake`）。
> 开发工程可能保留 Gemini 历史 adapter 供未来重新接入，但当前 release 包不携带它；公共入口已禁用：传
> `--provider gemini` 会在启动校验阶段失败（exit 1）且不产生任何 run 目录。
> 文中相关段落均标注为暂停接入，仅作历史参考。

安装后最短路径：

```bash
cd /path/to/your/workspace
# 首次项目会话先补齐项目规则、docs 地图和任务清单
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
- **Codex 的权限范围不止 workspace**：Codex adapter 为了允许 `.git/` 写入，固定使用
  `--sandbox danger-full-access`。该取值移除本地沙箱限制，模型生成的 shell 命令以你
  当前用户身份执行，不受 workspace 边界约束。Ralph 外层固定的是"哪个 workspace、
  哪份任务清单、写到哪个 run 目录"，不是 agent 的文件系统可达范围。
- **Claude 的权限范围同样不止 workspace**：adapter 固定使用
  `--dangerously-skip-permissions`，即绕过全部 permission 检查（等价
  `--permission-mode bypassPermissions`），所有工具调用都会直接执行。同一命令行里的
  `--allowedTools "Bash,Read,Edit,Write,Glob,Grep"` 只是"无需询问"清单，在该模式下
  **不生效**，所以它不是能力边界——请不要把那个 6 项清单当作 Claude 的权限收敛。
- 不要在含有未提交秘密、生产凭据或不想让 AI 读取的目录里直接运行 Ralph；也不要在
  "agent 越界写入会造成不可接受损失"的机器状态下运行。

这些权限参数写死在 adapter 源码里，`.env` 和 CLI flag 都改不了。审计方式见下文
[Provider 权限边界与审计证据](#provider-权限边界与审计证据)。

## 目录里有什么

```text
.ralph/
├── README.md              # 本文件
├── PROMPT.md              # 每轮发给 provider 的工作协议
├── TASKS.md               # 任务清单，使用时主要改这个文件
├── .env                   # 注释配置模板；填写后由 .gitignore 忽略
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

### 2. 部署 release

从 ralph-loop release 目录复制完整版本包：

```bash
cp -R /path/to/ralph-loop/release/0.1.1/. ./
```

上面的命令只适用于全新 workspace。目标已有 `AGENTS.md`、`CLAUDE.md`、`.ralph/`、
`.spec/` 或 `docs/` 时，先复制到临时目录再人工合并，不要静默覆盖已有入口或事实源。
不要从 ralph-loop 开发工程直接复制 `.ralph/`；那是本仓库的 dogfood 工作区。
release 包不会包含 `.ralph/runs/`、`.ralph/status.json` 或 `.ralph/lock`。
`.ralph/.env` 是随 release 提供的注释配置模板，不属于运行产物；填写真实配置后会由
`.ralph/.gitignore` 忽略。复制后可以检查运行态文件：

```bash
ls .ralph/runs .ralph/status.json .ralph/lock 2>/dev/null
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
```

只用其中一个也可以。你打算用哪个 provider，就保证哪个命令能在当前终端正常
运行。

Provider 认证提示：

- Claude: 先按 Claude Code CLI 自己的方式登录。
- Codex: 先按 Codex CLI 自己的方式登录，或在 CI 里配置 `CODEX_API_KEY`。
- Gemini: **暂停接入**（见下文 FAQ）。当前 release 不携带 Gemini adapter，公共入口不接受
  `--provider gemini`，因此现在不需要为 Gemini 配认证。历史要求是
  `~/.gemini/settings.json` 里有 auth method，或配置 `GEMINI_API_KEY` /
  `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA`。

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

Fake 示例，只用于测试 Ralph 本身，不会调用真实 AI：

```bash
cat > .ralph/.env <<'EOF'
RALPH_PROVIDER=fake
EOF
```

Fake provider 只适合检查 Ralph 的循环和状态文件，不代表 Claude / Codex 真实可用。
准备 release 或验证真实项目时，必须跑真实 provider。

Gemini 暂停接入，写 `RALPH_PROVIDER=gemini` 会在启动阶段直接失败，不产生 run。

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
./.ralph/bin/ralph run --provider fake
```

`--provider` 只接受这三个值；其他取值（含 `gemini`）会在启动校验阶段被拒绝，
exit 1，且不创建 run 目录。

带模型：

```bash
./.ralph/bin/ralph run --provider claude --model sonnet
./.ralph/bin/ralph run --provider codex --model gpt-5.2
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
| `--provider <name>` | `RALPH_PROVIDER` | 无 | 必填，只接受 `claude` / `codex` / `fake`；其他取值（含 `gemini`）启动即失败，exit 1 |
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
| `RALPH_PROVIDER_CONFIG_DIR` | 无 | 隔离 provider 配置目录；Claude → `CLAUDE_CONFIG_DIR`，Codex → `CODEX_HOME`。只改变凭据/配置来源，**不改变权限或沙箱模式** |
| `RALPH_PROGRESS_HEARTBEAT_SEC` | `60` | 普通文本模式 heartbeat 间隔，设成 `0` 关闭 |
| `RALPH_UI_STICKY_EVENT_LINES` | `6` | sticky 事件区行数 |
| `RALPH_UI_HEALTH_GREEN_SEC` | `60` | provider 日志静默超过该秒数后健康灯变黄 |
| `RALPH_UI_HEALTH_RED_SEC` | `300` | provider 日志静默超过该秒数后健康灯变红 |

## Provider 权限边界与审计证据

Ralph 是无人值守循环，所以 provider 不允许弹交互式 approval。各 provider 的
自动批准/沙箱参数**写死在 adapter 源码里**，`.env`、环境变量和 CLI flag 都无法
修改或扩大（也没有 `--approval` / `--sandbox` / `--allowedTools` 这类入口）。

| provider | 固定参数 | 权限含义 |
|---|---|---|
| Claude | `--dangerously-skip-permissions` + `--allowedTools "Bash,Read,Edit,Write,Glob,Grep"` | 绕过全部 permission 检查，所有工具直接执行。`--allowedTools` 只是免询问清单，在该模式下不生效，**不构成工具限制** |
| Codex | `codex exec --sandbox danger-full-access` | 移除本地沙箱限制，shell 命令以当前用户身份执行，**不受 workspace 边界约束** |
| Gemini | 无（暂停接入） | 入口拒绝，不会执行 |

一句话总结：**两条真实路径都等于"以你的用户身份无限制执行"，Ralph 没有 provider 侧
的能力收窄层。**

Codex 为什么用 `danger-full-access`：ralph 协议要求 agent 每轮执行
`git add -A && git commit`，而 `workspace-write` 会禁止写 `.git/index.lock`。

审计时需要看什么：

```bash
# 1. 实际生效的权限参数（确认部署副本没有被改动）
grep -n 'danger-full-access\|dangerously-skip-permissions\|allowedTools' .ralph/lib/adapter-*.sh

# 2. 本次 run 用的是哪一版 provider CLI、哪些配置来源
cat .ralph/runs/<run_id>/context.json

# 3. 单轮发生了什么（退出码、终态、错误类别、采集状态）
cat .ralph/runs/<run_id>/rounds/round-001/meta.json
```

权限参数本身**不会**写进 `meta.json`——它们是静态常量，不随 run 变化。若你需要
"每次 run 都带权限指纹"，当前只能靠第 1 步的源码检查 + 部署副本的 git 版本。
权威表述见 `docs/architecture/security.md` §Approval / Sandbox 固定策略与
§权限参数的审计路径。

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
- `rounds/round-NNN/meta.json`: 本轮元数据。`terminal_status` = `success` / `error` / `unknown` 是 provider 终态判定（`unknown` 时读 `terminal_warning` 看原因）；`capture_status` / `capture_warning` 是 session 采集结果。

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

### `--provider gemini` 直接失败

Gemini 暂停接入。你现在会看到：

```text
ralph: startup check failed: provider 'gemini' is temporarily disabled; use claude, codex or fake
```

这是预期行为，进程 exit 1，且不会创建 `.ralph/runs/`、`.ralph/lock`、
`.ralph/status.json`。改回 `--provider claude` 或 `--provider codex` 即可。

下面的内容只在未来重新接入 Gemini 后才适用（历史记录）：Gemini CLI 认证失败时常见错误是

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
