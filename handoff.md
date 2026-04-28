# 当前目标与约束

- 下一轮目标：T2 全部完成，等待用户决定 T3（Codex adapter）、T4（Gemini adapter）、T5（status/watch）或其他方向。
- 约束：事实源以 `docs/requirements/ralph-loop/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/integrations.md`、`docs/architecture/security.md` 为准；`task.md` 当前阶段 T2 所有子任务已勾；跨任务稳定决策沉淀于 `docs/architecture/*`（含 PM-0002）。

# 当前阶段与范围

- 阶段：**T2 — Claude Adapter 全部完成**，等待进入 T3/T4/T5。
- 影响模块（已落地）：
  - 代码：`.ralph/lib/common.sh`（依赖框架）、`.ralph/lib/adapter-claude.sh`（新建，四函数契约 + 派生视图）、`.ralph/lib/adapter-fake.sh`（`provider_check_deps` 接入）、`.ralph/lib/run.sh`（init_meta 顺序、依赖框架接入、timeout 路径 collect/diagnose、changed_files 写 meta）、`.ralph/lib/session.sh`（`update_meta_jq`、`capture_status` 默认 `pending`）、`.ralph/bin/ralph`（`--version` / `--help` / status 占位 help）
  - 测试：`tests/fixtures/mock-claude`（全场景）、`tests/fixtures/claude-session-sample.jsonl`（真实 schema）、`scripts/integration-test.sh`（PASS=34）
  - 文档：`docs/architecture/testing.md`（覆盖表更新至 T2.6，总 34 用例）
- 变更类型：代码 + 测试 + 文档补丁。
- **工作区未提交**：T2 全部改动在工作区，checkpoint 在本次 handoff 后由 `/checkpoint` 创建落仓。

# 稳定决策

T2 阶段（本轮已落地 + 沉淀，下一轮不重新讨论）：

- **依赖校验框架**：`ralph_require_cmd` + `ralph_report_missing_deps` + `provider_check_deps`；min_version 预留不实现；`ralph doctor` 后置 Deferred。
- **Session 文件命名约定**：`session.<provider>.*` 前缀；Claude stdout → `session.claude.stdout.json`；JSONL → `session.claude.jsonl`（沉淀于 `docs/architecture/integrations.md`）。
- **meta.json 复杂字段写入**：用 `update_meta_jq`（jq tmp+mv），禁止 sed 拼装对象；`capture_status` 默认 `pending`（在 collect 后升 ok/warning），不提前写 ok。
- **mock-claude 单一来源**：`tests/fixtures/mock-claude`，T2.1 骨架，T2.5 全场景扩展，不另起炉灶。
- **测试隔离**：HOME 隔离（独立 tmpdir/home 替代 `~/.claude/projects/`）+ PATH 隔离（修改限定在 `ralph run` 子进程）；规则在 `docs/architecture/testing.md`。
- **cwd_hash 严格步骤顺序**：先 `realpath` → 再字符替换；顺序写反会静默算错（PM-0002 锚点）。
- **真实 Claude JSONL schema**：tool_result 封装在 `type:"user"` 消息，内层 content 为字符串（非数组、非 `type:"tool"`）；派生视图 `_claude_derive_chat` / `_claude_derive_tools` 已按此修正；fixture/mock-claude 同步。
- **timeout 路径**：kill+wait 后必须调 `provider_collect_session` + `provider_diagnose`（否则 capture_status 留 pending）。
- **5xx 正则**：word-boundary `(^|[^0-9])5[0-9][0-9]([^0-9]|$)`，避免误匹配"500ms"；api error / internal server / service unavailable 明确字符串匹配。
- **ARG_MAX 防护**：prompt_file >900KB 时报错退出，不静默截断。

继承自 T1 的稳定决策：adapter 三函数契约、退出原因 7 种、macOS 兼容（PM-0001）、`set -euo pipefail`、approval/sandbox 写死、per-workspace 部署、每轮 fresh oneshot。

# 已完成工作

T2.0 — T2.6 全部落地（2026-04-27 ~ 2026-04-28）：

