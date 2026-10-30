# `.spec/` 协作规范入口

`.spec/` 只放当前项目的规范、指导和约束文档。它不是运行产物目录，也不是项目事实文档。

`.spec/README.md` 是入口例外；`.spec/rules/` 及其 `templates/` 下的规则和模板文件统一使用大写文件名。

## 边界

| 位置 | 职责 |
|---|---|
| `README.md` | 项目自行维护的产品/工程说明（不替代 `docs/README.md`） |
| `.spec/` | 协作模型、事实源边界、文档结构和模板；可规定动作触发条件、约束、目标与验收标准。具体状态迁移步骤由项目 workflow 承载；项目尚未声明 workflow 时，TASKS 规则中的最小手动归档 fallback 是明确例外 |
| `.spec/rules/templates/` | 与规则配套的可复制模板 |
| 当前任务事实源 | 由项目入口声明；必须唯一，不在 `.spec/` 中绑定具体路径 |
| 运行证据 | 由项目入口声明；不得替代任务完成事实 |
| 动作 workflow | 由项目入口声明；承载 checkpoint、handoff、postmortem、任务执行等有状态动作的具体执行步骤 |
| `docs/` | 项目事实、专题设计和运行过程文档，包括 `docs/troubleshooting/`、`docs/checkpoints/`、`docs/postmortems/` |

## 协作流程

从本文件确认当前协作阶段。不要从宽泛想法直接跳到任务执行，除非前置阶段已经由当前上下文或现有文档满足。

| 阶段 | 目标 | 先读 | 最终产物 |
|---|---|---|---|
| 1. 项目入口 | 让项目已有的 agent 入口和 `docs/README.md` 成为项目与文档地图 | `.spec/rules/DOCS.md` | 项目入口文件 + `docs/README.md` |
| 2. 需求澄清 | 引导用户澄清目标、边界、受众、成功标准和约束；必要时沉淀 `REQ -> SC -> BPF -> FR/NFR/TC` 追溯链 | `.spec/rules/REQUIREMENTS.md` | `docs/features/<feature>/requirements.md` |
| 3. 方案决策 | 仅在存在真实方案取舍时比较方案、边界、风险和代价 | `.spec/rules/SOLUTION.md` | 对应 feature、专题架构或当前任务事实源章节 |
| 4. 实施任务 | 用户决定生成任务清单后，把已确认的需求、架构和方案决策转成可执行、可验证、decision complete 的任务 | 项目声明的任务协议 | 当前任务事实源 |
| 5. 验证设计 | 明确测试规范、命令、人工检查和未覆盖风险 | `.spec/rules/TESTING.md` | feature `testing.md` 或按需创建的 `docs/testing.md` |
| 6. Review | agent 检查自己本次交付物的质量；整轮 Ralph 产物按已授权工作流或用户验收诉求审查 | `.spec/rules/REVIEW.md` | 对话 findings、事实源修订；已有授权范围内的返工任务 |
| 7. Adversarial Review | 主动寻找矛盾、遗漏、过度设计和不可验证点；在方案取舍和稳定合约变更时自动触发 | `.spec/rules/ADVERSARIAL-REVIEW.md` | 对话风险清单、事实源修订；已有授权范围内的返工任务 |
| 8. 任务执行 | 用户决定生成任务清单并授权执行后，按唯一任务事实源开展工作；按项目入口约定托管、调整和复审 | 项目声明的动作 workflow；使用 Ralph 时按需读取选定模式 | 当前任务事实源 |

## 快速路由

| 场景 | 先读 |
|---|---|
| 写或更新项目过程文档 | `.spec/rules/DOCS.md`；完成后同步项目的 `docs/README.md` |
| 做需求澄清或写需求 | `.spec/rules/REQUIREMENTS.md` |
| 存在多个真实方案取舍 | `.spec/rules/SOLUTION.md` |
| 写或更新架构文档 | `.spec/rules/ARCHITECTURE.md` |
| 拆解实施任务 | 项目声明的任务协议和当前任务事实源 |
| 制定验证策略 | `.spec/rules/TESTING.md` |
| Review / 检查 | `.spec/rules/REVIEW.md` |
| 反向审查 / 挑战方案 | `.spec/rules/ADVERSARIAL-REVIEW.md` |
| 业务系统排查 | `.spec/rules/TROUBLESHOOTING.md`；完成后写入 `docs/troubleshooting/<slug>.md` |
| 失败、回归、重复错误或校验异常 | 项目已有 `docs/postmortems/README.md` 时先读并检索，再按已声明的 postmortem 动作流程判断是否记录；尚未建立入口时先按项目事实定位，业务系统 RCA 走 `TROUBLESHOOTING.md` |
| 创建 checkpoint | 项目声明的 checkpoint 动作流程，并先执行 postmortem sweep |
| 记录失败模式 | 项目声明的 postmortem 动作流程 |

