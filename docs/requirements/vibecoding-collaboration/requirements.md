# Vibecoding Collaboration 需求文档

- 状态：已确认
- 来源：2026-09-16 用户澄清；现有 `.spec/`、Ralph harness、handoff、checkpoint、postmortem 契约。
- 范围：Codex 作为 Main Agent 时，从需求澄清到后台执行、最终验收和长期协作记忆的整体工作方式。
- 变更条件：Main Agent 产品、Ralph 执行边界、事实源职责或 release 部署单元发生变化时重新评估。

## 摘要

本模块把 `ralph-loop` 从单一 CLI harness 扩展为面向 Codex Main Agent 的 vibecoding 协作脚手架。Codex 在主会话中承担需求澄清、方案设计、任务拆解、执行派发和最终验收；Ralph 作为后台黑盒执行器，通过 provider fresh oneshot 完成任务；Main Agent 不消费 Ralph 的执行过程，而是直接检查最终代码、测试、文档和 Git 状态。

Handoff、checkpoint、postmortem 分别治理 Main Agent 会话交接、已验收稳定锚点和可复用失败模式。它们可以互相引用，但不共享触发条件或状态机。

## 背景

- 长任务若全部在一个 Main Agent 会话中执行，工具输出、中间推理和反复修正会挤占上下文，增加决策漂移和幻觉风险。
- Ralph 已能通过 provider fresh oneshot 执行任务，但当前项目事实源仍主要把它描述为独立 CLI，没有定义 Codex Main Agent 如何准备任务、后台派发、验收最终产物和管理长期记忆。
- 现有 handoff 依赖用户或 Agent 主观判断何时切换会话，尚未接入 Codex 已提供的真实会话压缩事件作为客观评估入口。
- checkpoint、postmortem 和 handoff 已各自存在，但尚未在同一协作生命周期中明确职责和引用关系。

## 目标

- 让人类和 Codex Main Agent 以日常口语化沟通完成需求澄清、方案设计和任务拆解，并由 `.spec/` 作为持续生效的协作 harness 约束产物质量。
- 让 Main Agent 在用户明确要求后后台启动 Ralph，使 provider oneshot 的执行过程不进入 Main Agent 上下文。
- 让 Main Agent 在 Ralph 结束后直接按需求、方案和任务验收最终仓库产物，而不是信任 Ralph 的运行结论或模型自报完成。
- 让不满足验收的结果能够形成明确返工任务并再次交给 Ralph 执行，直到目标完成或进入人工决策边界。
- 让 handoff 基于 Main Agent 会话的真实压缩状态触发评估，在用户授权下保存或切换到新会话。
- 让 checkpoint 保存已经验收的安全状态，让 postmortem 把重复或系统性失败转化为未来可执行的预防机制。
- 让上述能力随版本化 release 部署到新的使用者 workspace。

## 非目标

- 不把 `.spec/` 的需求、方案、任务拆解规则分别包装成必须显式调用的 Skill；`.spec/` 继续作为日常对话和文档产出的隐式协作 harness。
- 不让 Ralph 参与 Main Agent handoff 的触发判断；Ralph round、stall、provider session 和日志不属于 Main Agent 会话健康信号。
- 不把 Ralph 的 `result.json`、`exit-message.txt`、任务勾选或退出码当作需求完成证据。
- 不把 provider oneshot 的中间对话、工具事件或完整日志回灌到 Main Agent 正常上下文。
- 不使用 Codex subagent 替代 Ralph 的核心任务执行职责。
- 不在首期依赖 MCP、外部项目管理系统、云端 agent 或不可版本化记忆完成核心流程。
- 不因 Ralph 正常结束自动创建 checkpoint、postmortem 或 handoff。
- 不允许 handoff 在没有用户授权时自动创建新 Main Agent 会话或转移修改权。

## 受众与角色

- **人类负责人**：确认目标和关键取舍，决定何时派发 Ralph，验收高影响结果并授权会话切换。
- **Codex Main Agent**：作为 Team Leader，执行需求澄清、方案设计、任务拆解、后台派发、最终产物 Review 和协作记忆维护。
- **Ralph 执行引擎**：读取已确认任务，在后台通过 provider fresh oneshot 修改 workspace；不参与 Main Agent 会话治理。
- **Provider oneshot agent**：每轮按 Ralph 协议完成一个任务并退出，其内部会话不是 Main Agent 的事实源。
- **项目维护者**：维护 release、`.spec/`、动作 Skills、会话事件适配器、Ralph runtime 和验证门。

