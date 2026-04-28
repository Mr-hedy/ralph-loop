---
id: PM-0003
title: "任务收口 adversarial review 缺乏 REQ traceability + 现实条件外推，导致 P0 缺陷漏到下阶段"
status: active
domain: "process / verification"
severity: "high"
affected_modules:
  - ".ralph/lib/run.sh"
  - ".ralph/lib/adapter-claude.sh"
  - "scripts/integration-test.sh"
  - "task.md (任务收口流程)"
linked_commits:
  - "0cd99ab T2 done (T2 漏检的 commit)"
  - "pending T6 prep commit (本 PM 与 T6 prep 同包提交)"
trigger_conditions:
  - "任务收口 adversarial review 只检查'本任务实现 vs 任务范围'，不重新跑 P0/P1 REQ → 实现 traceability"
  - "测试覆盖完全建立在 fake / mock 条件下，未对'mock 假设是否成立于真实长链路'做显式声明"
  - "REQ 文本含'单元测试'/'集成测试'级别的 SC 但任务拆分时未显式排进子任务"
failure_pattern:
  - "fake/mock 路径通过 → 误判'内核能力已验证'，但 fake 隐含的简化条件（如 stagnation 场景从第 1 轮就不动）让真实长链路下才会暴露的 bug 永久潜伏"
  - "REQ 在 requirements.md 列出且有 SC 验收条目，但任务拆分时未显式列子任务 → adversarial review 只看任务范围内的实现 → SC 永远不被验证"
prevention_checks:
  - "任务收口 adversarial review 必须包含 'REQ traceability rerun' 步骤：对该任务声明覆盖的每条 P0/P1 REQ，grep 实现代码确认接入；grep 集成测试确认 SC-NNN-N 有对应用例；对照 SC 文本和实际用例断言是否一致"
  - "任务范围段必须显式列出'本任务覆盖的 SC-NNN-N 清单'；任务收口检查清单与之机械对账"
  - "fake/mock 测试用例必须在测试文件或 fixture 注释中标注'此场景隐含假设：<X>；真实长链路触发条件需在 T_real_smoke 阶段 cover'"
---

# 任务收口 adversarial review 缺乏 REQ traceability + 现实条件外推，导致 P0 缺陷漏到下阶段

## 现象

T2（Claude adapter）于 commit `0cd99ab` 收口，handoff 与 checkpoint 均声明 PASS=34、adversarial review 已修 8 项、"无新的可复用失败模式"。T6（v0.1 闭环）入场前重新做 adversarial review，发现 T2 漏检两个 P0 级缺陷：

1. **stagnation cumulative bug**：`run.sh:386` 用 `ralph_changed_files "$start_sha"` 是 run 起点 cumulative diff，第一轮一改文件后 cumulative 永远非空，stagnation_count 永远不再 ++，stagnation 在长链路里事实上失效。T1 fake adapter 的 `stagnation` 场景测试通过是因为 fake 从第 1 轮就不动文件，cumulative 一直空，掩盖了真实条件下的失败。
2. **`--effort` flag 完全未接入 Claude adapter**：`grep effort .ralph/lib/adapter-claude.sh` 空。REQ-014（P1）+ SC-014-1（"`--effort=low|medium|high` 翻译为各 provider 原生参数；`none` 或留空不传"）+ requirements §integrations Claude 节明文翻译为 `--thinking-budget`，但 adapter 完全没读 `$RALPH_EFFORT`，effort 被 run.sh 写进 context.json 后丢失。

两个 bug 都不是"实现错"——是"实现根本没写却被认为已写"。T2 收口的 adversarial review 没有发现。

## 根因

T2 任务收口 adversarial review 只看了"本轮 8 项修复实现层 bug"是否清账，没做两个关键检查：

