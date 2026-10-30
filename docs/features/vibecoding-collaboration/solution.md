# Vibecoding Collaboration Architecture

- 状态：草案
- 来源：`docs/features/vibecoding-collaboration/requirements.md`（REQ-033 ~ REQ-047）；2026-10-10 宿主/provider 边界与 2026-10-30 默认前台、动态调整及独立复审确认。
- 范围：Main Agent 协作控制面、Ralph 执行面、最终产物验收、handoff/checkpoint/postmortem 记忆面的长期结构和稳定边界。
- 不负责：Ralph 内部 run loop、provider adapter、round schema 和错误诊断细节；这些继续由 `docs/architecture.md`、`docs/integrations.md` 和 `docs/security.md` 管理。
- 变更条件：Main Agent 产品、执行模式与托管方式、事实源、会话生命周期事件、release 组成或动作 workflow 发生变化时重新评估。

## 1. 架构目标

本架构让 Main Agent 维护需求、方案与任务，按模式参与 Ralph 执行并独立复审。双方通过唯一任务源、真实工程产物与必要执行证据协作；完整 provider 会话不回灌，运行自报不替代验收。

```text
人类
  ↕
Codex Main Agent
  需求澄清 → 方案设计 → 用户要求任务拆解 → 授权执行 → 独立复审
       │                              ↑
       └────── 已确认任务 ──→ Ralph ─┘
                              │
                              └─ provider fresh oneshot

Main Agent 的验收对象：最终代码、测试、文档和 Git 状态
Ralph 的运行状态：用于托管与诊断；关键执行证据可触发任务修订，不直接证明验收通过
```

## 2. 方案取舍

### 2.1 选定方案：双平面 + repository 交付接口

- **Main Agent 控制面**：人类协作、`.spec/` harness、需求/方案/任务、派发、验收和动作 workflow。
- **Ralph 执行面**：shell harness、provider fresh oneshot、run 状态和执行证据。
- **Repository 交付接口**：任务源向执行面传递已确认工作；代码、测试、文档和 Git 状态向控制面交付最终产物。
- **协作记忆面**：handoff、checkpoint、postmortem 各自保存不同生命周期的持久信息。

选择理由：执行过程天然高噪声，而需求和验收需要稳定上下文。以 repository 为交付接口，Main Agent 可以独立判断产物正确性，不依赖执行 Agent 的自我评价。

### 2.2 备选：Codex Main Agent 直接执行全部任务

- 优点：工具链简单，Main Agent 可随时修正。
- 缺点：长执行过程、工具输出和反复试错污染主会话，与 REQ-036 冲突。
- 结论：仅适合低风险小改动，不作为长任务默认模式。

### 2.3 备选：Codex subagent 代替 Ralph

- 优点：原生委派和并行能力强。
- 缺点：subagent 结果仍会汇总回 Main Agent；不能复用 Ralph 的任务循环、provider 抽象和运行证据契约。
- 结论：可用于独立只读研究或 Review，不承担核心任务执行。

### 2.4 备选：Main Agent 依据 Ralph result 验收

- 优点：实现成本低。
- 缺点：退出码、任务勾选和模型自报无法证明需求满足，违反 REQ-037。
- 结论：拒绝。Ralph result 只属于运行控制面。

## 3. 组件与职责

### 3.1 Codex Main Agent

负责：

- 与用户通过自然语言澄清目标和约束；
- 按 `.spec/` 维护需求和架构，在用户决定生成任务清单后拆解任务；
- 在用户授权后按 Ralph skill 选择前台或后台并派发，保持原 provider/model/effort；
- Ralph 运行期间保持单写入者边界；
- 完整执行授权内独立审查最终产物与实际行为，复用同版本有效证据并补齐必要验证；遵从仅启动/状态或暂缓复审等较窄指令；
- 说明具体证据，确认写入停止后在已有授权内调整任务或追加必要返工；新的目标、关键契约、权限或预算决定交给用户；
- 在适用时执行 handoff、checkpoint 和 postmortem 动作 workflow。

不负责：

- 读取 Ralph 正常运行的完整 provider 对话；
- 根据 Ralph 自报完成直接宣布需求完成；
- 未经授权自动派发 Ralph 或创建接手会话。

### 3.2 `.spec/` 协作 harness

`.spec/` 是 Main Agent 在日常对话中持续遵循的协作方法和质量门，不是动作 Skill，也不产生独立运行状态。

- 需求、方案、架构、任务和 Review 的方法由 `.spec/rules/` 路由。
- 用户不需要显式说“调用需求 Skill”或“调用方案 Skill”。
- 规则产出的项目事实写入 `docs/` 或唯一任务事实源；`.spec/` 本身不保存项目需求正文。

