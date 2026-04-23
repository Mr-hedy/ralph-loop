# Integrations

- 状态：已确认
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-005 / REQ-006 / REQ-011 / FR-006 / FR-008 / NFR-SEC-002）、2026-04-20 三家官方文档、本机 CLI help 与会话目录观测。
- 范围：本文定义 Ralph harness 与三个外部 provider CLI（Claude Code / Codex CLI / Gemini CLI）的集成契约：命令构造、session 采集、错误诊断关键字、UUID 依赖和降级策略。跨 provider 的公共主循环、运行目录 schema 在 [`overview.md`](./overview.md)；approval/sandbox 的安全边界在 [`security.md`](./security.md)。本文不重写需求正文、不描述 adapter 之外的命令封装形式。
- 变更条件：任一 provider CLI 升级改变 session 路径、事件格式或 flag 语义；新增第四个 provider；NFR-SEC-002 变更导致 approval 策略调整；`.ralph/runs/` 布局变化影响 session 拷贝位置。

## 证据范围

本文基于 2026-04-20 的官方文档、本机 CLI help 和本机会话目录观测。

本机版本：

- Claude Code：`2.1.114`
- Codex CLI：`0.121.0`
- Gemini CLI：`0.38.2`

参考资料：

- Claude Code CLI reference: <https://docs.claude.com/en/docs/claude-code/cli-reference>
- Claude Code data usage: <https://docs.claude.com/en/docs/claude-code/data-usage>
- Codex CLI features: <https://developers.openai.com/codex/cli/features>
- Codex CLI command line options: <https://developers.openai.com/codex/cli/reference>
- Codex non-interactive mode: <https://developers.openai.com/codex/noninteractive>
- Gemini CLI session management: <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/session-management.md>
- Gemini CLI reference: <https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md>

## 总体原则

Ralph 默认使用 provider 的 fresh oneshot 执行，不默认 resume。session 采集只用于复盘分析，不作为任务完成事实源。

每轮至少保存两类证据：

- process log：provider CLI 的 stdout/stderr 原始输出，保存到 `iterations/iter-xxx/log`。
- native session：provider 自己持久化的会话文件，复制到 `iterations/iter-xxx/session.<provider>.*`。

采集失败不能直接判定任务失败。失败时应记录 warning，并继续使用 process log 和 `.ralph/TASKS.md` 判断 run 状态。

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
  --output-format json
```

`ALLOWED_TOOLS` 固定值：`"Bash,Read,Edit,Write,Glob,Grep"`（NFR-SEC-002 写死，不做开关）。

采集步骤：

- 每轮由 Ralph 生成 UUID，并通过 `--session-id` 传给 Claude。
- 不传 `--continue`、`--resume`、`--fork-session`。
- 不传 `--no-session-persistence`。
- stdout/stderr 全量保存为 `iterations/iter-xxx/log`。
- provider 退出后，按 `~/.claude/projects/<cwd_hash>/<session_id>.jsonl` 定位 session 文件。`cwd_hash` 规则：先 `realpath` 解析 symlink，再把所有非 `[A-Za-z0-9-]` 字符替换为 `-`。
- 找到后复制为 `iterations/iter-xxx/session.claude.jsonl`。
- 若未找到，记录 warning；后续可退化为按 started_at 之后修改的 Claude JSONL 候选文件排查。

选择 `--output-format json`（单个 JSON 对象）而非 `--output-format stream-json`：单 JSON 更好解析，可以直接从 `.session_id`（或 `.metadata.session_id`）取锚点，从 `.is_error` 做错误诊断，从 `.usage` 取 token 统计。`stream-json` 只在需要实时监听时使用，Ralph v0 不需要。

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
- `codex exec --json` 会把运行事件输出为 JSONL，事件包括 `thread.started`、`turn.started`、`turn.completed`、`turn.failed`、`item.*` 和 `error`。
- `thread.started` 事件包含 `thread_id`。
- `codex exec --ephemeral` 会跳过 session rollout 文件持久化。
- session ID 可从 picker、`/status` 或 `~/.codex/sessions/` 下的文件获取。

本机观测到的文件形态：

```text
~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-id>.jsonl
```

JSONL 首行是 `session_meta`，其中包含 `payload.id`、`payload.cwd`、`payload.cli_version` 等元数据。

### Ralph 采集方式

推荐执行策略：

```bash
codex exec --json \
  -C "$workspace" \
  --sandbox workspace-write \
  "$prompt"
