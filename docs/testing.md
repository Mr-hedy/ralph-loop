# Testing

- 状态：已确认。
- 最近验证：2026-10-09，0.1.8 在 macOS 系统 Bash 3.2.57 下完整集成测试 **193 PASS / 0 FAIL**；包括 18 项新增发布回归和 6 组详情/紧凑 PTY、实际状态写入并发检查。Shell/jq 语法、静态规则、发布包完整比对与空白检查通过。真实 Codex 0.159.2、Claude Code 2.1.284、Antigravity 1.3.2 的合成 workspace 发布包烟测均通过。Antigravity 首次隔离 HOME 在认证阶段退出（0 模型轮次）；经用户授权沿用本机现有登录态后通过，无需重新登录。
- 当前修复验证：2026-10-10，0.1.9 系统 Bash 3.2.57 下完整集成复验 **196 PASS / 0 FAIL**，包括 21 项发布回归、14 项详情/紧凑画面/状态回归，以及实际发布包部署。PTY 验证 80/120/180 列、1/4/8 行矮窗口、过大事件区、长中文/emoji/制表符、live → finished、跨帧健康灯、配置加载与十进制校验、并发读取一致性和 Ctrl-C 后终端恢复；实际 run -v 中断验证最终状态、锁释放与 provider 子进程清理。此前一轮 195 PASS / 1 FAIL 的键盘中断超时及处理记录保留在 PM-0008；最终复验全部通过。静态检查、发布包完整比对及空白检查通过，0.1.9 仅交付 Ralph skill。前期修复版曾通过隔离只读观察目录读取营销项目实际运行状态，Ctrl-C 后原 run 和锁保持；本次未重新调用三个真实模型，也未完成各宿主 skill 的交互端到端演练。
- 来源：`docs/features/ralph-loop/requirements.md`（REQ-006 / REQ-011 / REQ-012 / REQ-054 / NFR-* 系列）、`docs/features/antigravity-cli/requirements.md`（REQ-048 ~ REQ-053）、`docs/architecture.md`（启动校验、退出原因、运行目录 schema）、`docs/integrations.md`（provider 集成约束）、`docs/postmortems/pm-shell-macos-compat.md`（PM-0001）、`docs/postmortems/pm-cross-task-decision-sedimentation.md`（PM-0002）。
- 范围：本文承载 ralph-loop 项目的测试入口、基础设施约定、隔离规则、单一来源规则、运行平台和当前覆盖范围。本文不重复测试方法论（在 `.spec/rules/TESTING.md`），不写具体用例的验证计划；用户已建立对应任务时，计划写入 `.ralph/TASKS.md` 的“验证计划”段，其他工作在交付中报告。root `task.md` 已封版。
- 变更条件：测试入口脚本变化、新增 fixture 或 mock 类型、隔离规则失效、新平台支持、测试覆盖目标变化。

## 测试入口

| 命令 | 用途 | 通过标准 |
|---|---|---|
| `bash scripts/check.sh` | 逐文件 Shell 语法、协议版本指纹、安装文档依赖基线、现行文档位置、发布包从源文件重建后的完整比对 | stdout 含 `ralph-loop check passed` |
| `bash scripts/build-release.sh --verify` | 单独核对当前版本 release 的文件清单和全部生成内容，不修改现有发布包 | stdout 含 `release verified`；多文件、少文件或内容不同均失败 |
| `bash scripts/integration-test.sh` | 端到端集成测试（mock workspace + 退出原因 + 启动校验 + adapter 各分支 + 发布包部署） | `PASS=N FAIL=0`，N 随阶段扩展（当前实测：196） |
| `git diff --check` | 空白错误检查 | 无输出 |

完整验证 = `check.sh`、`integration-test.sh`、`git diff --check` 全过；`check.sh` 已调用发布包完整比对。文档/协作规则改动至少跑前两项；脚本/代码改动跑全套。

