# Integrations

- 状态：已确认（Codex DEV-1 校准 2026-05-03 / Antigravity DEV-9 校准 2026-09-28）；**支持矩阵包含 Claude Code、Codex CLI 和 Antigravity CLI**。
- 来源：`docs/features/ralph-loop/requirements.md`（REQ-005 / REQ-006 / REQ-011 / FR-006 / FR-008 / NFR-SEC-002 / REQ-028 / REQ-029 / REQ-030 / REQ-031）、`docs/features/antigravity-cli/requirements.md`（REQ-048 ~ REQ-053）、本机 provider CLI help 与会话目录观测、相关官方文档。
- 范围：本文定义 Ralph harness 与外部 provider CLI 的集成契约：命令构造、session 采集、错误诊断关键字、UUID 依赖和降级策略。当前生效范围是 Claude Code、Codex CLI 与 Antigravity CLI。跨 provider 的公共主循环、运行目录 schema 在 [`architecture.md`](./architecture.md)；approval/sandbox 的安全边界在 [`security.md`](./security.md)。本文不重写需求正文、不描述 adapter 之外的命令封装形式。
- 变更条件：任一 provider CLI 升级改变 session 路径、事件格式或 flag 语义；新增 provider；NFR-SEC-002 变更导致 approval 策略调整；`.ralph/runs/` 布局变化影响 session 拷贝位置。

## 证据范围

本文基于官方文档、本机 CLI help 和本机会话目录观测。

初始校准版本（历史记录，不代表当前安装版本）：

- Claude Code：`2.1.114`
- Codex CLI：`0.125.0`（CLI）；Desktop app 内核 `0.128.0-alpha.1`
- Antigravity CLI：`1.2.12`（CLI 名称 `agy`）

2026-10-09 的发布烟测使用 Codex CLI `0.159.2`、Claude Code `2.1.284`、Antigravity `1.3.2`；实际 run 与验证边界见 [测试文档](./testing.md)。

参考资料：

- Claude Code CLI reference: <https://docs.claude.com/en/docs/claude-code/cli-reference>
- Claude Code data usage: <https://docs.claude.com/en/docs/claude-code/data-usage>
- Codex CLI features: <https://developers.openai.com/codex/cli/features>
- Codex CLI command line options: <https://developers.openai.com/codex/cli/reference>
- Codex non-interactive mode: <https://developers.openai.com/codex/noninteractive>
- Antigravity CLI 集成方案: `docs/features/antigravity-cli/solution.md`

## round 目录文件结构（4 文件契约）

每轮 round 目录按统一契约保存以下四类文件；原生 session 副本仅在安全采集成功时出现：

| 文件 | 含义 | 出现条件 |
|---|---|---|
| `meta.json` | round 元数据（含 session_id / provider_started_at / runtime_block / capture_status / error / 任务进度 / changed_files / stall_count 等） | 始终 |
| `provider.stdout.log` | provider CLI stdout + stderr 合流原始输出（含 stream-json 事件、错误信息） | 始终 |
| `session.<provider>.jsonl` | provider 原生 session 文件副本（保留 30 天后过期 / 派生视图 bug 回滚 / 跨机器 evidence 自包含三个用途） | session 安全采集成功；Antigravity 不使用 mtime fallback |
| `session.history.log` | 跨 provider 人话视图（provider 间内容有差异：Claude 含 user/assistant/thinking/tool-use/tool-result，Codex 含 assistant/tool-use/tool-result 但无 user/thinking，Antigravity 含 session/assistant/tool-use/tool-result/subagent/result），Claude 从 `session.claude.jsonl` 派生，Codex 从 `provider.stdout.log`（`--json` stdout 事件流）派生，Antigravity 从 `provider.stdout.log`（`--output-format stream-json` 事件流）派生；完整 tool input 保留在各派生源中 | 始终；Antigravity 原生 session 缺失时仍可从 stdout 派生 |

