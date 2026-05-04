# Testing

- 状态：T1/T2/T6/I1/I2 已稳定；当前 83 PASS
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
| T6.1 完成期 | +2（实际 36） | partial_progress stagnation（stagnation_count 累加）+ happy stagnation_count=0（不误触发） |
| T6.2 完成期 | +4（实际 40） | SC-014-1：effort=low/medium/high/none 各触发一次；mock-claude `_received_effort` 回显 |
| T6.6 完成期 | +1（实际 41） | ralph --version 含 0.1.0（从 0.1.0-dev 提升） |
| T6 总目标 | ≥41（实际 41） | 上述累计；macOS 实测通过 |
| I1 status/watch + dogfood prep | +16（实际 57） | SC-023 status、SC-024 watch 自动化部分、HUMAN-N、iteration_name、任务前缀、Provider 配置目录、exit-message |
| M1 live tail regression | +2（实际 59） | `ralph run -v` happy/error stream-json filter marker 回归覆盖 |
| I2 Codex adapter | +20（实际 79） | Codex happy path、CODEX_HOME 翻译/隔离、history 派生、诊断矩阵、effort/model 参数、动态任务总数、Codex `run -v` live tail |
| I2 observability fix | +4（实际 83） | 长 provider oneshot 默认 heartbeat；timeout/interrupted 清理 provider 子进程树；`watch -v` 在 provider oneshot 运行中 tail 当前 iter；watch help 暴露 `-v` |

未覆盖范围（已知，不计入失败）：

- 真实 provider CLI 端到端：T2.6 单轮 smoke + T6.3 多轮 smoke + T6.4 边界三场景 均手动完成，证据贴 checkpoints/。
- lock 获取前 `interrupted` 竞争窗口：可观察风险，已在 T1 接受。
- 性能、并发压力：v0.1 不验证。

## 与方法论的边界

- 通用测试方法论（如何设计验证策略、追踪矩阵、报告口径）在 `.spec/rules/testing.md`，是协作规则。
- 项目具体测试规范（本文）和具体任务的验证计划（`task.md` 各任务"验证计划"段）是实施事实。
- 当通用方法论与本项目实际不一致时，以本文为准；同时考虑是否需要更新方法论。