## 澄清记录

### 轮次 1：外部 handoff Skill 评估

- 已确认：外部 `project-handoff` 只作为参考，不作为移植目标；本项目重新设计自身机制。
- 已确认：Codex Hook 是产品提供的生命周期扩展机制，支持 `PreCompact`、`PostCompact` 和 `SessionStart(source=compact)`；外部参考项目中依赖 `msvcrt` 的 Python handler 才是 Windows 定向实现，两者不能混同。
- 已确认：本项目不移植该 Windows handler；首期面向 macOS 自行实现最小会话事件适配器。

### 轮次 2：Main Agent 与 Ralph 边界

- 已确认：需求澄清、方案设计和任务拆解在 Codex Main Agent 主会话完成。
- 已确认：只有用户明确要求时，Main Agent 才后台运行 Ralph。
- 已确认：Ralph 具体执行过程对 Main Agent 不可见且不需要可见；正常验收不读取 provider 过程会话。
- 已确认：Main Agent 验收的是最终代码、测试、文档和 Git 状态，不是 Ralph 的运行报告。

### 轮次 3：协作记忆边界

- 已确认：handoff 只解决 Main Agent 长上下文和会话交接，不依赖 Ralph 进度。
- 已确认：checkpoint 是小功能完成并自测后形成的安全 Git 锚点。
- 已确认：postmortem 记录重复或系统性问题，并告知未来 Agent 在相似条件下如何处理。
- 已确认：`.spec/` 是人类与 Agent 日常协作的 harness，不是一个动作 Skill。

## 澄清结论

- 项目定位：Codex Main Agent 协作脚手架，Ralph 是其中独立的后台执行引擎。
- 主接口：Main Agent 向 Ralph 交付已确认任务；Ralph 向 workspace 交付最终工程产物。
- 验收原则：仓库产物和重新执行的验证是完成证据，运行日志和 Agent 自报只用于运行控制或失败诊断。
- 上下文原则：Main Agent 不吸收 Ralph 正常执行过程；handoff 只观察 Main Agent 会话本身。
- 记忆原则：handoff 是可刷新接续状态，checkpoint 是稳定锚点，postmortem 是可复用失败知识；三者不互相替代。
- 授权原则：Ralph 派发、完整 handoff 和破坏性动作仍由用户或既有明确授权控制。

## 需求清单

