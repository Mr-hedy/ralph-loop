# Testing

- 状态：当前 `bash scripts/integration-test.sh` 为 PASS=149 FAIL=0。
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-006 / REQ-011 / REQ-012 / NFR-* 系列）、`docs/architecture/overview.md`（启动校验、退出原因、运行目录 schema）、`docs/architecture/integrations.md`（provider 集成约束）、`docs/postmortems/pm-shell-macos-compat.md`（PM-0001）、`docs/postmortems/pm-cross-task-decision-sedimentation.md`（PM-0002）。
- 范围：本文承载 ralph-loop 项目的测试入口、基础设施约定、隔离规则、单一来源规则、运行平台和当前覆盖范围。本文不重复测试方法论（在 `.spec/rules/testing.md`），不写具体用例的验证计划（写到任务事实源 `task.md` 对应任务的"验证计划"段）。
- 变更条件：测试入口脚本变化、新增 fixture 或 mock 类型、隔离规则失效、新平台支持、测试覆盖目标变化。

## 测试入口

| 命令 | 用途 | 通过标准 |
|---|---|---|
| `bash scripts/check.sh` | 静态检查（`bash -n` 全 lib 文件 + integration-test.sh 存在性） | stdout 含 `ralph-loop check passed` |
| `bash scripts/integration-test.sh` | 端到端集成测试（mock workspace + 退出原因 + 启动校验 + adapter 各分支） | `PASS=N FAIL=0`，N 随阶段扩展（T1：14；T2：34；T6：41） |
| `git diff --check` | 空白错误检查 | 无输出 |

完整验证 = 三条命令全过。文档/协作规则改动至少跑前两条；脚本/代码改动跑全套。

## 测试基础设施

```text
scripts/
  check.sh                              # 静态检查入口
  integration-test.sh                   # 端到端测试 + helper（setup_workspace / setup_claude_workspace 等）
tests/
  fixtures/
    mock-claude                         # claude CLI 测试替身（单一来源）
    mock-codex                          # codex CLI 测试替身（单一来源）
    mock-gemini                         # gemini CLI 测试替身（单一来源，I4 DEV-2 建立）
    claude-session-sample.jsonl         # Claude session jsonl 样本（T2.4 起）
```

新增 mock 替身或 fixture 必须放 `tests/fixtures/` 下；helper 函数集中在 `scripts/integration-test.sh`，不另起脚本。

## 测试隔离规则

测试不得污染或破坏使用者环境。任何集成测试、smoke 测试、fixture 写入产生的副作用必须限定在临时目录或被测进程的子作用域内。

**强制要求**：

- **HOME 隔离**：测试若需要写入 `~/.claude/`、`~/.codex/`、`~/.gemini/` 等 provider 用户目录，必须先 `export HOME="$tmpdir/home"`，让 provider 文件落到临时 HOME 下，跑完即清。**禁止**直接写入真实用户 HOME。
- **PATH 隔离**：测试若需要修改 PATH（例如模拟某命令缺失），修改必须限定在被测子进程（`env PATH=... ralph run ...`），harness 自身 PATH 不得变更。harness 自己的 jq / git / bash 等工具必须始终可用，否则 harness 自身瘫痪后无法做断言。
- **配置文件隔离**：测试不得修改使用者的 `~/.gitconfig`、`~/.bashrc`、`~/.ssh/`、shell history 等配置；所有 git config 通过临时仓库的本地 config 设置。
- **网络隔离**：单元/集成测试默认不访问外网；需要真实 provider CLI 的 smoke 测试单独标识为人工触发。
- **RALPH 环境变量隔离**：测试若依赖 `RALPH_PROVIDER_CONFIG_DIR` 等变量为空值，必须在 `env` 命令中显式清空（`RALPH_PROVIDER_CONFIG_DIR=""`），否则 ralph loop 父进程环境会泄漏到测试子进程。I4 收口复验确认完整集成测试已恢复到 FAIL=0。

**自检要求**：

- 集成测试结束时至少做一项隔离自检（如 `ls ~/.claude/projects/ | wc -l` 跑测前后一致），把破坏类问题及早暴露。
- 失败时立即停止后续用例，避免雪崩污染。

## 测试基础设施单一来源

同类测试基础设施（mock 替身脚本、setup helper、fixture 文件）必须**单一来源**，不允许多个任务各自造一份。

**强制要求**：

- 第一个用到该基础设施的任务负责建立"骨架版"（最小可用 + 扩展点清晰），并在 commit 或 task 描述中明确标注"单一来源"。
- 后续任务在同一文件上**扩展**（加场景、加参数），不复制粘贴新建副本。
- 任务拆解时识别共享基础设施，把建立动作放在最早依赖它的任务，避免后续任务推倒重建。

违反此规则会导致：测试基础设施分裂、行为不一致、维护时多处改动易遗漏。

