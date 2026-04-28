# ralph-loop Agent Guide

面向用户的回复使用用户指定语言；未指定时沿用当前对话和既有项目文档语言。

本文件只做 agent 运行入口和路由。当前项目的协作规范、文档写法、流程质量门和模板在 `.spec/`；当前开发任务事实源在根 `task.md`；项目事实放在 `README.md`、`docs/`、代码和邻近配置中。

## Project Identity

- `ralph-loop` 是 shell-first CLI harness，用 provider CLI fresh oneshot 循环执行使用者 workspace `.ralph/TASKS.md` 中的长任务。
- **项目最终产物 = `.ralph/` 整个目录**。使用者通过 `cp -r .ralph/ <workspace>/.ralph/` 部署到自己的 project，单一目录单元，不依赖外部安装器。
- 本仓库是 ralph-loop 工具的开发工程；当前专项从需求澄清、run loop、provider adapter、status/watch 和 session capture 逐步推进。
- 项目事实沉淀在 `README.md`、`docs/requirements.md`、`docs/requirements/`、`docs/architecture/`、`task.md` 和邻近代码中。

## Top Rules

- 保持 `.spec/`、`docs/`、`.ralph/` 和 `.agents/skills/` 的职责分离。
- `.spec/` 承载协作模型、事实源边界、文档结构、非动作方法、流程质量门和模板。
- `docs/` 承载项目事实、专题设计和运行过程文档。
- 根 `task.md` 是**本仓库**的开发任务事实源（给开发 ralph-loop 的人 + Claude Code 用）；`.ralph/TASKS.md` 是**部署后使用者** workspace 的运行时任务源（给 ralph 外层循环 + provider agent 用）。两者职责不同，本仓库 `.ralph/TASKS.md` 仅作为参考样板存在，不混淆。
- `.ralph/` 是部署单元，**整个目录入仓**：`bin/` + `lib/`（工具代码）、`PROMPT.md` + `TASKS.md`（参考样板，部署时随 `cp -r` 一并到使用者 workspace，可按需裁剪）。`runs/` / `lock` / `status.json` / `.env` 是运行期产物或私有配置，**本仓库不运行 ralph 故不会出现**；使用者 workspace 中需自行在外层 `.gitignore` 处理（如 `.ralph/runs/`、`.ralph/lock`、`.ralph/status.json`、`.ralph/.env`）。
- `.agents/skills/` 承载带明确运行产物或状态迁移的动作 workflow。
- 不要把模板占位当成已确认项目事实。

## Default Orientation

- 进入项目先读 `README.md` 和 `.spec/README.md`，确认项目地图、协作阶段和事实源边界。
- 执行当前开发任务时读 `task.md`；需要续接上下文时再读 `handoff.md`。
- 做 Ralph harness 需求相关工作时读 `docs/requirements/ralph-loop/requirements.md`；做设计或实现时读 `docs/architecture/`（`overview.md` 起步，provider 集成看 `integrations.md`，安全边界看 `security.md`）。
- 写或移动项目文档时同步 `README.md` 和 `docs/README.md`。
- 遇到失败、回归、重复错误、校验异常或预防机制问题时，先读 `docs/postmortems/README.md`，再判断是否需要记录 postmortem。
- 续接、回滚、创建 checkpoint 或判断稳定锚点时，先读 `docs/checkpoints/README.md`。

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
