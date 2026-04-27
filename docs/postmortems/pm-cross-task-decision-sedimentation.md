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
  - .spec/rules/testing.md
linked_commits:
  - pending-t2-prep-commit
trigger_conditions:
  - "在任务拆解或 adversarial review 阶段做出跨任务的稳定决策（命名约定、协议步骤顺序、协作规则、测试基础设施位置）"
  - "决策只写进当前会话或当前任务条目，没有同步到对应的稳定文档（docs/architecture/* 或 .spec/rules/*）"
failure_pattern:
  - "下一个 session、下一个执行者或同 session 后续任务在实施时不读取/未关联到该决策，重新讨论或写错"
  - "对话上下文被压缩或换 session 后，决策从可用知识中消失"
prevention_checks:
  - "拆任务时，每条跨任务约定明确指明沉淀目标文档锚点；task.md 只引用文档锚点，不重复正文"
  - "adversarial review 发现的命名约定、步骤顺序、测试基础设施位置等结论必须更新到对应稳定文档后，才能视为修复完成"
  - "task.md 顶部规则段强制声明：跨任务稳定决策必须沉淀到 docs/architecture/* 或 .spec/rules/*"
---

# 跨任务稳定决策只在对话/任务文档中提及，未沉淀到稳定文档，下一轮容易偏离

## 现象

T2 任务拆解阶段，adversarial review 发现 4 类问题，根因都是"决策曾经讨论过但未沉淀到稳定文档"：

1. **Session 文件命名约定**：integrations.md 第 257 行 Codex 用 `session.codex.stdout.jsonl`（前缀 `session.<provider>.`），但没有总览性的命名约定段。T2.1 拆解时给 Claude stdout 起名 `provider.stdout.json`，与既有约定不一致，需要 review 才发现。
2. **测试基础设施单一来源**：T2.2 与 T2.5 各自打算建一份 `setup_claude_workspace` helper，无显式规则约束，差点重复造。
3. **cwd_hash 步骤顺序**：integrations.md 已记载"先 realpath 再字符替换"，但没有强调"严格顺序"+"写反的后果"。T2.2 任务拆解未重述，实施者容易写反顺序导致 session 找不到且无错误信息。
4. **测试隔离规则**：HOME / PATH 隔离是显然的最佳实践，但项目无成文规则，T2.5 拆解到 PATH 修改用例时才意识到会破坏 harness。

类似问题在 T1 阶段也出现过雏形（多次澄清后用户提醒"应该沉淀到文档"），但当时未触发 postmortem。

## 根因

- 拆任务和 adversarial review 阶段的对话信息密度高，结论容易停留在对话或当期 task.md，缺少把"跨任务约定"主动写到稳定文档（`docs/architecture/*` / `.spec/rules/*`）的强制环节。
- task.md 是阶段性事实源（每阶段重写），不适合承载跨阶段稳定约定；但缺少明示规则强迫拆任务时把稳定约定迁出去。
- adversarial review 找出问题后，常见反应是"在 task.md 里加一句澄清"，而不是"更新稳定文档 + task.md 引用文档锚点"。前者会随 task.md 重写而消失。

## 修复

- `task.md` 顶部规则段新增一条："跨任务的稳定决策（命名约定、协议步骤顺序、协作规则）必须沉淀到对应稳定文档（`docs/architecture/*` / `.spec/rules/*`），task.md 只引用文档锚点不重复正文。"
- `docs/architecture/integrations.md` 新增「Session 文件命名约定」段，把跨 provider 命名规则集中沉淀；T2.1 命名 `session.claude.stdout.json` 引用此段。
- `.spec/rules/testing.md` 新增「测试隔离规则」段（HOME / PATH / 配置 / 网络隔离 + 自检要求）和「测试基础设施单一来源」段；T2.0 / T2.2 / T2.5 引用这两段。
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

- 保留在本记录：根因机制（task.md 是阶段性事实源不承载稳定约定）、典型表现 4 类
- 需要提炼到 skill：可考虑在 task-loop 或 adversarial-review skill 加"沉淀检查"步骤；本期暂不动 skill，靠 task.md 规则段 + 本 PM 引用兜底
- 需要提炼到 `.spec/`：本 PM 触发了 `.spec/rules/testing.md` 新增两段；其他 `.spec/rules/*` 文件后续按需补
- 需要提炼到 `docs/`：本 PM 触发了 `docs/architecture/integrations.md` 新增 Session 文件命名约定段
- 需要提炼到脚本或测试：暂无（属流程类问题，不靠脚本预防）

## 后续

- T2 后续任务实施时按本规则执行：跨任务约定写到稳定文档，task.md 引用锚点。
- T3 / T4（Codex/Gemini adapter）实施时，新增的 provider 特定命名、错误诊断关键字、session 路径规则也必须沉淀到 integrations.md 对应段，不能只在 task.md 里写一次。
- 若未来 adversarial review 仍然反复发现同类问题，考虑提炼到 skill 强制执行（在 review 报告生成阶段加沉淀检查步骤）。
