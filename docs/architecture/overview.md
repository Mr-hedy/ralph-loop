# Architecture Overview

- 状态：已确认
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-032）和 `docs/requirements/vibecoding-collaboration/requirements.md`（REQ-033 ~ REQ-047）；本文在 design 层面给出总体系统入口。
- 范围：本文承载项目总体上下文，以及 Ralph 执行引擎的主要组成和稳定契约（CLI、运行目录、adapter 接口、退出码、stall、lock、错误诊断类别）。Codex Main Agent 协作控制面、后台派发、最终验收和长期记忆边界见 [`vibecoding-collaboration.md`](./vibecoding-collaboration.md)。
Provider 特定命令构造、session 路径和诊断关键字在 [`integrations.md`](./integrations.md)；approval / sandbox 策略和安全边界在 [`security.md`](./security.md)。
- 变更条件：CLI 契约、退出原因枚举、adapter 函数签名或 `.ralph/runs/<id>/` schema 变化时必须同步更新；并触发下游 `integrations.md` / `security.md` / 模块需求 / roadmap / task 检查。

## 总体模型

项目总体由 Codex Main Agent 协作控制面和 Ralph 后台执行面组成。Main Agent 负责需求、方案、任务和最终产物验收；Ralph 不做推理治理，只把已确认长任务组织成多轮 provider CLI fresh oneshot 执行。两者以任务事实源和最终 repository 状态交互，不以 provider 对话总结作为完成证据。

详细协作模型见 [`vibecoding-collaboration.md`](./vibecoding-collaboration.md)。以下内容继续描述 Ralph 执行引擎的稳定契约。

每轮执行流程：

