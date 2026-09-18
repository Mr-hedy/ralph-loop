# 当前目标与约束

- 当前目标：在已明确的 Codex Main Agent + Ralph 后台执行协作模型上，完成需求和技术架构确认后，再拆解实施任务。
- 硬约束：`.spec/` 是自然语言协作 harness，不是动作 Skill；Ralph 只负责 provider oneshot 执行，不参与 Main Agent handoff 判断；Main Agent 验收最终代码、测试、文档和 Git 状态，不消费 Ralph 正常执行过程。
- 本轮边界：只完成需求、技术架构、事实源同步和交接；尚未修改动作 Skills、Codex Hook、Ralph runtime、release 构建或任务清单。

# 当前阶段与范围

- 阶段：Vibecoding collaboration 需求已确认，技术架构为草案，等待用户审阅后进入任务拆解。
- 影响模块：项目级需求、Vibecoding collaboration 模块需求、总体架构、专题架构、测试基线、文档地图、根 README、AGENTS 入口和 Ralph release 契约。
- 变更类型：需求、架构、文档、事实源和 release 目标契约；无运行时代码变更。

# 稳定决策

- Codex Main Agent 是协作控制面，负责需求澄清、方案设计、任务拆解、用户授权后的执行派发和最终产物验收。
- Ralph 是独立后台执行面。Main Agent 不读取正常 provider 过程会话，也不以 Ralph `done`、退出码或任务勾选证明需求完成。
- Main Agent 与 Ralph 通过已确认任务和最终 repository 状态交付，不通过模型总结交付。
- 同一 checkout 默认单写入者：Ralph running 时 Main Agent 不修改业务文件；并行写入必须使用隔离 worktree。
- `.spec/` 持续约束日常自然语言协作；`.agents/skills/` 只承载 `ralph`、`handoff`、`checkpoint`、`postmortem` 这类有动作或状态迁移的 workflow。
- Handoff 只治理 Main Agent 长上下文，不读取 Ralph round、stall、status 或 provider session。
- Codex 原生 Hooks 支持 `PreCompact`、`PostCompact` 和 `SessionStart(source=compact)`；外部参考项目中依赖 `msvcrt` 的 Python handler 才是 Windows 定向实现，二者不能混同。
- 首期 handoff 方案选定项目级 `SessionStart(source=compact)` Hook + macOS shell handler。Hook 只注入评估提醒，不写 `handoff.md`、不创建新会话；保存或完整交接必须由用户授权。
- Checkpoint 是经过验收、可回退的 Git 稳定锚点；普通执行 commit 不自动成为 checkpoint。
- Postmortem 记录重复、系统性、回归或 prevention 失效问题，并把可执行预防规则提炼到 AGENTS、`.spec/`、Skill、脚本或测试。
- Release 目标组成扩展为 `.ralph/`、`.spec/`、`.agents/skills/`、必要的 `.codex/` 会话治理配置和 agent 入口；当前 v0.1.1 release 尚未实现该目标结构。

# 已完成工作

- 新增 `docs/requirements/vibecoding-collaboration/requirements.md`，定义 REQ-033 ~ REQ-047、成功标准、业务流程、功能/非功能需求、技术约束和追踪矩阵。
- 新增 `docs/architecture/vibecoding-collaboration.md`，定义双平面模型、repository 交付接口、Task Readiness Gate、后台派发、最终验收、返工、handoff/checkpoint/postmortem 边界、单写入者模型和 release 目标结构。
- 更新 `docs/requirements.md` 和 `docs/architecture/overview.md`，把项目定位从单一 CLI harness 扩展为 Codex Main Agent vibecoding 协作脚手架，Ralph 作为后台执行引擎。
- 更新 Ralph 模块 REQ-017 和新增 SC-017-2，消除旧 release 组成与 REQ-046 的稳定契约冲突。
- 更新 `README.md`、`AGENTS.md`、`docs/README.md` 和 `docs/architecture/testing.md`，同步入口、文档地图、当前/目标 release 区分和 PASS=156 测试基线。
- 使用官方 Codex 文档核实 Hooks 的 compaction 生命周期事件、项目级配置、信任机制和 compact 后上下文注入行为。

# 最新验证

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：输出 `ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过，`PASS=156 FAIL=0`
- 诊断：完整 Ralph 回归门通过；本轮没有运行时代码变更。

- 命令：Codex Hooks 官方文档核对
- 结果：通过
- 诊断：确认 `SessionStart(source=compact)` 在根会话手动或自动压缩后触发，并可向压缩后的即时续跑注入 developer context；项目 Hook 需要用户审查和信任。

# 已验证与未验证

- 已验证：需求编号与追踪结构、项目事实源同步、现有 Ralph 完整回归、Codex Hook 官方事件契约、Windows handler 与 Codex Hook 的概念边界。
- 未验证：项目级 `.codex/hooks.json` 的真实信任流程、Git 根路径解析、turn 中途自动压缩续跑；Main Agent 后台托管 Ralph 的具体机制；每次压缩触发评估是否需要静默策略；完整 release 部署 smoke。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无。本次用户要求普通 Git 提交，没有创建 checkpoint note；该 commit 不自动声明为稳定 checkpoint。
- Postmortem：本轮未新增或更新。收尾诊断命令曾因 zsh 特殊变量 `path` 覆盖 `PATH` 而失败，已改用 `doc_file` 重跑通过；该问题未进入项目代码，未达到新增 postmortem 的价值阈值。已查阅现有 PM-0001（macOS shell 兼容）。

# 工作区状态

- 分支：`main`。
- 提交前 dirty 范围：`AGENTS.md`、`README.md`、`handoff.md`、`docs/README.md`、`docs/requirements.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/requirements/vibecoding-collaboration/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/testing.md`、`docs/architecture/vibecoding-collaboration.md`。
- 本 handoff 与上述相干文档计划在同一个普通 commit 中提交；接手时以 `git log -1` 和 `git status --short` 的实际结果为准。
- 外部参考 `/Users/wacai/Downloads/Table-skills-main` 仅作为研究材料，不是源码、运行依赖或事实源。

# 建议下一步

- 用户先审阅 Vibecoding collaboration 需求与架构，重点确认后台 Ralph 托管方式和 handoff 提醒频率边界。
- 确认后按 `.spec/rules/tasks.md` 把实施拆入唯一任务事实源 `.ralph/TASKS.md`，不要创建新的任务板。
- 实施优先顺序建议：真实 Hook smoke → 后台派发与单写入者协议 → 最终产物验收 workflow → handoff/checkpoint/postmortem 协同 → release 构建与临时 workspace smoke。

# 交接摘要

- 当前已经完成“Codex Main Agent 控制面 + Ralph 黑盒执行面”的需求和架构定义；下一位 Agent 不应重新把 `.spec/` 设计成 Skill，也不应把 Ralph 运行过程或进度信号接入 Main Agent handoff。
