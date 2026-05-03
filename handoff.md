# 当前目标与约束

- 本轮目标：在 I2 Codex adapter 与 observability/timeout 修复收口后，先刷新 handoff，再创建 checkpoint rollback anchor。
- 硬约束：中文回复；当前开发任务事实源是 `.ralph/TASKS.md`；root `task.md` 已封版；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 和 provider 运行日志不入仓。
- 用户明确要求：先做 handoff，再做 checkpoint。后台/长任务不能强杀；本轮无需再跑真实 Claude/Codex 长 timeout，除非后续用户单独要求。

# 当前阶段与范围

- 阶段：I2 收口前 checkpoint 准备，主题仍为 dogfood T3 — Codex adapter。
- 影响模块：`.ralph/` 部署单元、run/status/watch/provider observability、Codex/fake adapter、集成测试、README/requirements/architecture docs、任务事实源。
- 变更类型：代码、测试、文档、任务源、流程记录。

# 稳定决策

- Codex iter 证据契约稳定为 4 文件：`meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`。
- Codex `session.history.log` 从 `provider.stdout.log` 的稳定 `codex exec --json` event stream 派生，不解析内部 rollout JSONL 作为 history 事实源。
- `RALPH_PROVIDER_CONFIG_DIR` 对 Codex 翻译为 `CODEX_HOME`；为空时不 export，避免破坏默认登录态。
- `ralph run -v` 负责 provider event live-tail；无 `-v` 时 run loop 每 60s 输出 provider heartbeat，可用 `RALPH_PROGRESS_HEARTBEAT_SEC=0` 关闭。
- `ralph watch -v` 依赖 `status.json.iteration` 定位当前 iter；run loop 必须在 provider oneshot 前写入当前 iteration 和已 touch 的 `provider.stdout.log`。
- `--timeout` 是单轮 provider oneshot timeout，不是整个 run 总超时；timeout 必须清理 provider oneshot 进程树。
- 真实 provider smoke 已覆盖 Codex happy path；真实 Claude/Codex timeout 长任务未重跑，当前用 fake external child 测试覆盖同一 Ralph 进程树风险。

# 已完成工作

- I2 Codex adapter 已实现并通过真实 Codex smoke 复验：run id `20260503-145326-3085d11`，`exit_reason=done`，`hello.txt` 内容正确，iter 4 文件齐全，`session.history.log` 非空。
- 修复 I2 adversarial review 提出的 docs/requirements/测试/任务源问题：Codex 使用入口、requirements 旧 artifact、DEV-5 完成证据、Codex effort/model 实参断言、error-event fallback fixture、动态追加任务总数。
- 修复 Codex `ralph run -v` 无事件 marker：`_ralph_filter_verbose` 支持 `thread.started`、`agent_message`、`command_execution`、`turn.completed`、`turn.failed`、`error`。
- 修复 Claude provider 长 oneshot 默认无反馈：新增 provider heartbeat，输出 elapsed、log bytes/lines 和 `tail -f provider.stdout.log` 路径。
- 修复 `ralph watch -v` 第一轮盯 `iter-000`/上一轮导致空白：provider 开始前更新 status 指向当前 iter。
- 修复 timeout 只杀 shell 不保证清理子进程：timeout 分支改为终止 provider oneshot 进程树，fake adapter 新增 `slow_child` 回归场景。
- 同步 README、`.ralph/README.md`、requirements、overview/security/testing docs、`.ralph/TASKS.md` 中的 I2 当前事实与验证证据。

# 最新验证

- 命令：`bash -n .ralph/lib/run.sh .ralph/lib/adapter-fake.sh .ralph/bin/ralph scripts/integration-test.sh tests/fixtures/mock-codex`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`RALPH_FAKE_SCENARIO=slow_child RALPH_FAKE_SLEEP=30 bash <temp>/.ralph/bin/ralph run --provider fake --timeout 2`
- 结果：通过
- 诊断：`exit_reason=timeout`，返回码 3，fixture 记录的 child pid 已退出。

- 命令：`bash .ralph/bin/ralph watch --help`
- 结果：通过
- 诊断：help 中包含 `--verbose, -v` 和 `provider.stdout.log`。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=83 FAIL=0`。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

# 已验证与未验证

- 已验证：Codex real happy path、Codex/fake automated adapter paths、run/watch observability regression、default heartbeat、timeout process tree cleanup、docs/help/requirements consistency、完整集成测试 83/83。
- 未验证：真实 Claude 长任务 + `ralph watch -v` 视觉观察未重跑；真实 Claude/Codex timeout 手工进程树未重跑。当前判断为不必重跑，因为根因位于 Ralph status/log 定位与 shell 进程树清理，已由 fake slow/slow_child 覆盖。

# Checkpoint 与 Postmortem 状态

- Checkpoint：本 handoff 写入时尚未创建；下一步将创建 `docs/checkpoints/2026-05-04-01-i2-codex-observability-hardening.md` 并提交。
- Postmortem：checkpoint sweep 已命中既有 PM-0003，下一步会更新 `docs/postmortems/pm-task-closure-req-traceability.md`，记录 2026-05-04 的观测面误定位与 timeout 子进程测试缺口。

# 工作区状态

- 分支：`main`
- 最近提交：`694aed8 fix(codex): derive history.log from provider.stdout.log, not session file`
- 当前 dirty scope：`.ralph/README.md`、`.ralph/TASKS.md`、`.ralph/bin/ralph`、`.ralph/lib/adapter-fake.sh`、`.ralph/lib/run.sh`、`README.md`、`docs/README.md`、`docs/architecture/overview.md`、`docs/architecture/security.md`、`docs/architecture/testing.md`、`docs/requirements/ralph-loop/requirements.md`、`scripts/integration-test.sh`、`tests/fixtures/mock-codex`，以及本文件。
- diff 范围为 I2 收口修复同一 coherent scope；未发现需要拆出的无关 dirty 改动。

# 建议下一步

- 立即完成 checkpoint note、postmortem 更新、验证与 commit；commit 后再轻量刷新本 handoff，补入 checkpoint commit id。
- checkpoint 之后若继续 I2，优先做一次最终 adversarial review 或按迭代归档约定生成 `docs/requirements/ralph-loop/I2-FINAL-TASK.md` 并推进 roadmap。

# 交接摘要

- I2 已从 Codex adapter 扩展到用户可见 observability 与 timeout hardening；当前核心事实是：真实 Codex happy path 已复验，剩余真实长 timeout smoke 不是 checkpoint 阻塞项，checkpoint 前必须把 PM-0003 再次命中记录下来。