修改 `.spec/` 或现行 `docs/` 布局时，还要对照 `.spec/rules/DOCS.md` 与 `ARCHITECTURE.md` 人工核对：新增或移动的文档已进入 `docs/README.md` 或其明确的历史索引；历史资料不会被标成现行规则；文档状态、可见链接文字和文档内容一致；方案文档不承载独立审查报告。`check.sh` 的文件存在性检查和 release 字节比对不能证明这些语义关系。

## Release 部署验证

发布包不仅要和构建脚本逐文件一致，还要在新 workspace 中可用。修改 `.spec/`、`.ralph/`、模板、构建脚本或发布入口时：

1. 运行 `bash scripts/build-release.sh --verify`，确认当前包没有多余或缺失文件，生成内容逐项一致，CLI 入口保持可执行。
2. 将 `release/<version>/.` 复制到仓库内的临时 Git workspace，确认 `CLAUDE.md` 软链、`ralph --version`，再用临时测试任务和 fake provider 跑到 `exit_reason=done`。不得使用本仓库真实 `.ralph/TASKS.md`。
3. 逐项核对发布版 `AGENTS.md`、`.spec/README.md`、`.ralph/README.md` 和 `README.md` 中要求用户或 agent **立即读取**的本地文件：必须存在于包内，或明确写成首次会话按需创建、仅在项目已有时读取、或仅存在于开发仓库。示例路径与未来目标结构不按已交付文件处理。
4. 检查包内无 `.ralph/runs/`、`status.json`、`lock`、真实 `.env`、本仓库任务状态，以及未交付的 Hook / Skills。0.1.9 仅交付 `.agents/skills/ralph/SKILL.md`；其他 skills 不进入包。

`scripts/integration-test.sh` 的「Release deployment: selected Bash compatibility」用例自动复制当前完整发布包到仓库内临时 Git workspace；通过统一的 `TEST_BASH` 解释器验证两任务两轮完成、任务勾选、result/status 的终态与计数、非 TTY watch、版本输出、CLI 可执行权限、`CLAUDE.md` 软链及只包含 Ralph skill。安装指引必须在复制命令前列出完整冲突清单（包括 `README.md` 与 `.agents/`）；发布 README 不能覆盖已有项目 README。

发布回归还覆盖同秒 run ID 碰撞保留旧证据，校验器拒绝同字节外部 CLI 软链与额外 skill；PTY 覆盖极矮窗口、过大事件区、跨帧健康灯、并发状态读取与 `NO_COLOR`，并验证独立 watch 加载 `.env` UI 配置、进程值优先。UI 数值回归覆盖前导零、非法阈值、过大值与表达式输入；Ctrl-C 退出后核对终端输入标志、中断键和自动折行均恢复。 实际 `run -v` 中断回归还核对退出码 130、最终 result/status、锁释放和 fake provider 外部子进程清理；共享 renderer 的单次调用保留原生 SIGINT。并发写入下，TTY watch、非 TTY watch 与文本 status 均核对同一快照内的轮次与任务进度。部署回归证明包的实际 CLI 行为及静态入口可读，不证明各宿主已完成 skill 交互端到端验证；Claude 主会话原生通知和宿主关闭/恢复仍需单独演练。

真实 Claude/Codex/Antigravity provider smoke 与上述 fake 部署验证分开报告；fake 通过不表示真实 provider 已验证。

## 测试基础设施

```text
scripts/
  check.sh                              # 静态检查入口
  integration-test.sh                   # 端到端测试 + helper（setup_workspace / setup_claude_workspace 等）
tests/
  release-regressions.sh                # 接入完整集成入口的新增发布回归
  watch-details-pty.py                  # Python 3 标准库 PTY 发布包验证
  fixtures/
    mock-claude                         # claude CLI 测试替身（单一来源）
    mock-codex                          # codex CLI 测试替身（单一来源）
    mock-antigravity                    # antigravity CLI (agy) 测试替身（单一来源，REQ-048 ~ REQ-053）
    mock-protocol-adapter               # 协议变化测试 adapter（只用于临时 workspace）
    claude-session-sample.jsonl         # Claude session jsonl 样本（T2.4 起）
```

