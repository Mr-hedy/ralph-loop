# 目标与约束

- 保留 I3 watch/status 观察面修复后的稳定状态，作为后续继续 I3、归档 bugfix 或进入 T4/T7 前的 rollback anchor。
- 本 checkpoint 覆盖 `ralph watch` 非 TTY fallback、SC-024 requirements/overview/testing 同步、postmortem 预防规则和任务事实源更新。
- 约束：`ralph status` 的详细 15 字段输出不变；`ralph watch` 默认仍是紧凑 sticky bar；runtime artifacts、provider 日志、`.env` 不入仓。

# 范围

- Runtime：`.ralph/bin/ralph`、`.ralph/lib/watch.sh`
- 测试：`scripts/integration-test.sh`
- 文档与任务源：README、`.ralph/README.md`、`.ralph/TASKS.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/testing.md`
- 续接与流程：`handoff.md`、`docs/postmortems/pm-task-closure-req-traceability.md`

# 核心变更

- `ralph watch` 非 TTY fallback 不再调用 `ralph_status`；新增 `ralph_watch_once` 输出一次 one-line watch bar 后 exit 0。
- SC-024-4 集成测试从“status-like output”改为“one-line bar + 反向断言无 status 详情字段”，防止 `workspace:` / `run_dir:` / `started_at:` / `last_error:` 再泄漏到 watch。
- requirements / overview / README / `.ralph/README.md` 同步为：默认 `watch` 只渲染 sticky bar，`watch -v` 才 tail 当前 iter log，非 TTY 是一次 one-line watch bar。
- 自审发现并修复 `docs/architecture/overview.md` provider 表仍写 `claude|codex|gemini` 的漂移，改为当前支持的 `claude|codex|fake` 并标注 Gemini T4。
- `.ralph/TASKS.md` 从 I3 待定切换为 I3 bugfix，并记录 DEV-1 完成证据、验证结果和未验证范围。

# 影响文件或模块

- `.ralph/bin/ralph`：watch help 和非 TTY fallback。
- `.ralph/lib/watch.sh`：新增 `ralph_watch_once`。
- `scripts/integration-test.sh`：SC-024-4 回归测试更新。
- `README.md`、`.ralph/README.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/testing.md`：watch/status 输出面和 provider surface 同步。
- `.ralph/TASKS.md`：I3 bugfix 任务事实源。
- `docs/postmortems/pm-task-closure-req-traceability.md`：记录 watch/status surface 混淆的可复用失败模式。
- `handoff.md`：checkpoint 前续接状态。

# 稳定决策

- `ralph status` = 详细快照；`ralph watch` = 紧凑监控面；两者可以共享 `status.json` 数据源，但输出契约不能互相替代。
- 非 TTY watch 不做持续 tail，也不输出详细 status；需要详细字段时用户显式调用 `ralph status`。
- `watch -v` 才拥有上方 tail 区域、run_id separator 和 iter tail target switching；默认 `watch` 不刷 provider log。
- 对成对观察命令，测试不仅要断言目标字段存在，还要反向断言相邻命令的详情字段不存在。

# 验证结果

- 命令：`bash -n .ralph/bin/ralph .ralph/lib/watch.sh scripts/integration-test.sh`
- 结果：通过
- 诊断：shell 语法检查无输出。

- 命令：`bash .ralph/bin/ralph watch | cat`
- 结果：通过
- 诊断：输出一次 one-line watch bar；未出现 `workspace:` / `run_dir:` 等 status 详情字段。

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
- 诊断：当前代码、README、requirements、overview、测试中未发现“watch 非 TTY = status 输出”旧契约；`.ralph/TASKS.md` 仅保留反向断言说明。

# Postmortem Sweep

- 结果：已更新既有条目
- 关联：`docs/postmortems/pm-task-closure-req-traceability.md`
- 说明：本轮再次命中 PM-0003 的“观察面误定位/契约漂移”模式。根因是实现、requirements、overview 和 integration test 都把 `watch` 非 TTY fallback 写成 `status` 输出，测试保护了错误契约。本轮已补 postmortem 条目和反向断言预防规则，并落实到 SC-024-4 集成测试。

# 未验证范围与风险

- 未重跑真实 TTY 视觉录屏；本轮实际改动重点是非 TTY fallback 和文档/测试契约，TTY 主循环仍由既有 watch helper 与 SC-024-2 覆盖。
- 未重跑真实 Claude/Codex 长任务 timeout；本轮未改 timeout/process cleanup。
- 当前仓库存在旧 runtime `.ralph/status.json`，直接 `ralph watch | cat` 会显示历史 `11/9 tasks`，但该文件被 gitignore 管理，不属于提交内容。

# 下一步

- 提交本 checkpoint 后，刷新 `handoff.md` 写入 checkpoint note path 和 commit id。
- 后续如果继续 I3，可考虑归档 bugfix 或将 `.ralph/TASKS.md` 清回下一主题；如果进入功能开发，优先由用户排序 T4 Gemini adapter 或 T7 skill 封装。
