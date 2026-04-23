# README 写作规则

根 `README.md` 是项目入口。它负责提供项目定位、当前状态、渐进式披露地图和 `docs/` 文档索引，不承载详细需求、方案、任务执行或运行记录。

## 读取方法

阅读 README 时按以下顺序吸收信息：

1. 先确认项目定位、非目标和当前阶段。
2. 再看入口地图，决定下一步应该读协作规范、当前任务事实源、动作 workflow 还是 `docs/`。
3. 如果要理解项目事实，读取 README 的 `docs/` 文档索引，而不是猜测文档位置。
4. 如果 README 的文档索引和实际文件不一致，先报告差异，再在当前范围内同步。
5. 如果 README 写着“待补齐”，不要把占位内容当成已确认事实。
6. 只继续读取当前任务需要的下游文档，避免把整个仓库当成上下文一次性塞入。

## 澄清方法

写或更新 README 前，先向用户或现有项目事实澄清：

- 项目定位：这个项目解决什么问题，不解决什么问题。
- 目标用户：谁会使用、维护或评审这个项目。
- 当前阶段：探索、设计、实现、维护还是迁移。
- 入口路径：用户、维护者和自动化执行者分别应该从哪里开始。
- 文档地图：`docs/README.md`、全局需求澄清、模块需求、业务结构、架构、checkpoint、postmortem、roadmap 分别在哪里。
- 验证入口：当前最可信的检查命令或人工验证路径是什么。

如果这些信息暂时未知，README 应明确写“待讨论”或“待补齐”，不要把模板假设写成项目事实。

## `docs/` 标准结构

所有项目使用同一套 `docs/` 标准结构，不按小、中、大项目分流。这样 agent 不需要判断项目规模，只需要判断某个文档当前是“已存在”“待补齐”还是“当前不适用”。

标准结构：

```text
docs/
├── README.md
├── requirements.md
├── requirements/
│   └── <module>/
│       ├── requirements.md
│       └── structure.md
├── architecture/
│   ├── overview.md
│   ├── api.md
│   ├── backend.md
│   ├── frontend.md
│   ├── database.md
│   ├── ui.md
│   ├── security.md
│   ├── testing.md
│   ├── deployment.md
│   └── integrations.md
├── checkpoints/
├── postmortems/
└── roadmap.md
```

不要在每个目录下都创建 `README.md`。`docs/README.md` 是唯一文档地图和概述入口；各子目录只承载对应事实。

## `docs/README.md` 写作规则

`docs/README.md` 是 `docs/` 的唯一文档地图。它的结构固定，内容必须由项目启动讨论和现有仓库事实生成，不把模板占位写成已确认事实。

`docs/README.md` 必须包含：

- 权威事实源索引：项目级需求、模块需求、架构、当前任务和专题文档的真实路径与状态。
- 模块索引：模块名、模块需求、业务结构和状态；没有模块时明确“当前不适用”。
- 架构索引：`architecture/**` 各文档的状态；没有应用架构时说明原因和重新评估条件。
- 运行过程文档入口：`docs/checkpoints/` 和 `docs/postmortems/`。
- 阅读入口：读者想了解目标、模块、架构、测试、当前任务、失败模式或 checkpoint 时先读哪里。
- 维护规则：新增、移动、重命名、废弃或删除 `docs/` 文档时必须同步更新。

状态值使用：

- `已确认`：已经由用户、代码事实或稳定项目文档确认。
- `草案`：已有内容但仍可能调整。
- `待补齐`：应该存在但尚未生成真实内容。
- `当前不适用`：当前项目不需要；必须说明重新评估条件或原因。

`docs/README.md` 不得包含：

- 需求正文、架构正文、测试策略正文或 runbook 正文。
- 当前任务计划、todo、验证结果或执行流水。
- review / adversarial-review 报告。
- checkpoint 或 postmortem 正文。
- 未确认的技术选型、模块、约束或状态。

项目启动时可以先创建占位版 `docs/README.md`，但第一次需求澄清后必须更新为真实文档地图。最终结构可参考 `.spec/rules/templates/docs-readme.md`。

### 职责

