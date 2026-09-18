# Vibecoding Collaboration Architecture

- 状态：草案
- 来源：`docs/requirements/vibecoding-collaboration/requirements.md`（REQ-033 ~ REQ-047）；2026-09-16 用户确认的 Codex Main Agent / Ralph 黑盒执行模型。
- 范围：Main Agent 协作控制面、Ralph 后台执行面、最终产物验收、handoff/checkpoint/postmortem 记忆面的长期结构和稳定边界。
- 不负责：Ralph 内部 run loop、provider adapter、round schema 和错误诊断细节；这些继续由 `overview.md`、`integrations.md` 和 `security.md` 管理。
- 变更条件：Main Agent 产品、后台执行托管方式、事实源、会话生命周期事件、release 组成或动作 workflow 发生变化时重新评估。

## 1. 架构目标

本架构让 Codex Main Agent 像 Team Leader 一样保留需求、方案和验收上下文，把高噪声任务执行交给 Ralph。两者不通过模型总结交接工作，而通过已确认任务和最终 repository 状态交互。

```text
人类
  ↕
Codex Main Agent
  需求澄清 → 方案设计 → 任务拆解 → 派发 → 最终验收
       │                              ↑
       └────── 已确认任务 ──→ Ralph ─┘
                              │
                              └─ provider fresh oneshot

Main Agent 的验收对象：最终代码、测试、文档和 Git 状态
Ralph 的运行状态：只用于启动、等待、停止和失败诊断
```

## 2. 方案取舍

### 2.1 选定方案：双平面 + repository 交付接口

- **Main Agent 控制面**：人类协作、`.spec/` harness、需求/方案/任务、派发、验收和动作 workflow。
- **Ralph 执行面**：后台 shell harness、provider fresh oneshot、run 状态和执行证据。
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
- 按 `.spec/` 生成和维护需求、架构、任务与 Review；
- 在用户明确要求后派发 Ralph；
- Ralph 运行期间保持单写入者边界；
- 运行结束后审查最终 repository 产物并重新执行必要验证；
- 根据验收结果结束、返工或请求人工决策；
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
| `ralph` | 启动、等待、查看终态、诊断 Ralph | 后台进程控制；Ralph 自有 run artifacts |
| `handoff` | 保存、恢复、完整交接 Main Agent 会话 | `handoff.md`、接手会话状态 |
| `checkpoint` | 在已验收安全点创建稳定锚点 | Git commit、checkpoint note |
| `postmortem` | 沉淀重复/系统性失败和预防机制 | postmortem entry、提炼后的规则/检查 |

需求澄清、方案设计、任务拆解和 Review 继续由 `.spec/` 隐式驱动，不新增同名动作 Skills。

### 3.4 Ralph 执行引擎

Ralph 继续遵守既有稳定契约：

- shell-first；
- per-workspace；
- provider fresh oneshot；
- 一轮一个任务；
- 运行态写入 `.ralph/runs/` 和 `.ralph/status.json`；
- provider session 只作为诊断证据，不作为完成事实。

本协作层不修改 adapter 和 run loop，只新增 Main Agent 如何托管 Ralph 的外部协议。

### 3.5 最终产物验收器

验收是 Main Agent workflow，不由 Ralph 执行。它至少检查：

1. 读取需求成功标准、方案约束和任务完成标准；
2. 确认 Ralph 已结束且 workspace 不再被写入；
3. 以派发前基线对比最终 Git diff/commits；
4. 阅读关键实现和测试；
5. 重新运行与风险匹配的验证；
6. 检查文档、generated output 和稳定契约；
7. 输出 `accepted`、`accepted-with-residual-risk`、`rework-required` 或 `blocked`；
8. 将失败差距转成新的可验证任务，而不是直接在 Review 中混入大规模修复。

Codex 原生 diff/review 能力可以作为代码审查证据，但不能替代需求级验收。

## 4. 关键流程

### 4.1 需求到任务

```text
用户目标
  → `.spec` 需求澄清
  → 需求事实源
  → 方案取舍 / 架构
  → 唯一任务事实源
  → Task Readiness Gate
```

Task Readiness Gate 必须确认：

- 目标、非目标和成功标准明确；
- 高影响决策已确认或变为 HUMAN 边界；
- 每个任务有范围、完成标准和验证方式；
- Ralph 能在无需重新做产品决策的情况下执行；
- Main Agent 知道最终如何验收。

### 4.2 后台派发