| 需求编号 | 名称 | 描述 | 优先级 | 类型 | 来源 |
|---|---|---|---|---|---|
| REQ-033 | Codex Main Agent 协作 | Codex Main Agent 必须负责需求澄清、方案设计、任务拆解、执行派发和最终验收，并保持这些决定可追溯到项目事实源 | P0-必须 | 协作 | 澄清轮次 2 |
| REQ-034 | `.spec/` 隐式 harness | `.spec/` 必须在日常自然语言协作中约束需求、方案、任务、Review 和文档质量，不要求用户逐阶段显式调用 Skill | P0-必须 | 协作 | 澄清轮次 3 |
| REQ-035 | 用户授权后后台派发 | 只有用户明确要求使用 Ralph 执行已准备任务时，Main Agent 才能后台启动 `ralph run`；启动后应立即回到可交互状态 | P0-必须 | 功能 | 澄清轮次 2 |
| REQ-036 | Ralph 过程隔离 | Ralph 的 provider oneshot 对话、工具事件和常规运行输出不得在正常路径持续进入 Main Agent 上下文 | P0-必须 | 非功能 | 澄清轮次 2 |
| REQ-037 | Workspace 最终产物验收 | Ralph 结束后，Main Agent 必须直接检查最终代码、测试、文档、Git diff/commit 和需求成功标准；不得以 Ralph 自报完成代替验收 | P0-必须 | 功能 | 澄清轮次 2 |
| REQ-038 | 验收返工闭环 | 最终产物不满足需求时，Main Agent 必须把差距转成可验证的返工任务，再按用户指令交给 Ralph 或在人工边界停止 | P0-必须 | 功能 | 用户协作模型确认 |
| REQ-039 | 单写入者边界 | Ralph 后台运行期间，Main Agent 不得并行修改同一 workspace 的业务文件；需要修改时必须先确认 Ralph 已停止或使用隔离 checkout | P0-必须 | 约束 | 并发一致性要求 |
| REQ-040 | Main Agent handoff 评估 | Handoff 必须仅根据 Main Agent 会话的真实压缩事件、当前任务阶段和已确认的上下文混淆进行评估，不读取 Ralph round 作为触发信号 | P0-必须 | 功能 | 澄清轮次 1-3 |
| REQ-041 | Handoff 授权与接续 | 系统可以自动要求进行 handoff 评估，但保存材料、创建新会话和转移修改权必须遵守用户授权；接手会话应先核对事实再继续 | P0-必须 | 协作 | 澄清轮次 1-3 |
| REQ-042 | Checkpoint 稳定锚点 | 当一个相干工作单元完成并通过相应验证后，checkpoint 应以可审查 Git commit 和 note 保存安全状态、验证结果及未覆盖风险 | P1-重要 | 功能 | 澄清轮次 3 |
| REQ-043 | Postmortem 可复用失败知识 | 重复、系统性、回归或预防机制失效的问题必须记录根因、修复、适用条件和预防检查，并把可执行规则提炼到正确载体 | P1-重要 | 功能 | 澄清轮次 3 / 现有项目规则 |
| REQ-044 | 协作事实源分离 | 需求、架构、任务、运行状态、handoff、checkpoint 和 postmortem 必须各有唯一职责；引用而非复制维护同一事实 | P0-必须 | 约束 | `.spec` 事实源边界 |
| REQ-045 | 最小失败诊断 | Ralph 非正常结束时，Main Agent 只读取定位阻塞所需的最小状态和诊断；完整日志按需查看，不默认灌入主会话 | P1-重要 | 非功能 | 上下文隔离目标 |
| REQ-046 | 协作能力进入 release | 版本化 release 必须携带 Main Agent 入口、`.spec/`、动作 Skills、必要的 Codex 会话治理配置、Ralph 执行单元和文档地图，且不包含开发工程状态 | P0-必须 | 约束 | 用户将项目定位为 vibecoding 脚手架 |
| REQ-047 | 核心能力本地可用 | 首期核心协作流程必须在 macOS 本地 workspace 可用，不依赖外部 SaaS、MCP 或云端记忆 | P1-重要 | 非功能 | 当前开发和使用环境 |

## 用户场景

### US-001：从想法到可执行任务

- 触发：用户在 Codex 主会话提出新的开发目标。
- 输入：用户目标、现有仓库事实和约束。
- 预期结果：Main Agent 按 `.spec/` 完成需求、方案和可验证任务拆解。
- 验收：文档和任务之间可追溯，且用户不需要逐个显式调用需求或方案 Skill。

### US-002：后台执行并保持主会话干净

- 触发：任务已经准备完成，用户要求使用 Ralph 执行。
- 输入：已确认任务源和当前 workspace。
- 预期结果：Ralph 在后台运行，Main Agent 不持续接收执行过程；同一 workspace 不发生双写。
- 验收：执行完成前 Main Agent 仍可交互，正常路径的主会话不包含 provider 完整输出。

### US-003：验收最终产物

- 触发：Ralph 已结束。
- 输入：需求、方案、任务完成标准和最终 workspace。
- 预期结果：Main Agent 通过代码审查、验证命令和必要的行为检查判断目标是否完成。
- 验收：结论能追溯到真实文件和验证证据，而不是 Ralph 退出码或任务勾选。

### US-004：长会话交接

- 触发：Main Agent 会话经历真实自动压缩，或出现已确认的上下文混淆。
- 输入：会话状态、当前项目事实和用户授权。
- 预期结果：系统在合适位置建议 handoff；获批后保存材料并由新会话核对后继续。
- 验收：不会因 Ralph 的内部进度误触发，也不会未经授权创建新会话。

### US-005：稳定点和失败知识沉淀

