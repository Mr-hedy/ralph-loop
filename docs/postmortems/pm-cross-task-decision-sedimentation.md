---
id: PM-0002
title: "跨任务稳定决策只在对话/任务文档中提及，未沉淀到稳定文档，下一轮容易偏离"
status: active
domain: process
severity: medium
affected_modules:
  - task.md
  - docs/architecture/integrations.md
  - docs/architecture/overview.md
  - docs/architecture/testing.md
  - .ralph/PROMPT.md
  - .ralph/lib/run.sh
  - .spec/rules/TASKS.md
  - templates/AGENTS.md
linked_commits:
  - pending-t2-prep-commit
  - pending-t2-prep-fixup-commit
trigger_conditions:
  - "在任务拆解或 adversarial review 阶段做出跨任务的稳定决策（命名约定、协议步骤顺序、项目契约、测试基础设施位置）"
  - "决策只写进当前会话或当前任务条目，没有同步到对应的稳定文档"
  - "或决策被沉淀但写进了错误的稳定文档（把项目事实写进 .spec/ 协作规则、或把方法论写进 docs/architecture/*）"
failure_pattern:
  - "下一个 session、下一个执行者或同 session 后续任务在实施时不读取/未关联到该决策，重新讨论或写错"
  - "对话上下文被压缩或换 session 后，决策从可用知识中消失"
  - "沉淀错位置后，方法论文档被项目事实污染，或项目契约散落难以查找"
  - "项目工作包约束被写入版本化工具协议，污染后续 oneshot 的执行入口"
prevention_checks:
  - "拆任务时，每条跨任务约定明确指明沉淀目标文档锚点；task.md 只引用文档锚点，不重复正文"
  - "adversarial review 发现的命名约定、步骤顺序、测试基础设施位置等结论必须更新到对应稳定文档后，才能视为修复完成"
  - "沉淀前先读目标文档自身的范围声明（首段 / 自述）确认归属：项目事实 → docs/architecture/*；agent 工作方法论 → .spec/rules/*"
  - "task.md 顶部规则段强制声明：跨任务稳定决策必须沉淀到 docs/architecture/*（项目事实）或 .spec/rules/*（方法论）"
  - "业务开发不得改写 Ralph 控制文件；项目长期规则进入 AGENTS，工作包约束进入 TASKS 及其事实源；scripts/check.sh 校验协议与版本指纹"
---

# 跨任务稳定决策只在对话/任务文档中提及，未沉淀到稳定文档，下一轮容易偏离

## 现象

T2 任务拆解阶段，adversarial review 发现 4 类问题，根因都是"决策曾经讨论过但未沉淀到稳定文档"：

1. **Session 文件命名约定**：integrations.md 第 257 行 Codex 用 `session.codex.stdout.jsonl`（前缀 `session.<provider>.`），但没有总览性的命名约定段。T2.1 拆解时给 Claude stdout 起名 `provider.stdout.json`，与既有约定不一致，需要 review 才发现。
2. **测试基础设施单一来源**：T2.2 与 T2.5 各自打算建一份 `setup_claude_workspace` helper，无显式规则约束，差点重复造。
3. **cwd_hash 步骤顺序**：integrations.md 已记载"先 realpath 再字符替换"，但没有强调"严格顺序"+"写反的后果"。T2.2 任务拆解未重述，实施者容易写反顺序导致 session 找不到且无错误信息。
4. **测试隔离规则**：HOME / PATH 隔离是显然的最佳实践，但项目无成文规则，T2.5 拆解到 PATH 修改用例时才意识到会破坏 harness。

类似问题在 T1 阶段也出现过雏形（多次澄清后用户提醒"应该沉淀到文档"），但当时未触发 postmortem。

5. **Meta：沉淀到错位置**（commit 后由用户指出）：上述修复 #2 一开始把"测试隔离规则"和"测试基础设施单一来源"两段写进了 `.spec/rules/testing.md`，但该文件第 60-66 行明确声明自己是协作方法论文档，输出（项目级测试规范）应去 `docs/architecture/testing.md`。我没读全目标文档自身的范围声明，导致沉淀到错位置——这正是本 PM 警告的同一根因（决策与文档归属未严格对齐）的另一种变体。已迁移到 `docs/architecture/testing.md` 并触发本 PM 增补 prevention check。

## 根因

- 拆任务和 adversarial review 阶段的对话信息密度高，结论容易停留在对话或当期 task.md，缺少把"跨任务约定"主动写到稳定文档（`docs/architecture/*` / `.spec/rules/*`）的强制环节。
- task.md 是阶段性事实源（每阶段重写），不适合承载跨阶段稳定约定；但缺少明示规则强迫拆任务时把稳定约定迁出去。
- adversarial review 找出问题后，常见反应是"在 task.md 里加一句澄清"，而不是"更新稳定文档 + task.md 引用文档锚点"。前者会随 task.md 重写而消失。
- 即便意识到要沉淀，**沉淀目标文档的归属边界**容易被忽略：`.spec/rules/*` 是 agent 工作方法论（怎么做事），`docs/architecture/*` 是本项目事实（项目契约/约定/规则）。混用会污染方法论或散落项目契约。

## 修复

