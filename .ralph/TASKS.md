# Tasks

> 这是 ralph 部署后的最小首跑样例，用来验证 `.ralph/` 已就绪、provider CLI 能通、循环能跑通。
>
> 使用方式：
> 1. 在目标 workspace 跑 `cp -r .ralph/ <workspace>/.ralph/`
> 2. 按需编辑 `.ralph/.env`
> 3. 在 workspace 跑 `.ralph/bin/ralph run`
> 4. 跑通后用真实任务清单替换本文件
>
> ralph 只识别顶层 `- [ ] / - [x]`；子 bullet 是给 agent 读的，不进解析。

- [x] 初始化：确认 `.ralph/` 已部署到本 workspace，git init 已完成。

- [x] DEV-1: 写 hello.txt，内容为 `hello ralph`，完成后 commit。
  - 文件路径：hello.txt（workspace 根目录）。
  - 内容严格为 `hello ralph`，无多余空行。
  - 完成后：`git add -A && git commit -m "add hello.txt"`。
  - 完成: 已创建根目录 `hello.txt`，内容为 `hello ralph`。
  - 验证: `od -An -tx1c hello.txt` 确认仅含 `hello ralph` 及单个文件结尾换行。
  - 未验证: None

- [ ] DEV-2: 在 README.md 末尾追加 `<!-- setup complete -->`，完成后 commit。

## 当前工作包（2026-09-14）

> 本工作包承接 provider 输出采集、权限边界和 Gemini 暂停接入的决策。旧的 DEV-1/DEV-2 首跑样例保留，不删除历史任务；ralph 按文件中第一个未完成顶层任务依次执行。

- [ ] DEV-3: 固化 Claude/Codex provider 输出与终态事件契约。
  - 预期：原始 `provider.stdout.log` 始终保留；Claude/Codex 的 `meta.json` 能区分 terminal event/status，解析异常不丢证据。
  - 输入：REQ-029、`docs/architecture/overview.md`、现有 adapter 和集成测试。
  - 范围：`.ralph/lib/adapter-claude.sh`、`.ralph/lib/adapter-codex.sh`、相关 schema/文档与测试；不得重新启用 Gemini。
  - 验证计划：bash 语法检查、fake 集成测试、成功/失败/未知终态 fixture，检查 raw log 未被覆盖。

- [ ] DEV-4: 强化 Codex native session 采集的活动/归档兼容性。
  - 预期：按 session id 校验并从活动或归档目录复制 session；找不到、截断或格式不匹配时 oneshot 仍完成且留下诊断。
  - 输入：REQ-030、Codex session 文档、现有 `provider_collect_session` 实现。
  - 范围：Codex adapter、meta 字段和针对配置目录隔离的测试；不改变 fresh oneshot 语义。
  - 验证计划：构造活动/归档/错误 rollout fixture，运行集成测试并检查 `session.history.log` 与错误诊断。

- [ ] DEV-5: 收敛 provider 入口和权限边界文档。
  - 预期：公开入口只允许 Claude/Codex/fake；Gemini 在启动阶段明确失败；Codex `danger-full-access` 的权限含义、配置目录和审计证据在 README/架构文档一致。
  - 输入：REQ-028、REQ-031、官方 CLI 行为记录、当前代码与文档。
  - 范围：`.ralph/bin/ralph`、`.ralph/lib/run.sh`、README 与 `docs/architecture/{overview,integrations,security}.md`；历史 Gemini 内容须标注为暂停/未来接入。
  - 验证计划：Gemini 入口失败且不产生 run；Claude/Codex/fake 入口检查通过；`git diff --check` 和文档一致性搜索。

- [ ] QA-1: 建立 provider 兼容性与权限 adversarial 回归门。
  - 预期：覆盖非零退出、未知/截断 JSON、终态缺失、session 丢失、配置目录隔离、Gemini 禁用和 Codex 权限提示；报告区分环境阻塞与未覆盖。
  - 输入：REQ-032、`.spec/rules/adversarial-review.md`、现有 `scripts/integration-test.sh`。
  - 范围：测试脚本与最小 fixture，不引入外部框架或 ACPX 重构。
  - 验证计划：完整 `bash scripts/check.sh`、完整集成测试、Claude/Codex smoke（可执行时）及 adversarial review 结论。

- [ ] REVIEW-1: 对本工作包全部修改做 adversarial review。
  - 预期：只报告有证据的高信号问题；重点检查 provider 输出完整性、权限扩大、路径穿越/错误 session 复制、Gemini 绕过入口和失败时的状态一致性。
  - 输入：REQ-028~REQ-032、全部代码/文档 diff、测试输出。
  - 范围：`.ralph/`、`scripts/`、README 和 architecture/requirements 文档；遵循 `.spec/rules/adversarial-review.md`。
  - 验证计划：逐项复核 diff，重跑受影响测试；发现问题则追加修复任务，不以 exit code 0 代替结论。
