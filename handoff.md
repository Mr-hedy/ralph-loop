# 当前目标与约束

- 下一轮目标：按 `task.md` 顺序执行 T2.0 → T2.6（Claude adapter 全套），从 T2.0「依赖校验框架」开工。
- 约束：事实源以 `docs/requirements/ralph-loop/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/integrations.md`、`docs/architecture/security.md` 为准；`task.md` 是当前开发任务事实源（T2 7 个任务，T1 已勾的内容已清空，新一轮的 7 个任务全为未勾）；跨任务稳定决策必须沉淀到稳定文档（PM-0002）。

# 当前阶段与范围

- 阶段：T2 准备阶段已完成（拆解 + 沉淀 + adversarial review + 修复），T2.0 尚未开工。
- 影响模块（T2 待落地）：
  - 代码：`.ralph/lib/common.sh`（依赖框架）、`.ralph/lib/adapter-claude.sh`（新建）、`.ralph/lib/run.sh`（init_meta 顺序、依赖框架接入）、`.ralph/lib/session.sh`（`update_meta_jq`）、`.ralph/bin/ralph`（`--version` / `--help` 补全）
  - 测试：`tests/fixtures/mock-claude`（新建，单一来源）、`tests/fixtures/claude-session-sample.jsonl`（T2.4 fixture）、`scripts/integration-test.sh`（新增 ≥15 用例，PASS 14 → ≥33）
  - 文档：`docs/architecture/overview.md`（伪代码同步）、其他 docs 按真实 smoke 偏差补丁
- 变更类型：代码 + 测试 + 少量文档补丁。

# 稳定决策

T2 阶段（本轮已沉淀，下一轮不重新讨论）：
- **依赖校验框架**：`ralph_require_cmd` + `ralph_report_missing_deps` + `provider_check_deps` 三件套；min_version 参数预留但本期不实现；`ralph doctor` / 版本检查后置（`docs/roadmap.md` Deferred 段）。
- **Session 文件命名约定**：统一 `session.<provider>.*` 前缀，Claude stdout 命名 `session.claude.stdout.json`（沉淀于 `docs/architecture/integrations.md` 「Session 文件命名约定」段）。
- **meta.json 复杂字段写入**：用 jq `update_meta_jq` 原地重写，禁用 sed 拼装对象（避免引号/嵌套边界问题）。
- **mock-claude 单一来源**：`tests/fixtures/mock-claude` 由 T2.1 建立骨架 + happy 场景，T2.5 在同一文件扩展全场景，不另起炉灶。
- **测试基础设施单一来源 + 隔离**：`setup_claude_workspace` helper 由 T2.2 建立，T2.5 扩展不重建；强制 HOME 隔离（避免污染 `~/.claude/projects/`）+ PATH 隔离（修改限定在 `ralph run` 子进程，harness 外层不变）；规则沉淀于 `.spec/rules/testing.md` 「测试隔离规则」+「测试基础设施单一来源」两段。
- **cwd_hash 严格步骤顺序**：先 `realpath` 解 symlink → 再字符替换为 `-`；写反对 symlink workspace 算错且无报错（PM-0002 防偏离锚点）。
- **Provider 默认值约定**：当前开发阶段 `.ralph/.env` 默认 `RALPH_PROVIDER=fake`；T2.0 / T2.1 测试用例显式 `RALPH_PROVIDER=fake`；T2.2-T2.5 用 `RALPH_PROVIDER=claude` + mock-claude；T2.6 真实 Claude smoke。
- **状态/手册命令未实现行为统一**：`ralph status` / `ralph watch` 无 flag 时改为输出占位 help + 退出 0（不再 exit 1 报错），统一专业行为；`ralph --version` / `-v` 由 T2.6 新增。
- **派生视图 schema**：严格遵循 `docs/architecture/overview.md` 派生视图段既有定义（chat.log 三类带 timestamp + tool-result 截 2000 字；tools.log 每行 `<ts> <tool> <brief_in> <brief_out>`），不自定义。