- 触发：相干功能通过验收，或任务过程中出现重复/系统性问题。
- 输入：最终仓库状态、验证证据和失败分析。
- 预期结果：分别创建 checkpoint 或 postmortem，并把预防规则放入实际执行载体。
- 验收：checkpoint 可定位可回滚；postmortem 能指导未来相似问题而不是只保存日志。

## 成功标准

| 标准编号 | 绑定需求 | 标准描述 | 度量方式 | 目标值 | 验证方法 |
|---|---|---|---|---|---|
| SC-033-1 | REQ-033 | 一次完整协作可以从用户目标追溯到需求、方案、任务和最终验收结论 | 追踪审查 | 核心目标无断链 | 文档 Review + 代表性场景演练 |
| SC-034-1 | REQ-034 | 用户只用自然语言沟通时，Main Agent 仍按 `.spec/` 产生正确阶段产物 | 显式 Skill 调用次数 | 需求/方案阶段为 0 | 对话演练 + 文档 Review |
| SC-035-1 | REQ-035 | 未收到明确 Ralph 执行请求时不会启动；收到后以后台方式启动且主会话可继续交互 | 行为观察 | 两项均满足 | macOS 端到端演练 |
| SC-036-1 | REQ-036 | 正常 Ralph run 的 provider 过程输出不进入 Main Agent 交付上下文 | 上下文审查 | 无完整过程输出 | 端到端演练 |
| SC-037-1 | REQ-037 | `done` 或任务全勾选但最终产物不符合成功标准时，Main Agent 不得判定需求完成 | 负向用例 | 正确拒绝完成 | 故障注入 + Review |
| SC-038-1 | REQ-038 | 每个验收失败项都能形成有范围、完成标准和验证方式的返工任务 | 返工任务审查 | 100% 高优先级差距覆盖 | 文档 Review |
| SC-039-1 | REQ-039 | 同一 checkout 中不会同时存在 Ralph 与 Main Agent 的业务文件写入 | 并发检查 | 0 次双写 | 集成演练 |
| SC-040-1 | REQ-040 | Handoff 的自动评估由真实 Main Agent 压缩/会话事件触发，Ralph round 变化不会单独触发 | 事件序列测试 | 规则全部通过 | 生命周期事件 fixture 测试 |
| SC-041-1 | REQ-041 | 未经授权不会创建接手会话；获批后接手会话先核对关键事实再修改 | 正反场景 | 两项均满足 | 端到端演练 |
| SC-042-1 | REQ-042 | Checkpoint 能定位唯一 commit，并记录已验证、未验证和关联 postmortem 状态 | 完整性检查 | 必填项完整 | Skill fixture + Git 演练 |
| SC-043-1 | REQ-043 | 代表性重复失败产生可执行 prevention check，并被正确路由到 Skill、`.spec/`、脚本、测试或 AGENTS | 沉淀审查 | 至少一个实际预防载体 | Postmortem 演练 |
| SC-044-1 | REQ-044 | 任一核心事实只有一个权威位置，其他文档使用引用 | 事实源审查 | 无第二事实源 | Review + 静态检查 |
| SC-045-1 | REQ-045 | Ralph 失败时默认只带回退出原因、阻塞点和必要诊断位置 | 输出审查 | 无整段 provider transcript | 故障演练 |
| SC-046-1 | REQ-046 | 新 workspace 从 release 部署后可以完成需求协作、Ralph 后台执行、最终验收和动作 Skill 调用 | 端到端部署 | 一条完整 happy path 通过 | 临时 workspace smoke |
| SC-047-1 | REQ-047 | 核心 happy path 在 macOS 离线于外部协作服务时仍可执行 | 依赖审计 | 无强制外部服务 | 依赖扫描 + smoke |

## 业务流程

### BPF-003：Main Agent 到 Ralph 再到验收

- 关联需求：REQ-033、REQ-034、REQ-035、REQ-036、REQ-037、REQ-038、REQ-039、REQ-045。
- 涉及角色：人类负责人、Codex Main Agent、Ralph、provider oneshot agent。
- 触发条件：用户提出开发目标。
- 主流程：Main Agent 澄清需求 → 形成方案 → 拆解任务 → 用户要求执行 → Main Agent 后台启动 Ralph 并停止业务写入 → Ralph 修改 workspace → Main Agent 确认运行结束 → 直接审查最终产物并复跑验证 → 通过则结束或 checkpoint，不通过则形成返工任务。
- 异常分支：任务未准备好则不启动；Ralph 阻塞则读取最小诊断并交还用户；执行期间需要 Main Agent 修改时先停止或隔离 Ralph；验收失败进入返工而非伪装完成。
- 输入：用户目标、项目事实、需求、方案、任务源、workspace。
- 输出：已验收工程产物，或明确返工/人工阻塞。
- 业务规则：Ralph 运行结论不等于需求完成；同一 checkout 单写入者。