- `docs/README.md`：文档总地图、模块索引、状态和权威事实源说明。
- `docs/requirements.md`：整个项目的需求澄清、全局目标、全局非目标、全局角色、跨模块约束和模块索引。
- `docs/requirements/<module>/requirements.md`：模块 PRD，包含业务需求、`REQ-*`、`SC-*`、`BPF-*`、功能需求、模块规则、用户角色和业务流程。
- `docs/requirements/<module>/structure.md`：模块业务数据结构，描述实体、字段业务含义、状态、关系和业务不变量；不写物理表名、DDL、索引或数据库迁移。
- `docs/architecture/**`：API、后端、前端、数据库、UI、安全、测试规范、部署、集成和技术约束。
- `docs/architecture/overview.md`：系统上下文、主要组成、架构边界、关键数据流和架构文档索引。
- `docs/architecture/database.md`：数据库选型、物理表设计、索引、约束、迁移策略，以及对 `docs/requirements/<module>/structure.md` 的引用和实现映射；不重新定义字段业务含义。
- `docs/architecture/testing.md`：单测、集测、端到端测试、人工验收和覆盖策略的长期规范。
- `docs/architecture/integrations.md`：外部系统、第三方服务、Webhook、消息队列、SSO、支付、邮件、短信等集成契约；流程性集成测试写入 `docs/architecture/testing.md`。
- `docs/checkpoints/`：checkpoint notes，记录可回滚、可比较的稳定点；不是当前任务事实源。
- `docs/postmortems/`：agent 错误复盘和可复用失败模式；结论只有被提炼进 `.spec/`、脚本或测试后才成为规则或预防机制。
- `docs/roadmap.md`：迭代计划、里程碑、优先级、暂缓事项和阶段验收口径。
- 当前任务事实源：当前可执行任务，不替代任何 `docs/` 文档。

### 记录规则

- 不适用的文档不要删除入口；在 `docs/README.md` 中标记“当前不适用”并说明重新评估条件。
- 不维护 `docs/decisions/` 作为默认目录；重要方案取舍应沉淀到需求、架构或当前任务事实源的对应章节，并保留用户确认依据。
- 不维护默认 `docs/testing.md`；测试规范和测试策略写入 `docs/architecture/testing.md`，本轮实际验证命令和结果写入当前任务事实源。
- 不维护默认 `docs/design.md` 或 `docs/implementation.md`；长期技术结构写入 `docs/architecture/**`，当前实施计划、验证和 todo 写入当前任务事实源。
- `docs/checkpoints/` 和 `docs/postmortems/` 是运行过程文档，不得作为需求、架构、roadmap 或当前任务的唯一事实源。
- 不允许同一事实在多个文档中并列维护；必须指定权威来源并用链接引用。

Architecture 文档的详细写法见 `.spec/rules/architecture.md`。

## 写作原则

- README 是地图，不是规则全集。
- 优先短、准、可导航；详细方法链接到 `.spec/`，项目事实链接到 `docs/`。
- 区分项目事实和协作规则：项目事实写 README / `docs/`，协作规则写 `.spec/`。
- 区分当前任务和长期说明：当前任务写入项目声明的当前任务事实源，README 只链接入口。
- 保持动作 workflow 的入口认知：可执行流程放在项目声明的位置，README 只说明从哪里进入。
- 根 README 必须链接 `docs/README.md`，并列出关键 `docs/` 事实源的状态。
- 新增、移动、重命名或删除项目文档时，同步根 README 和 `docs/README.md` 的文档索引。
- 不记录会话流水、临时诊断、run log 或 checkpoint 内容。

## 推荐结构

最终产物按 `.spec/rules/templates/readme.md` 输出。对于刚初始化的新项目，可以保留待补齐项；对于已有项目，应尽量使用真实项目事实替换占位。

## 完成标准

- 读者能在 30 秒内知道项目是什么、现在到哪一步、下一步看哪里。
- 读者能通过 README 找到协作规范、当前任务事实源、关键 `docs/` 产物和验证入口。
- README 中列出的 `docs/` 文档路径真实存在，或明确标记为待补齐。
- README 没有复制 `.spec/rules/` 的详细规范。
- README 没有把未知信息伪装成已确认事实。
