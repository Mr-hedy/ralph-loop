# 当前目标与约束

- T1（ralph run 骨架 + adapter 契约 + fake adapter）已完成，14 个集成用例全绿，代码经过两轮 adversarial review 并修复所有发现问题。
- 下一目标：创建 T1 完成 checkpoint（提交 + note），然后按 `docs/roadmap.md` 推进 T2（Claude adapter）或用户指定的下一个任务。
- 约束：事实源以 `docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-016）、`docs/architecture/overview.md`（adapter 契约、退出原因 7 种、stagnation）、`docs/architecture/integrations.md`、`docs/architecture/security.md` 为准；`task.md` 为当前开发任务事实源；T1 所有契约已冻结，不再调整。

# 当前阶段与范围

- 阶段：T1 完成，待 checkpoint 提交；T2 尚未开始。
- 影响模块（T1 新增 / 修改）：
  - `.ralph/bin/ralph`：`run` 路由 + flag 解析（`--provider/model/effort/max-iter/timeout`）
  - `.ralph/lib/common.sh`：扩展 workspace 自定位 / `load_env` / UUID 三路 fallback / 时间戳 / run_id / noclobber lock / `changed_files` / JSON emit helpers
  - `.ralph/lib/tasks.sh`：新增（`parse_tasks` / `count_checked` / `count_total`）
  - `.ralph/lib/session.sh`：新增（`init_meta` / `write_meta` / `update_meta_field`）
  - `.ralph/lib/adapter-fake.sh`：新增（五场景 + 三函数契约）
  - `.ralph/lib/run.sh`：新增（主循环 + 启动校验 + 退出分派 + result.json + status.json）
  - `scripts/integration-test.sh`：新增（14 用例）
  - `scripts/check.sh`：补充 `bash -n` + integration-test 存在性断言
  - `task.md`：T1 标记 `[x]`，填写完成 / 变更 / 验证 / 注意 / 参考 / 范围字段
- 变更类型：代码 + 集成测试。

# 稳定决策

- **退出原因 7 种**：`done`(0) / `provider_failed`(2) / `timeout`(3) / `max_iterations`(4) / `stagnated`(5) / `locked`(6) / `interrupted`(130)；`locked` 和 lock 前 `interrupted` 不产生 run 目录。
- **Adapter 契约**：三函数（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`）+ 全局 `RALPH_PROVIDER_CLI`（adapter source 时设定，run.sh 用于 `command -v` 校验）。
- **Fake 五场景**：`happy`（勾第 1 条 `- [ ]`） / `stagnation`（不改任何状态） / `crash`（exit 非零） / `api-error`（exit 非零 + log 含 `api` 关键字） / `slow`（`RALPH_FAKE_SLEEP` 秒 sleep）。
- **启动校验顺序**：PROMPT.md → TASKS.md → RALPH_PROVIDER 非空 → `.git/` → `command -v $RALPH_PROVIDER_CLI` → UUID（仅 `claude` provider）；stderr 固定前缀 `ralph: startup check failed:`；首个失败立即退出，不产生 run 目录。
- **macOS 兼容决策**：`flock` CLI 不可用 → noclobber + PID 文件锁；`date +%s%3N` 不可用 → `$(( $(date -u +%s) * 1000 ))`；SIGINT 在等待子进程时被 deferred → 集成测试用 SIGTERM（trap 同时处理 INT/TERM）。
- **`set -euo pipefail` 防御**：adapter 调用统一 `rc=0; provider_oneshot ... || rc=$?`；`changed_files` / `count_checked` 等管道末尾加 `|| true` 或变量捕获隔离 exit code。
- **空 / 全勾 TASKS.md**：主循环前预检，直接 `done` 退出，不产生 iteration。

# 已完成工作

- T1 全部 9 步实施完成（common.sh → tasks.sh → session.sh → adapter-fake.sh → run.sh → bin/ralph → integration-test.sh → check.sh 更新）。
- 两轮 adversarial review，累计发现并修复 7 个问题：
  1. `printf '- [ ] ...'` macOS 把 `-` 当 flag → 改 `printf '%s\n' "..."`
  2. `flock` CLI 不可用 → noclobber + PID 文件锁
  3. `count_checked` 双输出（`grep -c` exit 1 + `|| echo 0`） → 变量捕获隔离
  4. `date +%s%3N` macOS 不支持 → `*1000` 代替
  5. `grep -v '^\.ralph/'` 全过滤时 exit 1 导致主循环静默退出 → `|| true`
  6. `_ralph_write_status` 第 10 参数默认 `"null"` 导致 JSON 字符串而非 null → 改 `"${10:-}"`
  7. `api-error` 场景双写 log → 单写
  - 第二轮 review 另修复：空 TASKS.md 预检（Fix 2）、`latest_run_dir` 空目录安全（Fix 4）、删 session.sh 和 integration-test.sh 死代码（Fix 5）、`update_meta_field` 尾逗号 bug（用 `-E` + capture group 保留可选逗号）、删 `RALPH_BIN` 未使用变量。

# 最新验证

- 命令：`bash scripts/check.sh && bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`check.sh` → `ralph-loop check passed`；`integration-test.sh` → PASS=14 FAIL=0（7 退出原因 + 6 启动校验 + api-error 变体）

# 已验证与未验证

- 已验证：全部 14 个集成用例（7 退出原因 × 退出码 / result.json / run 目录存在性 + 6 启动校验 × stderr 前缀 / 无 run 目录）；`bash -n` 语法检查所有 lib 文件。
- 未验证：lock 获取前 `interrupted` 竞争窗口（窄竞争，列为可观察风险）；真实 provider adapter（T2–T4 范围）；`update_meta_field` 的 `-E` sed 在极端值（含 `|` 的字段名）下行为（当前无此用例）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无（T1 完成后尚未提交；本轮应创建 T1 完成 checkpoint）。最近 commit：`abfa69a Refine T1 scope and align adapter contract (checkpoint 02)`。
- Postmortem：无（无生产回归，macOS 兼容问题在实施中发现并即时修复，未单独立项）。

# 工作区状态

- 分支：`main`
- 未提交变更（git status）：
  - 修改：`.ralph/bin/ralph` / `.ralph/lib/common.sh` / `scripts/check.sh` / `task.md`
  - 未追踪（新增）：`.ralph/lib/adapter-fake.sh` / `.ralph/lib/run.sh` / `.ralph/lib/session.sh` / `.ralph/lib/tasks.sh` / `scripts/integration-test.sh` / `.agents/skills/task-loop/` / `docs/collaboration/`
- 无 stash，无 WIP 分支。

# 建议下一步

1. **创建 T1 完成 checkpoint**：提交所有 T1 新增 / 修改文件（见上方文件列表），commit message 标注 `T1 done`，在 `docs/checkpoints/` 写 note，更新 `docs/checkpoints/README.md`。
2. **确认下一阶段**：按 `docs/roadmap.md`，T2 为 Claude adapter（`adapter-claude.sh` + `--dangerously-skip-permissions` + approval 白名单）。询问用户是否开始 T2 或有其他优先任务。

# 交接摘要

T1 已 100% 完成并通过 14 个集成测试；工作区有大量未提交的 T1 实现文件，**下一步首先是 checkpoint 提交**，然后按 roadmap 推进 T2（Claude adapter）。不要重新实现或审查已经通过的 T1 代码。