1. 读 `.ralph/TASKS.md`，若全部勾选 → 退出 `done`
2. 拼 prompt：`.ralph/PROMPT.md` 全文 + runtime 上下文块（run_id、round、git sha 等）
3. 调 provider CLI oneshot，捕获 stdout/stderr
4. 采集 provider 原生 session → 派生 `session.history.log`（人话视图）
5. 错误诊断 + 收集 `changed_files`
6. 写 `round-NNN/meta.json`、刷新 `status.json`
7. 判断退出条件（见 [退出原因](#退出原因)）；否则进入下一轮

Agent 端契约由 PROMPT.md 承载："每轮恰好完成一个未勾选任务并勾 `[x]`"（REQ-003）。

## 运行时伪代码

```text
ralph run
  workspace = dirname(dirname(realpath($BASH_SOURCE)))      # .ralph/bin/ralph → workspace
  cd "$workspace"
  load .ralph/.env (only RALPH_* keys)
  check_dependencies (git + provider_check_deps from sourced adapter)  # 缺失依赖一次性聚合输出后退出，见 ralph_require_cmd / ralph_report_missing_deps
  validate: .ralph/PROMPT.md, .ralph/TASKS.md, RALPH_PROVIDER, .git/                # workspace 完整性（不再含 command -v RALPH_PROVIDER_CLI，已合并入依赖框架）
  acquire .ralph/lock     # flock; conflict → exit `locked`, do NOT create run dir
  run_id = YYYYMMDD-HHMMSS-<shortsha>
  mkdir .ralph/runs/$run_id/rounds/
  start_sha = git rev-parse HEAD || ""
  write .ralph/runs/$run_id/context.json
  write .ralph/status.json (state=running)
  stall_count = 0
  for round in 1..INF:
    tasks = parse_tasks(.ralph/TASKS.md)
    if all(t.checked for t in tasks): exit `done`
    # max_round / stall_limit 为 per-task 判定
    if max_round > 0 and current_task_try > max_round: exit `blocked_by_human` (auto-insert HUMAN)
    prompt_file = render_prompt(.ralph/PROMPT.md, run_id, round, tasks)
    source adapter-$provider.sh
    fp_before = worktree_fingerprint()         # 本轮前快照
    provider_oneshot $prompt_file round-$N/provider.stdout.log round-$N/
    provider_collect_session round-$N/
    provider_diagnose round-$N/
    fp_after = worktree_fingerprint()          # 本轮后快照
    tasks_after = parse_tasks(.ralph/TASKS.md)
    if checked_count(tasks_after) == checked_count(tasks) and fp_after == fp_before:
      stall_count += 1
    else:
      stall_count = 0
    if stall_count >= stall_limit: exit `blocked_by_human` (auto-insert HUMAN)
    write round-$N/meta.json
    update .ralph/status.json
  write .ralph/runs/$run_id/result.json
  copy .ralph/TASKS.md to .ralph/runs/$run_id/TASKS.md
  release lock
```

## CLI 契约

### 子命令

```bash
ralph run     # 主循环 (默认 plain 模式)
ralph run -v  # 启用 sticky TUI 模式 (仅 TTY)
ralph status  # 一次性状态快照
ralph watch   # 周期刷新 sticky TUI (TTY 默认，非 TTY 为 one-line bar)
ralph help    # 帮助
```

**没有** `ralph init`（全局非目标）。使用者自行创建 `.ralph/PROMPT.md`、`.ralph/TASKS.md`、`.ralph/.env`。

### `ralph run` 参数

| Flag | 值 | 环境变量 | `.env` 字段 | 默认 | 说明 |
|---|---|---|---|---|---|
| `--provider` | `claude\|codex\|fake` | `RALPH_PROVIDER` | `RALPH_PROVIDER` | **无默认**（必需） | provider 绑定；run 生命周期内不变；其他取值（含 `gemini`）在启动校验阶段被拒绝，exit 1，不创建 run 目录（REQ-028） |
| `--model` | provider 原生 model 名 | `RALPH_PROVIDER_MODEL` | `RALPH_PROVIDER_MODEL` | 空 → 不传 | 留空由 provider CLI 走自身默认 |
| `--effort` | `low\|medium\|high\|none` | `RALPH_PROVIDER_EFFORT` | `RALPH_PROVIDER_EFFORT` | 空或 `none` → 不传 | adapter 翻译到原生 flag |
| `--max-round` | 整数 | `RALPH_LOOP_MAX_ROUND` | `RALPH_LOOP_MAX_ROUND` | `0`（不限） | **Per-task** 上限；0 表示不限 |
| `--round-timeout` | 整数（秒） | `RALPH_LOOP_ROUND_TIMEOUT` | `RALPH_LOOP_ROUND_TIMEOUT` | `0`（不限） | 单 round 最长执行时间 |
| `--stall-limit` | 整数 | `RALPH_LOOP_STALL_LIMIT` | `RALPH_LOOP_STALL_LIMIT` | `5` | **Per-task** 连续无进展上限 |

**不存在**的 flag（显式声明为非目标）：

- `--cwd` —— workspace 根由脚本路径决定（REQ-010、TC-STK-004）
- `--resume` / `--resume-session` —— 每轮 fresh oneshot（REQ-001 SC-001-2）
- `--approval` / `--sandbox` —— 策略写死在 adapter 里，见 [`security.md`](./security.md)。Codex 侧固定 `--sandbox danger-full-access`（不等同于 workspace 内写入限制），权限语义与审计路径以 security.md 为准（REQ-031）

优先级：CLI flag > 进程环境变量 > `.ralph/.env` > adapter 内置 fallback。

### `ralph status` 参数

无参数。一次性打印到 stdout。

### `ralph watch` 参数

`ralph watch` 始终采用 sticky TUI 渲染（TTY 模式）；非 TTY 输出一次 one-line watch bar 后退出。不再支持 `-v` / `--verbose` flag。详细字段由 `ralph status` 提供。

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
      session.sh                    # session 派生 session.history.log
      adapter-claude.sh             # provider 实现
      adapter-codex.sh
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
  rounds/
    round-001/
      meta.json                     # 元数据（含 runtime_block + provider_started_at + capture_status + error）
      provider.stdout.log           # provider stdout (events 流) + stderr 全量 tee
      session.<provider>.jsonl      # provider 原生 session 副本（Claude/Codex `.jsonl`，Gemini 为 .json 但暂停接入；命名见 integrations.md §round 目录文件结构）
      session.history.log           # 跨 provider 人话视图（user / assistant / thinking / tool_use / tool_result）
    round-002/

    ...
```

round dir **4 文件契约** —— 详细命名约定见 [`integrations.md#round-目录文件结构-4-文件契约`](./integrations.md#round-目录文件结构4-文件契约)。

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
  "task_started_at": "2026-04-24T10:03:40Z",
  "updated_at": "2026-04-24T10:05:12Z",
  "round": 3,
  "state": "running",
  "tasks_total": 10,
  "tasks_checked": 4,
  "exit_reason": null,
  "last_error": null
}
```

`task_started_at` 标记当前第一个未勾任务首次成为活跃任务的时刻（task 切换时重写，跨 round 累计）；底栏 spinner 持续时间 = 当前时间 − `task_started_at`。run 结束时 `state` 变更为 `finished`，`exit_reason` 填入。

### `context.json` schema

```json
{
  "run_id": "...",
  "workspace": "/abs/path/to/workspace",
  "provider": "codex",
  "provider_version": "0.121.0",
  "model": null,
  "effort": null,
  "max_round": 0,
  "round_timeout": 0,
  "stall_limit": 5,
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
  "rounds": 7,
  "tasks_total": 10,
  "tasks_checked_start": 0,
  "tasks_checked_end": 10,
  "started_at": "...",
  "finished_at": "...",
  "duration_sec": 4812,
  "last_error": null
}
```

### `round-xxx/meta.json` schema

```json
{
  "round": 3,
  "provider": "codex",
  "session_id": "abc-...",
  "provider_started_at": "2026-04-24T10:03:12Z",
  "terminal_event": "turn.completed",
  "terminal_status": "success",
  "terminal_warning": null,
  "runtime_block": "run_id: ...\nround: 3\nstart_sha: ...\nworkspace: ...",
  "session_source_path": "/home/.../rollout-...jsonl",
  "session_copied_path": ".ralph/runs/.../round-003/session.codex.jsonl",
  "capture_status": "ok",
  "capture_warning": null,
  "exit_code": 0,
  "duration_ms": 48000,
  "error": null,
  "changed_files_total": ["src/foo.ts"],
  "changed_files_round": ["src/foo.ts"],
  "tasks_before": { "total": 10, "checked": 3 },
  "tasks_after":  { "total": 10, "checked": 4 },
  "stall_count": 0
}
```

字段说明：
- `provider_started_at`：provider CLI 调用前的 ISO 8601 UTC 时间戳，用于 session 文件 mtime fallback 锚点（替代旧 `.session_start` 文件）
- `terminal_event` / `terminal_status` / `terminal_warning`：provider 终态事件契约（REQ-029），语义见 [`integrations.md#终态事件契约`](./integrations.md#终态事件契约)
- `runtime_block`：本轮 prompt 中动态部分（`<ralph-runtime>` 块内容），与 git `start_sha` 的 PROMPT.md 共同构成完整 prompt 还原源（替代旧 `prompt.md` 文件）
- `changed_files_total`：自 run 启动至本轮结束的累计文件变更
- `changed_files_round`：本轮（vs 上轮）的文件变更，用于 stall 判定

