# 当前目标与约束

- 目标：完成 v0.1.1 release candidate 收口后的交接；本次请求要求先刷新 handoff，再创建 checkpoint。
- 硬约束：中文回复；当前开发任务事实源为 `.ralph/TASKS.md`；发布单元是 `.ralph/` 整个目录；不要把 `.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.ralph/.env` 带入发布包。
- 当前 release 判断：Claude/Codex 真实 smoke 已通过；Gemini adapter 逻辑和 mock 回归通过，但 Gemini 真实 full smoke 被本机认证缺失阻塞，不能声明三 provider 全部真实验证完成。

# 当前阶段与范围

- 阶段：release readiness / v0.1.1 收口。
- 影响模块：`.ralph/` CLI/runtime/provider adapters/docs、`scripts/integration-test.sh`、`tests/fixtures/mock-gemini`、README/requirements/architecture docs、`.agents/skills/`、`docs/postmortems/`。
- 变更类型：代码修复、发布文档、真实 provider smoke、UX 回归、skills 沉淀、postmortem、checkpoint 准备。

# 稳定决策

- Runtime 不再暴露 iteration 元数据；运行时统一使用 `round` / `rounds`，开发文档里的 `I<N>` 只作为历史归档编号。
- `parse_current_iteration()` 已删除；`.ralph/TASKS.md` 顶部 legacy 当前迭代声明即使存在，也不会写入 `status.json` / `result.json`。
- Codex adapter 使用 `--sandbox danger-full-access`，因为 ralph oneshot 协议要求 provider 在每轮内完成 `git add -A && git commit`，真实 Codex `workspace-write` 不能写 `.git/index.lock`。
- Gemini adapter 使用 `--approval-mode yolo --skip-trust --output-format stream-json`；`--skip-trust` 用于避免新 workspace trust 降级 approval。
- `.ralph/README.md` 是部署后新手手册，应独立覆盖安装、认证、`.env`、TASKS 写法、所有 CLI 命令/参数、status/watch、退出原因、日志和故障处理。
- Release/provider adapter 收口不能只看 mock 集成测试；必须记录真实 provider smoke 的 passed / failed / blocked-by-auth / not-run 状态。

# 已完成工作

- 版本收口：`.ralph/bin/ralph` 当前为 `0.1.1`，README 状态同步到 `v0.1.1`。
- 发布迭代信息清理：删除 `parse_current_iteration()`；移除 runtime/status/watch/exit-message 中的 iteration 字段；更新 PROMPT、requirements、architecture、README、tests。
- Codex 真实 smoke 暴露 `.git/index.lock` 权限问题后，adapter 改为 `danger-full-access`，docs 和 mock 断言同步。
- Gemini 真实 smoke 暴露新 workspace trust downgrade 后，adapter 增加 `--skip-trust`，docs 和 mock 断言同步；真实 full smoke 仍被本机 Gemini auth 阻塞。
- 修复 Gemini/Codex 日志事件区：verbose filter 不再丢弃 Gemini assistant delta，`run -v` / `watch` 能显示 assistant delta + tool/result marker。
- 修复 plain heartbeat 后台 `sleep` 清理：heartbeat 子 shell 增加 trap，并新增集成测试断言 fast plain run 后无 orphan sleep。
- 重写 `.ralph/README.md` 为手把手新手文档，枚举所有命令、参数和示例，并说明 provider 权限边界、runtime artifacts 复制风险、Gemini auth 前置条件。
- skills 沉淀：
  - `checkpoint`：release/provider adapter checkpoint 必须记录真实 smoke 状态。
  - `postmortem`：sweep 覆盖 mock-vs-real 验证差异和 release smoke 阻塞。
  - `task-loop`：任务源改为 `.ralph/TASKS.md`，并把真实 provider smoke 状态纳入 exit gate。
- postmortem：
  - 新增 `docs/postmortems/pm-real-provider-smoke-permission-gap.md`（PM-0004）。
  - 更新 `docs/postmortems/pm-task-closure-req-traceability.md`（PM-0003）记录 heartbeat orphan sleep 失败模式。

