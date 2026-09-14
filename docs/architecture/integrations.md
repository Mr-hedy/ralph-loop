# Integrations

- 状态：已确认（I2 DEV-1 校准 2026-05-03 / I4 DEV-1 校准 2026-05-04）
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-005 / REQ-006 / REQ-011 / FR-006 / FR-008 / NFR-SEC-002）、2026-04-20 三家官方文档、I2 DEV-1 本机 CLI help 与会话目录观测（2026-05-03）、I4 DEV-1 本机 Gemini CLI help 与会话目录观测（2026-05-04）、OpenAI 官方 non-interactive mode / command line options / config reference 文档。
- 范围：本文定义 Ralph harness 与三个外部 provider CLI（Claude Code / Codex CLI / Gemini CLI）的集成契约：命令构造、session 采集、错误诊断关键字、UUID 依赖和降级策略。跨 provider 的公共主循环、运行目录 schema 在 [`overview.md`](./overview.md)；approval/sandbox 的安全边界在 [`security.md`](./security.md)。本文不重写需求正文、不描述 adapter 之外的命令封装形式。
- 变更条件：任一 provider CLI 升级改变 session 路径、事件格式或 flag 语义；新增第四个 provider；NFR-SEC-002 变更导致 approval 策略调整；`.ralph/runs/` 布局变化影响 session 拷贝位置。

## 证据范围

本文基于 2026-04-20 的官方文档、I2 DEV-1（2026-05-03）本机 CLI help 和本机会话目录观测、I4 DEV-1（2026-05-04）本机 Gemini CLI help 与会话目录观测。

本机版本：

- Claude Code：`2.1.114`
- Codex CLI：`0.125.0`（CLI）；Desktop app 内核 `0.128.0-alpha.1`
- Gemini CLI：当前未纳入支持矩阵（adapter 保留，入口暂时禁用）

参考资料：

- Claude Code CLI reference: <https://docs.claude.com/en/docs/claude-code/cli-reference>
- Claude Code data usage: <https://docs.claude.com/en/docs/claude-code/data-usage>
- Codex CLI features: <https://developers.openai.com/codex/cli/features>
- Codex CLI command line options: <https://developers.openai.com/codex/cli/reference>
- Codex non-interactive mode: <https://developers.openai.com/codex/noninteractive>
- Gemini CLI session management: <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/session-management.md>
- Gemini CLI reference: <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md>

## round 目录文件结构（4 文件契约）

每轮 round 目录最终包含 4 个文件，跨 provider 统一：

| 文件 | 含义 | 出现条件 |
|---|---|---|
| `meta.json` | round 元数据（含 session_id / provider_started_at / runtime_block / capture_status / error / 任务进度 / changed_files / stall_count 等） | 始终 |
| `provider.stdout.log` | provider CLI stdout + stderr 合流原始输出（含 stream-json 事件、错误信息） | 始终 |
| `session.<provider>.jsonl` | provider 原生 session 文件副本（保留 30 天后过期 / 派生视图 bug 回滚 / 跨机器 evidence 自包含三个用途；Gemini 为 `.json` 而非 `.jsonl`） | session 采集成功（精确匹配或 mtime fallback） |
| `session.history.log` | 跨 provider 人话视图（provider 间内容有差异：Claude 含 user/assistant/thinking/tool-use/tool-result，Codex 含 assistant/tool-use/tool-result 但无 user/thinking，Gemini 含 assistant/tool-use/tool-result/result），Claude 从 `session.claude.jsonl` 派生，Codex 从 `provider.stdout.log`（`--json` stdout 事件流）派生，Gemini 从 `provider.stdout.log`（`--output-format stream-json` 事件流）派生；完整 tool input 保留在各派生源中 | 始终（capture 失败时为空文件） |

各 provider native session 文件实例：
- Claude：`session.claude.jsonl`（从 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd_hash>/<session_id>.jsonl` 复制；stream-json 模式下与 stdout 事件流内容相同，但保留独立副本作为 30 天后回看 anchor）
- Codex（T3 落地）：`session.codex.jsonl`（从 `~/.codex/sessions/rollout-*-<thread_id>.jsonl` 复制）
- Gemini（T4 落地）：`session.gemini.json`（从 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/*.json` 复制；native session 为 JSON 格式，与其他 provider 的 JSONL 不同；与 `provider.stdout.log` 事件流互补，不可替代）
- native session 为 JSON 格式，与其他 provider 的 JSONL 不同；与 `provider.stdout.log` 事件流互补，不可替代）

