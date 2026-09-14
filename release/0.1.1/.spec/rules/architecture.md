# Architecture 写作规则

本规则指导 agent 如何创建和维护 `docs/architecture/**`。Architecture 文档描述长期技术结构、稳定契约和工程约束，不承载需求正文、当前任务计划、运行日志或临时实现步骤。

## 适用范围

`docs/architecture/` 的标准逻辑结构是：

```text
docs/architecture/
├── overview.md
├── api.md
├── backend.md
├── frontend.md
├── database.md
├── ui.md
├── security.md
├── testing.md
├── deployment.md
└── integrations.md
```

这是逻辑结构和索引标准，不表示每个项目启动时都必须创建所有物理文件。当前不适用或尚未确认的文档，在 `docs/README.md` 标记状态和重新评估条件，不创建空文档冒充事实。

## 输入依据

写 architecture 前先读取：

- `docs/README.md`，确认文档地图和状态。
- `docs/requirements.md` 和相关 `docs/requirements/<module>/requirements.md`，确认需求来源。
- 相关 `docs/requirements/<module>/structure.md`，确认业务数据结构。
- `.spec/rules/solution.md` 产出的方案取舍结论，若存在。
- 代码、配置、部署脚本或真实运行环境事实，若项目已有实现。

不要把 agent 自己偏好的技术选型、框架、目录结构或云服务写成已确认事实。

## 通用写法

每个 architecture 文档应包含：

- 状态：`已确认`、`草案`、`待补齐` 或 `当前不适用`。
- 来源：来自哪些需求、方案取舍、代码事实或用户确认。
- 范围：本文负责什么，不负责什么。
- 稳定契约：对实现、测试、部署或协作有约束力的决定。
- 变更条件：什么情况下需要重新评估。

每个 architecture 文档不得包含：

- 需求正文或业务字段含义的重复定义。
- 当前迭代 todo、任务拆分、执行日志或验证流水。
- 未确认的技术选型。
- review / adversarial-review 报告。
- checkpoint、postmortem、运行日志或外部工具原文。

## 各文件职责

- `overview.md`：系统上下文、主要组成、架构边界、关键数据流、外部依赖总览和架构文档索引；不写模块 PRD 或详细 API 字段。
- `api.md`：API 风格、协议、鉴权方式、错误模型、版本策略、兼容性规则和接口索引；具体接口细节可链接 OpenAPI、代码或模块文档。
- `backend.md`：已确认的后端技术选型、模块分层、包结构、服务边界、配置管理、错误处理和后台任务约定；不写前端实现细节。
- `frontend.md`：已确认的前端技术选型、路由、状态管理、模块结构、数据获取、错误/空状态和可访问性约定；不写视觉品牌细节。
- `database.md`：数据库选型、物理表设计、索引、约束、迁移策略、备份恢复和对 `docs/requirements/<module>/structure.md` 的实现映射；不重新定义字段业务含义。
- `ui.md`：整体 UI 风格、组件原则、布局密度、交互状态、文案语气和设计系统约束；详细业务流程仍回到需求文档。
- `security.md`：认证、授权、敏感数据、密钥、审计、依赖安全、输入校验和威胁边界；不保存 secrets。
- `testing.md`：单测、集测、端到端测试、人工验收、覆盖策略、测试数据和 CI 检查的长期规范；本轮实际命令和结果写当前任务事实源。
- `deployment.md`：环境、构建、发布、回滚、配置、迁移执行、CI/CD 和运行时观测约定；不写一次性发布流水。
- `integrations.md`：外部系统、第三方服务、Webhook、消息队列、SSO、支付、邮件、短信等集成契约；流程性集成测试写 `testing.md`。

## 完成标准

- `docs/README.md` 已同步 architecture 文档状态和入口。
- 每条架构约束都有来源或明确假设。
- 与需求、业务结构、测试规范和任务事实源没有重复维护同一事实。
- 未确认或不适用的领域被明确标注，而不是留空文件。
- 影响稳定合约时，按 `.spec/rules/adversarial-review.md` 做反向审查。
