# Roadmap 写作规则

本规则指导 agent 如何创建和维护 `docs/roadmap.md`。Roadmap 用于表达阶段目标、优先级、验收口径、暂缓事项和已接受风险；它不是需求正文、方案正文，也不是当前任务事实源。

## 进入条件

- 需求澄清已经形成稳定目标，开始按阶段组织交付。
- 用户要求给出阶段计划、里程碑、优先级或暂缓事项。
- 项目方向、优先级、验收口径或阶段边界发生调整。

如果当前只有单个很小的即时任务，且没有真实阶段规划需求，可以暂时不扩写 roadmap，但 `docs/README.md` 仍要标明其状态。

## 输入依据

写 roadmap 前先读取：

- `docs/requirements.md` 和相关 `docs/requirements/<module>/requirements.md`，确认目标、非目标和成功标准。
- `docs/architecture/**`，确认长期技术结构约束；如尚未形成，则明确标为待补齐。
- `.spec/rules/solution.md` 产出的方案取舍，若存在。
- 当前任务事实源，确认当前正在推进什么，但不要直接把任务清单复制进 roadmap。
- 真实代码、脚本、仓库状态或用户确认，若项目已有实现。

不要把 agent 自己偏好的节奏、里程碑命名或实现顺序写成已确认事实。

## 写法

`docs/roadmap.md` 应聚焦：

- 当前状态：项目处于哪个阶段，哪些前提已经具备，哪些仍待确认。
- 阶段划分：按 Phase、Milestone 或版本切分交付阶段。
- 每阶段目标：该阶段要解决什么，不解决什么。
- 验收口径：如何判断阶段完成。
- 关键风险与已接受决策：哪些风险真实存在，哪些取舍已经接受。
- 暂缓事项：明确哪些内容延后，不混入当前阶段。

`docs/roadmap.md` 不得包含：

- `REQ-*`、`FR-*` 等需求正文的完整重复。
- 当前任务逐条 todo、执行日志、验证流水或完成打勾记录。
- 临时技术设计细节、表结构正文或接口字段清单。
- review / adversarial-review 报告。
- checkpoint 或 postmortem 正文。

## 推荐结构

最终产物可参考以下结构：

```md
# Roadmap

> 阶段目标、优先级、验收口径和风险。

## Current State

- <当前阶段与前提>

## Phased Delivery

| Phase | Goal | Acceptance |
|---|---|---|
| P0 | <阶段目标> | <阶段完成标准> |

## Known Risks And Decisions

- <风险或已接受决策>
```

可以增加 `Deferred`、`Open Questions`、`Dependencies` 等章节，但不要把当前任务事实源挪进来。

## 与其他事实源的边界

- 需求是什么、为什么做：写入 `docs/requirements.md` 和模块需求文档。
- 技术结构和稳定契约：写入 `docs/architecture/**`。
- 当前执行什么、验证什么：写入当前任务事实源。
- Roadmap 只负责阶段化表达“先做什么、后做什么、怎么判断一个阶段结束”。

## Phase / Iteration 完成动作（归档约定）

每个 phase / iteration 完成时（验收口径满足、当前任务源全部勾选 `[x]`）执行归档动作，把当前任务源的最终态作为不可变快照沉淀：

1. `cp <当前任务源> docs/requirements/<module>/<phase>-FINAL-TASK.md`，例如 `cp .ralph/TASKS.md docs/requirements/ralph-loop/I1-FINAL-TASK.md`
2. 清空当前任务源的“当前任务”段，准备下一个 phase / iteration（保留四段结构骨架，更新顶部声明）
3. `docs/roadmap.md` 添加完成行，引用归档文件
4. 同 commit 提交三个动作

归档文件不可变，归档后不再修改；后续如需修订相关结论，写入新 phase / iteration，不回改历史归档。

## 完成标准

- `docs/README.md` 已同步 roadmap 的状态和入口。
- 每个阶段都有目标和验收口径，不只是标题。
- 暂缓事项、已接受风险和当前阶段边界区分明确。
- 没有把任务事实源、需求正文或实现细节整段复制进 roadmap。
- 变更后的阶段划分能追溯到需求、方案或用户确认。
