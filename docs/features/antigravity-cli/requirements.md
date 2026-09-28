# Antigravity CLI 接入需求

> 状态：需求已收敛，待方案与实施验证。本文描述目标行为；当前发布包尚不支持 `antigravity` provider。

## 摘要

让 Ralph 通过 Antigravity CLI（可执行文件 `agy`）执行与 Claude Code、Codex CLI 同一套 fresh oneshot 任务协议，并按现有 round 证据契约采集过程、会话、终态和错误数据。新增 provider 不改变现有 provider 的数据 schema，也不恢复已暂停的 Gemini CLI 入口。

## 背景

- Ralph 当前公开入口只接受 `claude`、`codex`、`fake`；Antigravity CLI 尚无 adapter 或发布包入口。
- 本机 `agy --version` 为 `1.2.12`；`agy --help` 提供非交互 `--print`、`--output-format stream-json`、`--model`、`--effort` 和 `--dangerously-skip-permissions`。这些是命令能力证据，不等于本项目已完成真实运行验证。
- [Antigravity 官方 Headless 文档](https://www.antigravity.google/docs/cli/headless/)说明流式输出含 `init`、`step_update`、`result`，可观察工具调用、终态和 usage；默认权限策略可能软拒绝工具调用且进程仍返回 0。
- 现有 Ralph round 证据契约见 [`../../integrations.md`](../../integrations.md)：`meta.json`、原始 `provider.stdout.log`、尽力采集的原生 session 副本，以及 `session.history.log`。session 证据只用于复盘，不决定任务是否完成。

## 目标

- 使用者能够像选择 Claude/Codex 一样选择 Antigravity CLI 执行 Ralph 任务。
- 每轮保留可追溯的原始输出、会话标识、可读历史、终态和错误诊断；能取得原生会话时保存经过本轮身份校验的副本。
- 无人值守执行时，权限策略允许 agent 完成现有任务协议要求的文件修改、测试和 Git 提交，并且实际生效的权限行为可验证。
- CLI、会话或权限异常有明确诊断，不能被进程退出码 0 或模型自报成功掩盖。

## 非目标

- 不改为跨 round 续接 Antigravity 会话；每轮仍是 fresh oneshot。
- 不新增跨 provider 的 token、耗时或工具调用汇总 schema；Antigravity 输出中的 usage 保留在原始证据中，是否统一统计另立需求。
- 不改变 Claude/Codex 的既有采集格式、权限策略或任务完成判据。
- 不恢复 `gemini` 公开入口，不把 Antigravity CLI 当作 Gemini CLI 的别名。
- 不把 provider 会话或 usage 当作任务完成、代码质量或 Main Agent 验收结论。

## 受众

- 使用者与维护者：选择 provider、观察执行并复盘失败。
- Ralph 工具开发者：维护 adapter、发布包和验证用例。
- Codex Main Agent：在用户要求验收时检查最终工程产物；正常执行过程不回灌主会话。

## 澄清记录

### 轮次 1：接入目标（2026-09-28）

- 用户提出：让 ralph-loop 对接 Antigravity CLI，像 Codex、Claude 一样采集各类数据；先做需求分析。
- 仓库事实：现有 provider 采用 fresh oneshot、统一 round 证据和 best-effort 原生 session 采集，公开入口尚不支持 Antigravity。
- 官方与本机证据：`agy` 提供 headless 流式事件和自动批准工具调用的参数；尚未执行真实 oneshot。

### 轮次 2：数据与权限边界（2026-09-28）

- 用户追问是否能在 oneshot 命令直接指定权限，举例 `--dangerously-skip-permissions`；本机帮助和官方文档均确认 `agy` 有该参数。
- 将“像 Codex、Claude 一样采集”收敛为沿用现有 round 证据契约；额外的统一统计格式不进入本需求。
- 可选配置目录按现有安全预期处理：未配置时用 provider 默认行为；显式配置时必须证明使用了指定配置/凭据域，否则在启动前明确失败，不能静默改用默认账号。
- 用户要求形成需求文档；原生 session 定位与配置目录覆盖方式属于待实测的技术事实，不预填为已确认实现。

## 澄清结论

- **范围**：新增正式可选的 `antigravity` provider（对应 `agy`），覆盖启动、每轮执行、数据采集、终态诊断、观察和发布验证。
- **权限**：无人值守 oneshot 固定使用 Antigravity CLI 的自动批准参数，遵守现有“provider 权限策略写在 adapter、不是运行时开关”的边界。
- **数据**：延续既有四类 round 证据；原生 session 采集失败须留诊断，不能错采另一会话，也不单独阻断 run。
- **任务完成**：仍以 `.ralph/TASKS.md` 状态和现有 run 控制流判断；provider 证据用于执行诊断与复盘。
- **待验证事实**：在受支持的 AGY 版本上，headless 原生 transcript 能否稳定按本轮 ID 定位；是否存在受支持的配置目录覆盖方式。

## 需求清单

| 需求编号 | 名称 | 描述 | 优先级 | 类型 | 来源 |
|---|---|---|---|---|---|
| REQ-048 | Antigravity 正式入口 | 使用者选择 `antigravity` 时，Ralph 应在既有 workspace 和任务协议下启动 `agy` 的全新非交互轮次；未安装或无法启动时给出明确错误 | P0-必须 | 功能 | 用户目标；现有 REQ-004/005/011 |
| REQ-049 | 无人值守权限与参数 | Antigravity 每轮应按现有配置优先级使用模型和共同 effort 值，并固定自动批准工具调用；权限参数不能由 `.env` 或 CLI 任意改变 | P0-必须 | 功能/安全 | 用户轮次 2；现有 REQ-014、NFR-SEC-002 |
| REQ-050 | 同等级 round 证据 | 每轮应保留原始输出、元数据和可读历史；应以本轮身份校验尽力采集原生会话，失败时记录原因且不得采入其他会话 | P0-必须 | 功能 | 用户“像 Codex、Claude 一样”；现有 REQ-006/022/030 |
| REQ-051 | 终态与错误诊断 | 应区分成功、失败、未知终态，识别权限拒绝和 provider 错误；进程退出码 0 不得单独证明成功，截断输出不得破坏原始证据 | P0-必须 | 功能/可靠性 | 现有 REQ-006/029；官方 headless 行为 |
| REQ-052 | 配置域一致性 | 未设置 `RALPH_PROVIDER_CONFIG_DIR` 时应使用 AGY 默认配置；显式设置时必须使用可验证的对应配置域，否则启动前失败并解释原因 | P1-重要 | 安全/约束 | 现有 REQ-022；澄清轮次 2 的安全默认 |
| REQ-053 | 发布与兼容验证 | 正式支持声明必须以发布包可运行、既有 provider 回归通过和真实 AGY 隔离 workspace smoke 为依据；未验证能力不得宣称已支持 | P0-必须 | 约束 | 项目发布单元与验证最低要求；现有 REQ-032 |

## 用户场景

### US-048：运行 Antigravity 任务

- 触发：使用者在已部署 Ralph 的 Git workspace 选择 `antigravity` 并启动 `ralph run`。
- 输入：既有 `.ralph/PROMPT.md`、`.ralph/TASKS.md`、可选 model/effort 和 `agy` 登录态。
- 预期结果：Ralph 每轮启动全新 AGY oneshot，任务、状态、超时和退出行为与现有 provider 一致。
- 验收：在隔离 workspace 完成一项需修改文件并提交的任务，最终工程产物和 round 证据均可检查。

### US-049：复盘失败或证据缺失

- 触发：AGY 报错、拒绝工具、输出中断，或原生 session 未找到。
- 输入：本轮原始输出和运行元数据。
- 预期结果：维护者能区分 provider 失败、未知终态和仅 session 采集失败；不会读到另一轮的 session。
- 验收：对应 fixture 和真实 smoke 能复现诊断，原始日志保持不变。

## 成功标准

| 标准编号 | 绑定需求 | 标准描述 | 度量方式 | 目标值 | 验证方法 |
|---|---|---|---|---|---|
| SC-048-1 | REQ-048 | 使用者可选择 Antigravity 完成单任务 fresh oneshot；启动失败不产生误导性的运行成功状态 | 实际任务结果、轮次和退出状态 | 一轮完成一个任务；失败有明确原因 | 隔离 workspace 真实 smoke + mock 集成测试 |
| SC-049-1 | REQ-049 | 每轮按已配置 model/effort 执行，权限足以执行任务协议；空值沿用 provider 默认 | 本轮执行行为与启动参数审计 | 有值准确生效，空值不覆盖默认；无软拒绝被当作成功 | 参数矩阵 mock + 真实权限 smoke |
| SC-050-1 | REQ-050 | 每轮原始输出、元数据和可读历史可追溯；原生会话只在身份匹配时复制 | round 文件、session ID、内容及采集状态 | 100% 原始输出保留；0 次跨会话误采；缺失时有原因 | 多候选/缺失/截断 fixture + 真实 smoke |
| SC-051-1 | REQ-051 | 成功、失败、未知终态及权限拒绝能被区分，原始证据不被改写 | 终态字段、错误诊断、原始日志字节 | 各状态与 fixture 预期一致；exit 0 不掩盖错误 | 终态矩阵、截断行和软拒绝 fixture |
| SC-052-1 | REQ-052 | 显式配置的 provider 配置目录不会被静默忽略 | 实际配置域或启动错误 | 使用指定域，或启动前明确失败且无 run 目录 | 隔离账号/配置目录 smoke + 启动校验测试 |
| SC-053-1 | REQ-053 | 发布包中的 Antigravity 入口可用且既有 provider 行为无回归 | 发布包与测试结果 | 完整项目检查通过；隔离真实 smoke 通过 | 发布包部署测试 + 现有集成回归 + 真实 AGY smoke |

## 业务流程

### BPF-007：Antigravity 每轮执行与采集

- 关联需求：REQ-048、REQ-049、REQ-050、REQ-051、REQ-052。
- 涉及角色：使用者或维护者、Ralph、AGY oneshot、复盘者。
- 触发条件：使用者选择 `antigravity` 且启动校验通过。
- 主流程：Ralph 按既有任务协议准备一轮输入 → AGY 无人值守执行 → 保存原始过程和本轮 ID → 判定结构化终态及错误 → 派生可读历史并尽力采集经过身份校验的原生会话 → Ralph 按既有任务状态继续或退出。
- 异常分支：CLI/登录态不可用时启动失败；权限拒绝、AGY 错误或未知终态留下诊断；原生 session 缺失只留下采集 warning；显式配置目录无法兑现时启动前失败。
- 输入：workspace、任务与 PROMPT、既有 provider 配置。
- 输出：既有 run/status/result 与 round 证据；不输出新的任务完成判据。
- 业务规则：每轮 fresh oneshot；原始输出是复盘事实源；session 只是附加证据。

## 功能需求

### FR-014：Antigravity 启动与参数

- 来源需求：REQ-048、REQ-049、REQ-052。
- 关联流程：BPF-007。
- 输入：既有 provider、model、effort 和可选配置目录。
- 输出：全新的 AGY 非交互轮次，或启动前可诊断失败。
- 业务规则：`antigravity` 对应原生 `agy` CLI；只接受 Ralph 既有共同 effort 集合；权限策略固定而非用户可调；显式配置目录不得静默失效。

### FR-015：证据采集与派生

- 来源需求：REQ-050。
- 关联流程：BPF-007。
- 输入：本轮 AGY 输出及可获得的原生会话。
- 输出：现有 round 证据契约要求的文件和采集状态。
- 业务规则：保留原始 stdout/stderr；原生会话必须和本轮 ID 一致才可复制；缺失时保留可读诊断，不能用“最新会话”代替身份校验；原生 session 缺失不阻断 run。

### FR-016：终态与诊断

- 来源需求：REQ-051。
- 关联流程：BPF-007。
- 输入：本轮原始输出和进程退出状态。
- 输出：既有终态三态字段与错误诊断。
- 业务规则：结构化终态与进程退出状态分别保存和解释；权限拒绝不得视作正常成功；未知或截断流留下 warning，原始输出只读不改。

## 非功能需求

| 编号 | 类别 | 描述 | 指标或目标值 | 测量方法 | 来源 |
|---|---|---|---|---|---|
| NFR-REL-005 | 可靠性 | 原生 session 采集失败不得中断已成功完成的 provider 轮次，但不得误采其他会话 | 采集缺失为 warning；跨会话误采为 0 | 多候选/缺失 fixture | REQ-050；现有 NFR-REL-002 |
| NFR-OBS-002 | 可观察性 | 原始事件、stderr 与后续合法终态在截断行存在时仍可复盘 | 原始 log 字节保留，后续合法事件可解析 | 字节比较 + 终态 fixture | REQ-050、REQ-051；现有 REQ-029 |
| NFR-SEC-004 | 安全 | Ralph 不主动把 provider 凭据或配置文件复制进运行元数据、文档和发布包；原始日志与会话按敏感本地证据管理；显式配置域不得静默回退 | 0 个主动复制的凭据文件；0 次静默回退 | 文件来源审查 + 发布包检查 + 配置域 smoke | REQ-052；现有安全边界 |

## 约束

| 编号 | 类别 | 约束描述 | 来源依据 | 是否可协商 |
|---|---|---|---|---|
| TC-INT-004 | 集成 | 使用原生 `agy` CLI，不封装 Antigravity API；运行期仍遵守现有 shell-first、per-workspace 和 adapter 契约 | REQ-048；现有 TC-STK-001/002/005 | 否（本需求） |
| TC-INT-005 | 版本 | 真实 smoke 应记录 AGY 版本；不同版本的事件、权限或会话位置差异不能被假定相同 | REQ-053；CLI 外部依赖 | 否 |
| TC-REG-003 | 发布 | 对外支持声明以生成的 `release/<version>/` 为准，不以开发仓库中存在 adapter 为准 | REQ-053；项目发布边界 | 否 |

## 假设

- `antigravity` 是 Ralph 的 provider 名称，`agy` 是对应二进制名；沿用现有 `--provider` / `RALPH_PROVIDER` 入口，不新增并行入口。
- 只要求和现有 provider 等价的证据采集。usage 保留在原始事件中，本需求不新增统一统计字段。
- 未显式指定模型、effort 或配置目录时，保留 provider 默认行为。
- 原生会话是复盘附加证据；若 AGY 当前版本无法提供可校验的 headless 原生 transcript，保留原始流与明确采集 warning，并在发布说明中如实说明覆盖范围。

## 边缘情况

- `agy` 不在 PATH、未登录、模型名称无效或输出异常：应有可定位的启动/轮次错误，不把空输出标成成功。
- 进程退出 0 但终态错误或工具被软拒绝：不能仅凭退出码判定成功。
- 输出混有 stderr 或半行 JSON，后面仍有合法终态：原始字节保留，合法事件仍可被识别。
- 本轮 ID 缺失、原生 session 未落盘、候选属于其他会话：不得复制不确定文件；保留采集 warning。
- 设置 `RALPH_PROVIDER_CONFIG_DIR` 但 AGY 无受支持的对应配置域覆盖方式：启动前失败，不使用默认账号继续运行。
- 每轮可能产生子 agent 事件：原始输出全量保留；可读历史只承诺可解释的事件类型，不臆造缺失内容。
- 原始 provider 输出或会话可能包含 prompt、工具输出及敏感信息；沿用 `.ralph/runs/` 默认 Git 忽略和分享前人工审查规则，不承诺自动脱敏。

## 待澄清

- **实施前技术核实**：`agy 1.2.12` headless 运行是否稳定提供可按 `conversation_id` 校验的原生 transcript；官方状态行文档的可选 `transcript_path` 不直接证明 headless 可用。[官方状态行文档](https://www.antigravity.google/docs/cli/statusline/)
- **实施前技术核实**：AGY 是否提供受支持的配置目录覆盖方式；若没有，按 REQ-052 的显式配置失败规则处理，不阻断未配置该选项的正常接入。
- 上述两项由实施阶段通过官方资料和隔离 smoke 查证，不推给使用者作事实判断。

## 追踪矩阵

| 上游 | 下游覆盖 | 验证 | 状态 |
|---|---|---|---|
| REQ-048 | SC-048-1、BPF-007、FR-014、TC-INT-004 | mock + 真实 smoke | 需求已定义，待实施 |
| REQ-049 | SC-049-1、BPF-007、FR-014 | 参数矩阵 + 权限 smoke | 需求已定义，待实施 |
| REQ-050 | SC-050-1、BPF-007、FR-015、NFR-REL-005、NFR-OBS-002 | 证据 fixture + 真实 smoke | 需求已定义，待实施 |
| REQ-051 | SC-051-1、BPF-007、FR-016、NFR-OBS-002 | 终态矩阵 + 截断 fixture | 需求已定义，待实施 |
| REQ-052 | SC-052-1、BPF-007、FR-014、NFR-SEC-004 | 配置域 smoke + 启动测试 | 需求已定义，技术路径待核实 |
| REQ-053 | SC-053-1、TC-INT-005、TC-REG-003 | 发布包部署 + 完整回归 + 真实 smoke | 需求已定义，待实施 |

## 变更影响

- 实施时检查现有 Ralph 入口与 adapter、`docs/architecture.md`、`docs/integrations.md`、`docs/security.md`、`docs/testing.md`、`README.md`、发布构建和完整检查；只有经验证后才更新正式支持矩阵。
- 若后续要把 usage 汇总写入公共元数据，须另行更新所有 provider 和消费端的 schema 与成功标准。
- 不在本需求阶段改写 `.ralph/TASKS.md` 或生成 release；任务清单的建立和派发时机由用户决定。

## 质量检查

- [x] 目标行为与实现路径分离；未证实的原生 session 和配置目录能力标为技术核实项。
- [x] 每个目标有对应的 `REQ-*` 和 `SC-*`。
- [x] P0/P1 需求均有可观察的成功标准。
- [x] 核心流程包含触发、角色、输入、输出和异常分支。
- [x] `FR-*`、`NFR-*`、`TC-*` 均有来源依据。
- [x] 没有把运行证据、退出码或本机 CLI 帮助当作端到端完成事实。