# 最新验证

- 命令：`bash -n .ralph/bin/ralph .ralph/lib/*.sh scripts/integration-test.sh tests/*.exp`
- 结果：通过
- 诊断：所有 shell/expect 脚本语法 OK。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：项目声明检查通过，输出 `ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过，`PASS=150 FAIL=0`
- 诊断：覆盖 exit reason、retry、timeout child cleanup、per-task max_round/stall、round 命名、plain/sticky UX、status/watch、Claude/Codex/Gemini mock adapters、Gemini verbose assistant delta、heartbeat cleanup 等。

- 命令：真实 Claude smoke
- 结果：通过
- 诊断：临时 workspace run_id `20260520-035742-071467e`，`exit_reason=done`，1/1 task，目标文件和任务勾选 OK，commits=2，`capture_status=ok`，history bytes 12274。

- 命令：真实 Codex smoke
- 结果：先失败后修复通过
- 诊断：首次 `workspace-write` 因 `.git/index.lock` 权限失败；修复为 `danger-full-access` 后临时 workspace run_id `20260520-040808-326dbfc`，`exit_reason=done`，1/1 task，目标文件和任务勾选 OK，commits=2，`capture_status=ok`，history bytes 3271。

- 命令：真实 Gemini smoke
- 结果：阻塞
- 诊断：本机没有 `~/.gemini/settings.json`，且 `GEMINI_API_KEY` / `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` 未设置；直接命令加 `--skip-trust` 后只剩 auth error，无 trust downgrade 警告。

- 命令：进程残留检查 `ps aux | rg 'ralph|integration-test|mock-claude|mock-codex|mock-gemini|claude|codex|gemini|sleep 17|sleep 60'`
- 结果：通过
- 诊断：未见 ralph/integration-test/mock provider/heartbeat sleep 残留；仅有 Codex app server、Claude native host、VS Code 这类常驻进程。

# 已验证与未验证

- 已验证：release cleanup 后 runtime round/rounds 契约；Codex/Gemini adapter 关键参数；Gemini/Codex 日志事件区 UX；plain/sticky/status/watch 自动化 UX；heartbeat cleanup；Claude/Codex 真实 provider 完整 smoke。
- 未验证：Gemini 真实 full smoke。原因是本机 Gemini CLI 认证未配置；这是环境/auth 阻塞，不是当前已知产品代码阻塞。

# Checkpoint 与 Postmortem 状态

- Checkpoint：本 handoff 刷新后将创建 `docs/checkpoints/2026-05-21-01-release-readiness.md` 并提交；最终以该 checkpoint note 和提交为准。
- Postmortem：新增 PM-0004；更新 PM-0003。PM sweep 结论为“已新增/已更新”，且已把规则提炼到 skills 和 `scripts/integration-test.sh`。

# 工作区状态

- 分支：`main`
- HEAD：`af9c54f docs(sticky): unify \`(Ctrl+C to exit)\` formatting across hint & frozen footer`
- 当前 dirty 范围包含 release 收口代码/文档/skills/postmortem/checkpoint 准备，以及一批历史 mode-only 文件状态。提交 checkpoint 时应避免把无关 mode-only 噪音混入。
- 新增文件：`docs/postmortems/pm-real-provider-smoke-permission-gap.md`；checkpoint note 待创建。

# 建议下一步

- 创建并提交 checkpoint：`docs/checkpoints/2026-05-21-01-release-readiness.md`。
- Gemini CLI auth 配置完成后，重新执行 Gemini 真实 smoke；若通过，更新 release 验证结论。
- 若准备正式 release，建议先确认是否要清理工作树中的 mode-only 噪音，避免后续 diff 继续污染审查。

# 交接摘要

- v0.1.1 release candidate 的代码、文档、UX、mock 回归、Claude/Codex 真实链路已收口；唯一未完成的真实验证是 Gemini full smoke，阻塞原因是本机 auth 缺失。