### BPF-004：Main Agent Handoff

- 关联需求：REQ-040、REQ-041、REQ-044。
- 涉及角色：当前 Main Agent、用户、接手 Main Agent。
- 触发条件：发生真实会话压缩、已确认上下文混淆，或用户显式要求。
- 主流程：接收会话事件 → 要求评估 → 核对安全位置、明确后续和切换收益 → 提出建议 → 用户授权 → 保存 `handoff.md` → 创建/打开接手会话 → 接手方核对 → 转移修改权。
- 异常分支：用户选择继续则本次不交接；关键事实不清则先补齐；创建结果未知则查询而非重复创建；未授权则不新建会话。
- 输入：Main Agent 会话状态、项目事实、用户回应。
- 输出：继续当前会话、只保存材料、或已核对的接手会话。
- 业务规则：不以 Ralph 状态作为触发；运行状态不是项目事实。

### BPF-005：Checkpoint

- 关联需求：REQ-042、REQ-044。
- 涉及角色：人类负责人、Codex Main Agent。
- 触发条件：相干工作单元已完成并通过相应验证，且当前状态值得保留为安全锚点。
- 主流程：确认范围和工作树 → 执行 postmortem sweep → 记录验证和风险 → 只暂存相干改动 → 创建 checkpoint note 和 commit → 回读确认。
- 异常分支：存在无法分离的无关改动、状态未验证或仍是实验时不创建。
- 输入：已验收 workspace、验证证据、postmortem 状态。
- 输出：唯一 commit 和 checkpoint note。
- 业务规则：普通执行 commit 不自动成为 checkpoint；checkpoint 表示已审查稳定点。

### BPF-006：Postmortem

- 关联需求：REQ-043、REQ-044。
- 涉及角色：Codex Main Agent、项目维护者、未来 Agent。
- 触发条件：重复错误、回归、系统性边界问题或预防机制失效。
- 主流程：检索已有条目 → 分析现象、根因、修复和适用条件 → 新增或更新条目 → 定义 prevention check → 把未来行为提炼到正确载体。
- 异常分支：一次性低价值错误不记录；已有条目覆盖时更新或引用；缺少根因时标记待补而不伪造。
- 输入：可复核失败证据、修复结果和影响范围。
- 输出：可检索失败模式及至少一个具体预防方向。
- 业务规则：postmortem 不是日志，也不是需求或当前任务事实源。

## 功能需求

### FR-009：后台 Ralph 派发

- 来源需求：REQ-035、REQ-036、REQ-039、REQ-045。
- 关联流程：BPF-003。
- 用户故事：作为 Main Agent，我希望在用户授权后启动后台 Ralph 并只保留运行控制句柄，以便执行过程不污染主会话。
- 输入：已确认 workspace、任务源、provider 配置和用户执行指令。
- 输出：已启动标识；结束后提供终态；失败时提供最小诊断入口。
- 业务规则：启动前确认任务已准备；运行期同一 checkout 不双写；正常路径不读取完整输出。

### FR-010：最终产物验收

- 来源需求：REQ-037、REQ-038。
- 关联流程：BPF-003。
- 用户故事：作为人类负责人，我希望 Main Agent 按需求和成功标准检查最终 workspace，以便 Ralph 的自报完成不会掩盖缺陷。
- 输入：需求、方案、任务、派发前基线、最终代码/测试/文档/Git 状态。
- 输出：`accepted`、`accepted-with-residual-risk`、`rework-required` 或 `blocked`，以及证据和未验证范围。
- 业务规则：必须重新执行与风险匹配的验证；高优先级差距必须形成返工任务。

### FR-011：会话健康跟踪与 Handoff