```

采集步骤：

- 使用 `-C "$workspace"` 明确 workspace root。
- 使用 `--json` 获取 JSONL 事件流。
- 使用 `--sandbox workspace-write` 让 Codex 在自带 sandbox 下写 workspace。
- 不传 `--ephemeral`。
- 不使用 `codex exec resume`；resume 是明确非目标（见需求文档非目标段）。
- stdout/stderr 全量保存为 `iterations/iter-xxx/log`。
- 从 stdout JSONL 中解析 `thread.started.thread_id`。
- provider 退出后，在 `~/.codex/sessions/` 下查找文件名包含该 `thread_id` 的 `rollout-*.jsonl`。
- 找到后复制为 `iterations/iter-xxx/session.codex.jsonl`。
- 同时把 Codex 的 `--json` stdout 原文保存为 `iterations/iter-xxx/session.codex.stdout.jsonl`，它本身就是 Codex 非交互模式下完整的事件流。
- 若没有拿到 `thread_id`，退化为查找 started_at 之后修改、且首行 `session_meta.payload.cwd` 等于 workspace 的候选文件。

Codex 的 `--json` 事件流本身也有复盘价值，但 Ralph 仍应复制 native rollout 文件，因为它是 Codex resume 使用的本地 transcript。

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
- `--output-format text|json|stream-json`：输出格式。

官方文档说明 session 存储在：

```text
~/.gemini/tmp/<project_hash>/chats/
```

并且 scope 是 project-specific。切换目录会切换 session history。

本机 Gemini CLI v0.38.2 源码和目录观测显示，新版本还通过 `~/.gemini/projects.json` 管理 project root 到 project identifier 的映射，并会迁移旧 hash 目录。因此 Ralph 不应自行计算或拼接 `<project_hash>`。

本机观测到的文件形态：

```text
~/.gemini/tmp/<project-identifier>/chats/session-YYYY-MM-DDTHH-MM-<session-id-prefix>.json
```

JSON 内容包含 `sessionId`、`projectHash`、`startTime`、`lastUpdated` 和 `messages`。

### Ralph 采集方式

推荐执行策略：

```bash
gemini -p "$prompt" --yolo
```

采集步骤：

- 在 workspace root 下执行 Gemini。
- 不传 `--resume`。
- stdout/stderr 全量保存为 `iterations/iter-xxx/log`。
- 优先方式：若输出包含 `session_id`（某些 Gemini 版本会在 stream-json 初始化事件里给出），精确匹配 `~/.gemini/tmp/*/chats/` 下 `sessionId` 等于该 ID 的文件。
- 退化方式：Gemini v0.38.x 的 `-p` 输出不稳定包含 session id 时，按 `~/.gemini/tmp/<basename>[-N]/chats/` 筛选 mtime 大于 started_at 的 JSON 文件，按 mtime 升序排列，取最后一个作为本轮 session。`<basename>` 是 workspace 目录名的小写。
- 找到后复制为 `iterations/iter-xxx/session.gemini.json`。
- 若候选为空，记录 warning。

不建议默认设置 `GEMINI_CLI_HOME` 隔离状态。该变量会改变 Gemini 的用户级配置和认证存储位置，适合未来 CI 或沙箱模式作为显式选项，不适合作为本地默认行为。

## 错误诊断

provider exit code 0 不等于 agent 成功。Ralph 需要按 provider 协议做二次诊断。统一错误类别表见 [`overview.md#错误诊断类别`](./overview.md#错误诊断类别)；provider 特定字段和关键字如下：

- **Claude**：`--output-format json` 的 stdout 顶层如果 `is_error: true`，说明 provider 通道成功但 agent 逻辑失败。常见子类：
  - API 错误（401 / 5xx）：`result` 含 `unauthor`、`api`、`5xx` 等关键字 → 归入 `auth` 或 `api`。
  - `tool_use_concurrency` 错误：Claude 自身 tool_use 并发态异常 → 归入 `concurrency`，下一轮必须丢弃本 session，重新 `--session-id`，不复用。
- **Codex**：`codex exec --json` 的事件流里，`turn.failed` 是最终权威失败事件（retry 循环里单条 `error` 事件可能被后续重试覆盖）。两者同时存在时以 `turn.failed.error.message` 为准。按以下互斥优先级（case-insensitive）匹配 message，命中第一条即止：
  1. `401` / `unauthor` / `invalid api key` / `not logged in` → `auth`
  2. `429` / `rate.?limit` / `too many requests` → `rate_limit`
  3. `quota` / `credits exhausted` / `billing` → `quota`
  4. 其他 provider 明确错误（含 5xx） → `api`
- **Gemini**：`-p` 模式下 stdout 不是结构化 JSON，只能依赖 exit code 和 stderr 关键字，若 session 文件里最后 `gemini` 消息带错误信息可以作为补充。

诊断结果写入 `iterations/iter-xxx/meta.json`，并作为 `result.json` 的聚合错误摘要。诊断本身不决定是否退出循环，但会影响：

- 是否在下一轮丢弃上轮 session（只对 Claude concurrency 生效，Ralph v0 默认 fresh 本来就满足）。
- 是否把本轮计入 stagnation（带错误的轮次计为无进展）。
- `result.json` 中 `last_error` 的 `type` 和 `message`。

## 统一采集输出

每轮目录（每轮只有一个 provider，按 provider 出现对应文件）：

```text
.ralph/runs/<run-id>/
  iterations/
    iter-001/
      log                             # provider stdout/stderr 原始输出（全量 tee）
      session.claude.jsonl            # Claude 选择时
      session.codex.jsonl             # Codex 选择时
      session.codex.stdout.jsonl      # Codex --json stdout 原文（与 session.codex.jsonl 并存）
      session.gemini.json             # Gemini 选择时
      chat.log                        # 派生视图：对话流（见 overview.md）
      tools.log                       # 派生视图：工具调用摘要（见 overview.md）
      meta.json
```

`meta.json` 权威 schema 在 [`overview.md#iter-xxxmetajson-schema`](./overview.md#iter-xxxmetajson-schema)；session 相关字段：

- `provider`
- `session_id`
- `session_source_path`（provider 原生 session 文件的绝对路径）
- `session_copied_path`（`iter-xxx/session.<provider>.*` 的相对路径）
- `capture_status`：`ok` / `missing` / `warning`
- `capture_warning`：自由文本
- `exit_code`
- `duration_ms`
- `error`：`null` 或 `{ type, message, raw }`（来自错误诊断）
- `changed_files`：`git diff --name-only <start_sha>..HEAD` ∪ `git status --porcelain`，过滤 `.ralph/`

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
