# Checkpoints

本目录存放当前项目的 checkpoint note，用于描述可回滚、可比较的稳定点。

运行时遇到续接、回滚、创建 checkpoint 或判断稳定锚点时，agent 应先读取本文件，再按需读取相关 checkpoint note。

## 规则

- 只有当前轮工作形成可用成果时才创建 checkpoint。
- 创建 checkpoint 前必须执行 postmortem sweep；发现可复用失败模式时先暂停 checkpoint，单独处理 postmortem 后再继续；没有可复用失败模式时只在 checkpoint note 中记录“无需要新增”。
- 每个 checkpoint note 必须和对应代码或文档改动进入同一个 commit。
- 新 note 从 `.agents/skills/checkpoint/TEMPLATE.md` 复制。
- 机制细节见 `.agents/skills/checkpoint/SKILL.md`。