## 运行平台

- **强制平台**：macOS（开发者本机；BSD 工具链）。
- 所有 shell 代码必须遵守 macOS 兼容约束（PM-0001 列举的 `flock` / `date +%N` / `printf` flag-like / `grep -c` exit / pipefail 边界等）。
- 完成实施后必须在 macOS 上运行 `bash scripts/integration-test.sh` 全绿才算验证通过；不接受"代码看起来对"或"`bash -n` 通过"作为充分证据。
- 未来引入 CI 时优先 macOS runner。

## 当前覆盖范围

| 阶段 | PASS 数 | 覆盖类别 |
|---|---|---|
| T1 已完成 | 14 | 7 退出原因 + 6 启动校验 + api-error 变体 |
| T2.0 完成期 | +3（实际 17） | 依赖框架 happy / 单缺失 / 多缺失 |
| T2.1 完成期 | +1（实际 18） | claude adapter 骨架 happy |
| T2.2 完成期 | +3（实际 21） | session 采集 happy / mtime fallback / missing |
| T2.3 完成期 | +6（实际 28） | 错误诊断 6 种类别 |
| T2.4 完成期 | +0（复用 T2.1/T2.2 用例加派生视图断言） | `session.history.log` 内容与格式符合 overview.md schema |
| T2.5 完成期 | +2（实际 30） | dep_missing_jq + claude+jq 双缺失非 fail-fast |
| T2.6 完成期 | +4（实际 34） | --version + --help + run --help + status placeholder；真实 smoke 手动通过（2026-04-27，claude 2.1.119） |
| T2 总目标 | ≥33（实际 34） | 上述累计；schema 修正：real Claude JSONL tool_result 在 type:"user" 而非 type:"tool" |
| T6.1 完成期 | +2（实际 36） | partial_progress stall（stall_count 累加）+ happy stall_count=0（不误触发） |
| T6.2 完成期 | +4（实际 40） | SC-014-1：effort=low/medium/high/none 各触发一次；mock-claude `_received_effort` 回显 |
| T6.6 完成期 | +1（实际 41） | ralph --version 含 0.1.0（从 0.1.0-dev 提升） |
| T6 总目标 | ≥41（实际 41） | 上述累计；macOS 实测通过 |
| I1 status/watch + dogfood prep | +16（实际 57） | SC-023 status、SC-024 watch 自动化部分、HUMAN-N、legacy 迭代字段隔离、任务前缀、Provider 配置目录、exit-message |
| M1 live tail regression | +2（实际 59） | `ralph run -v` happy/error stream-json filter marker 回归覆盖 |
| I2 Codex adapter | +20（实际 79） | Codex happy path、CODEX_HOME 翻译/隔离、history 派生、诊断矩阵、effort/model 参数、动态任务总数、Codex `run -v` live tail |
| I2 observability fix | +4（实际 83） | 长 provider oneshot 默认 heartbeat；timeout/interrupted 清理 provider 子进程树；`watch` 运行中 tail 当前 round |
| I3 watch surface fix | 0（实际 83） | `watch` 非 TTY fallback 改为 one-line watch bar，并断言不泄漏 `status` 详情字段 |
| I4 Gemini mock tests | +17（实际 100） | Gemini happy path + run -v markers、GEMINI_CLI_HOME 翻译/隔离/空值鲁棒、session capture（精确/mtime fallback/missing）、错误诊断矩阵 7 类、model 参数、依赖缺失 |
| I5 sticky/plain/round | +20（实际 120） | sticky 渲染（首帧/重绘/健康灯/事件区/退出还原）、plain 模式回归（heartbeat/marker）、per-task round/stall 触发、HUMAN 自动插入、legacy 命名到 round 的回归、env 分组重命名 |
| Release cleanup | +29（实际 149） | runtime 不暴露迭代元数据、Gemini/Codex 事件区回归、sticky UX、旧 flag/env 拒绝、release 文档口径 |

## Provider 兼容性与权限回归门（QA-1）

每次改动 provider adapter、输出解析/终态契约、session 采集路径或权限参数时，除完整集成测试外必须复核本节用例组。用例集中在 `scripts/integration-test.sh` 的「QA-1」段（`SC-028-1` / `SC-030-1` / `SC-031-1` + REQ-029 非零退出组合），共 11 例。