新增 mock 替身或 fixture 必须放 `tests/fixtures/` 下；helper 函数集中在 `scripts/integration-test.sh`，不另起脚本。

## 测试隔离规则

测试不得污染或破坏使用者环境。自动化测试和 fixture 的副作用必须限定在临时目录或被测进程的子作用域内；真实 provider smoke 的原生用户目录写入须按下方规则取得明确授权。

**强制要求**：

- **HOME 隔离**：自动化测试必须使用临时 HOME 或已验证的 provider 配置域，用户目录写入落到临时目录。真实 provider smoke 先核对原生认证机制；复制单个凭据文件不能证明新 HOME 已取得现有登录态。若必须沿用本机登录态，先说明原生会话/认证缓存可能写入的位置，并取得用户明确授权；合成任务 workspace 仍须隔离。不得把隔离环境的认证失败推断为本机未登录，也不得未经授权启动重新登录。
- **PATH 隔离**：测试若需要修改 PATH（例如模拟某命令缺失），修改必须限定在被测子进程（`env PATH=... ralph run ...`），harness 自身 PATH 不得变更。harness 自己的 jq / git / bash 等工具必须始终可用，否则 harness 自身瘫痪后无法做断言。
- **配置文件隔离**：测试不得修改使用者的 `~/.gitconfig`、`~/.bashrc`、`~/.ssh/`、shell history 等配置；所有 git config 通过临时仓库的本地 config 设置。
- **网络隔离**：单元/集成测试默认不访问外网；需要真实 provider CLI 的 smoke 测试单独标识为人工触发。
- **RALPH 环境变量隔离**：测试若依赖 `RALPH_PROVIDER_CONFIG_DIR` 等变量为空值，必须在 `env` 命令中显式清空（`RALPH_PROVIDER_CONFIG_DIR=""`），否则 ralph loop 父进程环境会泄漏到测试子进程。I4 收口复验确认完整集成测试已恢复到 FAIL=0。

**自检要求**：

- 集成测试结束时至少做一项隔离自检（如 `ls ~/.claude/projects/ | wc -l` 跑测前后一致），把破坏类问题及早暴露。
- 发现隔离失效或可能污染真实环境时，立即停止后续用例。普通断言失败可在隔离 workspace 中收尾、清理并汇总，不得扩大副作用。

## 测试基础设施单一来源

同类测试基础设施（mock 替身脚本、setup helper、fixture 文件）必须**单一来源**，不允许多个任务各自造一份。

**强制要求**：

- 第一个用到该基础设施的任务负责建立"骨架版"（最小可用 + 扩展点清晰），并在 commit 或 task 描述中明确标注"单一来源"。
- 后续任务在同一文件上**扩展**（加场景、加参数），不复制粘贴新建副本。
- 任务拆解时识别共享基础设施，把建立动作放在最早依赖它的任务，避免后续任务推倒重建。

违反此规则会导致：测试基础设施分裂、行为不一致、维护时多处改动易遗漏。

## 运行平台

