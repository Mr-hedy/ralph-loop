# `.spec/` 协作规范入口

`.spec/` 只放当前项目的规范、指导和约束文档。它不是运行产物目录，也不是项目事实文档。

## 边界

| 位置 | 职责 |
|---|---|
| `README.md` | 当前工程总入口和渐进式披露导航 |
| `.spec/` | 协作模型、事实源边界、文档结构和模板；不规定具体执行 workflow |
| `.spec/rules/templates/` | 与规则配套的可复制模板 |
| 当前任务事实源 | 由项目入口声明；必须唯一，不在 `.spec/` 中绑定具体路径 |
| 运行证据 | 由项目入口声明；不得替代任务完成事实 |
| 动作 workflow | 由项目入口声明；承载 checkpoint、handoff、postmortem、任务执行等有状态动作 |
| `docs/` | 项目事实、专题设计和运行过程文档，包括 `docs/checkpoints/`、`docs/postmortems/` |

## 协作流程

从本文件确认当前协作阶段。不要从宽泛想法直接跳到任务执行，除非前置阶段已经由当前上下文或现有文档满足。

| 阶段 | 目标 | 先读 | 最终产物 |
|---|---|---|---|
| 1. 项目入口 | 让 README 成为人和 agent 的项目地图 | `.spec/rules/readme.md` | `README.md` |
| 2. 需求澄清 | 引导用户澄清目标、边界、受众、成功标准和约束；必要时沉淀 `REQ -> SC -> BPF -> FR/NFR/TC` 追溯链 | `.spec/rules/requirements.md` | `docs/requirements.md` 和 `docs/requirements/<module>/` |
| 3. 方案决策 | 仅在存在真实方案取舍时比较方案、边界、风险和代价 | `.spec/rules/solution.md` | 对应需求、架构或当前任务事实源章节 |
| 4. 实施任务 | 把已确认的需求、架构和方案决策转成可执行、可验证、decision complete 的任务 | 项目声明的任务协议 | 当前任务事实源 |
| 5. 验证设计 | 明确测试规范、命令、人工检查和未覆盖风险 | `.spec/rules/testing.md` | `docs/architecture/testing.md` |
| 6. Review | 检查需求、方案、计划、验证和任务是否一致；在阶段交接和实施完成前自动触发 | `.spec/rules/review.md` | 对话 findings、事实源修订或当前任务事实源后续项 |
| 7. Adversarial Review | 主动寻找矛盾、遗漏、过度设计和不可验证点；在方案取舍和稳定合约变更时自动触发 | `.spec/rules/adversarial-review.md` | 对话风险清单、事实源修订或当前任务事实源后续项 |
| 8. 任务执行 | 把已确认范围拆入唯一任务事实源并执行 | 项目声明的动作 workflow | 当前任务事实源 |

## 快速路由

| 场景 | 先读 |
|---|---|
| 写或更新根 `README.md` | `.spec/rules/readme.md` |
| 做需求澄清或写需求 | `.spec/rules/requirements.md` |
| 存在多个真实方案取舍 | `.spec/rules/solution.md` |
| 写或更新架构文档 | `.spec/rules/architecture.md` |
| 拆解实施任务 | 项目声明的任务协议和当前任务事实源 |
| 制定验证策略 | `.spec/rules/testing.md` |
| Review / 检查 | `.spec/rules/review.md` |
| 反向审查 / 挑战方案 | `.spec/rules/adversarial-review.md` |
| 失败、回归、重复错误或校验异常 | 先读 `docs/postmortems/README.md`，再按项目声明的 postmortem 动作流程判断是否记录 |
| 创建 checkpoint | 项目声明的 checkpoint 动作流程，并先执行 postmortem sweep |
| 记录失败模式 | 项目声明的 postmortem 动作流程 |

## 规则

- `.spec/` 只放协作模型、事实源边界、文档结构、非动作方法、流程质量门和模板；带明确运行产物或状态迁移的动作由项目声明的 workflow 承载。
- 当前任务事实源必须唯一；不要创建根 `task.md` 或其他并行任务板。
- Checkpoint、handoff 和任务执行的具体协议由项目声明的动作 workflow 承载。
- Review 和 adversarial review 是流程质量门，默认不产出独立文档；用户显式要求检查或挑刺时也按对应规则执行。
- Postmortem 是带运行过程产物的动作，执行协议由项目声明的 postmortem 动作流程承载。
- 失败处理是流程质量门：发生失败、回归、重复错误、校验异常或预防机制失效时，先读 `docs/postmortems/README.md` 并搜索相关条目；若没有现有条目且问题属于重复、系统性、回归或预防机制失效，则触发项目声明的 postmortem 动作流程。
- 创建 checkpoint 前必须执行 postmortem sweep；只有发现值得沉淀的失败模式时才创建或更新 postmortem，并在 checkpoint note 里记录 sweep 结果。
- Checkpoint 和 postmortem 是运行过程文档，分别放 `docs/checkpoints/` 和 `docs/postmortems/`；它们不是需求、架构或当前任务事实源。
- `docs/` 使用固定结构：`docs/README.md`、`docs/requirements.md`、`docs/requirements/<module>/`、`docs/architecture/`、`docs/checkpoints/`、`docs/postmortems/` 和 `docs/roadmap.md`。
- 不默认维护 `docs/design.md`、`docs/testing.md`、`docs/implementation.md` 或 `docs/decisions/`；对应事实分别落入 requirements、architecture 或当前任务事实源。
- 规格采用 Spec-anchored-lite：规格进入版本控制并持续演进，但代码不要求完全由规格生成。