- 来源需求：REQ-040、REQ-041。
- 关联流程：BPF-004。
- 用户故事：作为长会话使用者，我希望系统根据真实压缩事件要求评估 handoff，以便在上下文退化前切换且不被机械打扰。
- 输入：Codex Main Agent 生命周期事件、当前交接状态、用户回应。
- 输出：无需提醒、延后、交接建议、已保存或已接手状态。
- 业务规则：事件采集与业务判断分离；无用户授权不创建新会话。

### FR-012：稳定锚点

- 来源需求：REQ-042。
- 关联流程：BPF-005。
- 用户故事：作为项目维护者，我希望在已验收安全点创建可追溯 checkpoint，以便后续工作失败时可明确回退。
- 输入：相干改动、验证结果、工作树、postmortem sweep。
- 输出：checkpoint note、commit 和剩余风险。
- 业务规则：不混入无关改动，不用未验证草稿冒充稳定点。

### FR-013：失败知识沉淀

- 来源需求：REQ-043。
- 关联流程：BPF-006。
- 用户故事：作为未来 Agent，我希望在相似失败条件下能找到适用条目和 prevention check，以便不重复同类错误。
- 输入：失败证据、根因、修复和适用范围。
- 输出：postmortem 条目及规则/检查提炼位置。
- 业务规则：一次性低价值错误不创建条目；只记录脱敏证据。

## 非功能需求

| 编号 | 类别 | 描述 | 指标或目标值 | 测量方法 | 来源 |
|---|---|---|---|---|---|
| NFR-CTX-001 | 上下文隔离 | Ralph 正常执行过程不得持续占用 Main Agent 上下文 | 不出现完整 provider 过程输出 | 会话审查 | REQ-036 |
| NFR-REL-004 | 可靠性 | 会话事件观察或提醒失败不得阻止原业务工作继续 | 会话治理组件 fail-open | 故障注入 | REQ-040、REQ-041 |
| NFR-AUD-001 | 可审计性 | 验收、checkpoint 和 postmortem 结论必须能定位真实文件、命令、commit 或稳定文档 | 高影响结论 100% 有证据位置 | Review | REQ-037、REQ-042、REQ-043 |
| NFR-COMP-001 | 兼容性 | Main Agent 协作层不得改变 Ralph provider adapter 和 fresh oneshot 稳定契约 | 现有 Ralph 集成测试全绿 | 回归测试 | REQ-035、现有 Ralph 契约 |
| NFR-PRIV-001 | 隐私 | Handoff、checkpoint、postmortem 和会话事件状态不得保存 secrets 或完整私人会话 | 0 个完整凭据/私人 transcript | 静态扫描 + Review | 项目安全边界 |

## 技术约束

| 编号 | 类别 | 约束描述 | 来源依据 | 是否可协商 |
|---|---|---|---|---|
| TC-MAIN-001 | Main Agent | 首期以本地 Codex 作为 vibecoding Main Agent | 用户明确指定 | 否（首期） |
| TC-EXEC-001 | 执行 | 后台任务执行继续复用现有 Ralph shell harness 和 provider fresh oneshot，不由 Codex subagent 替代 | 用户协作模型 / 现有契约 | 否 |
| TC-STATE-001 | 状态 | Main Agent 会话运行状态与项目事实分离；运行状态不得成为第二项目事实源 | REQ-040、REQ-044 | 否 |
| TC-REG-002 | 版本控制 | 需求、架构、动作协议、checkpoint 和 postmortem 继续以 repository 文件作为可审查载体 | `.spec` / 用户协作模型 | 否 |
| TC-PLAT-001 | 平台 | 首期开发和端到端验证平台为 macOS | 用户环境 / 现有 testing 契约 | 否（首期） |

## 假设

- Main Agent 与 Ralph 默认操作同一个本地 Git workspace，但任一时刻只有一个业务写入者。
- Ralph 的后台启动和终态等待可使用 Codex 当前本地 shell/终端能力；具体进程托管方式在实现设计中确定。
- Handoff 首期使用 Codex 本地生命周期事件作为客观信号；事件不可用或项目 Hook 未获信任时退化为显式用户调用和人工自检。
- 正常 Ralph run 无需读取 `result.json` 才能验收；运行终态仅用于判断何时可以开始审查 workspace。

## 边缘情况