## `.ralph/.env` 格式

```bash
# 必需
RALPH_PROVIDER=codex

# 可选；留空或不写 = 不传对应 flag
RALPH_PROVIDER_MODEL=
RALPH_PROVIDER_EFFORT=
RALPH_LOOP_MAX_ROUND=
RALPH_LOOP_ROUND_TIMEOUT=
RALPH_LOOP_STALL_LIMIT=

# UI 渲染 (可选)
RALPH_UI_STICKY_EVENT_LINES=
RALPH_UI_HEALTH_GREEN_SEC=
RALPH_UI_HEALTH_RED_SEC=
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
round: 3
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

全部勾选 → `done` 退出。TASKS.md 空或无 checklist → 视为完成，`done` 退出不产生 round。

## Adapter 契约

三个 shell 函数契约（TC-STK-005）。每个 provider 的 `adapter-<name>.sh` 通过 `source` 动态载入后，必须：

> **支持矩阵**：公共入口只接受 `claude` / `codex` / `fake`（REQ-028）。`adapter-gemini.sh` 保留在本节契约下供未来重新接入，但 `gemini` 在启动校验阶段即被拒绝（exit 1，不创建 run 目录），因此其契约当前不可达——下文提到 Gemini 的分支均为暂停状态。

1. 定义全局变量 `RALPH_PROVIDER_CLI`，值是启动校验 `command -v` 检查的可执行文件名（例如 Claude adapter 设为 `claude`、Codex adapter 设为 `codex`、Gemini adapter 设为 `gemini`、fake adapter 设为 `bash` 或 `$RALPH_FAKE_CLI`）；run.sh 只通过这个变量做 provider CLI 可执行校验，不做 provider 名到 CLI 名的硬编码映射。
2. 提供以下三个函数：

### `provider_oneshot`

```bash
provider_oneshot <prompt_file> <log_path> <round_dir>
# 副作用：
#   - 执行 provider CLI oneshot
#   - stdout/stderr tee 到 <log_path>
#   - 写 <round_dir>/provider.meta（至少含 session_id, provider, model, start_ts, end_ts）
# 返回码：
#   0 = provider 正常退出（不代表 agent 成功）
#   非 0 = provider 本身异常（crash、认证失败等）
```

### `provider_collect_session`

```bash
provider_collect_session <round_dir>
# 副作用：
#   - best-effort 采集 provider 原生 session 文件到 <round_dir>/session.<provider>.jsonl（Gemini 为 .json）
#   - 按 provider-specific source 派生 <round_dir>/session.history.log
#     Claude: session.claude.jsonl；Codex: provider.stdout.log JSONL events；Gemini: provider.stdout.log stream-json events
#   - 更新 <round_dir>/meta.json 的 capture_status / capture_warning / session_source_path / session_copied_path
# 返回码：
#   0 = 成功或受控降级（写了 warning 也算成功）
#   非 0 不应出现（失败必须内部降级为 warning，不中断 loop）
```

### `provider_diagnose`

```bash
provider_diagnose <round_dir>
# 副作用：
#   - 分析 log、session 和 exit code，确定错误类别
#   - 更新 <round_dir>/meta.json 的 error 字段
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
| `timeout` | 3 | 单 round 执行超时 | 有 | 有 |
| `locked` | 6 | 已有 run 运行中 | **无** | **无** |
| `blocked_by_human` | 7 | 第一个未勾选任务前缀是 `HUMAN-` 或触发 per-task 熔断 (I5) | 有 | 有 |
| `interrupted` | 130 | SIGINT / Ctrl-C | 有 | 有 |