不再保留：
- `session.<provider>.stdout.<ext>`（与 `provider.stdout.log` 字节相同，重复）
- `chat.log` / `tools.log`（合并进 `session.history.log`，避免双视图）
- `prompt.md` / `.session_start`（前者可由 `meta.json.runtime_block` + `meta.json.start_sha` 还原 PROMPT.md；后者由 `meta.json.provider_started_at` 时间戳替代）

新增 provider 必须遵循此 4 文件契约；偏离需通过新需求或文档 PR 显式覆盖。

## 总体原则

Ralph 默认使用 provider 的 fresh oneshot 执行，不默认 resume。session 采集只用于复盘分析，不作为任务完成事实源。

每轮至少保存两类证据：

- process log：provider CLI 的 stdout/stderr 原始输出，保存到 `rounds/round-NNN/provider.stdout.log`。
- native session：provider 自己持久化的会话文件，复制到 `rounds/round-NNN/session.<provider>.<ext>`（Claude/Codex 为 `.jsonl`，Gemini 为 `.json`）。

采集失败不能直接判定任务失败。失败时应记录 warning，并继续使用 process log 和 `.ralph/TASKS.md` 判断 run 状态。

## Adapter 配置目录翻译契约

REQ-022 引入的隐式契约（不增三函数签名）。每个 adapter 在 source 时执行：

- 检查 ralph 中立变量 `RALPH_PROVIDER_CONFIG_DIR` 是否非空。
- 非空 → `export <provider 原生环境变量>="$RALPH_PROVIDER_CONFIG_DIR"`，让 provider CLI 子进程读独立 config dir。
- 空或未设 → 不 export（避免空值干扰 provider 默认行为）。

各 provider 翻译目标：

| Provider | 原生环境变量 | 来源 / 备注 |
|---|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` | 官方 [authentication.md](https://code.claude.com/docs/en/authentication.md)；macOS 上当 settings.json 含 API key / apiKeyHelper / `ANTHROPIC_BASE_URL` 时切换该目录 = 切换账号（OAuth/Keychain 不参与） |
| Codex CLI | `CODEX_HOME` | 官方 config-reference `log_dir` 说明"defaults to `$CODEX_HOME/log`"；CLI `--ignore-user-config` help 明确"auth still uses `CODEX_HOME`"；默认 `~/.codex` |
| Gemini CLI | `GEMINI_CLI_HOME` | 官方 configuration 文档 `GEMINI_CLI_HOME` 条目："Specifies the root directory for Gemini CLI's user-level configuration and storage. The CLI will create a `.gemini` folder inside this directory."；实际配置目录 = `$GEMINI_CLI_HOME/.gemini/`（默认 `~/.gemini/`）；session 采集路径 = `$GEMINI_CLI_HOME/.gemini/tmp/...` |
| fake adapter | n/a | 测试用，不读真实 provider 配置 |

实现位置：`.ralph/lib/adapter-<provider>.sh` 顶部 source 时执行的 if 块（不放进 `provider_oneshot` / `provider_collect_session` / `provider_diagnose` 函数体内，避免每次调用重复 export）。

子进程继承走 bash 默认行为：父进程 export 的环境变量自动透传给所有 fork+exec 出来的子进程。无需在 `provider_oneshot` 用命令前缀语法（`VAR=val command...`）显式注入。

## Claude Code

### Session 机制

Claude Code 支持交互和 headless 两类入口：

```bash
claude
claude -p "query"
```

和 session 相关的官方 CLI 能力包括：

- `--continue` / `-c`：继续当前目录最近会话。
- `--resume` / `-r`：按 session ID 或 name 恢复会话，也可打开交互选择器。
- `--session-id <uuid>`：使用指定 UUID 作为当前会话 ID。
- `--fork-session`：resume 时创建新 session ID。
- `--no-session-persistence`：print mode 下不保存本地 session，且不能 resume。
- `--output-format text|json|stream-json`：print mode 输出格式。

Claude 官方 data usage 文档明确：Claude Code 客户端会把 session transcript 以明文保存在 `~/.claude/projects/`，默认保留 30 天，用于 session resumption。

本机观测到的文件形态：

```text
~/.claude/projects/<encoded-project-path>/<session-id>.jsonl
```

其中 `<session-id>` 是 UUID，JSONL 内容包含 `sessionId` 等 session 元数据和后续事件。

### Ralph 采集方式

推荐执行策略：

```bash
session_id="$(ralph_gen_uuid)"   # 见末尾 UUID 依赖说明
claude -p "$prompt" \
  --session-id "$session_id" \
  --dangerously-skip-permissions \
  --allowedTools "$ALLOWED_TOOLS" \
  --output-format stream-json \
  --verbose