- `task.md` 顶部规则段新增一条："跨任务的稳定决策（命名约定、协议步骤顺序、项目契约）必须沉淀到对应稳定文档（`docs/architecture/*` 项目事实 / `.spec/rules/*` 方法论），task.md 只引用文档锚点不重复正文。"
- `docs/architecture/integrations.md` 新增「Session 文件命名约定」段，把跨 provider 命名规则集中沉淀；T2.1 命名 `session.claude.stdout.json` 引用此段。
- `docs/architecture/testing.md` **新建**（之前是"待补齐"），承载本项目的测试入口、基础设施、隔离规则、单一来源规则、运行平台、当前覆盖范围；T2.0 / T2.2 / T2.5 引用此文档。原先误写到 `.spec/rules/testing.md` 的两段已迁出。
- T2.2 任务范围内显式重述 cwd_hash 严格步骤顺序 + 写反后果，加 PM-0002 引用作为防偏离锚点（不是因为重要而重复，而是因为偏离后果隐蔽）。

## 预防检查

- 类型：manual-check（任务拆解阶段 / adversarial review 阶段）
- 位置：每次拆任务和 review 时回答两个问题：
  - "本轮做出的哪些决策是跨任务/跨阶段稳定的？"
  - "这些决策的稳定文档锚点是什么？是否已写入？"
- 通过标准：所有跨任务约定有对应的 `docs/architecture/*` 或 `.spec/rules/*` 锚点；task.md 只引用不重复正文。
- 适用范围：所有任务拆解、adversarial review、需求澄清环节。

---

- 类型：manual-check（adversarial review 报告时）
- 位置：review 报告分类时区分"任务范围内表述"和"跨任务约定"两类问题
- 通过标准：跨任务约定类问题的修复必须包含稳定文档更新，仅 task.md 表述修正不算修完
- 适用范围：所有 adversarial review

## 知识沉淀

- 保留在本记录：根因机制（task.md 是阶段性事实源不承载稳定约定 + 沉淀目标文档归属边界易混淆）、典型表现 5 类
- 需要提炼到 skill：可考虑在 ralph 或 adversarial-review skill 加"沉淀检查"步骤；本期暂不动 skill，靠 task.md 规则段 + 本 PM 引用兜底
- 需要提炼到 `.spec/`：无（`.spec/rules/testing.md` 保持纯方法论；项目级测试规范应进 `docs/architecture/testing.md`，详见沉淀边界条款）
- 需要提炼到 `docs/`：本 PM 触发了 `docs/architecture/integrations.md` 新增 Session 文件命名约定段，并触发新建 `docs/architecture/testing.md` 承载项目级测试规范
- 需要提炼到脚本或测试：暂无（属流程类问题，不靠脚本预防）

## 后续

- T2 后续任务实施时按本规则执行：跨任务约定写到稳定文档，task.md 引用锚点。
- T3 / T4（Codex/Gemini adapter）实施时，新增的 provider 特定命名、错误诊断关键字、session 路径规则也必须沉淀到 integrations.md 对应段，不能只在 task.md 里写一次。
- 若未来 adversarial review 仍然反复发现同类问题，考虑提炼到 skill 强制执行（在 review 报告生成阶段加沉淀检查步骤）。

## 2026-10-09 增补：把工作包约束沉淀到执行协议

上述历史记录中的 `task.md` 和 `docs/architecture/*` 是当时的路径；当前任务源是 `.ralph/TASKS.md`，项目事实入口以 `docs/README.md` 为准。

现场只读检查发现，marketing-projects 的 Main Agent 为落实“不提交”“不新增表”等用户约束，多次改写 `.ralph/PROMPT.md`。主对话的文件修改记录能确认作者；并非仅凭 oneshot 日志推断。没有修改或升级现场。

直接触发是旧协议要求完成任务后提交，与用户禁止提交的授权冲突。根因是协议自身允许在两次 run 之间编辑，发布入口和协作规则又没有明确 Main Agent 的控制文件边界；runtime 每轮重新读取可变协议，缺少版本校验和变化拦截。结果是本应写入项目事实源的限制进入工具协议，后续任务可能继续使用被改写的引导。

修复把长期规则路由到 AGENTS、工作包约束路由到 TASKS 与引用事实源；协议只按授权处理提交。AGENTS 模板、TASKS 规则与 Ralph skill 明确普通 Main Agent/oneshot 不得改写工具控制文件。runtime 启动校验版本指纹，保存 run 级协议快照，并在派发及 provider 返回后检查源协议与快照，变化时停止后续派发和重试，不自动覆盖文件或回滚业务成果。该机制不是文件系统写隔离，也不保证正在执行的 oneshot 立即停止。

预防检查：

- 自动静态门：`/bin/bash scripts/check.sh` 校验 PROMPT 的 Git blob 指纹与 CLI 固定值，并完整比对当前发布包；维护协议时必须有授权且同步版本指纹。
- 人工归属检查：新增“禁止提交”“只修改某仓库”“不新增表”等约束时，确认它们写入项目/工作包事实源，并被任务引用；不得靠修改通用 PROMPT 传递。
- 行为复核门：见 `docs/testing.md` 的 REQ-054 覆盖缺口，验证启动拒绝、运行中源文件/快照变化、done 与 retry 优先级以及成果保留。本轮遵照用户要求未运行单测、集成或真实 provider；静态门不能替代这些证据。

本次把规则提炼到 `.spec/`、AGENTS 模板和 Ralph skill，把完整性检查提炼到 runtime 与 `scripts/check.sh`，不只保留在复盘正文。

0.1.8 复核补齐检查与使用之间的失败路径：读取快照用显式错误分支收尾，并校验已读入的静态输入，避免检查通过后快照消失时被 `set -e` 直接退出、留下 running 状态和锁。预防复核必须覆盖“最后一次检查后、实际读取时失败”，不能只覆盖检查前修改文件；行为验证项同步在 `docs/testing.md`，本轮未运行。
