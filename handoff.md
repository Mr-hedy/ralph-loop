# 当前目标与约束

- 本轮目标：修复 `ralph watch` 与 `ralph status` 输出契约混淆，完成自审后先刷新 handoff，再创建 checkpoint rollback anchor。
- 硬约束：中文回复；当前开发任务事实源是 `.ralph/TASKS.md`；root `task.md` 已封版；`.ralph/runs/`、`.ralph/status.json`、`.ralph/lock`、`.env` 和 provider 运行日志不入仓。
- 用户明确要求：修复后自行 adversarial-review，有问题自行修；没问题先做 handoff，再做 checkpoint。

# 当前阶段与范围

- 阶段：I3 bugfix，主题为 watch/status 观察面修复。
- 影响模块：`.ralph/` 部署单元的 CLI/watch helper、SC-024 integration test、README/requirements/architecture/testing docs、任务事实源、postmortem。
- 变更类型：代码、测试、文档、任务源、流程记录。

# 稳定决策

- `ralph status` 是详细一次性快照，继续输出 status.json 的 15 个字段。
- `ralph watch` 默认是紧凑 sticky bar；`ralph watch -v` 才展示上方当前 iter `provider.stdout.log` tail。
- `ralph watch | cat` / redirect / 非 TTY 不应退化为 `ralph status`；只输出一次 one-line watch bar 后 exit 0。
- `watch -v` 的 run_id separator、iter tail 切换只属于 verbose tail 区域；默认 watch 不刷详细 log。
- 当前支持的 provider flag 为 `claude|codex|fake`；Gemini 仍是 T4 计划项。

# 已完成工作

- `.ralph/bin/ralph` 的非 TTY fallback 改为调用 `ralph_watch_once`，不再 source `status.sh` 后调用 `ralph_status`。
- `.ralph/lib/watch.sh` 新增 `ralph_watch_once`，复用 `_ralph_watch_bar_text` 输出单行 watch bar，并在非 TTY 下自然无颜色。
- `scripts/integration-test.sh` 的 SC-024-4 改为断言 one-line watch bar，并反向断言不出现 `workspace:` / `run_dir:` / `started_at:` / `last_error:` 等 status 详情字段。
- README、`.ralph/README.md`、requirements、overview、testing docs 已同步默认 sticky、`-v` tail、非 TTY one-line bar 的契约。
- `.ralph/TASKS.md` 已进入 I3 bugfix 主题并勾选 DEV-1，记录完成证据与未验证范围。
- `docs/postmortems/pm-task-closure-req-traceability.md` 已追加 2026-05-04 watch/status 观察面混淆条目，并新增反向断言预防规则。
- 自审额外修复 `docs/architecture/overview.md` provider 表仍写 `claude|codex|gemini` 的漂移，改为 `claude|codex|fake` 并标注 Gemini T4。

# 最新验证

- 命令：`bash -n .ralph/bin/ralph .ralph/lib/watch.sh scripts/integration-test.sh`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`bash .ralph/bin/ralph watch | cat`
- 结果：通过
- 诊断：输出一行 watch bar：`run: ... iter_name: I2 iter 5 11/9 tasks state: finished exit_reason: done provider: claude`；无 `workspace:` / `run_dir:` 详情字段。`11/9 tasks` 来自本仓库已忽略的旧 runtime `.ralph/status.json`，不是本次代码契约。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=83 FAIL=0`。

- 命令：`rg` 自审旧契约残留
- 结果：通过
- 诊断：当前代码、README、requirements、overview、测试中未发现“watch 非 TTY = status 输出”旧契约；唯一命中是 `.ralph/TASKS.md` 中记录的反向断言说明。

# 已验证与未验证

- 已验证：非 TTY watch fallback、SC-024-4 自动化、watch help 文案、provider flag 文档同步、requirements/overview/README/testing docs 一致性、完整集成测试 83/83。
- 未验证：真实 TTY 视觉录屏未重跑；真实 Claude/Codex 长任务 timeout 未重跑。本轮风险集中在非 TTY fallback 与文档/测试契约，已由 direct probe 和 integration test 覆盖。

# Checkpoint 与 Postmortem 状态

- Checkpoint：本轮 checkpoint 尚未创建；计划创建 `docs/checkpoints/2026-05-04-02-watch-status-surface-fix.md` 并提交。上一稳定 checkpoint 是 `docs/checkpoints/2026-05-04-01-i2-codex-observability-hardening.md`，commit `de01779 checkpoint: I2 codex observability hardening`。
- Postmortem：已更新既有 PM-0003：`docs/postmortems/pm-task-closure-req-traceability.md`，记录 watch/status surface separation 回归模式和预防检查。

# 工作区状态

- 分支：`main`
- 最近提交：`b569060 docs(I2): archive Codex adapter iteration`
- 当前 dirty 范围：`.ralph/bin/ralph`、`.ralph/lib/watch.sh`、`scripts/integration-test.sh`、README、`.ralph/README.md`、requirements、overview、testing docs、`.ralph/TASKS.md`、postmortem、`handoff.md`。
- diff 范围符合本轮 bugfix；未发现 runtime artifact、`.env` 或 provider 日志进入仓库。

# 建议下一步

- 立即按 checkpoint skill 创建 `docs/checkpoints/2026-05-04-02-watch-status-surface-fix.md`。
- checkpoint commit 后刷新 `handoff.md`，写入 checkpoint note path 和 commit id，确保最终 handoff 不停留在“待创建”状态。

# 交接摘要

- 当前核心事实：watch/status 输出面已经重新分离，自动化明确防止 `watch` 非 TTY 再泄漏 `status` 详情字段；下一步只剩 checkpoint 提交与最终 handoff 刷新。
