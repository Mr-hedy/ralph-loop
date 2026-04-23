# Postmortems

本目录存放当前项目的可复用失败模式。

运行时遇到失败、回归、重复错误、校验异常或预防机制问题时，agent 应先读取本文件，再搜索相关 postmortem。

创建 checkpoint 前必须做 postmortem sweep。sweep 只判断本轮是否有值得沉淀的失败模式；没有可复用失败模式时不要创建空 postmortem。

## 规则

- 满足 `.agents/skills/postmortem/SKILL.md` 的触发条件时，新增或更新条目。
- 新条目从 `.agents/skills/postmortem/TEMPLATE.md` 复制。
- postmortem 必须包含可执行或可复核的预防检查。
- postmortem 结论只有被提炼到 skill、`.spec/`、脚本或测试后才成为规则或预防机制。

暂无正式 postmortem 条目。
