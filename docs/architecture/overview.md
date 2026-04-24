# Architecture Overview

- 状态：已确认
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-016，澄清结论 22 条决策）；本文在 design 层面给出稳定契约。
- 范围：本文承载 Ralph 系统上下文、主要组成、稳定契约（CLI、运行目录、adapter 接口、退出码、stagnation、lock、错误诊断类别）、关键数据流和架构文档索引。Provider 特定命令构造、session 路径和诊断关键字在 [`integrations.md`](./integrations.md)；approval / sandbox 策略和安全边界在 [`security.md`](./security.md)。
- 变更条件：CLI 契约、退出原因枚举、adapter 函数签名或 `.ralph/runs/<id>/` schema 变化时必须同步更新；并触发下游 `integrations.md` / `security.md` / 模块需求 / roadmap / task 检查。

## 总体模型

Ralph 是一个 shell-first CLI harness。它不做推理，只把长任务组织成多轮 provider CLI fresh oneshot 执行。

每轮执行流程：

1. 读 `.ralph/TASKS.md`，若全部勾选 → 退出 `done`
2. 拼 prompt：`.ralph/PROMPT.md` 全文 + runtime 上下文块（run_id、iteration、git sha 等）
3. 调 provider CLI oneshot，捕获 stdout/stderr
4. 采集 provider 原生 session → 派生 `chat.log` / `tools.log`
5. 错误诊断 + 收集 `changed_files`
6. 写 `iter-xxx/meta.json`、刷新 `status.json`
7. 判断退出条件（见 [退出原因](#退出原因)）；否则进入下一轮

Agent 端契约由 PROMPT.md 承载："每轮恰好完成一个未勾选任务并勾 `[x]`"（REQ-003）。

## 运行时伪代码

```text
ralph run
  workspace = dirname(dirname(realpath($BASH_SOURCE)))      # .ralph/bin/ralph → workspace
  cd "$workspace"
  load .ralph/.env (only RALPH_* keys)
  validate: .ralph/PROMPT.md, .ralph/TASKS.md, RALPH_PROVIDER, .git/, command -v "$RALPH_PROVIDER_CLI"  # RALPH_PROVIDER_CLI 来自 adapter 载入时
  acquire .ralph/lock     # flock; conflict → exit `locked`, do NOT create run dir
  run_id = YYYYMMDD-HHMMSS-<shortsha>
  mkdir .ralph/runs/$run_id/iterations/
  start_sha = git rev-parse HEAD || ""
  write .ralph/runs/$run_id/context.json
  write .ralph/status.json (state=running)
  stagnation_count = 0
  for iteration in 1..INF:
    tasks = parse_tasks(.ralph/TASKS.md)
    if all(t.checked for t in tasks): exit `done`
    if max_iter > 0 and iteration > max_iter: exit `max_iterations`
    prompt_file = render_prompt(.ralph/PROMPT.md, run_id, iteration, tasks)
    source adapter-$provider.sh
    provider_oneshot $prompt_file iter-$N/log iter-$N/  # writes log, meta drafts
    provider_collect_session iter-$N/      # writes session.*, chat.log, tools.log
    provider_diagnose iter-$N/             # writes error{type,message} to meta
    changed = git_changed_files $start_sha  # diff since run start
    tasks_after = parse_tasks(.ralph/TASKS.md)
    if checked_count(tasks_after) == checked_count(tasks) and empty(changed):
      stagnation_count += 1
    else:
      stagnation_count = 0
    if stagnation_count >= stagnation_limit: exit `stagnated`
    write iter-$N/meta.json
    update .ralph/status.json
  write .ralph/runs/$run_id/result.json
  copy .ralph/TASKS.md to .ralph/runs/$run_id/TASKS.md
  release lock
```

## CLI 契约

### 子命令

```bash
ralph run     # 主循环
ralph status  # 一次性状态快照
ralph watch   # 周期刷新状态 + 日志 tail
ralph help    # 帮助
```

**没有** `ralph init`（全局非目标）。使用者自行创建 `.ralph/PROMPT.md`、`.ralph/TASKS.md`、`.ralph/.env`。

### `ralph run` 参数

| Flag | 值 | 环境变量 | `.env` 字段 | 默认 | 说明 |
|---|---|---|---|---|---|
| `--provider` | `claude\|codex\|gemini` | `RALPH_PROVIDER` | `RALPH_PROVIDER` | **无默认**（必需） | provider 绑定；run 生命周期内不变 |
| `--model` | provider 原生 model 名 | `RALPH_MODEL` | `RALPH_MODEL` | 空 → 不传 | 留空由 provider CLI 走自身默认 |
| `--effort` | `low\|medium\|high\|none` | `RALPH_EFFORT` | `RALPH_EFFORT` | 空或 `none` → 不传 | adapter 翻译到原生 flag |
| `--max-iter` | 整数 | `RALPH_MAX_ITER` | `RALPH_MAX_ITER` | `0`（不限） | 0 表示不限 |
| `--timeout` | 整数（秒） | `RALPH_TIMEOUT` | `RALPH_TIMEOUT` | `0`（不限） | 单轮最长执行时间 |

**不存在**的 flag（显式声明为非目标）：

- `--cwd` —— workspace 根由脚本路径决定（REQ-010、TC-STK-004）
- `--resume` / `--resume-session` —— 每轮 fresh oneshot（REQ-001 SC-001-2）
- `--approval` / `--sandbox` —— 策略写死在 adapter 里，见 [`security.md`](./security.md)

优先级：CLI flag > 进程环境变量 > `.ralph/.env` > adapter 内置 fallback。

### `ralph status` 参数

无参数。一次性打印到 stdout。

### `ralph watch` 参数

| Flag | 默认 | 说明 |
|---|---|---|
| `--interval` | `2`（秒） | 刷新间隔 |

## 运行目录

### 部署形态（per-workspace，REQ-008）

使用者 workspace 目录结构：

```text
<workspace>/
  .ralph/
    bin/
      ralph                         # 工具入口脚本
    lib/
      common.sh                     # 通用函数
      run.sh                        # ralph run 主循环
      status.sh                     # ralph status
      watch.sh                      # ralph watch
      tasks.sh                      # TASKS.md 解析
      session.sh                    # session 派生 chat.log / tools.log
      adapter-claude.sh             # provider 实现
      adapter-codex.sh
      adapter-gemini.sh
      adapter-fake.sh               # T1 smoke test 用
    PROMPT.md                       # 使用者输入（必需）
    TASKS.md                        # 使用者输入（必需）
    .env                            # 使用者输入（必需，至少含 RALPH_PROVIDER）
    .gitignore                      # 建议
    runs/                           # 运行期产物
    status.json                     # 运行期产物
    lock                            # 运行期产物
```

`.ralph/bin/` 和 `.ralph/lib/` 由本仓库发布，使用者通过 `cp -r`、git submodule 或 symlink 安装到各自 workspace。

### Run 目录

```text
.ralph/runs/<run_id>/
  context.json                      # 启动参数、provider、版本、start_sha
  result.json                       # 退出原因、迭代次数、任务统计、last_error
  TASKS.md                          # run 结束时的任务板快照
  iterations/
    iter-001/
      log                           # provider stdout/stderr 原始输出（tee）
      session.<provider>.*          # provider 原生 session 副本（文件名由 adapter 决定）
      chat.log                      # 派生：对话流（消息+tool result 纯文本）
      tools.log                     # 派生：工具调用摘要（每行一条）
      meta.json                     # 本轮元数据（见下）
    iter-002/
    ...
```

### `run_id` 规则

`YYYYMMDD-HHMMSS-<7 位 git short sha>`。若无 git 提交，用 `YYYYMMDD-HHMMSS-nogit`。

### `.ralph/status.json` schema

```json
{
  "run_id": "20260424-100000-abc1234",
  "run_dir": ".ralph/runs/20260424-100000-abc1234",
  "workspace": "/abs/path/to/workspace",
  "provider": "codex",
  "model": null,
  "effort": null,
  "started_at": "2026-04-24T10:00:00Z",
  "updated_at": "2026-04-24T10:05:12Z",
  "iteration": 3,
  "state": "running",
  "tasks_total": 10,
  "tasks_checked": 4,
  "exit_reason": null,
  "last_error": null
}
```

run 结束时 `state` 变更为 `finished`，`exit_reason` 填入。

### `context.json` schema

```json
{
  "run_id": "...",
  "workspace": "/abs/path/to/workspace",
  "provider": "codex",
  "provider_version": "0.121.0",
  "model": null,
  "effort": null,
  "max_iter": 0,
  "timeout": 0,
  "stagnation_limit": 5,
  "start_sha": "abc1234...",
  "started_at": "...",
  "env_source": ".ralph/.env + process env + CLI flags"
}
```

### `result.json` schema

```json
{
  "run_id": "...",
  "exit_reason": "done",
  "iterations": 7,
  "tasks_total": 10,
  "tasks_checked_start": 0,
  "tasks_checked_end": 10,
  "started_at": "...",
  "finished_at": "...",
  "duration_sec": 4812,
  "last_error": null
}
```

### `iter-xxx/meta.json` schema

```json
{
  "iteration": 3,
  "provider": "codex",
  "session_id": "abc-...",
  "session_source_path": "/home/.../rollout-...jsonl",
  "session_copied_path": ".ralph/runs/.../iter-003/session.codex.jsonl",
  "capture_status": "ok",
  "capture_warning": null,
  "exit_code": 0,
  "duration_ms": 48000,
  "error": null,
  "changed_files": ["src/foo.ts"],
  "tasks_before": { "total": 10, "checked": 3 },
  "tasks_after":  { "total": 10, "checked": 4 },
  "stagnation_count": 0
}
```

## `.ralph/.env` 格式

```bash
# 必需
RALPH_PROVIDER=codex

# 可选；留空或不写 = 不传对应 flag
RALPH_MODEL=
RALPH_EFFORT=
RALPH_MAX_ITER=
RALPH_TIMEOUT=
```

加载规则（TC-STK-003）：

- 路径写死：ralph 脚本按 `${BASH_SOURCE[0]}` 解析 `.ralph/bin/ralph` → `.ralph/.env`
- 只 export 以 `RALPH_` 开头的 key
- 注释 `#`、空行忽略
- 不执行任何 shell 语句（不 `source`，用逐行解析）——避免 `.env` 变成任意代码执行点

## PROMPT.md 协议模板

PROMPT.md 由使用者编写，但以下协议段落是 Ralph 的硬契约（REQ-003 SC-003-1），使用者在自己的 PROMPT.md 中必须包含等价表述：

```markdown
# Ralph Loop 硬契约

本次调用是一个 ralph-loop 的 oneshot。你必须严格遵守以下协议：

1. 读取 `.ralph/TASKS.md`。
2. 从中选择**恰好一个**未勾选（`- [ ]`）的任务。
3. 完成该任务的实现和验证。
4. 把该任务从 `- [ ]` 改为 `- [x]`（保留标题与缩进不变）。
5. 退出。不要追加新任务，不要一次勾多条，不要跨任务操作。

如果没有未勾选任务，直接退出，不做任何修改。

失败时保持任务为 `- [ ]`，把失败原因写在该任务下一级子项里。
```

Ralph 每轮把 PROMPT.md 全文拼到 oneshot 前，并附加 runtime 上下文块：

```markdown
<ralph-runtime>
run_id: 20260424-100000-abc1234
iteration: 3
start_sha: abc1234...
workspace: /abs/path
</ralph-runtime>
```

## TASKS.md 协议

Ralph 只解析顶层 checklist（REQ-002 FR-004）：

```md
- [ ] 未完成任务
- [x] 已完成任务
```

规则：

- 正则：`^\s*-\s+\[([ xX])\]`
- `space` → 未完成；`x` 或 `X` → 已完成
- 不限缩进（深层缩进的 `- [ ]` 也视为顶层任务；这是 trantor parseTasks 的既有行为，沿用）
- 子项语义由 agent 自由使用；Ralph 不解析

全部勾选 → `done` 退出。TASKS.md 空或无 checklist → 视为完成，`done` 退出不产生 iteration。

## Adapter 契约

三个 shell 函数契约（TC-STK-005）。每个 provider 的 `adapter-<name>.sh` 通过 `source` 动态载入后，必须：

1. 定义全局变量 `RALPH_PROVIDER_CLI`，值是启动校验 `command -v` 检查的可执行文件名（例如 Claude adapter 设为 `claude`、Codex adapter 设为 `codex`、Gemini adapter 设为 `gemini`、fake adapter 设为 `bash` 或 `$RALPH_FAKE_CLI`）；run.sh 只通过这个变量做 provider CLI 可执行校验，不做 provider 名到 CLI 名的硬编码映射。
2. 提供以下三个函数：

### `provider_oneshot`

```bash
provider_oneshot <prompt_file> <log_path> <iter_dir>
# 副作用：
#   - 执行 provider CLI oneshot
#   - stdout/stderr tee 到 <log_path>
#   - 写 <iter_dir>/provider.meta（至少含 session_id, provider, model, start_ts, end_ts）
# 返回码：
#   0 = provider 正常退出（不代表 agent 成功）
#   非 0 = provider 本身异常（crash、认证失败等）
```

### `provider_collect_session`

```bash
provider_collect_session <iter_dir>
# 副作用：
#   - 从 provider 原生 session 目录定位本轮 session 文件
#   - 硬链接或复制到 <iter_dir>/session.<provider>.*
#   - 派生 <iter_dir>/chat.log（纯文本对话流）
#   - 派生 <iter_dir>/tools.log（工具调用摘要，每行一条）
#   - 更新 <iter_dir>/meta.json 的 capture_status / capture_warning / session_source_path / session_copied_path
# 返回码：
#   0 = 成功或受控降级（写了 warning 也算成功）
#   非 0 不应出现（失败必须内部降级为 warning，不中断 loop）
```

### `provider_diagnose`

```bash
provider_diagnose <iter_dir>
# 副作用：
#   - 分析 log、session 和 exit code，确定错误类别
#   - 更新 <iter_dir>/meta.json 的 error 字段
#     error = null                           # provider 正常 + agent 正常
#     error = { type, message, raw }         # 其中 type ∈ auth | quota | rate_limit | network | concurrency | api | unknown
# 返回码：始终 0（诊断本身不失败）
```

各 adapter 的具体实现（命令构造、session 路径、诊断关键字）见 [`integrations.md`](./integrations.md)。

## 退出原因

`exit_reason` 和进程退出码的映射：

| exit_reason | 退出码 | 说明 | result.json | run 目录 |
|---|---|---|---|---|
| `done` | 0 | 所有顶层 checklist 完成 | 有 | 有 |
| `provider_failed` | 2 | provider CLI 退出码非 0 | 有 | 有 |
| `timeout` | 3 | 单轮执行超时 | 有 | 有 |
| `max_iterations` | 4 | 达到 `--max-iter`（仅当 `>0` 时触发） | 有 | 有 |
| `stagnated` | 5 | 连续 N 轮无进展 | 有 | 有 |
| `locked` | 6 | 已有 run 运行中 | **无** | **无** |
| `interrupted` | 130 | SIGINT / Ctrl-C | 有（尽力写） | 有（若在 lock 获取前被中断，则同 `locked`，不产生 run 目录、不写 `result.json`） |

`locked` 始终**不产生 run 目录**；`interrupted` 在 lock 获取前触发时同样不产生（REQ-012）。

## Stagnation 判定

每轮结束后：

```text
if tasks_checked_after == tasks_checked_before AND changed_files is empty:
  stagnation_count += 1
else:
  stagnation_count = 0

if stagnation_count >= stagnation_limit:
  exit `stagnated`
```

`changed_files` 定义（决策 #7）：

```bash
git diff --name-only "$start_sha" HEAD     # 相对 run 起点的已提交变更
  ∪
git status --porcelain | awk '{print $NF}' # 当前工作区未提交变更
```

取并集，过滤 `.ralph/`（避免 run 自身产物触发）。

默认 `stagnation_limit=5`（决策 #4）。

## Lock 机制

- 路径：`.ralph/lock`
- 实现：`flock -xn 9`（非阻塞独占锁），`9>$lock_file`
- 冲突：`flock` 失败 → stderr 报错、退出 `locked`、**不创建 run 目录**
- 释放：`ralph run` 正常或异常退出都释放（`trap` 清理)
- Stale lock：v0.1 不做 stale 检测，使用者需要手动清理持有进程已死的 lock