### 3.3 动作 Skills

`.agents/skills/` 只承载有明确动作、产物或状态迁移的 workflow：

| Skill | 主要动作 | 主要产物 |
|---|---|---|
| `ralph` | 前台/后台托管、证据驱动任务调整、独立复审与范围内返工、状态与诊断 | 宿主句柄与 run_id；任务修订；有证据的执行/验收结论 |
| `handoff` | 保存、恢复、完整交接 Main Agent 会话 | `handoff.md`、接手会话状态 |
| `checkpoint` | 在已验收安全点创建稳定锚点 | Git commit、checkpoint note |
| `postmortem` | 沉淀重复/系统性失败和预防机制 | postmortem entry、提炼后的规则/检查 |

需求澄清、方案设计、任务写作和 agent 对自身交付物的 Review 继续由 `.spec/` 指导，不新增同名动作 Skills。任务清单由用户决定建立；完整工作包执行包含独立复审与必要返工，单独审查和较窄指令按用户范围。

### 3.4 Ralph 执行引擎

Ralph 继续遵守既有稳定契约：

- shell-first；
- per-workspace；
- provider fresh oneshot；
- 一轮一个任务；
- 运行态写入 `.ralph/runs/` 和 `.ralph/status.json`；
- provider session 只作为诊断证据，不作为完成事实。
- oneshot 执行者可根据现场发现向任务源追加后续任务，按完成标准记录验证并勾选；需要人类裁决的目标或取舍进入 HUMAN 阻塞。

本协作层不修改 adapter 和 run loop，只新增 Main Agent 如何托管 Ralph 的外部协议。

### 3.5 最终产物验收器

独立产物验收由 Main Agent 执行，完整工作包授权默认包含，较窄请求不扩展。Main Agent 按现有授权确定范围和深度；若要给整个工作包 `accepted` 结论，至少检查：

1. 读取需求成功标准、方案约束和任务完成标准；
2. 确认 Ralph 已结束且 workspace 不再被写入；
3. 以派发前基线对比最终 Git diff/commits；
4. 阅读关键实现和测试；
5. 核对同版本已有证据，补齐与风险匹配的验证，确认断言实际证明目标行为；
6. 检查文档、generated output 和稳定契约；
7. 输出标明范围的 `accepted`、`accepted-with-residual-risk`、`rework-required` 或 `blocked`；局部验收不声明整个工作包通过；
8. 说明真实差距，在既有授权内追加可验证修复并交回 Ralph；超出控制边界时交给用户决定。

局部或快速 Review 可以只检查用户指定范围，但必须列明未覆盖的需求与未运行的验证，不得给整个工作包 `accepted` 结论。Codex 原生 diff/review 能力可以作为代码审查证据，但不能替代需求级验收。

## 4. 关键流程

### 4.1 需求到任务

```text
用户目标
  → `.spec` 需求澄清
  → 需求事实源
  → 方案取舍 / 架构
  → 用户决定生成任务清单
  → 唯一任务事实源
  → Task Readiness Gate
```

Task Readiness Gate 必须确认：

- 目标、非目标和成功标准明确；
- 高影响决策已确认或变为 HUMAN 边界；
- 每个任务有范围、完成标准和验证方式；
- Ralph 能在无需重新做产品决策的情况下执行；
- Main Agent 知道最终如何验收。

### 4.2 执行模式与动态任务调整

具体操作唯一入口为 [Ralph skill](../../../.agents/skills/ralph/SKILL.md)。该入口定义请求范围、模式选择、启动身份、停止/恢复与复审共同边界；[前台流程](../../../.agents/skills/ralph/references/foreground.md) 和 [后台流程](../../../.agents/skills/ralph/references/background.md) 按选定模式读取。宿主负责托管，provider 负责 oneshot，两者独立；不新增 runtime 模式字段或 CLI 参数。

```text
用户授权工作包执行
  → 核对 workspace/branch、已有 run、任务与配置
  → 明确模式和依据；默认前台，用户明确模式优先
  → 原生执行句柄 ↔ workspace ↔ run_id 启动核对
     ├─ 前台：持续参与，按需读取关键事件和实际产物
     │    → 证据显示需调整：停止并确认所有写入退出 → 修订任务 → 承接进度续跑
     └─ 后台：启动核对后交还控制权
          → 原生完成通知或用户返回 → 核对原 run 终态
```