| 维度 | 用例 | 断言要点 |
|---|---|---|
| 入口收敛（REQ-028 / SC-028-1） | `gate gemini` × 4（`--provider` flag / `.env RALPH_PROVIDER` / 进程 env / mock CLI 在 PATH 上） | rc=1、stderr 含 `temporarily disabled` + `claude, codex or fake`，且 `.ralph/` 下无 `runs/`、`lock`、`status.json` |
| session 采集鲁棒性（REQ-030 / SC-030-1） | `codex archived session`、`codex no session`、Codex/Claude 配置目录隔离诱饵各 1 | 归档 rollout 靠内嵌 id 命中（文件名不匹配）且复制件与原件逐字节一致；采集失败落 `capture_status=warning` + 非空 `capture_warning` 且 run 仍 `done`、`session.history.log` 仍从 stdout 派生；`CODEX_HOME` / `CLAUDE_CONFIG_DIR` 不可达时不得回落到 `$HOME` 配置目录 |
| 权限参数审计（REQ-031 / SC-031-1） | Claude 权限参数运行时审计、扩权参数文件扫描 | mock 回显的 `--dangerously-skip-permissions` / `--allowedTools` 与 adapter 源码声明一致；扩权 flag 只允许出现在 provider adapter 文件内（防第四个文件隐式扩权） |
| 非零退出 × 终态（REQ-029） | `codex completed_then_rc1` | `turn.completed` + 进程非零退出 → `exit_reason=provider_failed`；success 终态不得掩盖退出码 |

**诱饵（decoy）用例的判别力**：配置目录隔离两例由 mock 在**采集期内**（`provider_started_at` 之后）向真实 HOME 配置目录写入与 `session_id` / `thread_id` 同名的诱饵 session（scenario `home_decoy`），刻意忽略 `CLAUDE_CONFIG_DIR` / `CODEX_HOME`。诱饵必须写在采集期之后，否则时间锚点不命中，用例会退化成恒真。已做变异验证——去掉 `CODEX_HOME` / `CLAUDE_CONFIG_DIR` 后诱饵确实被采成 `capture_status=ok`（Claude 走 `fallback by mtime`），说明用例能区分「隔离生效」与「回落泄露」。

**权限的已知缺口（不计入失败）**：REQ-031 字面要求把沙箱 / approval 参数记录到 `meta.json`，当前 meta 无权限字段；实际可审计通道是 adapter 源码声明 + `provider.stdout.log` 中 provider 回显的 argv + `docs/architecture/security.md`。缺口本体已在 security.md 记录，属新 REQ 决策而非测试问题。

**Gemini 测试层状态**：`mock-gemini` 与历史 Gemini 用例组保留在 `integration-test.sh` 的 `if false; then` 块内（`--provider gemini` 已在入口被 REQ-028 拒绝），当前不计入回归门；重新接入 Gemini 时需同时恢复该块并新增兼容性验证。

**真实 provider smoke**：本回归门只跑 mock/fake。真实 Claude/Codex CLI 端到端 smoke 属人工触发项（见下文「未覆盖范围」），不阻塞本门结论，但必须在报告里显式声明是否执行。

## I5 特色测试策略 (Sticky / Plain / Per-task)

I5 引入了复杂的 TUI 渲染和 per-task 熔断逻辑，测试策略扩展如下：

### 1. Sticky 渲染仿真 (QA-1)

由于 `sticky.sh` 依赖 TTY 状态和 ANSI 控制码，集成测试通过以下方式仿真：
- **TTY Mock**：使用 `script` 或 `expect` 环境模拟真实终端。
- **布局断言**：断言 stdout 包含预期的 ANSI 向上移动序列（如 `\033[10A`）和行清理序列（`\033[K`）。
- **健康灯时钟模拟**：通过 `touch -t` 修改 provider log 的 mtime，验证健康灯在静默 60s/300s 后的颜色切换。

### 2. Plain 模式回归 (QA-2)

验证 `ralph run` 在非 TTY 或无 `-v` 时保持 agent 友好性：
- **无 ANSI 检查**：断言 stdout 不含任何 `\033[` 控制序列。
- **Heartbeat 验证**：模拟长 round（60s+），验证 heartbeat 字符输出。

### 3. Per-task 熔断与 HUMAN 插入 (QA-3)

验证防死循环机制的侵入性修改：
- **TASKS.md 监测**：在触发 `max_round` 或 `stall_limit` 后，验证 TASKS.md 确实被插入了 HUMAN-N 任务，且位置正确。
- **Exit 状态**：验证退出码为 7 (`blocked_by_human`) 且 status.json 记录了正确的触发原因。

未覆盖范围（已知，不计入失败）：

- 真实 provider CLI 端到端：T2.6 单轮 smoke + T6.3 多轮 smoke + T6.4 边界三场景 均手动完成，证据贴 checkpoints/。
- lock 获取前 `interrupted` 竞争窗口：可观察风险，已在 T1 接受。
- 性能、并发压力：v0.1 不验证。

## 与方法论的边界

- 通用测试方法论（如何设计验证策略、追踪矩阵、报告口径）在 `.spec/rules/testing.md`，是协作规则。
- 项目具体测试规范（本文）和具体任务的验证计划（`task.md` 各任务"验证计划"段）是实施事实。
- 当通用方法论与本项目实际不一致时，以本文为准；同时考虑是否需要更新方法论。
