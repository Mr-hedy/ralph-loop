# 项目文档地图

本文件是项目过程文档的唯一入口。新增、移动或归档文档时同步维护这里。

## 功能索引

| Feature | 需求 | 方案 | 验证 | 最终任务 | 状态 |
|---|---|---|---|---|---|
| `<feature>` | `features/<feature>/requirements.md` | `features/<feature>/solution.md`（可选） | `features/<feature>/testing.md`（可选） | `features/<feature>/final-task.md`（完成后） | <状态> |

## 项目级专题

| 主题 | 文档 | 状态 | 说明 |
|---|---|---|---|
| 架构 | `architecture.md`（按需创建） | <状态> | <说明> |
| 安全 | `security.md`（按需创建） | <状态> | <说明> |
| 集成 | `integrations.md`（按需创建） | <状态> | <说明> |
| 测试策略 | `testing.md`（按需创建） | <状态> | <说明> |

状态可使用：已确认、草案、待补齐、当前不适用。

## 运行过程文档

| 类型 | 路径 | 用途 |
|---|---|---|
| Troubleshooting | `troubleshooting/` | 业务系统故障排查与 RCA |
| Checkpoints | `checkpoints/` | 可回滚、可比较的稳定点记录 |
| Postmortems | `postmortems/` | Agent、工具链和协作流程的可复用失败模式 |
| Roadmap | `roadmap.md`（按需创建） | 阶段目标、优先级和暂缓事项 |

## 阅读入口

| 想了解什么 | 先读 |
|---|---|
| 某个功能需求 | `features/<feature>/requirements.md` |
| 某个功能方案 | `features/<feature>/solution.md`（存在时） |
| 某个功能验证 | `features/<feature>/testing.md`（存在时） |
| 当前任务 | <当前任务事实源路径> |
| 项目级稳定契约 | 对应的根级专题文档 |
| 业务系统排查 | `troubleshooting/<slug>.md` |
| 已知失败模式 | `postmortems/README.md` |
| 稳定 checkpoint | `checkpoints/README.md` |

## 维护规则

- 本文件是 `docs/` 唯一文档地图。
- 新增、移动、重命名、废弃或删除 `docs/` 文档时必须同步更新。
- 未确认内容必须标为“待补齐”“草案”或“当前不适用”，不能写成已确认事实。
- 项目级专题文档只在存在真实跨功能事实时创建，不创建空文件。
- 需求正文、架构正文、任务计划、review 报告、checkpoint 正文和 postmortem 正文不写在本文件。