- **T2.0**：`ralph_require_cmd` / `ralph_report_missing_deps` in `common.sh`；fake `provider_check_deps`；`run.sh` 依赖阶段接入，删除原 `command -v RALPH_PROVIDER_CLI` 检查；3 个集成测试用例。
- **T2.1**：`adapter-claude.sh` 骨架（`provider_oneshot` 完整实现）；`update_meta_jq` in `session.sh`；`run.sh` init_meta 提前；`mock-claude` 单一来源建立（happy 场景）；1 个集成测试用例。
- **T2.2**：`provider_collect_session` 完整版（精确匹配 → mtime 降级 → warning）；`setup_claude_workspace` helper；3 个集成测试用例。
- **T2.3**：`provider_diagnose` + `_claude_classify_error` 六分类；`run.sh` last_error 读 meta error.message；6 个集成测试用例。
- **T2.4**：`_claude_derive_chat` / `_claude_derive_tools`；`claude-session-sample.jsonl` fixture；chat/tools 正常 + warning 用例。
- **T2.5**：`mock-claude` 全场景扩展（is_error_auth/rate/quota/api/concurrency/crash/missing_session/mtime_fallback）；2 个集成测试用例；总 PASS=30。
- **T2.6**：`ralph --version / -v / --help / run --help / help <cmd>`；status/watch 占位 help exit 0；4 个集成测试用例；真实 Claude smoke（run_id `20260427-121516-ef055eb`，exit_reason=done，capture_status=ok）；PASS=34。
- **Adversarial review 修复（T2 结尾）**：
  - `capture_status` 默认 `pending`（session.sh）
  - timeout 路径补 collect/diagnose（run.sh）
  - `changed_files` 写入 meta.json（run.sh）
  - 5xx 正则 word-boundary + api error 字符串收窄（adapter-claude.sh）
  - ARG_MAX 900KB 防护（adapter-claude.sh）
  - fixture/mock-claude JSONL schema 修正（`type:user`）
  - chat/tools `! grep '\[thinking\]'` 断言（integration-test.sh）

# 最新验证

- 命令：`bash scripts/check.sh && bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`check.sh` → `ralph-loop check passed`；`integration-test.sh` → **PASS=34 FAIL=0**（含 T2.6 schema 修正后，含 `! grep '\[thinking\]'` 断言）

# 已验证与未验证

- 已验证：T2.0–T2.6 全部集成测试 PASS=34 FAIL=0；真实 Claude smoke 端到端；`git diff --check` 无空白错误；`bash -n` 所有 `.sh` 文件语法检查通过。
- 未验证：T3（Codex adapter）、T4（Gemini adapter）、T5（status/watch）——尚未实现；多条 task TASKS.md 长链路（T6 范围）；prompt >900KB 的 ARG_MAX 真实触发路径；2000-char tool-result 截断未有专项测试用例（已知 v0.1 限制）；stagnation 检测可被 untracked file 写入绕过（已知 v0.1 限制）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：T2 完成 checkpoint 在本次 handoff 后通过 `/checkpoint` 创建（尚未落仓）。上一锚点：`889977b` / `docs/checkpoints/2026-04-24-03-t1-done.md`（T1 完成）。
- Postmortem：PM-0001（macOS compat，T2 shell 代码强约束）、PM-0002（跨任务决策沉淀，本轮新建）均已命中并引用。本轮无新 postmortem 需要创建。

# 工作区状态

- 分支：`main`
- 工作区：有未提交文件（T2 全量改动）
  - Modified: `.ralph/bin/ralph`、`.ralph/lib/adapter-fake.sh`、`.ralph/lib/common.sh`、`.ralph/lib/run.sh`、`.ralph/lib/session.sh`、`docs/architecture/testing.md`、`scripts/integration-test.sh`、`task.md`
  - Untracked: `.ralph/lib/adapter-claude.sh`、`tests/`
- 最近 commit：`2179c76 docs/testing: add T2.4 row to coverage table`（T2 改动均未提交）
- 无额外 worktree。

# 建议下一步

1. `/checkpoint` 创建 T2 完成锚点，把全量 T2 改动提交落仓。
2. 和用户确认 T3 方向（Codex adapter）或 T5（status/watch）还是其他优先级。
3. 进入下一阶段时先读 `task.md` → `docs/roadmap.md` → 对应 `docs/architecture/` 文档。

# 交接摘要

T2（Claude Adapter）已全部完成并通过 PASS=34 验证，包含 adversarial review 修复；工作区改动未提交，需先 `/checkpoint` 落仓再进入下一阶段。
