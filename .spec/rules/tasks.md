# 任务事实源（TASKS.md）规则

本规则规范当前任务事实源（本仓库 = `.ralph/TASKS.md`，使用者 workspace = 同名）的**结构、模板、自修改规则、归档约定**。目标是让 agent 在 ralph oneshot 内能稳定按规则执行，让 reviewer 能快速读出每个任务的契约和验证状态。

## 边界

- 任务事实源是**当前迭代**的可执行任务集合 + 关键稳定结论 + 历史索引；不是 changelog、不是设计文档、不是 review findings 容器。
- 历史完成细节归档到 `docs/checkpoints/`；本文件只保留当前有效结论、历史索引和当前迭代任务。
- 模块级最终任务包归档到 `docs/requirements/<module>/I<N>-FINAL-TASK.md`（iteration 完成后由人类执行 cp 动作）。

## 文件结构（4 段）

```markdown
# Tasks

> 当前迭代: I<N>
> 主题: <一句话主题>
> 关联 roadmap: <对应 roadmap 项，可选>
> 起始: <YYYY-MM-DD>
> 设计方案: `docs/requirements/<module>/I<N>-design.md`（可选）

## 当前有效结论

- (本迭代关键决策、含 HUMAN 任务最终答案摘要)

## 历史索引

- v0.1 历史：root `task.md`（封版后）
- 需求事实源：`docs/requirements/<module>/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 子 bullet 是给 agent 读的上下文，不进 ralph 解析（只识别 `^\s*- \[([ xX])\]`）。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `→ BLOCKED by HUMAN-N` 或 `→ BLOCKED by REVIEW-N`。
- HUMAN-N 任务在 ralph oneshot 内不可勾选（人类在 Claude Code 对话里勾）。
- 不创建根 `task.md` 或其他并行任务板。
- 历史完成细节进入 checkpoint；本文件只保留当前有效结论、历史索引和当前迭代任务。

## 当前任务

(具体任务列表，按下文模板填写)
```

顶部 blockquote 声明：
- 冒号必须 ASCII `:`（不接受全角 `：`）
- "当前迭代"行被 ralph 工具解析写入 `status.json.iteration_name` / `result.json.iteration_name`

## 任务前缀（8 类）

任务标题前缀决定 agent 本轮 mindset 和参考的 `.spec/` 规范段。**ralph 工具内核不解析普通前缀**（HUMAN- 除外）；普通前缀仅作为 agent 自检入口。

| 前缀 | 执行方 | mindset | 必读 spec | 主要产出 |
|------|--------|---------|-----------|---------|
| `REQ-N` | ralph oneshot 内 agent | 需求澄清 | `.spec/rules/requirements.md` | `docs/requirements/<module>/requirements.md` |
| `SOL-N` | ralph oneshot 内 agent | 方案决策（存在真实取舍时） | `.spec/rules/solution.md` | requirements / architecture / 任务源对应章节 |
| `ROADMAP-N` | ralph oneshot 内 agent | Roadmap 阶段规划（版本切分、阶段目标、优先级、验收口径） | `.spec/rules/roadmap.md` | `docs/roadmap.md` |
| `PLAN-N` | ralph oneshot 内 agent | 任务列表规划（基于已确认 REQ/SOL/架构，产出当前迭代任务列表；与 trantor PLAN / 业界 sprint planning 同义） | `.spec/README.md` 阶段 4 + 本文件 | TASKS.md 后续追加 |
| (空) / `DEV-N` | ralph oneshot 内 agent | 开发实施（默认） | 项目入口 + 代码事实 | 代码 / 文档 / 提示词 / 论文等任何"按已确认需求/方案产出具体交付物"的工作 |
| `QA-N` | ralph oneshot 内 agent | 测试设计与实施 | `.spec/rules/testing.md` | `docs/architecture/testing.md` + 测试代码 |
| `REVIEW-N` | ralph oneshot 内 agent | 审查（见 §REVIEW-N 两种用法） | `.spec/rules/review.md` 或 `.spec/rules/adversarial-review.md` | findings / 事实源修订 |
| `HUMAN-N` | **main agent 对话内人类协作** | 必须人工介入决策；ralph oneshot 内不可执行不可勾选 | — | 答案落到对应 docs + HUMAN 任务里追加"答："摘要 + 由人类勾选 |

**强约束**（ralph 启动校验，违反则启动失败 exit 1）：

- 任务前缀**必须全大写英文 + 连字符 + 数字 + 冒号**，正则 `^[A-Z]+-[0-9]+:`
- 不允许小写、混合大小写、全角字符或省略数字（`Dev-1` / `dev-1` / `DEV1` / `DEV-` 全部启动失败）
- 没有前缀的任务（如 `- [ ] 写 hello.txt`）**视为默认 DEV**，向后兼容；不触发前缀校验

## 未完成任务模板

```markdown
- [ ] DEV-N: <一句话标题>
  - 预期：<完成后用户/系统能做到什么；面向用户价值或系统能力>
  - 输入：<触发原因 / 关联 REQ / 关联 SC / 上游任务 / 用户决策>
  - 范围：<将动到的文件 / 模块 / 配置；明确避免哪些>
  - 验证计划：<执行什么命令 / 看什么字段 / 谁验 / 通过条件>