- **强制平台**：macOS（开发者本机；BSD 工具链）。
- **Bash 兼容基线**：`.ralph/bin/ralph` 的 `RALPH_BASH_MIN_VERSION` 声明支持基线，当前为 3.2；它用于生成安装说明，不新增启动硬拦截。构建脚本从该常量生成发布 README，静态检查核对根 README 的版本值、模板占位和完整生成包。目标机器按实际版本判断，不推定所有 macOS 或工具链都已验证，也不声称更旧版本必然无法运行。最低支持版本或依赖变更必须有对应实现和基线运行证据，不能只改文案或常量。
- macOS 上用 `/bin/bash scripts/check.sh` 和 `/bin/bash scripts/integration-test.sh` 验证基线，记录实际解释器与版本。检查脚本和集成 harness 尊重调用者选定的 Bash；全部 Ralph 命令、adapter 单独调用、过滤器及 expect 场景统一使用启动 harness 的 `TEST_BASH`，可显式用其他 Bash 版本复验。此选择不修改 harness 的 PATH，provider 测试替身仍按各场景的隔离 PATH 启动。它验证 Ralph 对 Bash 的兼容性，不验证真实 provider 自身的运行环境要求。
- `check.sh` 对每个 runtime、开发脚本及 mock fixture 分别运行 `bash -n`；多个文件紧跟在一次 `bash -n` 后只会检查首个文件。依赖声明通过运行入口常量、发布模板生成和完整包比对保持一致；字节一致性和语法检查仍不能证明全部依赖的语义正确，需人工对照代码与实际环境。
- 所有 shell 代码必须遵守 macOS 兼容约束（PM-0001 列举的 `flock` / `date +%N` / `printf` flag-like / `grep -c` exit / pipefail 边界等）。
- 完成实施后必须在 macOS 上运行 `bash scripts/integration-test.sh` 全绿才算验证通过；不接受"代码看起来对"或"`bash -n` 通过"作为充分证据。
- 未来引入 CI 时优先 macOS runner。

## 当前覆盖范围

完整集成测试覆盖启动校验、任务循环与退出原因、超时和进程清理、状态观察、Claude/Codex/Antigravity adapter 的成功及失败分支、会话采集安全、权限参数和发布包行为。当前通过数量以 `bash scripts/integration-test.sh` 实测汇总为准；过去版本的用例数量保留在 Git 历史中，不再作为当前基线相加。

`watch --details` 与协议完整性的新增行为由 `tests/release-regressions.sh` 接入完整集成入口，复用唯一 workspace helper；`tests/fixtures/mock-protocol-adapter` 仅安装到临时测试 workspace，不进入发布包。`tests/watch-details-pty.py` 用 Python 3 标准库驱动实际发布 CLI 的 PTY，不模拟渲染函数。

- 协议保护：启动拒绝改写协议；源文件/快照修改、删除、不可读 × provider 成功/网络错误的 12 种组合均以 exit 8 优先于 done/retry，只有一次派发，保留业务成果及损坏现场，写入 result/status/meta 并释放锁；读取瞬间删除、实际读入内容损坏时不派发且正常收尾；SHA-1/SHA-256 仓库输入与快照匹配，runtime 块存在。
- 详情入口：发布包的非 TTY 完整回放、真实 Codex aggregated_output 与错误状态、reasoning、MCP/文件变更、Antigravity DONE 带错误和输出、最终回复、未知/非法事件回退、控制字符清理；TTY 状态短暂损坏恢复与持续损坏有限退出、半行补全、同轮短/等长/长日志替换、换轮与补读中间轮、run 切换、末行无换行和结束退出全部通过。
- Ctrl-C：针对仍运行的真实 Ralph + fake oneshot 验证，详情退出后 run 进程、running 状态和锁保持；默认紧凑 watch 在日志 inode 替换后仍显示新内容。
- 紧凑画面：PTY 输出交给独立终端解释器处理光标回移、清行、宽字符和自动折行，检查屏幕与滚屏历史只出现一个头部，而非只数换行或匹配 ANSI。覆盖长中文结果、emoji/制表符、80/120/180 列、运行到结束及 Ctrl-C 后自动折行恢复。
- 状态原子写入：直接使用发布包 `_ralph_write_status` 连续写入 30 次，另一进程并发读取；样本均为完整 JSON 且 round/tasks_checked 一致。样本数输出在当次日志中，不作为固定基准。

这些验证覆盖当前机器与合成事件；并发压力、其他平台和未来 provider 协议变化没有被外推为已验证。真实授权遵守由下方三个 provider 的“不提交”烟测覆盖。

## 0.1.8 真实 provider 烟测（2026-10-09）

三个 workspace 都从完整 `release/0.1.8/` 复制，在仓库内 `.tmp/verification-0.1.8/real-smoke/<provider>/` 初始化独立 Git 仓库。仅一条合成任务：创建 `smoke.txt`，内容严格为 `ralph 0.1.8 <provider> smoke\n`，验证并勾选任务；禁止暂存、提交、推送和修改控制协议。