继承自 T1 的稳定决策（不重述）：adapter 三函数契约、退出原因 7 种、macOS 兼容（PM-0001）、`set -euo pipefail` 防御、approval/sandbox 写死、per-workspace 部署、每轮 fresh oneshot。

# 已完成工作

本轮（T2 准备阶段，工作区改动尚未提交）：
- `task.md` 全量重写：T2.0–T2.6 共 7 个任务，每个含目标 / 范围 / 实施步骤 / 验证计划 / 不做 / 参考；顶部规则段加跨任务决策沉淀强制。
- `docs/architecture/overview.md`：运行时伪代码段把 `command -v RALPH_PROVIDER_CLI` 替换为 `check_dependencies`。
- `docs/architecture/integrations.md`：新增「Session 文件命名约定」段（沉淀跨 provider 命名规则）。
- `.spec/rules/testing.md`：新增「测试隔离规则」+「测试基础设施单一来源」两段。
- `docs/postmortems/pm-cross-task-decision-sedimentation.md`：新建 PM-0002，记录"跨任务决策未沉淀到稳定文档"meta-pattern + 4 类典型表现 + 预防机制。
- `docs/postmortems/README.md`：加 PM-0002 索引行。
- `docs/roadmap.md`（前序已落地）：新增 Deferred 段，登记 `ralph doctor` + provider 版本检查后置 v0.2/T7。

# 最新验证

- 命令：`bash scripts/check.sh && bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`check.sh` → `ralph-loop check passed`；`integration-test.sh` → `PASS=14 FAIL=0`（T1 14 用例全绿，无回归）

# 已验证与未验证

- 已验证：所有文档 / 协作规则改动通过 `scripts/check.sh`；T1 集成测试无回归（PASS=14 FAIL=0）；`git diff --check` 无空白错误。
- 未验证：T2.0–T2.6 任何代码（尚未实现）；真实 Claude CLI smoke（T2.6）；`tests/fixtures/mock-claude` 行为；HOME / PATH 隔离机制（T2.0 / T2.2 实施时验证）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：上一锚点 `889977b` / `docs/checkpoints/2026-04-24-03-t1-done.md`（T1 完成）。本轮准备工作的 checkpoint 待用户在本 handoff 后通过 `/checkpoint` 创建。
- Postmortem：本轮新增 PM-0002 `docs/postmortems/pm-cross-task-decision-sedimentation.md`（跨任务决策沉淀机制）；命中并扩展引用 PM-0001（macOS 兼容仍是 T2 shell 代码硬约束）。

# 工作区状态

- 分支：`main`，**有未提交变更**（待用户 `/checkpoint` 提交）：
  - 修改：`.spec/rules/testing.md`、`docs/architecture/integrations.md`、`docs/architecture/overview.md`、`docs/postmortems/README.md`、`docs/roadmap.md`、`task.md`
  - 新增：`docs/postmortems/pm-cross-task-decision-sedimentation.md`
- 最近 commit：`1f74b69 Clean session close: refresh handoff for T2 start`（上一会话结束）。
- 无额外 worktree。

# 建议下一步

1. 创建 T2 开始 checkpoint（`/checkpoint`），把本轮准备工作落仓，作为 T2 实施的回滚锚点。
2. 进入 T2.0：实现依赖校验框架（`ralph_require_cmd` / `ralph_report_missing_deps` / fake `provider_check_deps` / run.sh 接入 / overview.md 伪代码同步 / integration-test.sh 断言改 + 3 用例）。完成后 macOS 实测 `bash scripts/check.sh && bash scripts/integration-test.sh` 全绿。
3. T2.0 完成后按 task.md 顺序推进 T2.1（Claude adapter 骨架 + mock-claude 单一来源建立）。

# 交接摘要

T2 准备阶段（任务拆解 + 横切设计 + adversarial review + 沉淀文档 + PM-0002）已完成并验证；工作区有 7 个未提交文件等待 checkpoint。下一轮**先 `/checkpoint` 落仓**，然后从 T2.0「依赖校验框架」开工，严格按 `task.md` 7 任务顺序，所有跨任务约定通过 `docs/architecture/*` 和 `.spec/rules/testing.md` 锚点找回，不在对话里重新讨论。