**已于 I5 移除**：`max_iterations`（由 per-task `max_round` 熔断替代）和 `stagnated`（由 per-task `stall_limit` 触发 `blocked_by_human` 替代）。

**接力打印**：所有 exit_reason 下，ralph 退出时向 stderr 打印格式化总结，并写入 `.ralph/runs/<run_id>/exit-message.txt`。打印内容含 `run_id` / `exit_reason` / `rounds` / 任务进度 / 阻塞点（如有）/ 接力提示。

## 协作协议

v0.1.1 引入的协作协议层约定，承载 ralph + 人类 + main agent 三方协作的稳定契约。

### 任务类型路由（PROMPT 层约定）

`.ralph/TASKS.md` 任务前缀决定 agent mindset 和参考的 `.spec/` 规范段。**ralph 工具内核不解析前缀**；前缀仅作为 prompt 层 agent 自检入口。

| 前缀 | 对应 `.spec/` 段 |
|------|-----------------|
| `REQ-N` | `.spec/rules/REQUIREMENTS.md` |
| `SOL-N` | `.spec/rules/SOLUTION.md` |
| `ROADMAP-N` | `.spec/rules/ROADMAP.md`（Roadmap 阶段规划） |
| `PLAN-N` | `.spec/README.md` 阶段 4（任务列表规划，trantor PLAN / sprint planning 同义） |
| (空) / `DEV-N` | `CLAUDE.md` + 代码事实（默认） |
| `QA-N` | `.spec/rules/TESTING.md` |
| `REVIEW-N` | `.spec/rules/REVIEW.md` 或 `.spec/rules/ADVERSARIAL-REVIEW.md` |
| `HUMAN-N` | 等人类决策（见下文 HUMAN-N 阻塞机制） |