前台持续参与不等于频繁打断。正常实现尝试、失败测试与日志暂静由 Ralph 处理；目标偏离、假设失效、验收假阳性或证据/预算风险才构成介入依据。运行中的源码只作为线索，以稳定产物或停止后核对确认发现。Main Agent 修改任务、规格或启动写产物的验证前，确认 Ralph、provider 与相关写入进程退出且锁释放。

修订保留原任务要求、完成历史与证据；未完成任务可细化并记录理由，完成任务的缺陷另追加修复。重启承接部分成果及累计预算，不绕过用户的轮次、时间或调用限制。明确暂停后不自动恢复；失去句柄或退出 watch 不等于停止，锁冲突时核对原 run；控制协议异常保留现场，不自动修改工具文件。

后台必须由宿主原生能力管理，保持可见状态与可查询/停止的句柄。支持原生自动恢复时接续汇报与已授权复审；不支持时启动即说明须用户返回。2026-10-10 的宿主观察仅属于当时环境记录，不证明当前或所有宿主能力；每次使用按实际能力核对。不用 `nohup`、脱管 shell、定时任务或外挂通知替代缺失能力。用户指定后台而后续需要持续判断时，说明证据并等待模式变更决定，已有授权内的必要保护动作仍可执行。

### 4.3 独立复审与返工

```text
核对原 run 的执行终态与完成范围
  → 完整工作包授权：Main Agent 独立复审
    较窄请求或暂缓复审：只报告执行结果与未验收状态
  → 追踪 REQ / SC / 方案 / TASK 到实际产物及行为
  → 复用有效证据，补齐必要验证
     ├─ 通过：标明范围的 accepted
     ├─ 有剩余风险：accepted-with-residual-risk，说明接受依据
     ├─ 真实缺陷：rework-required → 唯一任务源追加修复 → Ralph 实施 → 再复审
     └─ 关键决定/权限/预算缺失或无法验证：blocked → 说明最小待决事项
```

Ralph 的 `done`、任务勾选或 exit code 0 只证明相应执行状态。验收需覆盖真实代码、测试条件、持久化或生成物和必要端到端行为；阻塞问题未关闭不得宣称工作包完成。已有授权内的必要修复不重复确认，也不把风格偏好、未来能力或重复测试变为新验收门。运行与验收结果分别汇报；不会因完成自动提交、部署、归档或创建 checkpoint。

### 4.4 Main Agent Handoff

Handoff 是与 Ralph 独立的 Main Agent 会话治理状态机：

```text
Codex 生命周期事件
  → compact 事件触发评估提示
  → Agent 检查安全位置、明确后续和切换收益
  → 用户选择继续 / 暂缓 / 只保存 / 完整交接
```

首期采用 Codex 项目级 `SessionStart` Hook，匹配 `source=compact`。该事件在根会话完成手动或自动压缩后触发；即使自动压缩发生在一个 turn 中间，Hook 注入的简短 developer context 也会进入紧接着的续跑。handler 只要求 Main Agent 执行 handoff 评估，不直接写 `handoff.md`、不创建新会话，也不读取 Ralph 状态。