执行命令：`/bin/bash .ralph/bin/ralph run --provider <provider> --max-round 1 --max-retry 0 --round-timeout 180`。真实调用及账户使用已获用户授权；Codex/Claude 使用临时配置域，Antigravity 使用用户另行授权的本机 HOME/登录态，允许其原生会话和认证缓存写入。

| Provider / 实测 CLI 版本 | run_id | 端到端结果 |
|---|---|---|
| Codex 0.159.2 | `20261009-130937-e3bb8ea` | exit 0、done、1/1、capture ok、terminal success |
| Claude Code 2.1.284 | `20261009-130938-d29a5ee` | exit 0、done、1/1、capture ok、terminal success |
| Antigravity 1.3.2 | `20261009-132330-de88f1f` | exit 0、done、1/1、capture ok、terminal success |

每个 workspace 均核对目标文件完整内容、任务勾选、result/status/meta 一致、原生会话副本与 history 存在、锁已释放。Git HEAD 与暂存区未改变；PROMPT、bin/、lib/ 与发布包一致。实际发布 CLI 的 `watch --details` 非 TTY 回放均 exit 0；AGY 回放包含工具开始/完成与输出、文字增量及完整最终回复，实时流未提供的思考没有被补造。临时 HOME 中的认证副本在验证完成后清理；测试证据保留在 Git 忽略的 `.tmp/verification-0.1.8/`。

首次 AGY 隔离 HOME 的 `20261009-130939-de88f1f` 返回 exit 2 / provider_failed / auth，0 模型轮次；它是认证环境准备失败，不能记为成功，也不能推断本机未登录。成功补验单独保留上述 run_id。真实烟测仅覆盖当前 CLI 版本、单轮单任务和不提交授权；真实多轮、超长任务、实际提交和其他系统未在本次重跑。

## Antigravity 回归门（QA-3）

改动 `adapter-antigravity.sh`、事件过滤流（`run.sh` / `watch.sh`）或 Antigravity 会话处理时，运行完整 `scripts/integration-test.sh`；其中 18 项 Antigravity 专项断言覆盖 `SC-048-1` ~ `SC-052-1`。下表保留最初 8 项的覆盖说明，后续边界断言以测试脚本为准：

| 场景 | 覆盖要点 | 断言要点 |
|---|---|---|
| `happy path` (SC-048-1) | 正常执行与完整 4 文件采集 | rc=0, done, `session.antigravity.jsonl` 采集成功, `capture_status=ok`, `terminal_status=success`, `session.history.log` 包含人话视图 |
| `flags audit` (SC-049-1) | model/effort 透传与权限参数 | `--dangerously-skip-permissions` 固定传递，`--model` 与非 `none` 的 `--effort` 正常透传 |
| `missing transcript` (SC-050-1) | 原生 transcript 缺失时降级 | `capture_status=warning`，oneshot 正常走完（rc=0），`session.history.log` 从 stdout 正常派生 |
| `decoy isolation` (SC-050-1) | 会话目录 0 误采（防偷跑） | 其他 conversation_id 的 transcript 存在时不被复制，强校验 ID 一致 |
| `denied_actions` (SC-051-1) | 软拒绝覆盖退出码 0 | result 含 `denied_actions` 时即便 CLI exit 0 也判定为 `error.type=permission`，adapter 返回 2，run 退出 `provider_failed` |
| `completed_then_rc1` (SC-051-1) | CLI 非零退出覆盖 SUCCESS | 即使 result 事件声明 SUCCESS，CLI exit 1 仍强制判定为 `provider_failed` (rc=2) |
| `truncated_then_result` (SC-051-1) | 截断坏行容错 | 日志中混入畸形截断行时不崩溃，后续合法 result 事件仍能被正常解析且 `terminal_status=success` |
| `config dir reject` (SC-052-1) | 显式 CONFIG_DIR 快速失败 | 显式设置 `RALPH_PROVIDER_CONFIG_DIR` 时 exit 1，提示暂不支持，且不产生任何 runs/lock/status.json 产物 |