### HUMAN-N 阻塞机制（REQ-018）

**触发**：agent 在执行任意类型任务时遇到无法独立决策的需求层歧义/矛盾/缺口。

**Agent 动作**（`.ralph/PROMPT.md` 强约束）：

1. 在阻塞任务**上方**插入 `- [ ] HUMAN-N: <问题>`（含上下文、选项、影响）。
2. 阻塞任务后追加 `→ BLOCKED by HUMAN-N`，保留 `- [ ]`（不勾不删）。
3. `git commit && exit`。

**Agent 强约束**：

- ralph oneshot 内**不得勾选 `[x]` HUMAN-N 任务**（人类的动作）。
- ralph oneshot 内**不得执行 HUMAN-N 任务的内容**（HUMAN-N 是给人类的）。
- 普通 Claude Code 对话里 PROMPT.md 不被加载，无此约束（人类主导对话时可勾选）。

**ralph 工具层动作**：

- 每轮启动前调用 `is_blocked_by_human()`（`.ralph/lib/tasks.sh`）扫描 TASKS.md 第一个 `- [ ]` 任务。
- 前缀匹配 `HUMAN-[0-9]+` → 不调用 provider，立即以 `blocked_by_human`（exit code 7）退出。
- 主循环外预检（首轮启动前）+ 主循环内每轮检查（done 之后、max_round 之前）双重保险。

**人类侧解锁**：

- Claude Code 对话里和 agent 协作得出共识；落地到对应 docs（requirements / architecture）。
- HUMAN-N 任务描述末尾追加 `答（<日期>）: <答案摘要>，落地: <docs 路径>`。
- HUMAN-N 改 `[x]` + commit；重跑 `ralph run`，agent 回到原阻塞任务按答案继续。

## Stall 判定 (I5: Per-task)

每轮结束后（**本轮 vs 上轮**对比）：

```text
if tasks_checked_after == tasks_checked_before AND worktree_fingerprint_after == worktree_fingerprint_before:
  stall_count += 1
else:
  stall_count = 0  # task 切换或有进展时归零

if stall_count >= stall_limit:
  exit `blocked_by_human` (auto-insert HUMAN)
```

**Worktree fingerprint 定义**：

```bash
# git ls-files -s：每个 tracked 文件的 blob sha
# git status -z：未提交变更（含 untracked），\0 分隔转换为换行
{ git ls-files -s; git status -z | tr '\0' '\n'; } | sha256sum | cut -d' ' -f1
```

跨平台：`sha256sum`（Linux/coreutils）→ `shasum -a 256`（macOS 内置）。  
不写 `.git/refs/`、不创建 git 对象（保"不污染用户 git 状态"契约）。  
过滤 `.ralph/` 路径由 `git ls-files` 自然区分（`.ralph/` 可以是 tracked，不影响判据）。

**meta.json changed_files 字段**：

- `changed_files_total`：cumulative，自 run `start_sha` 至今，用于诊断。
- `changed_files_round`：本轮 vs 上轮，fingerprint 不变时为 `[]`，fingerprint 变化时取 `ralph_changed_files(before_iter_head)`。

默认 `stall_limit=5`；可通过 `--stall-limit` / `RALPH_LOOP_STALL_LIMIT` 覆盖。

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

`session.history.log` 是每个 one-shot 的**非权威**跨 provider 人话视图（REQ-006），目的是让复盘时不必直接读 provider 原始 JSONL；统一 chat + tools 双视图为单一文件。

派生来源是 provider-specific：