```text
用户明确要求使用 Ralph
  → Main Agent 运行前检查
  → 记录派发前 Git 基线和写入权
  → 在本地后台启动 `ralph run`
  → Main Agent 不消费正常过程输出
  → 等待运行终态
```

后台控制句柄至少能回答：仍在运行、已结束、需要注意。具体采用 Codex 终端会话、detached shell 或新增 Ralph 管理接口，在实现验证后锁定。

正常路径不调用 `ralph watch`，也不把 provider stdout 注入主会话。非正常结束时先读 `exit_reason`、阻塞任务和最小错误摘要；只有这些不足以定位问题时才按需查看日志。

### 4.3 最终验收和返工

```text
Ralph 结束
  → Main Agent 取得唯一写入权
  → 读取最终 workspace
  → 追踪 REQ / SC / 方案 / TASK
  → 复跑验证
     ├─ 通过：accepted → 可创建 checkpoint
     ├─ 有剩余风险：accepted-with-residual-risk → 用户裁决
     ├─ 不通过：rework-required → 追加返工任务
     └─ 无法验证：blocked → HUMAN
```

Ralph 的 `done`、`tasks_checked_end == tasks_total` 或 exit code 0 只表示可以开始验收，不表示验收通过。

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
| 项目需求和架构 | `docs/requirements*`、`docs/architecture*` | 项目长期 | 当前任务状态 |
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
- 本地 shell/terminal：启动和控制后台 Ralph。
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
| Ralph running | Ralph/provider | 只读运行状态；不得修改同一业务文件 |
| Ralph stopped | Main Agent | 取得写入权后 Review 或修复 |
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
| 后台双写 | Main Agent 与 Ralph 覆盖彼此改动 | 单写入者状态；并行时 worktree 隔离 |
| 自报完成误判 | tasks 全勾但产物不满足需求 | 独立 Acceptance Review + 复跑验证 |
| 过程回灌污染 | provider 日志挤占 Main Agent 上下文 | 正常路径不读日志；失败最小诊断 |
| Handoff 机械提醒 | 每次压缩都直接要求切换会打断工作 | Hook 只要求评估；安全位置、上下文质量和切换收益仍需判断；真实使用出现干扰后再增加静默策略 |
| 记忆事实漂移 | handoff/checkpoint/postmortem 复制需求正文 | 唯一事实源表 + 引用而非复制 |
| Codex 能力变化 | Hook 或任务 API 变更导致流程失效 | Codex 集成层独立、fail-open、版本兼容 smoke |

## 11. Adversarial Review

### 必须修复后才能实施

- **双写保护尚未实现**：后台派发前必须定义并验证写入权协议，否则 Main Agent 可在 Ralph 运行时破坏工作区一致性。
- **验收入口缺失**：当前有 review 规则但没有明确的 Ralph 后最终产物验收 workflow；不能用 `ralph` Skill 的运行结果报告代替。
- **Hook 信任和路径尚未做真实 smoke**：文档已确认 Codex 事件契约，但项目级配置的信任提示、Git 根路径解析和 turn 中间自动压缩续跑仍需在当前 Codex/macOS 版本验证后才能进入 release。

### 可观察风险

- 每次压缩都触发评估是否过于频繁尚未通过真实长会话校准；首期先保持无计数状态机的最小实现，出现干扰后再增加静默策略。
- Ralph 后台托管方式可能受 Codex terminal/session 生命周期影响；必须验证断开、恢复和进程归属。

### 接受风险

- 首期只保证 macOS；其他平台在有真实使用需求和验证环境后扩展。
- 首期不使用 MCP、云端 Memory 或 subagent 完成核心流程，减少外部依赖和上下文回流。

## 12. 验证方向

- 临时 workspace 端到端：自然语言需求 → 方案/任务 → 后台 Ralph → 最终产物验收 → checkpoint。
- 上下文隔离：正常执行不向 Main Agent 注入完整 provider 输出；失败只返回最小诊断。
- 故障注入：Ralph `done` 但代码故意不满足 SC，Main Agent 必须输出 `rework-required`。
- 并发保护：Ralph running 时阻止或明确拒绝 Main Agent 业务写入。
- Handoff fixture：`SessionStart(source=compact)`、未信任/禁用退化、延后、授权和接手核验状态迁移。
- Postmortem 演练：重复失败能形成 prevention check 并提炼到正确载体。
- Release smoke：复制 release 到新 workspace 后完成完整协作 happy path。
