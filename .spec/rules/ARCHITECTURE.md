# ARCHITECTURE 写作规则

本规则指导 agent 如何创建和维护项目级架构文档。Architecture 文档描述长期技术结构、稳定契约和工程约束，不承载需求正文、当前任务计划、运行日志或临时实现步骤。

## 适用范围

项目级架构文档默认直接放在 `docs/` 根部：

```text
docs/architecture.md       # 可选：系统上下文和跨功能边界
docs/security.md            # 可选：安全边界
docs/testing.md             # 可选：项目长期测试规范
docs/integrations.md        # 可选：外部集成契约
```

这些文件按实际事实按需创建，不表示每个项目启动时都必须生成一套空文档。feature 局部的方案和验证仍分别写入 `docs/features/<feature>/solution.md` 与 `testing.md`。旧项目的 `docs/architecture/` 结构在迁移完成前继续保持可读，新工作不再创建该结构。

## 输入依据

写 architecture 前先读取：

- `docs/README.md`，确认文档地图和状态。
- 相关 `docs/features/<feature>/requirements.md`，确认需求来源。
- `.spec/rules/SOLUTION.md` 产出的方案取舍结论，若存在。
- 代码、配置、部署脚本或真实运行环境事实，若项目已有实现。

不要把 agent 自己偏好的技术选型、框架、目录结构或云服务写成已确认事实。

## 通用写法

每个 architecture 文档应包含：

- 状态：`已确认`、`草案`、`待补齐` 或 `当前不适用`；
- 来源：来自哪些需求、方案取舍、代码事实或用户确认；
- 范围：本文负责什么，不负责什么；
- 稳定契约：对实现、测试、部署或协作有约束力的决定；
- 变更条件：什么情况下需要重新评估。

每个 architecture 文档不得包含：

- 需求正文或业务字段含义的重复定义；
- 当前迭代 todo、任务拆分、执行日志或验证流水；
- 未确认的技术选型；
- review / adversarial-review 报告；
- checkpoint、postmortem、运行日志或外部工具原文。

## 各文件职责

- `architecture.md`：系统上下文、主要组成、架构边界、关键数据流和跨功能依赖；不写 feature PRD 或详细 API 字段。
- `security.md`：认证、授权、敏感数据、密钥、审计、依赖安全、输入校验和威胁边界；不保存 secrets。
- `testing.md`：单测、集测、端到端测试、人工验收、覆盖策略、测试数据和 CI 检查的长期规范；本轮实际命令和结果写当前任务事实源。
- `integrations.md`：外部系统、第三方服务、Webhook、消息队列、SSO、支付、邮件、短信等集成契约；流程性集成测试写 `testing.md`。
- 其他跨功能主题使用明确的根级小写文件名，不创建泛化的 `docs/architecture/` 包装目录。

## 完成标准

- `docs/README.md` 已同步项目级架构文档状态和入口；
- 每条架构约束都有来源或明确假设；
- 与需求、业务结构、测试规范和任务事实源没有重复维护同一事实；
- 未确认或不适用的领域被明确标注，而不是留空文件；
- 影响稳定合约时，按 `.spec/rules/ADVERSARIAL-REVIEW.md` 做反向审查。