- Claude：从 `session.claude.jsonl` 派生，包含 user / assistant / thinking / tool_use / tool_result。
- Codex：从 `provider.stdout.log` 的 `codex exec --json` stdout JSONL events 派生，当前包含 assistant / tool_use / tool_result；`session.codex.jsonl` 保留为 raw evidence 和派生 bug 回滚 anchor，不作为 history parser 主输入。
- Gemini（**暂停接入**）：从 `provider.stdout.log` 的 `--output-format stream-json` stdout 事件流派生（I4 DEV-1 校准）；`session.gemini.json` 保留为 native session 副本。该分支当前不可达（REQ-028）。
- 新增 provider 必须在 `docs/architecture/integrations.md` 明确 history source；不得默认假设 `session.<provider>.jsonl` 可解析成人话视图。

### `session.history.log` 格式

```text
[user] <timestamp>
<prompt text>

[thinking] <timestamp>
<assistant thinking block, full content, no filtering>

[assistant] <timestamp>
<assistant text>

[tool-use name=Bash] <timestamp>
<tool input / command summary; long input is truncated with a pointer to the provider-specific source>

[tool-result name=Bash] <timestamp>
<truncated tool output, max 2000 chars>
```

要素：
- 用户消息 / assistant 文本 / thinking 块（**保留全文**）/ tool_use（长 input 摘要化，完整内容保留在 provider-specific source；Claude 指向 `session.claude.jsonl`，Codex 指向 `provider.stdout.log`）/ tool_result（截 2000 字符）+ 时间戳
- 删除原 `chat.log` 中"thinking 不输出"的过滤；删除独立 `tools.log` 文件（合并进来）

派生规则由各 adapter 实现（参考 `_claude_derive_history` / `_codex_derive_history`）。

## 状态观察

`ralph status` 和 `ralph watch` 提供人类维护者观察当前 run 的能力（REQ-007）。两者共享同一数据源 `.ralph/status.json`，不做 session 解析、不做变更诊断、不写文件。

### 数据流

```text
.ralph/status.json ───── ralph status ──→ stdout（一次性详细打印，exit 0）
                   │
                   └──→ ralph watch ──→ TTY sticky TUI / 非 TTY one-line bar
                          │
                          └──→ tail 当前活跃 round log ──→ 事件区
```

- `status`：单次读取 status.json，渲染 plain text（`run_id` / `run_dir` / `workspace` / `provider` / `model` / `effort` / `started_at` / `updated_at` / `round` / `state` / `tasks_total` / `tasks_checked` / `exit_reason` / `last_error`），任务进度渲染为 `<checked> / <total> checked`。status.json 不存在时输出提示文案，exit 0。
- `watch`：每 200ms (sticky 渲染循环) 重读 status.json，默认渲染 sticky TUI；非 TTY 环境输出一次 one-line watch bar 后退出。

### Sticky TUI 布局 (I5)

```text
[HH:MM:SS] ralph 0.2 · tasks N/M · oneshots 12 · provider claude · elapsed H:MM:SS
─────────────────────────────────────────────────────────────────────────────────
[ts] event 1
[ts] event 2
... (up to 6 lines of events)
─────────────────────────────────────────────────────────────────────────────────
● round 2/∞ · stall 1/5 · ⠹ HH:MM:SS · → DEV-1 任务名截断...
```

- **健康灯** (底栏首位)：🟢 (≤60s) / 🟡 (60~300s) / 🔴 (>300s) 监测 stdout 字节增长。退出时显示 ✓ / ✗ / ⏸。
- **Per-task 状态**：底栏显示当前 task 的 round 数 and stall 数。
- **事件区**：通过 tail `provider.stdout.log` 并过滤 marker 得到，滚动显示最近 6 条事件。
- **退出行为**：`run -v` 结束后退出；`watch` 结束后不退出，最后一帧保留等 Ctrl-C。

### Watch 行为规则

