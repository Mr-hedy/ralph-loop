# 项目文档地图

## 权威事实源

| 主题 | 文档 | 状态 | 说明 |
|---|---|---|---|
| 项目级需求 | `docs/requirements.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| 模块需求 | `docs/requirements/<module>/requirements.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| 架构总览 | `docs/architecture/overview.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| 当前任务 | <当前任务事实源路径> | <已存在> | 当前可执行任务事实源 |

## 模块索引

| 模块 | 需求 | 业务结构 | 状态 |
|---|---|---|---|
| `<module>` | `requirements/<module>/requirements.md` | `requirements/<module>/structure.md` | <已确认 | 草案 | 待补齐 | 当前不适用> |

## 架构索引

| 领域 | 文档 | 状态 | 说明 |
|---|---|---|---|
| Overview | `architecture/overview.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| API | `architecture/api.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Backend | `architecture/backend.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Frontend | `architecture/frontend.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Database | `architecture/database.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| UI | `architecture/ui.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Security | `architecture/security.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Testing | `architecture/testing.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Deployment | `architecture/deployment.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |
| Integrations | `architecture/integrations.md` | <已确认 | 草案 | 待补齐 | 当前不适用> | <说明> |

## 运行过程文档

| 类型 | 路径 | 用途 |
|---|---|---|
| Checkpoints | `checkpoints/` | 可回滚、可比较的稳定点记录 |
| Postmortems | `postmortems/` | agent 错误复盘和可复用失败模式 |

## 阅读入口

| 想了解什么 | 先读 |
|---|---|
| 项目目标和边界 | `requirements.md` |
| 某个模块需求 | `requirements/<module>/requirements.md` |
| 系统架构 | `architecture/overview.md` |
| 测试策略 | `architecture/testing.md` |
| 当前任务 | <当前任务事实源路径> |
| 已知失败模式 | `postmortems/README.md` |
| 稳定 checkpoint | `checkpoints/README.md` |

## 维护规则

- 本文件是 `docs/` 唯一文档地图。
- 新增、移动、重命名、废弃或删除 `docs/` 文档时必须同步更新。
- 未确认内容必须标为“待补齐”“草案”或“当前不适用”，不能写成已确认事实。
- 需求正文、架构正文、任务计划、review 报告、checkpoint 正文和 postmortem 正文不写在本文件。