各 provider native session 文件实例：
- Claude：`session.claude.jsonl`（从 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd_hash>/<session_id>.jsonl` 复制；stream-json 模式下与 stdout 事件流内容相同，但保留独立副本作为 30 天后回看 anchor）
- Codex（T3 落地）：`session.codex.jsonl`（从 `~/.codex/sessions/rollout-*-<thread_id>.jsonl` 复制；另有归档目录兼容与 id 校验路径，见 REQ-030）
- Antigravity（T5 落地）：`session.antigravity.jsonl`（默认优先从 `$HOME/.gemini/antigravity-cli/brain/<conversation_id>/.system_generated/logs/transcript.jsonl` 复制；再检查 `$HOME/.gemini/antigravity/`，显式设置 `ANTIGRAVITY_APP_DATA_DIR` 时优先检查该目录；仅复制与本轮 `conversation_id` 对应且通过路径安全校验的文件，缺失时降级为 warning）

不再保留：
- `session.<provider>.stdout.<ext>`（与 `provider.stdout.log` 字节相同，重复）
- `chat.log` / `tools.log`（合并进 `session.history.log`，避免双视图）
- round 内的 `prompt.md` / `.session_start`（前者由 run 级 `protocol.md` + `meta.json.runtime_block` 还原输入；后者由 `meta.json.provider_started_at` 时间戳替代）

新增 provider 必须遵循此 4 文件契约；偏离需通过新需求或文档 PR 显式覆盖。

## 总体原则

Ralph 默认使用 provider 的 fresh oneshot 执行，不默认 resume。session 采集只用于复盘分析，不作为任务完成事实源。

每轮至少保存两类证据：

- process log：provider CLI 的 stdout/stderr 原始输出，保存到 `rounds/round-NNN/provider.stdout.log`。
- native session：provider 自己持久化的会话文件；安全采集成功时复制到 `rounds/round-NNN/session.<provider>.jsonl`。

采集失败不能直接判定任务失败。失败时应记录 warning，并继续使用 process log 和 `.ralph/TASKS.md` 判断 run 状态。

## Adapter 配置目录翻译契约

REQ-022 引入的隐式契约（不增三函数签名）。支持独立配置目录的 adapter 在 source 时执行：

- 检查 ralph 中立变量 `RALPH_PROVIDER_CONFIG_DIR` 是否非空。
- 非空 → `export <provider 原生环境变量>="$RALPH_PROVIDER_CONFIG_DIR"`，让 provider CLI 子进程读独立 config dir；Antigravity 无已验证的配置覆盖方式，因此拒绝非空值。
- 空或未设 → 不 export（避免空值干扰 provider 默认行为）。

各 provider 翻译目标：

| Provider | 原生环境变量 | 来源 / 备注 |
|---|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` | 官方 [authentication.md](https://code.claude.com/docs/en/authentication.md)；macOS 上当 settings.json 含 API key / apiKeyHelper / `ANTHROPIC_BASE_URL` 时切换该目录 = 切换账号（OAuth/Keychain 不参与） |
| Codex CLI | `CODEX_HOME` | 官方 config-reference `log_dir` 说明"defaults to `$CODEX_HOME/log`"；CLI `--ignore-user-config` help 明确"auth still uses `CODEX_HOME`"；默认 `~/.codex` |
| Antigravity CLI | 暂无（显式设值报错） | 官方暂未提供可验证的独立配置目录覆盖参数；显式设置 `RALPH_PROVIDER_CONFIG_DIR` 时 fail-fast 报错退出（exit 1），防止未隔离运行 |
| fake adapter | n/a | 测试用，不读真实 provider 配置 |

实现位置：`.ralph/lib/adapter-<provider>.sh` 顶部 source 时执行的检查或翻译逻辑（不放进 `provider_oneshot` / `provider_collect_session` / `provider_diagnose` 函数体内）。

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

`ALLOWED_TOOLS` 固定值：`"Bash,Read,Edit,Write,Glob,Grep"`（NFR-SEC-002 写死，不做开关）。**注意该参数不是工具限制**：`--allowedTools` 是 pre-approve（allow）规则，官方明确 "Allow rules have no effect in `bypassPermissions`"，而本命令同时传了 `--dangerously-skip-permissions`，因此这 6 项清单不构成 Claude 的能力边界（详见 [`security.md` §Approval / Sandbox 固定策略](./security.md#approval--sandbox-固定策略)）。要收窄可用工具需改用 `--tools`（需新 REQ）。

采集步骤：

- 每轮由 Ralph 生成 UUID，并通过 `--session-id` 传给 Claude。
- 不传 `--continue`、`--resume`、`--fork-session`。
- 不传 `--no-session-persistence`。
- stdout（stream-json events 流）+ stderr 全量保存为 `rounds/round-NNN/provider.stdout.log`。
- provider 退出后，按 `<claude_root>/projects/<cwd_hash>/<session_id>.jsonl` 定位 session 文件，其中 `claude_root = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}`（CLAUDE_CONFIG_DIR 由 RALPH_PROVIDER_CONFIG_DIR 翻译而来，见本文 §Adapter 配置目录翻译契约 + REQ-022）。`cwd_hash` 规则：先用 `cd -- "$path" && pwd -P` 解析目录物理路径（不依赖外部 `realpath` 命令），再把所有非 `[A-Za-z0-9-]` 字符替换为 `-`。
- 物理路径解析失败时写入 `capture_status=warning` 和 `workspace physical path resolution failed`，不继续用空路径搜索；该可选采集失败不阻塞 run。
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
- `--full-auto` 已废弃。ralph 保留既有 `--sandbox danger-full-access` 契约，以支持获授权的 `.git/` 写入；真实 Codex CLI 的 `workspace-write` 曾禁止写 `.git/index.lock`。是否暂存、提交仍由用户、项目及工作包授权决定，禁止提交不会自动改变沙箱参数。
- **`danger-full-access` 的权限含义**：移除本地沙箱限制，模型生成的 shell 命令不再受 workspace 边界约束，以当前用户身份在整机可达范围内执行；REQ-031 的"等同于 workspace 内任意写入权限"是这条的下界。该取值写死在 `adapter-codex.sh`，不随 `.env` / CLI flag 变化。权限语义、风险承担和审计路径的权威表述在 [`security.md` §Approval / Sandbox 固定策略](./security.md#approval--sandbox-固定策略) 与 §权限参数的审计路径；配置目录翻译（`RALPH_PROVIDER_CONFIG_DIR` → `CODEX_HOME`）只影响凭据/配置来源，不影响沙箱模式。`--sandbox` 取值清单来自本机 `codex exec --help`（`read-only` / `workspace-write` / `danger-full-access`）。
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
- 使用 `--sandbox danger-full-access`，支持获授权的 `.git/` 写入和提交；外层仍由 ralph 固定 workspace、任务清单和运行目录边界，不构成文件系统写隔离。
- 不传 `--ephemeral`。
- 不使用 `codex exec resume`；resume 是明确非目标（见需求文档非目标段）。
- 不传 `--full-auto`（已废弃）。
- stdout/stderr 全量保存为 `rounds/round-NNN/provider.stdout.log`。
- 从 stdout JSONL 中解析 `thread.started` 事件的 `thread_id` 字段。
- provider 退出后，在 `${CODEX_HOME:-$HOME/.codex}/sessions/` 下递归查找文件名包含该 `thread_id` 的 `rollout-*.jsonl`。
- 找到后复制为 `rounds/round-NNN/session.codex.jsonl`。
- 若没有拿到 `thread_id`，退化为查找 started_at 之后修改、且首行 `session_meta.payload.cwd` 等于 workspace 的候选文件。

Ralph 不额外保存 `session.codex.stdout.jsonl`：`--json` stdout 事件流已作为 `provider.stdout.log` 全量保存，与 4 文件 round 契约一致，不引入额外持久化文件。

Codex 执行可观察性：命令完成事件的输出取自官方 `item.aggregated_output`（兼容 `output` / `stdout`），退出码和失败状态进入显示摘要与派生 history。事件字段以 [Codex 官方类型定义](https://github.com/openai/codex/blob/main/sdk/typescript/src/items.ts) 为核对入口；mock 必须使用真实字段，不允许因 fixture 与解析器共同写错而假通过。实时视图另外显示 provider 提供的 reasoning 摘要、文件变更、MCP 操作和搜索；这不是隐藏思考的获取机制。

### Effort 映射

Ralph `--effort=low|medium|high` 映射为 `-c model_reasoning_effort=<value>`。`none` 或留空不传。Codex 原生支持 `minimal | low | medium | high | xhigh`，Ralph 不暴露 `minimal` 和 `xhigh`。

## Antigravity CLI

### Session 机制

Antigravity CLI 支持交互和非交互两类入口：

```bash
agy
agy --print "query" --output-format stream-json --dangerously-skip-permissions
```

相关特性与 session 机制：

- `agy --print "$prompt"` 用于非交互模式直接执行单个 prompt。
- `--output-format stream-json` 会把运行事件输出为结构化 JSONL（到 stdout），事件流包含 `init`、`step_update` 和 `result`。
- `init` 事件中包含当前会话的 `conversation_id`。
- `result` 事件中包含 `status`（如 `"SUCCESS"` / `"FAILURE"`）以及 `denied_actions` 数组。
- Antigravity 原生 session 存储在：

```text
$HOME/.gemini/antigravity-cli/brain/<conversation_id>/.system_generated/logs/transcript.jsonl
```

Adapter 还会检查显式 `ANTIGRAVITY_APP_DATA_DIR`（优先）和旧目录 `$HOME/.gemini/antigravity`；每个会话目录优先选择非空的 `transcript.jsonl`，否则尝试 `transcript_full.jsonl`。
- Session 采集必须通过 `conversation_id` 强校验：只有与当前轮 `init` 事件中 `conversation_id` 完全一致的文件才会被采集，严格杜绝跨会话误采（0 次误采契约）。
- 当原生 session 缺失时（如环境未落盘或清理），安全降级为 warning（不阻塞 oneshot 流程），此时 `provider.stdout.log` 作为第一事实源（primary source of truth）完整保留全部运行事件与证据，并派生 `session.history.log`。

### Ralph 采集方式

推荐执行策略：

```bash
agy --print "$prompt" \
  --output-format stream-json \
  --dangerously-skip-permissions \
  [--model <model>]
```

采集与流转步骤：

- 使用 `--print "$prompt"` 注入组合好的 oneshot prompt。
- 使用 `--output-format stream-json` 获取结构化 JSONL 事件流（stdout）。
- 使用 `--dangerously-skip-permissions` 绕过工具调用确认，让 agent 以当前用户身份直接执行工具。
- stdout / stderr 原始输出合流保存为 `rounds/round-NNN/provider.stdout.log`。
- 从 `provider.stdout.log` 的 `init` 事件中提取 `conversation_id`。
- 按上述目录优先级检查本轮会话的原生 transcript；只有非空普通文件通过会话目录和文件物理路径校验且复制成功时，才写入 `session.antigravity.jsonl` 和 `capture_status=ok`，否则写入 `capture_status=warning` 与原因。
- 从 `provider.stdout.log` 派生 `session.history.log`：解析 `init` 会话 ID、`step_update` 中的 assistant 文本增量、工具名与输出、子 agent 摘要，并记录 `[result] status=<status>`；未出现在原始事件中的 thinking 不补造。
- 实时观察用 `watch --details`：兼容嵌套 `step_update` 与旧的顶层字段，区分工具 ACTIVE/DONE/ERROR；`tool_info.error` 优先于 DONE 状态判断失败，保留同时提供的输出，并展示终态 `result.response` 中的最终回复。此入口不读取 provider 原生目录。
- 2026-10-09 核对本机 `agy 1.3.2 --help` 与[官方 headless 协议](https://www.antigravity.google/docs/cli/headless/)：未发现公开的思考正文输出开关或流式 thinking 字段；`usage.thinking_tokens` 只是计数。现场流没有思考正文，而采集的原生 transcript 有 thinking，故不能承诺此版本实时显示思考。若事件实际提供 thinking/thinking_delta，显示层会展示；缺失时仍可观察回复、工具过程及结果。

### 参数映射

- `--model <name>`：直接透传为 `--model <name>`。未设置时不传。
- `--effort`：`low` / `medium` / `high` 有值时透传给 `agy --effort`；`none` 或留空时不传。
- `RALPH_PROVIDER_CONFIG_DIR`：Antigravity CLI 暂无独立配置覆盖支持，显式设置时在启动校验阶段报错（exit 1），防止未隔离运行。

## 错误诊断

provider exit code 0 不等于 agent 成功。Ralph 需要按 provider 协议做二次诊断。统一错误类别表见 [`architecture.md#错误诊断类别`](./architecture.md#错误诊断类别)；provider 特定字段和关键字如下：

- **Claude**：stream-json events 末尾的 `result` 事件 (`{type:"result", ...}`) 如果 `is_error: true`，说明 provider 通道成功但 agent 逻辑失败。常见子类：
  - API 错误（401 / 5xx）：`result` 含 `unauthor`、`api`、`5xx` 等关键字 → 归入 `auth` 或 `api`。
  - `tool_use_concurrency` 错误：Claude 自身 tool_use 并发态异常 → 归入 `concurrency`，下一轮必须丢弃本 session，重新 `--session-id`，不复用。
- **Codex**：`codex exec --json` 的事件流里，`turn.failed` 是最终权威失败事件（retry 循环里单条 `error` 事件可能被后续重试覆盖）。两者同时存在时以 `turn.failed.error.message` 为准。按以下互斥优先级（case-insensitive）匹配 message，命中第一条即止：
  1. `401` / `unauthor` / `invalid api key` / `not logged in` → `auth`
  2. `429` / `rate.?limit` / `too many requests` → `rate_limit`
  3. `quota` / `credits exhausted` / `billing` → `quota`
  4. `ECONNRESET` / `ETIMEDOUT` / `ENOTFOUND` / `fetch failed` / `connection refused` / `network error` → `network`
  5. 其他 provider 明确错误（含 5xx） → `api`
- **Antigravity**：从 `provider.stdout.log` 的 `result` 事件与合流日志综合诊断：
  - 软拒绝识别：若 `result` 事件中包含非空 `denied_actions`，即便 CLI exit code 为 0，也强制覆盖归入 `permission` 错误，并由 adapter 返回退出码 2。
  - 错误分类（case-insensitive）：
    1. `401` / `unauthor` / `not logged in` → `auth`
    2. `429` / `rate.?limit` / `too many requests` → `rate_limit`
    3. `quota` / `credits exhausted` / `billing` → `quota`
    4. `ECONNRESET` / `ETIMEDOUT` / `ENOTFOUND` / `fetch failed` / `connection refused` / `network error` → `network`
    5. `denied_actions` / `permission` → `permission`
    6. 其他 provider 明确错误（含 5xx） → `api`
    7. 否则 → `unknown`

诊断结果写入 `rounds/round-NNN/meta.json`，并作为 `result.json` 的聚合错误摘要。

## 终态事件契约

REQ-029 契约（SC-029-1 / SC-029-2 / SC-051-1）：**进程退出码不等于 provider 产出了终态事件**。Claude / Codex / Antigravity adapter 每轮必须把结构化终态写入 `meta.json`，原始证据单独保留。

| 字段 | 取值 | 含义 |
|---|---|---|
| `terminal_event` | `result`（Claude/Antigravity）/ `turn.completed` / `turn.failed` / `error`（Codex）/ `null` | 判定终态所依据的事件类型；无可用终态事件时为 `null` |
| `terminal_status` | `success` / `error` / `unknown` | 终态判定结果；`unknown` = 无终态事件或事件不可解析 |
| `terminal_warning` | 自由文本 / `null` | `unknown` 或退化判定的原因说明（诊断入口） |

判定规则：

- **Claude**：末尾 `result` 事件 `is_error=false` → `success`；`is_error=true` → `error`（adapter 返回非零，即使 CLI 退出码为 0）；无 `result` 事件，或 `is_error` 缺失/非布尔 → `unknown` + `terminal_warning`。
- **Codex**：末尾 `turn.completed` → `success`；`turn.failed` → `error`（`turn.*` 是权威终态，`turn.completed` 之后的 `error` 事件不覆盖它）；无 `turn.*` 时末尾 `error` 事件退化为 `error` 并写 `terminal_warning`；三者皆无 → `unknown` + `terminal_warning`。
- **Antigravity**：末尾 `result` 事件 `status == "SUCCESS"` 且 `denied_actions` 为空、无结构化错误 → `success`；`denied_actions` 非空、非空错误对象或字符串、`status == "ERROR"` → `error`；未识别的状态或无 `result` 事件 → `unknown` + `terminal_warning`。所有非成功情况 adapter 均返回非零，即使 CLI 退出码为 0；CLI 自身退出非零也会令 run 判为 `provider_failed`。
- `terminal_status=error` 时 adapter 返回非零，run 层按 `provider_failed` 处理；即终态事件可以推翻 CLI 的退出码，反之亦然（exit 0 + 无终态事件仍是 `unknown`）。

证据保留（SC-029-1）：`provider.stdout.log` 是唯一事实源，adapter 只读不写——解析、诊断、派生 `session.history.log` 都不截断、不重写、不删除该文件。截断行（timeout 杀进程、stderr 交错写入、CLI 崩溃）按原文保留；解析时先经 `ralph_json_lines`（`common.sh`）过滤掉结构不完整的行，避免 jq 在非法行上提前退出而丢掉其后的合法事件（jq 1.7 实测行为）。`fake` adapter 无事件流，保持三字段为 `null`。

## 统一采集输出

每轮目录（每轮只有一个 provider，按 provider 出现对应 session 文件）：

```text
.ralph/runs/<run-id>/
  rounds/
    round-001/
      meta.json                       # 元数据 + runtime_block + provider_started_at + capture_status
      provider.stdout.log             # provider stdout (events 流) + stderr 全量 tee
      session.<provider>.jsonl       # native session 副本（采集成功时存在）
      session.history.log             # 跨 provider 人话视图（user / assistant / thinking / tool-use / tool-result / result）
```

`meta.json` 权威 schema 在 [`architecture.md#round-nnnmetajson-schema`](./architecture.md#round-nnnmetajson-schema)；session 相关字段：

- `provider`
- `session_id`
- `session_source_path`（provider 原生 session 文件的绝对路径）
- `session_copied_path`（实际复制目标路径；现行 adapter 写入绝对路径）
- `capture_status`：`ok` / `missing` / `warning`
- `capture_warning`：自由文本
- `terminal_event` / `terminal_status` / `terminal_warning`：终态事件契约字段（见上文 §终态事件契约）
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