- **run_id 切换**：status.json `run_id` 变化时，sticky 渲染器全量重置，tail 目标切换到新 run 的 round log。
- **round 切换**：同一 run 内 `round` 变化时，tail 目标自动切换到新 round log，偏移量重置。
- **run 结束**：`state=finished` 后 watch 不自动退出，最后一帧保留并继续刷新。
- **退出**：仅 Ctrl-C（SIGINT），退出时还原 stty 状态并显示光标。

### Watch 彩色规则

条件：`isatty(stdout) && [ -z "$NO_COLOR" ]`（SC-024-5）。

| 状态 | 颜色 | 覆盖字段 |
|------|------|---------|
| `state=running` 或 `exit_reason=done` | 绿 | `state` / `exit_reason` |
| `exit_reason` ∈ {`provider_failed`, `timeout`, `blocked_by_human`} | 红 | `state` / `exit_reason` |
| `exit_reason` ∈ {`interrupted`, `locked`} | 黄 | `state` / `exit_reason` |
| 标签文本 | dim 灰 | `tasks` / `round` / `provider` 等标签 |

`NO_COLOR=1` 或非 TTY 时全部不上色。

## 方案取舍

| 取舍 | 选择 | 原因 | 放弃方案的代价 |
|---|---|---|---|
| TUI 实现 | 纯 append + cursor_up | 最小化依赖，保留 shell scrollback；不设 scroll region 兼容性更好 | ANSI scroll region 或 alternate screen 会破坏之前的 shell 历史 |
| 防死循环 | Per-task + 自动插 HUMAN | 避免全局限制导致的误杀，提供清晰的人类干预入口 | 若用全局 max_rounds，长任务中后期容易被误杀 |
| 环境变量 | 分组重命名 (provider/loop/ui) | 明确配置归属，减少冲突；符合 I5 的重组逻辑 | 旧环境变量名容易混淆 loop 逻辑与 provider 逻辑 |
| 任务协议 | TASKS.md checklist | 人类可读、可 diff、和 agent 自我更新天然对齐 | 若用 JSON/YAML，agent 更新更费 token，且 diff 噪音大 |

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
| UI | `ui.md` | 当前不适用 | `ralph watch` 终端 UI 细节已在本文 [状态观察](#状态观察) 段落覆盖 |
| Security | [`security.md`](./security.md) | 已确认 | approval / sandbox 策略、secrets 边界、provider 侧权限收敛（当前不存在：Claude 走 bypass、Codex 走 `danger-full-access`） |
| Testing | [`testing.md`](./testing.md) | 已建立（T2 阶段持续扩展） | 测试入口、基础设施、隔离规则、单一来源、运行平台、当前覆盖范围 |
| Deployment | `deployment.md` | 当前不适用 | per-workspace 部署方式已在本文 [部署形态](#部署形态per-workspacereq-008) 段落覆盖 |
| Integrations | [`integrations.md`](./integrations.md) | 已确认 | Claude / Codex 原生 session 路径、采集命令、退化策略、UUID 依赖（Gemini 段落为暂停接入的历史契约） |

## 待落实

- `adapter-fake.sh` 由 `RALPH_FAKE_SCENARIO` 环境变量 select 场景（不依赖"第 N 轮"模式），核心场景：`happy`（勾第 1 条未勾选任务，`exit=0`）/ `stall`（不改 TASKS + 不改 git，`exit=0`）/ `crash`（`exit=非零`，无结构化错误，诊断为 `unknown`）/ `api-error`（`exit=非零` + stderr 含 api 错误关键字，诊断为 `api`）/ `slow`（`sleep` 远超 `--round-timeout`，用于 `timeout` 用例）/ `slow_child`（启动外部 child 并等待，用于 timeout/interrupted 进程树清理）/ `append_task_once`（运行中追加任务，用于任务总数刷新）。
接受 `RALPH_FAKE_CLI` 覆盖 `RALPH_PROVIDER_CLI`、`RALPH_FAKE_SLEEP` 控制 sleep 时长。
- Skill 封装（REQ-016）的具体接口在 v0.1 完成后单独设计。
- `docs/architecture/testing.md` 在 T1 集成测试脚本成形后补齐。