```

四个字段是**必填**：
- **预期**：用户或系统视角的"完成后会怎样"，**不写实施细节**
- **输入**：上游依据，让 agent 知道这个任务的契约从哪里来
- **范围**：明确边界，避免范围扩张
- **验证计划**：可执行、可观察的成功判据

## 已完成任务模板（追加完成 + 验证条目）

```markdown
- [x] DEV-N: <一句话标题>
  - 预期：<同未完成模板>
  - 输入：<同未完成模板>
  - 范围：<同未完成模板>
  - 验证计划：<同未完成模板>
  - 完成：<阶段产出 1，含文件路径或 commit sha>
  - 完成：<阶段产出 2>
  - 验证：<执行的命令 + 结果，e.g. "scripts/check.sh + integration-test.sh PASS=57">
  - 未验证：<residual risk 或 None>
```

**追加规则**：
- "完成" 是过程中**逐步追加**的（不是任务结束才一次性写），形成阶段性 audit trail
- "验证" 是任务结束时一行总结，写实际跑过的命令 + 结果
- "未验证" **必填**：显式标注本任务未覆盖的 residual risk，对齐 "Evidence over confidence" 原则；无残留时写 `None`
- 已勾选 `[x]` 的任务**不再修改**预期/输入/范围/验证计划/完成 历史条目；如需更正，新建任务

## HUMAN-N 模板

ralph oneshot 内 agent 触发 HUMAN-N 阻塞时，在阻塞任务**上方**插入：

```markdown
- [ ] HUMAN-N: <一句话问题陈述>
  - 上下文：<触发任务编号 + 描述>
  - 选项：
    - 选项 A：<描述 + 影响>
    - 选项 B：<描述 + 影响>
    - ...
  - 影响：<会决定哪些 task / 文档章节>
  - 答（待）：
```

人类（在 main agent 对话里）回答后，main agent 在任务里追加：

```markdown
  - 答（YYYY-MM-DD）：<答案摘要>
  - 落地：<docs 路径 / commit sha>
```

然后改 `[x]`，commit。重跑 `ralph run`，下一轮 agent 看到 HUMAN-N 已勾，回到原阻塞任务按答案继续。

## REVIEW-N 两种用法（互斥，不可混用）

**常规审查任务**（独立的 review work item，不阻塞其他任务）：

```markdown
- [ ] REVIEW-N: <对象> | review
- [ ] REVIEW-N: <对象> | adversarial-review
```

任务描述**第一行末尾**用 `| review` 或 `| adversarial-review` 后缀明确审查模式。

**Escalation 路径 A**（DEV 等任务阻塞、需要先回炉修订需求/方案）：

```markdown
- [ ] REVIEW-N [blocked-by <被阻塞任务>]: <一句问题陈述>
```

必带 `[blocked-by <task>]` 标记，描述用一句话说清楚问题，**不带** `| review` / `| adversarial-review` 后缀。

## 自修改规则

**允许**（ralph oneshot 内 agent 操作）：

- **只追加**新任务到文件末尾
- 在阻塞任务**上方**插入 REVIEW-N（含 `[blocked-by]` escalation 用法）或 HUMAN-N 任务
- 将本轮**真正完成**的任务由 `- [ ]` 改 `- [x]`（HUMAN-N 除外）
- 给已完成任务追加 `- 完成: ...` / `- 验证: ...` / `- 未验证: ...` 条目（仅当本轮工作直接产生这些更新时）

**禁止**：

- **禁止删任务**——已写入的任务不得移除
- **禁止改写**他人/上轮已读的任务文本（含已勾选任务的预期/输入/范围/验证计划字段）
- **禁止 fake-mark**——未真正完成的任务绝对不标 `[x]`
- **禁止勾选 HUMAN-N**——见上文强约束（ralph oneshot 内）
- **禁止违反前缀全大写约束**——启动校验会拦住，但你写新任务时也要遵守

## 归档约定（iteration 完成时）

iteration 完成（`ralph run` 退出 `exit_reason=done` + 所有任务 `[x]`）：

```bash
cp .ralph/TASKS.md docs/requirements/<module>/I<N>-FINAL-TASK.md
# 清空 .ralph/TASKS.md 当前任务段，"当前迭代"改为下一个 iteration
git commit
```

归档原则：
- 归档物 = `.ralph/TASKS.md` 本身（含所有 `[x]` 状态、预期/输入/范围/验证计划/完成/验证/未验证 全字段、HUMAN 任务最终答案、决策记录），自包含
- I<N>-FINAL-TASK.md **不可变**，归档后不再修改
- roadmap.md 添加完成行 + 引用归档文件

## 与 .ralph/PROMPT.md 的边界

- 本文件（`.spec/rules/tasks.md`）规定 **TASKS.md 的结构和格式契约**——是 spec 层
- `.ralph/PROMPT.md` 规定 **agent 在 oneshot 内的执行协议**——是 runtime 层
- 重复内容（如自修改规则、HUMAN-N 触发条件、REVIEW-N 两种用法）以本文件为准；PROMPT.md 路由到本文件，不重复完整描述

## 验证

本规则为 spec 文档。检查命令：

- `bash scripts/check.sh`（验证 .spec/ 边界 + 文档结构）
- `bash scripts/integration-test.sh`（验证启动校验前缀全大写规则触发）