```

`ALLOWED_TOOLS` 固定值：`"Bash,Read,Edit,Write,Glob,Grep"`（NFR-SEC-002 写死，不做开关）。

采集步骤：

- 每轮由 Ralph 生成 UUID，并通过 `--session-id` 传给 Claude。
- 不传 `--continue`、`--resume`、`--fork-session`。
- 不传 `--no-session-persistence`。
- stdout（stream-json events 流）+ stderr 全量保存为 `rounds/round-NNN/provider.stdout.log`。
- provider 退出后，按 `<claude_root>/projects/<cwd_hash>/<session_id>.jsonl` 定位 session 文件，其中 `claude_root = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}`（CLAUDE_CONFIG_DIR 由 RALPH_PROVIDER_CONFIG_DIR 翻译而来，见本文 §Adapter 配置目录翻译契约 + REQ-022）。`cwd_hash` 规则：先 `realpath` 解析 symlink，再把所有非 `[A-Za-z0-9-]` 字符替换为 `-`。
- 找到后复制为 `rounds/round-NNN/session.claude.jsonl`。
- 若未找到，按 `meta.json.provider_started_at` 时间戳（-1s 缓冲）作 mtime fallback 搜索 session_dir 下 `*.jsonl`。

选择 `--output-format stream-json --verbose`（events 流）而非 `--output-format json`（单 JSON 对象）：events 流可实时观察 agent 行为（dogfood / `-v` live tail）；末尾 `result` event 含 `is_error` / `result` / `usage` 字段，diagnose 用 `grep ^{ | jq 'select(.type == "result")' | tail -1` 提取末尾 result 事件解析。`provider.stdout.log` 里的 events 与 `~/.claude/projects/<hash>/<id>.jsonl` 内容相同（provider 双写）；保留 native session 拷贝作 30 天过期后的长期 anchor + 派生 bug 回滚。

这样可以避免根据 project path 编码规则盲目拼目录，也避免依赖 mtime 猜最新文件。

## Codex CLI

### Session 机制

Codex CLI 支持交互和非交互两类入口：

```bash
codex
codex exec "task"
```

官方文档明确 Codex 会把 transcript 保存在本地，用户可以通过 `resume` 继续历史会话：

```bash
codex resume
codex resume --last
codex resume <SESSION_ID>
codex exec resume --last "next task"
codex exec resume <SESSION_ID> "next task"
```

Codex 文档还说明：

- `codex exec` 用于脚本和 CI 风格的非交互任务。
- `codex exec --json` 会把运行事件输出为 JSONL（到 stdout），事件类型包括 `thread.started`、`turn.started`、`item.started`、`item.completed`、`turn.completed`、`turn.failed` 和 `error`。
- `thread.started` 事件含 `thread_id` 字段（与 rollout 文件名中的 session ID 一致）。
- `codex exec --ephemeral` 会跳过 session rollout 文件持久化。
- `--full-auto` 已废弃。ralph 使用 `--sandbox danger-full-access`，因为 ralph oneshot 协议要求 agent 执行 `git add -A && git commit`，真实 Codex CLI 的 `workspace-write` 会禁止写 `.git/index.lock`。
- session ID 可从 picker、`/status` 或 `~/.codex/sessions/` 下的文件获取。
- `CODEX_API_KEY` 环境变量仅在 `codex exec` 中支持，用于 CI 认证。
- effort 通过 config key `model_reasoning_effort` 控制（值：`minimal | low | medium | high | xhigh`），CLI 传递方式为 `-c model_reasoning_effort=<value>`；不存在 `--reasoning-effort` flag。

本机观测到的文件形态：

```text
${CODEX_HOME:-$HOME/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl
```

Rollout 文件首行是 `session_meta` 类型，其中包含 `payload.id`、`payload.cwd`、`payload.cli_version` 等元数据。后续行使用与 stdout JSONL 不同的事件格式：`event_msg`、`response_item`、`turn_context` 等（rollout 是 Codex 内部 transcript 格式，用于 resume；stdout `--json` 是面向外部消费的结构化事件流）。

### Ralph 采集方式

推荐执行策略：

```bash
codex exec --json \
  -C "$workspace" \
  --sandbox danger-full-access \
  "$prompt"
```

采集步骤：

- 使用 `-C "$workspace"` 明确 workspace root。
- 使用 `--json` 获取 JSONL 事件流（到 stdout）。
- 使用 `--sandbox danger-full-access`，确保 Codex 能完成 `.git/` 写入和本轮 commit；外层仍由 ralph 固定 workspace、任务清单和运行目录边界。
- 不传 `--ephemeral`。
- 不使用 `codex exec resume`；resume 是明确非目标（见需求文档非目标段）。
- 不传 `--full-auto`（已废弃）。
- stdout/stderr 全量保存为 `rounds/round-NNN/provider.stdout.log`。
- 从 stdout JSONL 中解析 `thread.started` 事件的 `thread_id` 字段。
- provider 退出后，在 `${CODEX_HOME:-$HOME/.codex}/sessions/` 下递归查找文件名包含该 `thread_id` 的 `rollout-*.jsonl`。
- 找到后复制为 `rounds/round-NNN/session.codex.jsonl`。
- 若没有拿到 `thread_id`，退化为查找 started_at 之后修改、且首行 `session_meta.payload.cwd` 等于 workspace 的候选文件。

Ralph 不额外保存 `session.codex.stdout.jsonl`：`--json` stdout 事件流已作为 `provider.stdout.log` 全量保存，与 4 文件 round 契约一致，不引入额外持久化文件。

### Effort 映射

Ralph `--effort=low|medium|high` 映射为 `-c model_reasoning_effort=<value>`。`none` 或留空不传。Codex 原生支持 `minimal | low | medium | high | xhigh`，Ralph 不暴露 `minimal` 和 `xhigh`。

## Gemini CLI

### Session 机制

Gemini CLI 支持交互和 headless 两类入口：

```bash
gemini
gemini -p "query"
```

官方文档明确 Gemini 会自动保存 session，并支持：

- `--resume` / `-r`：恢复历史 session。
- `--resume latest`：恢复最近 session。
- `--resume <index>`：按 `--list-sessions` 中的 index 恢复。
- `--resume <uuid>`：按 session UUID 恢复。
- `/resume`：交互模式打开 Session Browser。
- `--list-sessions`：列出当前 project 的 session。
- `--delete-session`：删除 session。
- `--output-format text|json|stream-json`：输出格式（I4 DEV-1 校准：`stream-json` 支持，可用于结构化输出和实时事件流）。

I4 DEV-1（2026-05-04）本机 Gemini CLI `0.39.1` 校准结果：

- `--yolo` 已被官方 CLI reference 标记为 deprecated，推荐使用 `--approval-mode=yolo`（二者行为等价，`--yolo` 仍可用但不建议新代码使用）。
- 新 workspace 必须带 `--skip-trust`，否则真实 Gemini CLI 会把 `--approval-mode yolo` 降回 `default`。
- `--thinking-budget` 不是 CLI flag；`thinkingBudget` 是 `settings.json` 中 `modelConfigs` 的内部配置，不暴露命令行入口。Ralph `--effort` 无法翻译为 Gemini CLI flag，暂不传递。
- `--output-format stream-json` 支持，可用于结构化错误诊断和 live tail（与 Claude/Codex 对齐）。

官方文档说明 session 存储在：

```text
${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/<project-identifier>/chats/
```

scope 是 project-specific。切换目录会切换 session history。

本机 Gemini CLI 通过 `~/.gemini/projects.json` 管理 project root 到 project identifier 的映射（如 `/Users/hedy/Develop/code/trantor-project` → `trantor-project`），并会迁移旧 hash 目录。Ralph 不应自行计算或拼接 `<project_hash>` 或 `<project-identifier>`。

本机观测到的文件形态：

```text
${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/<project-identifier>/chats/session-YYYY-MM-DDTHH-MM-<session-id-prefix>.json
```

JSON 内容包含 `sessionId`、`projectHash`、`startTime`、`lastUpdated`、`messages` 和 `kind`。

### Ralph 采集方式

推荐执行策略：

```bash
gemini -p "$prompt" --approval-mode yolo --skip-trust --output-format stream-json
```

采集步骤：

- 在 workspace root 下执行 Gemini。
- 不传 `--resume`。
- stdout/stderr 全量保存为 `rounds/round-NNN/provider.stdout.log`。
- 优先方式：若 `--output-format stream-json` 输出包含 session id（初始化事件），精确匹配 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/` 下 `sessionId` 等于该 ID 的文件。
- 退化方式：按 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/` 筛选 mtime 大于 started_at 的 JSON 文件，按 mtime 升序排列，取最后一个作为本轮 session。
- 找到后复制为 `rounds/round-NNN/session.gemini.json`。
- 若候选为空，记录 warning。

`GEMINI_CLI_HOME` 隔离说明（I4 DEV-1 校准）：

- `GEMINI_CLI_HOME` 由 `RALPH_PROVIDER_CONFIG_DIR` 翻译而来（adapter source 时 export）。
- 该变量改变 Gemini CLI 的根目录（CLI 在该目录下创建 `.gemini/`），影响配置、认证存储和 session 位置。
- adapter session 采集路径必须感知该变量：`${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/...`。

### Effort 映射

Gemini CLI 无 `--thinking-budget` 或等价 CLI flag。`thinkingBudget` 仅可通过 `settings.json` 的 `modelConfigs` 配置，不在命令行暴露。

Ralph `--effort` 对 Gemini **不传递**（`none` 或留空同样不传）。未来若 Gemini CLI 新增 CLI 入口，再扩展映射。

### History 派生

Gemini `session.history.log` 从 `provider.stdout.log`（`--output-format stream-json` stdout 事件流）派生。真实 CLI 事件类型（2026-05-06 校准 stdout 实测）：

- `init`：含 `session_id` + `model` 字段（session capture 用），history 派生跳过
- `message`：含 `role`（`user` / `assistant`）+ `delta`（boolean）+ `content`（字符串）字段；assistant 消息为流式 delta 片段，派生时按相邻 delta 聚合为单个 `[assistant]` 块
- `tool_use`：含 `tool_name` + `tool_id` + `parameters` 字段，标记为 `[tool-use <tool_name>]`，parameters 截断 2000 字符
- `tool_result`：含 `tool_id` + `status` + `output` 字段，标记为 `[tool-result]`，output 截断 2000 字符
- `result`：含 `status` + `stats`（total_tokens / tool_calls / duration_ms 等）字段，标记为 `[result]`，无独立 text 字段

## 错误诊断（续 Gemini）

- **Gemini**（I4 DEV-1 校准）：`--output-format stream-json` 模式下，stdout 为 JSONL 事件流，可解析结构化错误事件。退化模式（`text` 或无 `stream-json`）依赖 exit code + stderr 关键字。按以下互斥优先级（case-insensitive）匹配，命中第一条即止：
  1. `401` / `unauthor` / `not logged in` → `auth`
  2. `429` / `rate.?limit` / `too many requests` → `rate_limit`
  3. `quota` / `credits exhausted` / `billing` → `quota`
  4. `ECONNRESET` / `ETIMEDOUT` / `ENOTFOUND` / `fetch failed` / `connection refused` / `network error` → `network`
  5. 其他 provider 明确错误（含 5xx） → `api`
  6. 无明确错误 → `unknown`

## 错误诊断

provider exit code 0 不等于 agent 成功。Ralph 需要按 provider 协议做二次诊断。统一错误类别表见 [`overview.md#错误诊断类别`](./overview.md#错误诊断类别)；provider 特定字段和关键字如下：

- **Claude**：stream-json events 末尾的 `result` 事件 (`{type:"result", ...}`) 如果 `is_error: true`，说明 provider 通道成功但 agent 逻辑失败。常见子类：
  - API 错误（401 / 5xx）：`result` 含 `unauthor`、`api`、`5xx` 等关键字 → 归入 `auth` 或 `api`。
  - `tool_use_concurrency` 错误：Claude 自身 tool_use 并发态异常 → 归入 `concurrency`，下一轮必须丢弃本 session，重新 `--session-id`，不复用。
- **Codex**：`codex exec --json` 的事件流里，`turn.failed` 是最终权威失败事件（retry 循环里单条 `error` 事件可能被后续重试覆盖）。两者同时存在时以 `turn.failed.error.message` 为准。按以下互斥优先级（case-insensitive）匹配 message，命中第一条即止：
  1. `401` / `unauthor` / `invalid api key` / `not logged in` → `auth`
  2. `429` / `rate.?limit` / `too many requests` → `rate_limit`
  3. `quota` / `credits exhausted` / `billing` → `quota`
  4. `ECONNRESET` / `ETIMEDOUT` / `ENOTFOUND` / `fetch failed` / `connection refused` / `network error` → `network`
  5. 其他 provider 明确错误（含 5xx） → `api`
- **Gemini**：`--output-format stream-json` 模式下从 stdout 事件流诊断；退化时依赖 exit code + stderr 关键字。详细规则见下文 §Gemini CLI 错误诊断。

诊断结果写入 `rounds/round-NNN/meta.json`，并作为 `result.json` 的聚合错误摘要。
...
## 统一采集输出

每轮目录（每轮只有一个 provider，按 provider 出现对应 session 文件）：

```text
.ralph/runs/<run-id>/
  rounds/
    round-001/
      meta.json                       # 元数据 + runtime_block + provider_started_at + capture_status
      provider.stdout.log             # provider stdout (events 流) + stderr 全量 tee
      session.<provider>.<ext>        # native session 副本（Claude/Codex 为 .jsonl，Gemini 为 .json；命名见上文 §round 目录文件结构）
      session.history.log             # 跨 provider 人话视图（user / assistant / thinking / tool-use / tool-result / result）
```

`meta.json` 权威 schema 在 [`overview.md#round-nnnmetajson-schema`](./overview.md#round-nnnmetajson-schema)；session 相关字段：

- `provider`
- `session_id`
- `session_source_path`（provider 原生 session 文件的绝对路径）
- `session_copied_path`（`round-NNN/session.<provider>.*` 的相对路径）
- `capture_status`：`ok` / `missing` / `warning`
- `capture_warning`：自由文本
- `exit_code`
- `duration_ms`
- `error`：`null` 或 `{ type, message, raw }`（来自错误诊断）
- `changed_files_total`：自 run 启动至本轮结束的累计文件变更
- `changed_files_round`：本轮（vs 上轮）的文件变更，用于 stall 判定

这些字段是采集元数据，不替代 `.ralph/TASKS.md` 中的任务完成记录。

## UUID 依赖

Claude session 锚点依赖 UUID 生成。macOS 自带 `uuidgen`；Linux 上 `uuid-runtime` 不一定预装。Ralph 应按以下顺序生成 UUID：

1. `uuidgen 2>/dev/null`（util-linux / macOS）。
2. `cat /proc/sys/kernel/random/uuid`（大部分 Linux 内核）。
3. `python3 -c 'import uuid; print(uuid.uuid4())'`。

若三种都失败，`ralph run` 启动校验阶段给出明确报错，提示用户安装 `uuid-runtime` 或保证 `python3` 可用（无 `ralph init`）。

## 风险与边界

- provider native session 文件通常包含完整 prompts、tool outputs、命令结果和可能的敏感信息。
- `.ralph/runs/` 默认应被 `.ralph/.gitignore` 忽略。
- `log` 和 `session.*` 都是本地复盘材料，不应默认提交到 git。
- provider 的 session store 是各自产品内部实现，Ralph adapter 必须按 provider 和版本做 best-effort 采集，并在失败时保留 process log。
- Ralph 默认 fresh oneshot；resume 是明确非目标（需求文档非目标段），不由 session capture 需求间接启用。