- Ralph 报告 `done`，但代码没有满足成功标准：必须进入 `rework-required`。
- Ralph 失败但留下部分有价值改动：Main Agent 先确认进程已停止，再审查工作树并决定保留、返工或回退。
- 用户在 Ralph 运行中要求修改同一业务文件：必须停止/等待 Ralph，或显式使用隔离 checkout。
- Main Agent 在 Ralph 运行期间发生 handoff：接手材料必须记录运行控制句柄和写入权归属，但不能把 Ralph 内部过程复制进 handoff。
- 自动压缩发生在尚未安全收拢的位置：记录待评估状态，继续到最近安全点再建议，不强制中断。
- Checkpoint 前发现重复失败：先完成 postmortem sweep 和必要沉淀，再创建稳定锚点。

## 待澄清

- Main Agent 后台托管 Ralph 的首期具体方式（Codex 终端会话、detached shell 还是新增 Ralph 子命令）留给技术实现验证后锁定。
- Handoff 是否需要在每次压缩评估之外增加静默期或更细的提醒频率控制，应通过真实长会话试验校准；首期不移植外部参考实现的计数阈值。

## 追踪矩阵

| 上游 | 下游覆盖 | 验证 | 状态 |
|---|---|---|---|
| REQ-033 | SC-033-1, BPF-003 | 文档 Review + 场景演练 | 完整 |
| REQ-034 | SC-034-1, US-001, BPF-003 | 自然语言协作演练 | 完整 |
| REQ-035 | SC-035-1, US-002, BPF-003, FR-009 | macOS 端到端演练 | 完整 |
| REQ-036 | SC-036-1, US-002, FR-009, NFR-CTX-001 | 会话审查 | 完整 |
| REQ-037 | SC-037-1, US-003, BPF-003, FR-010, NFR-AUD-001 | 故障注入 + Review | 完整 |
| REQ-038 | SC-038-1, US-003, BPF-003, FR-010 | 返工场景演练 | 完整 |
| REQ-039 | SC-039-1, BPF-003, FR-009 | 并发集成演练 | 完整 |
| REQ-040 | SC-040-1, US-004, BPF-004, FR-011, NFR-REL-004 | 生命周期事件 fixture | 完整 |
| REQ-041 | SC-041-1, US-004, BPF-004, FR-011 | Handoff 端到端演练 | 完整 |
| REQ-042 | SC-042-1, US-005, BPF-005, FR-012, NFR-AUD-001 | Git 演练 | 完整 |
| REQ-043 | SC-043-1, US-005, BPF-006, FR-013, NFR-AUD-001 | Postmortem 演练 | 完整 |
| REQ-044 | SC-044-1, BPF-003~006, TC-STATE-001, TC-REG-002 | 事实源 Review | 完整 |
| REQ-045 | SC-045-1, BPF-003, FR-009 | 故障演练 | 完整 |
| REQ-046 | SC-046-1 | 临时 workspace release smoke | 完整 |
| REQ-047 | SC-047-1, TC-PLAT-001 | 依赖审查 + macOS smoke | 完整 |

## 变更影响

- 项目级定位：`docs/requirements.md`、根 `README.md`、`AGENTS.md` 和 release README。
- 长期架构：`docs/architecture/overview.md`、`docs/architecture/vibecoding-collaboration.md`、testing/security/deployment 相关章节。
- 动作 workflow：`.agents/skills/ralph`、`handoff`、`checkpoint`、`postmortem`。
- 发布单元：`scripts/build-release.sh`、`release/<version>/` 完整性检查和新 workspace smoke。
- 当前任务事实源：实施前按本需求和架构另行拆解，不在本文维护任务列表。

## 质量检查

- [x] 没有把 `.spec/` 重新定义为动作 Skill。
- [x] 每个目标至少对应一个 `REQ-*` 和成功标准。
- [x] P0/P1 需求均有 `SC-*`。
- [x] 核心流程覆盖角色、输入、输出和异常分支。
- [x] Ralph 运行事实与最终产物验收边界明确。
- [x] Handoff、checkpoint、postmortem 的职责未混写。
- [x] 技术约束均有用户确认或现有项目事实来源。
- [x] 未锁定的实现选择保留为待澄清，不伪装成稳定契约。
