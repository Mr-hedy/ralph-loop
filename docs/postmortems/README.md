# Postmortems

本目录存放当前项目的可复用失败模式。

运行时遇到失败、回归、重复错误、校验异常或预防机制问题时，agent 应先读取本文件，再搜索相关 postmortem。

创建 checkpoint 前必须做 postmortem sweep。sweep 只判断本轮是否有值得沉淀的失败模式；没有可复用失败模式时不要创建空 postmortem。

## 规则

- 满足 `.agents/skills/postmortem/SKILL.md` 的触发条件时，新增或更新条目。
- 新条目从 `.agents/skills/postmortem/TEMPLATE.md` 复制。
- postmortem 必须包含可执行或可复核的预防检查。
- postmortem 结论只有被提炼到 skill、`.spec/`、脚本或测试后才成为规则或预防机制。

## 条目

| ID | 文件 | 标题 | 状态 |
|----|------|------|------|
| PM-0001 | [pm-shell-macos-compat.md](pm-shell-macos-compat.md) | Shell 脚本 macOS 兼容性 bug 在实施阶段未发现，集中在 adversarial review 阶段暴露 | active |
| PM-0002 | [pm-cross-task-decision-sedimentation.md](pm-cross-task-decision-sedimentation.md) | 跨任务稳定决策只在对话/任务文档中提及，未沉淀到稳定文档，下一轮容易偏离 | active |