之所以选择 `SessionStart(source=compact)`，而不是外部参考项目的 Python handler：前者是 Codex 原生会话事件，能直接向压缩后的模型上下文注入评估指令；后者依赖 Windows `msvcrt`，既不适配本项目 macOS 环境，也没有必要成为运行依赖。官方能力依据见 [Codex Hooks](https://learn.chatgpt.com/docs/hooks.md)。

稳定边界：

- 客观信号来自 Main Agent 的自动压缩和会话事件；
- Ralph round、stall、status 和 provider session 不参与 handoff 触发；
- Hook 只注入简短评估提醒，不写业务文件，不保存或解析完整 transcript；
- Hook 故障 fail-open；
- 项目 Hook 未获用户信任或被禁用时，退化为用户显式调用 handoff；
- 完整交接需要用户授权；
- 新会话先只读核对 `handoff.md` 和关键 workspace 事实，再获得修改权。

### 4.5 Checkpoint

Checkpoint 在已验收的相干工作单元上创建：

```text
验收通过
  → 判断当前状态是否值得作为安全锚点
  → postmortem sweep
  → 核对工作树和相干范围
  → checkpoint note + Git commit
```

Ralph 内部普通 commit 不自动成为 checkpoint。Checkpoint 表达“此状态已审查、可回退、剩余风险已知”。

### 4.6 Postmortem

Postmortem 由失败模式触发，而不是由任意命令失败触发：

- 重复发生；
- 修复引入回归；
- 权限、事实源或稳定契约边界被误判；
- mock/fixture 通过但真实链路失败；
- 已有 prevention check 缺失或失效。

Postmortem 必须回答：现象、直接触发、根因、修复、适用范围和 prevention check。需要改变未来 Agent 行为时，把规则提炼到 `AGENTS.md`、`.spec/`、动作 Skill、脚本或测试；postmortem 本身只保存证据和解释。

## 5. 状态与事实源

| 信息 | 权威位置 | 生命周期 | 不得替代 |
|---|---|---|---|
| 协作方法和质量门 | `.spec/` | 随 release 演进 | 项目需求正文 |
| 项目需求和架构 | `docs/requirements.md`、`docs/architecture.md`、`docs/features/` 及相关专题文档 | 项目长期 | 当前任务状态 |
| 当前执行任务 | 项目声明的唯一任务事实源 | 当前工作包 | requirement/architecture |
| Ralph 运行状态 | `.ralph/status.json`、`.ralph/runs/` | 单次 run | 完成事实 |
| 最终工程产物 | Git workspace、代码、测试、文档 | 项目长期 | Ralph 自报结论 |
| Main Agent 接续状态 | `handoff.md` | 当前会话链 | checkpoint 历史 |
| 稳定锚点 | Git commit + `docs/checkpoints/` | 不可变历史 | 当前任务板 |
| 可复用失败知识 | `docs/postmortems/` | 长期知识 | 需求或规则本身 |

## 6. Codex 能力映射

### 6.1 直接采用

- `AGENTS.md`：项目入口、职责边界和路由。
- Repository files：`.spec/`、`docs/`、任务源和动作 Skills。
- 本地 shell/terminal：按选定模式启动和控制 Ralph。
- Project Hooks：通过 `SessionStart(source=compact)` 观察真实压缩并注入 handoff 评估；项目 Hook 需要用户审查并信任。
- Code review/diff surface：最终产物的代码审查证据。
- Thread/task 创建与导航：用户批准后的完整 handoff。

### 6.2 有条件采用

- Git worktree：只有需要并行写任务时使用；默认同 workspace 顺序执行。
- Codex subagent：只用于边界清楚的只读研究或独立 Review，不替代 Ralph。
- Plugins：协作能力稳定后可作为 Skills + Hooks 的分发单元；首期使用 release 内的项目级配置，避免增加独立安装面。
- MCP：只有核心流程需要外部系统时引入。

### 6.3 不作为事实源或核心依赖

- Codex/ChatGPT 非版本化 Memory：不保存需求、方案、授权或完成事实。
- Goal Mode：不替代 Ralph 执行；Main Agent 的目标和完成标准写入项目事实源。
- Ralph provider session：不回灌正常主会话，不证明需求完成。
- Subagent 汇总：不作为最终验收结论。

## 7. 写入权与并发

默认同一 workspace 采用单写入者状态：

| 状态 | 业务文件写入者 | Main Agent 允许动作 |
|---|---|---|
| 规划/验收 | Main Agent | 读写、验证、形成任务 |
| Ralph running | Ralph/provider | 按模式只读观察关键证据；不改任务、规格、代码或启动同产物构建 |
| Ralph stopped | Main Agent | 确认全部写入停止后复审、修订任务；代码与测试修复交回 Ralph |
| Handoff waiting | 当前 Main Agent | 保存交接；接手方只读核验 |
| Handoff transferred | 接手 Main Agent | 源会话停止业务修改 |

未来并行执行必须为每个写任务提供独立 worktree，并定义合并责任；不得通过“大家尽量别冲突”替代隔离。

## 8. Release 目标结构

```text
release/<version>/
  AGENTS.md
  CLAUDE.md
  .spec/
  .agents/skills/
    ralph/
    handoff/
    checkpoint/
    postmortem/
  .codex/
    hooks.json                 # SessionStart(source=compact)
    scripts/
      handoff-on-compact.sh    # macOS 最小评估提醒适配器
  .ralph/
  docs/README.md
  README.md
```

首期选定项目级 `.codex/hooks.json`，因为它能随 release 自包含部署，且当前平台明确为 macOS。用户首次使用或 Hook 内容变化后必须在 Codex 中审查并信任；未信任时核心开发流程仍可继续，只失去自动 handoff 评估。独立插件保留为能力稳定后的可选分发方式，不与首期入口并存。

当前 0.1.9 交付 `.agents/skills/ralph/SKILL.md` 与 `references/foreground.md`、`references/background.md`，发布入口显式路由。2026-10-30 按用户要求在同版本同步此次技能升级；已部署 workspace 仍需人工合并升级内容，单看版本号不能区分此次修订。handoff、checkpoint、postmortem skills 与 `.codex/` 会话治理仍待完善，不随本版交付；上面的目录树是目标结构。

## 9. 兼容与迁移

- 现有 Ralph CLI、adapter、run schema 和 provider 行为保持兼容。
- 现有 `.agents/skills/{ralph,handoff,checkpoint,postmortem}` 原位演进，不新增含义重叠的第二组 Skills。
- 项目级需求从“仅 CLI harness”升级为“协作脚手架 + Ralph 执行引擎”；根 README 和 release 文案在实施阶段同步迁移。
- `REQ-017` 已扩展 release 组成契约；REQ-046 负责验证完整协作闭环，本方案阶段不直接修改现有 release 产物。
- 外部 `project-handoff` 只作为研究参考，不成为源码、运行依赖或事实源。

## 10. 风险与控制

| 风险 | 失败场景 | 控制 |
|---|---|---|
| 任务未准备好就派发 | Ralph 重新做产品决策或实现错误方向 | Task Readiness Gate；高影响缺口转 HUMAN |
| 执行期双写 | Main Agent 与 Ralph 覆盖彼此改动 | 单写入者状态；并行时 worktree 隔离 |
| 自报完成误判 | tasks 全勾但产物不满足需求 | 独立复审 + 风险匹配验证 |
| 过程回灌污染 | provider 日志挤占 Main Agent 上下文 | 前台只读取决策所需证据；后台不持续观察；不回灌完整会话 |
| Handoff 机械提醒 | 每次压缩都直接要求切换会打断工作 | Hook 只要求评估；安全位置、上下文质量和切换收益仍需判断；真实使用出现干扰后再增加静默策略 |
| 记忆事实漂移 | handoff/checkpoint/postmortem 复制需求正文 | 唯一事实源表 + 引用而非复制 |
| Codex 能力变化 | Hook 或任务 API 变更导致流程失效 | Codex 集成层独立、fail-open、版本兼容 smoke |

## 11. 实施前置条件与风险处置

### 实施前置条件

- **写入权协议依赖 agent 遵守**：技能已定义停止与核验要求，尚无机器强制隔离；需通过真实宿主停止/恢复演练检验，不能把文档规则称作已实现的防护。
- **独立复审已纳入 Ralph skill**：规则覆盖不代表新会话行为已验证；需在真实工作包检查模式选择、任务调整和范围内返工能否稳定复现。
- **Hook 信任和路径尚未做真实 smoke**：文档已确认 Codex 事件契约，但项目级配置的信任提示、Git 根路径解析和 turn 中间自动压缩续跑仍需在当前 Codex/macOS 版本验证后才能进入 release。

### 后续观察

- 每次压缩都触发评估是否过于频繁尚未通过真实长会话校准；首期先保持无计数状态机的最小实现，出现干扰后再增加静默策略。
- Ralph 后台托管可能受宿主 terminal/session 生命周期影响；必须验证断开、恢复和进程归属。规则随 0.1.9 Ralph skill 交付，不代表所有宿主已完成端到端验证；失去句柄时先核对现有 run，不自动再启动。

### 已接受边界

- 首期只保证 macOS；其他平台在有真实使用需求和验证环境后扩展。
- 首期不使用 MCP、云端 Memory 或 subagent 完成核心流程，减少外部依赖和上下文回流。

## 12. 验证方向

- 临时 workspace 端到端：任务准备 → 已授权执行 → 默认前台/明确后台 → 独立复审 → 必要返工 → 有证据的验收结论。仅启动、状态查询、暂停与明确延后复审分别验证不越界。
- 上下文隔离：前台仅读取关键证据，后台启动后交还控制权；均不回灌完整 provider 输出。
- 宿主/provider 分离：覆盖 Codex 宿主 + Antigravity provider、Claude 宿主 + Codex provider；检查原生运行标识、查询句柄、主会话可交互及按能力汇报。另查快速结束、锁冲突、句柄丢失和原生能力缺失时不会误报运行或重复启动。
- 故障注入：done 但实际产物不满足 SC 时进入返工；假阳性断言、证据清理、预算跨重启与重复失败无新证据时按技能边界处置。
- 并发保护：Ralph running 时阻止或明确拒绝 Main Agent 业务写入。
- Handoff fixture：`SessionStart(source=compact)`、未信任/禁用退化、延后、授权和接手核验状态迁移。
- Postmortem 演练：重复失败能形成 prevention check 并提炼到正确载体。
- Release smoke：复制 release 到新 workspace 后完成完整协作 happy path。