## Provider 兼容性与权限回归门（QA-1）

每次改动 provider adapter、输出解析/终态契约、session 采集路径或权限参数时，除完整集成测试外必须复核本节用例组。用例集中在 `scripts/integration-test.sh` 的「QA-1」段（`SC-028-1` / `SC-030-1` / `SC-031-1` + REQ-029 非零退出组合），共 11 例。

| 维度 | 用例 | 断言要点 |
|---|---|---|
| 入口收敛（REQ-028 / SC-028-1） | `gate unknown` × 4（`--provider` flag / `.env RALPH_PROVIDER` / 进程 env / 同名 CLI 在 PATH 上） | rc=1、stderr 含 `unsupported provider` 与当前四个合法值，且 `.ralph/` 下无 `runs/`、`lock`、`status.json` |
| session 采集鲁棒性（REQ-030 / SC-030-1） | `codex archived session`、`codex no session`、Codex/Claude 配置目录隔离诱饵各 1 | 归档 rollout 靠内嵌 id 命中（文件名不匹配）且复制件与原件逐字节一致；采集失败落 `capture_status=warning` + 非空 `capture_warning` 且 run 仍 `done`、`session.history.log` 仍从 stdout 派生；`CODEX_HOME` / `CLAUDE_CONFIG_DIR` 不可达时不得回落到 `$HOME` 配置目录 |
| 权限参数审计（REQ-031 / SC-031-1） | Claude 权限参数运行时审计、扩权参数文件扫描 | mock 回显的 `--dangerously-skip-permissions` / `--allowedTools` 与 adapter 源码声明一致；扩权 flag 只允许出现在 provider adapter 文件内（防第四个文件隐式扩权） |
| 非零退出 × 终态（REQ-029） | `codex completed_then_rc1` | `turn.completed` + 进程非零退出 → `exit_reason=provider_failed`；success 终态不得掩盖退出码 |

**诱饵（decoy）用例的判别力**：配置目录隔离两例由 mock 在**采集期内**（`provider_started_at` 之后）向真实 HOME 配置目录写入与 `session_id` / `thread_id` 同名的诱饵 session（scenario `home_decoy`），刻意忽略 `CLAUDE_CONFIG_DIR` / `CODEX_HOME`。诱饵必须写在采集期之后，否则时间锚点不命中，用例会退化成恒真。已做变异验证——去掉 `CODEX_HOME` / `CLAUDE_CONFIG_DIR` 后诱饵确实被采成 `capture_status=ok`（Claude 走 `fallback by mtime`），说明用例能区分「隔离生效」与「回落泄露」。

**权限的已知缺口（不计入失败）**：REQ-031 字面要求把沙箱 / approval 参数记录到 `meta.json`，当前 meta 无权限字段；实际可审计通道是 adapter 源码声明 + `provider.stdout.log` 中 provider 回显的 argv + `docs/security.md`。缺口本体已在 security.md 记录，属新 REQ 决策而非测试问题。

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

- 历史 T2.6 单轮 smoke、T6.3 多轮 smoke 和 T6.4 边界三场景的手工验证保留在 `docs/checkpoints/`；不作为当前版本真实 provider 验证通过的证据，当前结论见本文最近验证及真实 smoke 记录。
- lock 获取前 `interrupted` 竞争窗口：可观察风险，已在 T1 接受。
- 性能、并发压力：v0.1 不验证。

## 与方法论的边界

- 通用测试方法论（如何设计验证策略、追踪矩阵、报告口径）在 `.spec/rules/TESTING.md`，是协作规则。
- 项目具体测试规范（本文）和用户已建立任务的验证计划（`.ralph/TASKS.md` 对应任务“验证计划”段）是实施事实；没有对应任务时在交付中说明实际验证。
- 当通用方法论与本项目实际不一致时，以本文为准；同时考虑是否需要更新方法论。