1. **REQ traceability rerun**：T2 声明覆盖 REQ-001~REQ-016 中的 Claude adapter 相关项，但没有机械对照"每条 P0/P1 REQ 是否在 adapter / run.sh / 测试三方都接入"。REQ-014（effort 抽象）的接入完全跳过了 Claude adapter 这一层，且 SC-014-1 的"单元测试"在集成测试中找不到对应用例，但 adversarial review 没 grep / 没对账。
2. **现实条件外推不足**：T1 fake adapter 的 stagnation 场景从设计起就是"第 1 轮即停，cumulative 一直空"——这个简化让 stagnation 检测的 cumulative-vs-per-iter 语义差异**永远不会在 fake 测试下暴露**。T2 复用了 T1 的 stagnation 测试用例并 PASS，没有人在收口时问"fake 路径通过是否意味着真实长链路也通过"，导致问题潜伏到 T6 真实多轮 smoke 设计阶段才被识别。

更本质的问题：**任务收口 adversarial review 把"覆盖率" mistakenly 等同于"集成测试用例数 / fake smoke pass"**，缺了**REQ → 实现 → 测试**的三方对账，也缺了**mock 假设的现实条件外推**这一层显式提醒。

## 修复

- 短期：T6.1（修 stagnation per-iter 语义 + 加 `partial_progress` mock 场景）+ T6.2（接入 effort + 加 SC-014-1 unit test）—— 两个 P0 缺陷在 T6 内独立修复，不挂 T6.7 patch 池（独立子任务保留可见性）。
- 中期：本 PM 沉淀流程预防机制（见预防检查段）；后续任务收口 checklist 必须含"REQ traceability rerun + mock 假设外推"两步。
- 不修：T2 done checkpoint（`docs/checkpoints/2026-04-28-01-t2-done.md`）保留原状作为历史快照，本 PM 反过来引用作为"历史漏检证据"。

## 预防检查

- 类型：`manual-check`（在 task.md / checkpoint 流程层落地）
- 位置：
  - `task.md` 当前阶段段头：必须显式列"本阶段覆盖的 SC-NNN-N 清单"。
  - 任务收口 checkpoint note 的 `# 验证结果` 段：必须按"SC-NNN-N → 集成测试用例名 → PASS"格式机械对账。
  - mock fixture（如 `tests/fixtures/mock-claude`）顶部注释：每个场景需注"此场景隐含的简化假设；真实条件验证延期到 T_real_smoke"。
- 通过标准：
  - 任务声明覆盖的每条 P0/P1 REQ 在 adversarial review 时被 `grep <REQ key> .ralph/lib/ scripts/` 至少命中实现 + 测试两处。
  - 每条 SC-NNN-N 在集成测试中能定位到对应断言行。
  - mock 场景的简化假设外推条件被显式列入"未验证范围"段。
- 失败标准：以上任一条件不成立时不允许打 task `[x]`、不允许 checkpoint 写"无新失败模式"。
- 适用范围：所有任务收口（T1/T2/T3/...），所有 mock/fake 路径覆盖的 P0/P1 REQ，所有跨 fake → real 转场（如 T2.6/T6 的真实 CLI smoke）。

## 知识沉淀

- 保留在本记录：T2 漏检证据（具体两个 bug 的 git anchor + 检测命令）。
- 需要提炼到 skill：**有**——`.agents/skills/checkpoint/SKILL.md` 应增加一条 "task closure 必须做 REQ traceability rerun，证据贴 checkpoint 验证段"。本轮先记 PM-0003，后续视用户裁决是否更新 SKILL.md。
- 需要提炼到 `.spec/`：**可能有**——任务收口质量门 / adversarial review checklist 在 `.spec/` 下若有专题，应纳入此预防检查；本 PM 暂不主动改 `.spec/`，待项目梳理 `.spec/` 时一并处理。
- 需要提炼到 `docs/`：无（本 PM 与 T6.1/T6.2 task 描述已自洽，不需要扩散）。
- 需要提炼到脚本或测试：长期可考虑在 `scripts/check.sh` 增加"REQ→实现 grep 对账"轻量校验（每条 P0/P1 REQ 至少在某 lib 文件 grep 命中），但需先稳定 REQ 命名约定再实施。

## 后续

- T6.1 / T6.2 完成后回查本 PM，验证修复确实让"真实长链路 stagnation 触发 + effort 接入"通过。
- 后续任务（T3 Codex / T4 Gemini）收口前必须显式跑 REQ traceability rerun，证据贴 checkpoint。
- `.agents/skills/checkpoint/SKILL.md` 是否纳入此预防检查，待用户裁决（不在 T6 范围）。
