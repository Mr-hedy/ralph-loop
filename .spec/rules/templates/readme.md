# <项目名>

<一句话说明项目定位。未知时写：待需求讨论后补齐。>

## 定位

- 做什么：<项目要解决的问题>
- 不做什么：<明确非目标>
- 谁在用：<用户、维护者或评审者>

## 当前状态

- 阶段：<探索 | 设计 | 实现 | 维护 | 迁移>
- 当前任务：<当前任务事实源路径>
- 续接状态：`handoff.md`

## 入口地图

| 想做什么 | 从哪里开始 |
|---|---|
| 查看项目边界与运行入口 | <项目运行入口> |
| 查看协作与规格规范 | `.spec/README.md` |
| 查看当前任务 | <当前任务事实源路径> |
| 查看项目文档地图 | `docs/README.md` |
| 查看项目设计文档 | `docs/` |
| 查看可执行 workflow | <动作 workflow 入口> |
| Review / 检查 | `.spec/rules/review.md` |
| 反向审查 / 挑刺 | `.spec/rules/adversarial-review.md` |
| 记录失败模式 | <postmortem 动作流程入口> |
| 查看 checkpoint | `docs/checkpoints/` |
| 查看 postmortem | `docs/postmortems/` |

## 项目文档

| 文档 | 状态 | 用途 |
|---|---|---|
| `docs/README.md` | <待补齐 | 已存在> | 文档总地图、模块索引和权威事实源说明 |
| `docs/requirements.md` | <待补齐 | 已存在> | 项目级需求澄清、全局目标、边界、跨模块约束和模块索引 |
| `docs/requirements/<module>/requirements.md` | <待补齐 | 已存在> | 模块 PRD、需求、成功标准、业务流程和规则 |
| `docs/requirements/<module>/structure.md` | <待补齐 | 已存在 | 当前不适用> | 模块业务数据结构，不包含物理表设计 |
| `docs/architecture/` | <待补齐 | 已存在> | API、前后端、数据库、UI、安全、测试、部署和集成架构 |
| `docs/architecture/overview.md` | <待补齐 | 已存在> | 系统上下文、架构边界、关键数据流和架构文档索引 |
| `docs/architecture/database.md` | <待补齐 | 已存在 | 当前不适用> | 数据库选型、物理表、索引、迁移和业务结构映射 |
| `docs/architecture/testing.md` | <待补齐 | 已存在> | 单测、集测、端到端测试、人工验收和覆盖策略 |
| `docs/architecture/integrations.md` | <待补齐 | 已存在 | 当前不适用> | 外部系统和第三方服务集成契约 |
| `docs/checkpoints/` | <待补齐 | 已存在> | 可回滚、可比较的稳定点记录，不是当前任务事实源 |
| `docs/postmortems/` | <待补齐 | 已存在> | agent 错误复盘和可复用失败模式，不是需求或架构事实源 |
| `docs/roadmap.md` | <待补齐 | 已存在> | 阶段目标、优先级、验收口径和风险 |

## 文档规则

- 不在每个子目录创建 README；概述和索引统一写入 `docs/README.md`。
- 不适用的文档在 `docs/README.md` 标记“当前不适用”，并说明重新评估条件。
- 不默认维护 `docs/design.md`、`docs/testing.md`、`docs/implementation.md` 或 `docs/decisions/`。
- 测试规范写入 `docs/architecture/testing.md`；本轮实施计划、验证和 todo 写入当前任务事实源。
- Review 和 adversarial review 是流程质量门，执行口径在 `.spec/rules/`，默认不产出独立文档。
- Postmortem 是带运行过程产物的动作，执行协议在项目声明的动作 workflow。
- `docs/checkpoints/` 和 `docs/postmortems/` 是运行过程文档；可复用结论需要提炼到动作 workflow、`.spec/`、脚本或测试后才成为规则或预防机制。

新增、移动、重命名或删除项目文档时，同步更新本表。

## 验证

```bash
<主要检查命令>
```

## 项目边界

- <重要边界或约束>
