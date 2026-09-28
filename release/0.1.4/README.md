# Ralph Loop 0.1.4

这是 Ralph Loop 的可部署 release 包，包含 `.ralph/` 运行单元、`.spec/` 协作规范和 agent 启动入口。

## 部署

目标 workspace 已存在 `AGENTS.md`、`CLAUDE.md`、`.ralph/`、`.spec/` 或 `docs/` 时，不要直接覆盖；先将本目录复制到临时位置，再逐项人工合并。全新 workspace 才可以直接复制本目录内容。首次项目会话先阅读 `AGENTS.md`、`docs/README.md` 和 `.spec/README.md`，根据用户目标建立项目事实；用户决定生成任务清单后再补齐 `.ralph/TASKS.md`，用户要求执行且清单准备好后才运行 Ralph。

正式支持 provider：Claude Code、Codex CLI；`fake` 仅用于测试。Gemini 暂停接入。
