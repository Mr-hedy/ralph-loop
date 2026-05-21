# ralph-loop Agent Guide

面向用户的回复使用用户指定语言；未指定时沿用当前对话和既有项目文档语言。

本文件只做 agent 运行入口和路由。当前项目的协作规范、文档写法、流程质量门和模板在 `.spec/`；当前开发任务事实源在 `.ralph/TASKS.md`（v0.1 后从 root `task.md` 切换）；项目事实放在 `README.md`、`docs/`、代码和邻近配置中。

## Project Identity

- `ralph-loop` 是 shell-first CLI harness，用 provider CLI fresh oneshot 循环执行使用者 workspace `.ralph/TASKS.md` 中的长任务。
- **项目最终产物 = `.ralph/` 整个目录**。使用者通过 `cp -r .ralph/ <workspace>/.ralph/` 部署到自己的 project，单一目录单元，不依赖外部安装器。
- 本仓库是 ralph-loop 工具的开发工程；当前专项从需求澄清、run loop、provider adapter、status/watch 和 session capture 逐步推进。
- 项目事实沉淀在 `README.md`、`docs/requirements.md`、`docs/requirements/`、`docs/architecture/`、`.ralph/TASKS.md` 和邻近代码中。
- 本仓库自 v0.1 后可用 ralph dogfood 推进开发；release 分支中的 `.ralph/TASKS.md` 是可部署首跑样例，真实开发任务以用户请求、handoff、项目文档和显式任务清单为准。root `task.md` 已封版作为 v0.1 历史归档。

## Top Rules

- 保持 `.spec/`、`docs/`、`.ralph/` 和 `.agents/skills/` 的职责分离。
- `.spec/` 承载协作模型、事实源边界、文档结构、非动作方法、流程质量门和模板。
- `docs/` 承载项目事实、专题设计和运行过程文档。
- `.ralph/TASKS.md` 随 `.ralph/` 作为部署首跑样例入仓；root `task.md` 已封版作为 v0.1 历史归档，不再更新；`.ralph/TASKS.bak` 是 hello world 部署样例参考，不被 ralph 识别。
- `.ralph/` 是部署单元 + 本仓库自用工作目录。入仓边界：`bin/` + `lib/` + `PROMPT.md` + `TASKS.md` + `TASKS.bak` 入仓；`runs/` + `lock` + `status.json` + `.env` 是运行期产物或私有配置，**gitignore**。
- `.agents/skills/` 承载带明确运行产物或状态迁移的动作 workflow。
- 不要把模板占位当成已确认项目事实。

## Default Orientation

- 进入项目先读 `README.md` 和 `.spec/README.md`，确认项目地图、协作阶段和事实源边界。
- 执行当前开发任务时先读用户请求、`handoff.md` 和相关项目事实源；只有明确在 dogfood/ralph 任务循环中工作时，才把 `.ralph/TASKS.md` 当作当前任务清单。查询 v0.1 历史读 root `task.md`（已封版）。
- 做 Ralph harness 需求相关工作时读 `docs/requirements/ralph-loop/requirements.md`；做设计或实现时读 `docs/architecture/`（`overview.md` 起步，provider 集成看 `integrations.md`，安全边界看 `security.md`）。
- 历史 I<N> 设计方案和归档保留在 `docs/requirements/ralph-loop/`；这些编号是项目文档索引，不属于 ralph runtime 契约。
- 写或移动项目文档时同步 `README.md` 和 `docs/README.md`。
- 遇到失败、回归、重复错误、校验异常或预防机制问题时，先读 `docs/postmortems/README.md`，再判断是否需要记录 postmortem。
- 续接、回滚、创建 checkpoint 或判断稳定锚点时，先读 `docs/checkpoints/README.md`。

## 任务类型路由（用于 `.ralph/TASKS.md`）

`.ralph/TASKS.md` 任务前缀决定本轮 mindset 和参考的 `.spec/` 规范段。完整规范在 `.ralph/PROMPT.md`，路由速查：

| 前缀 | 必读 spec |
|------|-----------|
| `REQ-N` | `.spec/rules/requirements.md` |
| `SOL-N` | `.spec/rules/solution.md` |
| `ROADMAP-N` | `.spec/rules/roadmap.md`（Roadmap 阶段规划） |
| `PLAN-N` | `.spec/rules/tasks.md` + `.spec/README.md` 阶段 4（任务列表规划，trantor PLAN / sprint planning 同义） |
| (空) / `DEV-N` | CLAUDE.md + 代码事实（默认） |
| `QA-N` | `.spec/rules/testing.md` |
| `REVIEW-N` | `.spec/rules/review.md` 或 `.spec/rules/adversarial-review.md`（任务描述明确） |
| `HUMAN-N` | 等人类决策 — ralph oneshot 内不可勾选不可执行；普通对话里和人类协作回答 |

## Runtime 命名边界

- ralph runtime 使用 `round` / `rounds` 描述循环轮次，不解析、不展示、不写入迭代元数据。
- `I<N>-design.md` / `I<N>-FINAL-TASK.md` 只作为历史项目文档编号保留，不进入 `.ralph/` 发布单元运行契约。

## Boundaries

- 不要把需求正文、架构正文、当前任务、checkpoint 或 postmortem 混写到 `docs/README.md`。
- 不要把运行日志、临时诊断或模型输出当成任务完成事实。
- 不要把应用架构、技术选型或目录结构写成已确认事实，除非来自用户确认、代码事实或稳定项目文档。
- 不要保存 secrets、完整凭据或敏感配置到 docs、handoff、checkpoint、postmortem 或任务源。

## Verification Minimums

- 文档、协作规则或任务源变更：运行项目声明的完整检查；若项目尚无检查命令，至少运行 `git diff --check` 并说明未覆盖范围。
- 脚本或代码变更：先运行最小直接命令，再运行项目声明的完整检查。
- 模板、软链、生成物或项目入口变更：验证实际生成/链接/入口行为。
- 验证受阻时，说明阻塞原因和未验证范围。

## Keep This File Small

- 本文件只放路由、边界和最低验证要求。
- 详细协作规范放 `.spec/`。
- 运行过程文档放 `docs/checkpoints/`、`docs/postmortems/` 和 `handoff.md`。
- 过程产物使用项目约定语言；未约定时沿用既有文档语言，包括 `task.md`、`handoff.md`、checkpoint notes 和 postmortem entries。