## 任务类型路由

| 前缀 | 工作类型 | 必读规范 |
|---|---|---|
| `REQ-N` | 需求澄清 | `.spec/rules/REQUIREMENTS.md` |
| `SOL-N` | 方案决策 | `.spec/rules/SOLUTION.md` |
| `ROADMAP-N` | 阶段规划 | `.spec/rules/ROADMAP.md` |
| `PLAN-N` | 任务规划 | `.spec/rules/TASKS.md` |
| `QA-N` | 测试设计与实施 | `.spec/rules/TESTING.md` |
| `REVIEW-N` | 常规审查 | `.spec/rules/REVIEW.md` |
| `DEV-N` | 开发实施 | 项目级 `AGENTS.md`、代码事实和任务引用规范 |
| `HUMAN-N` | 人工决策与协作 | `.spec/rules/TASKS.md` |

涉及权限、持久化、公开契约、generated output、release 或事实源路由的变更，额外阅读 `.spec/rules/ADVERSARIAL-REVIEW.md`。

## 规则

- `.spec/` 定义协作规则、事实源边界、文档结构、动作触发条件与产物契约、流程质量门和模板；带文件变更或状态迁移的具体执行步骤由项目声明的 workflow 承载。项目尚未声明 workflow 时，仅按 `.spec/rules/TASKS.md` 的手动归档 fallback 执行归档，不把该 fallback 扩展成其他动作的通用 workflow。
- 当前任务事实源必须唯一；不要创建根 `task.md` 或其他并行任务板。
- 版本化执行工具的控制文件与项目事实分离。普通开发不得由 Main Agent 或任务执行者自行改写控制协议来传递用户约束；长期项目规则进入项目 agent 入口，工作包约束进入任务源与对应事实源。维护或升级执行工具须明确授权，并在停止运行后进行。
- Checkpoint、handoff 和任务执行的触发条件、约束及产物契约可由 `.spec/` 定义；具体执行步骤由项目声明的动作 workflow 承载。TASKS 归档在缺少 workflow 时遵循其明确的手动 fallback。
- Review 和 adversarial review 是 agent 对本次工作执行的流程质量门，默认不产出独立文档；整轮 Ralph 产物的验收依据已授权工作流或用户验收诉求。项目入口已明确完整执行包含独立复审时，无需再次索取同范围授权；仅查状态等较窄请求不扩展，Ralph 终态本身不代表验收通过。
- Postmortem 是带运行过程产物的动作，执行协议由项目声明的 postmortem 动作流程承载。
- 失败处理是流程质量门：项目已有 `docs/postmortems/README.md` 时，先读并搜索相关条目；若尚未建立该入口，先按项目事实定位失败。问题属于重复、系统性、回归或预防机制失效且需要持久化时，使用项目声明的 postmortem 动作流程；项目尚未声明流程时，先建立并索引项目的 postmortem 入口，不把未创建的文件当作可读事实源。
- 创建 checkpoint 前必须执行 postmortem sweep；只有发现值得沉淀的失败模式时才创建或更新 postmortem，并在 checkpoint note 里记录 sweep 结果。
- Checkpoint 和 postmortem 是运行过程文档，分别放 `docs/checkpoints/` 和 `docs/postmortems/`；它们不是需求、架构或当前任务事实源。
- `docs/` 以 `docs/README.md` 为地图；功能文档按 `docs/features/<feature>/` 聚合，项目级专题文档按需直接放在 `docs/` 根部，运行过程文档使用 `docs/checkpoints/`、`docs/postmortems/` 和 `docs/troubleshooting/`。
- 不默认创建项目级 requirements、architecture 或 testing 文件；只有存在跨功能稳定事实时才创建对应的根级专题文档。
- 规格采用 Spec-anchored-lite：规格进入版本控制并持续演进，但代码不要求完全由规格生成。