## 错误诊断类别

统一类别（FR-008）：

| type | 含义 | 触发 |
|---|---|---|
| `auth` | 认证失败 | 401 / unauthorized / invalid api key / not logged in |
| `quota` | 额度耗尽 | quota / credits exhausted / billing |
| `rate_limit` | 速率限制 | 429 / rate limit / too many requests |
| `network` | 网络异常 | ECONNRESET / timeout / DNS / ENOTFOUND |
| `concurrency` | 工具并发态异常 | `tool_use_concurrency`（仅 Claude） |
| `api` | 5xx 或其他 provider 明确错误 | provider 结构化 error 不属以上类 |
| `unknown` | 其他 | fallback |

provider 特定字段、优先级和关键字匹配见 [`integrations.md#错误诊断`](./integrations.md#错误诊断)。

## 派生视图

`chat.log` 和 `tools.log` 是从 provider 原生 session 文件派生的**非权威**人类可读视图（REQ-006），目的是让复盘时不必直接读 JSONL：

### `chat.log` 格式

```text
[user] <timestamp>
<prompt text>

[assistant] <timestamp>
<assistant text>

[tool-result name=Bash] <timestamp>
<truncated text, max 2000 chars>
```

### `tools.log` 格式

每行一条工具调用摘要：

```text
<timestamp>  <tool_name>  <brief_input>  <brief_output_or_status>
```

派生规则由各 adapter 实现（参考 trantor-skills 的 `deriveSessionViews` / `deriveGeminiSessionViews` / `deriveCodexSessionViews`）。

## 方案取舍

| 取舍 | 选择 | 原因 | 放弃方案的代价 |
|---|---|---|---|
| 任务协议 | TASKS.md checklist | 人类可读、可 diff、和 agent 自我更新天然对齐 | 若用 JSON/YAML，agent 更新更费 token，且 diff 噪音大 |
| 事实源 | `.ralph/TASKS.md` 是任务完成唯一事实源；session 只是复盘证据 | 模型自述不可信；文件状态可验证 | 若以 session 为事实源，无法区分"agent 说完成了"和"agent 真完成了" |
| Session 采集失败 | 降级为 warning，不中断 loop | provider session store 是 provider 内部实现，Ralph 不应绑死 | 若当作致命错误，一次 provider 版本升级就能导致所有 run 失败 |
| 并发策略 | 单 workspace 单 run；`locked` 快速退出 | `.ralph/runs/` 和 TASKS.md 无锁并发会互相破坏 | 若允许并发，需要引入 run 级任务分区 |
| cwd 策略 | 脚本路径决定 workspace；不接受 `--cwd` | 消除"coding agent 幻觉传错 cwd"风险；单真相 | 失去从外部动态指定 workspace 的灵活性，但用 `cd <workspace>` 能等价满足 |
| 全局安装 | 不支持 | workspace 自治；工具升级 = 该 workspace 内更新 | 失去 `brew install` 一次到处用的便利 |
| Init 模板 | 不提供 | 使用者自己写 PROMPT/TASKS 更贴需求；避免把模板占位当事实 | 新用户上手成本略高，未来由 skill 解决（REQ-016） |
| Approval 策略 | 写死，不做开关 | 见 [`security.md`](./security.md)；三个 provider 各自策略已由 trantor 验证过 | 失去对接 CI 白名单 / policy file 的灵活性；未来按需加 `--approval=<mode>` |
| Effort 抽象 | 统一 `low\|medium\|high\|none` | 使用者不必记三家原生参数 | 失去 Claude 的 token 精细控制；若需精细指定，直接改 adapter 映射 |
| TUI | 仅 `watch` 最小 sticky bar；不引 TUI 框架 | shell-first 原则；避免依赖 | 观感不如专业 TUI，但复盘主要看 run 目录文件 |

## 与外部参考的关系

- **trantor-skills `cli/lib/build.ts`**：是 Ralph loop 的事实前身（同一作者）。parse_tasks、run loop、session capture、error diagnose 的算法沿用；但 CLI 命名（`build` → `run`）、模板机制（删）、`ralph init`（删）、`--resume` / `--backup` / tmux（删）、三态熔断（删）是本项目独立演进的部分。
- **`frankbria/ralph-claude-code`**：Claude-only 原版，作为背景输入；Ralph 在此基础上多 provider 化、shell 化并收缩默认复杂度。

两者均为输入参考，不是对标目标。Ralph 的 API 和内部约定独立演进。

## 架构文档索引

| 领域 | 文档 | 状态 | 范围 |
|---|---|---|---|
| Overview | [`overview.md`](./overview.md) | 已确认 | 本文 |
| API | `api.md` | 当前不适用 | Ralph 是 CLI 工具，无 HTTP/RPC API |
| Backend | `backend.md` | 当前不适用 | Bash 模块结构已在本文 [运行目录](#运行目录) 段落覆盖 |
| Frontend | `frontend.md` | 当前不适用 | 无前端 |
| Database | `database.md` | 当前不适用 | 无持久化业务实体；运行期状态在 `.ralph/runs/` 文件中 |
| UI | `ui.md` | 当前不适用 | 仅 `ralph watch` 的终端 UI，细节待 T5 细化 |
| Security | [`security.md`](./security.md) | 已确认 | approval / sandbox 策略、secrets 边界、 allowedTools 白名单 |
| Testing | `testing.md` | 待补齐 | T1 完成后按 `scripts/integration-test.sh` 成形再沉淀 |
| Deployment | `deployment.md` | 当前不适用 | per-workspace 部署方式已在本文 [部署形态](#部署形态per-workspacereq-008) 段落覆盖 |
| Integrations | [`integrations.md`](./integrations.md) | 已确认 | Claude / Codex / Gemini 原生 session 路径、采集命令、退化策略、UUID 依赖 |

## 待落实

- `ralph watch` 的 sticky bottom bar 具体布局和窄终端降级策略在 T5 实现前细化，不在本文写死。
- `adapter-fake.sh` 由 `RALPH_FAKE_SCENARIO` 环境变量选场景（不依赖"第 N 轮"模式），T1 五场景：`happy`（勾第 1 条未勾选任务，`exit=0`）/ `stagnation`（不改 TASKS + 不改 git，`exit=0`）/ `crash`（`exit=非零`，无结构化错误，诊断为 `unknown`）/ `api-error`（`exit=非零` + stderr 含 api 错误关键字，诊断为 `api`）/ `slow`（`sleep` 远超 `--timeout`，用于 `timeout` 用例）。接受 `RALPH_FAKE_CLI` 覆盖 `RALPH_PROVIDER_CLI`、`RALPH_FAKE_SLEEP` 控制 sleep 时长。
- Skill 封装（REQ-016）的具体接口在 v0.1 完成后单独设计。
- `docs/architecture/testing.md` 在 T1 集成测试脚本成形后补齐。
