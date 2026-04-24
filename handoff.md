# 当前目标与约束

- 当前目标：按 `task.md` T1 的 9 步实施清单开工；第一步是 `.ralph/lib/common.sh` 基础扩展（workspace 自定位 / `load_env` / UUID 生成 + `RALPH_UUID_FORCE_FAIL` 钩子 / 时间戳 / run_id）。
- 约束：事实源以 `docs/requirements.md`、`docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-016，BPF-002 使用 `command -v <provider-cli>`）、`docs/architecture/overview.md`（adapter 契约含 `RALPH_PROVIDER_CLI` 变量、fake 五场景、退出原因 7 种）、`docs/architecture/integrations.md`、`docs/architecture/security.md` 为准；`task.md` 为当前开发任务事实源。

# 当前阶段与范围

- 阶段：实现（T1）；需求、架构、集成和 fake 场景契约已冻结。
- 影响模块：`.ralph/bin/ralph`、`.ralph/lib/*.sh`（新增 `run.sh` / `tasks.sh` / `session.sh` / `adapter-fake.sh`，扩展 `common.sh`）、`scripts/integration-test.sh`（新增）、`scripts/check.sh`（补充 `bash -n` + integration-test 存在性断言）。
- 变更类型：代码 + 集成测试（不再改 `docs/` 结构）。

# 稳定决策

- 22 条需求决策 + T1 实施契约已固化，关键项：
  - 退出原因 7 种：`done` / `provider_failed` / `timeout` / `max_iterations` / `stagnated` / `interrupted` 写 `result.json`；`locked` 和 lock 获取前的 `interrupted` 不产生 run 目录、不写 `result.json`。
  - Adapter 契约 = 三函数（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`）+ 全局变量 `RALPH_PROVIDER_CLI`（adapter 载入时设定，run.sh 用它做 `command -v` 校验）。
  - Fake adapter 五场景：`happy` / `stagnation` / `crash` / `api-error`（exit 非零 + stderr 含 api 关键字）/ `slow`（`RALPH_FAKE_SLEEP`）。`RALPH_FAKE_CLI` 覆盖 `RALPH_PROVIDER_CLI`；`RALPH_UUID_FORCE_FAIL=1` 作为 UUID 校验测试钩子。
  - 启动校验顺序：PROMPT.md → TASKS.md → .env（+ `RALPH_PROVIDER` 非空） → `.git/` → `command -v "$RALPH_PROVIDER_CLI"` → （仅 `RALPH_PROVIDER=claude`）UUID 三路校验；stderr 固定前缀 `ralph: startup check failed:`，首个失败立即退出。
  - 主循环 adapter 调用统一 `rc=0; provider_oneshot ... || rc=$?`，避免被 `set -euo pipefail` 中断；`trap SIGINT/SIGTERM` 按 lock 前 / lock 后分派 `interrupted`。
  - approval/sandbox 写死在 adapter；Claude 白名单固定 `Bash,Read,Edit,Write,Glob,Grep`。
  - Per-workspace 部署；`.env` 路径写死 `.ralph/.env`、只读 `RALPH_*`、不 `source`；workspace 根由脚本路径决定，不接受 `--cwd`；每轮 fresh oneshot。
  - 集成测试 13 用例 = 7 退出原因 + 6 启动校验；mock workspace 在临时目录搭建。
- 本仓库不维护 `.ralph/PROMPT.md` / `.ralph/TASKS.md`；`docs/` 结构稳定，本轮不再动。

# 已完成工作

- 本轮（T1 启动前拆解 + adversarial review + 事实源对齐）：
  - `task.md`：把 T1 拆成 9 步实施清单，修掉 `api-error → provider_failed` 语义冲突（重新定义为 exit 非零 + api 关键字），补 `slow` 场景、`RALPH_PROVIDER_CLI`、`RALPH_UUID_FORCE_FAIL`、`RALPH_FAKE_CLI`、启动校验 stderr 前缀、13 用例触发编排。
  - `docs/architecture/overview.md`：adapter 契约段补 `RALPH_PROVIDER_CLI` 变量约定；伪代码 validate 行改成 `command -v "$RALPH_PROVIDER_CLI"`；"待落实" 段 fake 行为从 "第 N 轮模式" 改为五场景驱动，移除 `is_error:true` 旧语义痕迹。
  - `docs/roadmap.md`：T1 fake adapter 描述同步为五场景 + 场景→退出原因映射。
  - `docs/requirements/ralph-loop/requirements.md` BPF-002：`command -v <provider>` → `command -v <provider-cli>` 并注明来源。
- 保留：`.ralph/bin/ralph` 仅 `help` 路由；`.ralph/lib/common.sh` 仅基础函数；`scripts/check.sh` 覆盖结构性回归。

# 最新验证

- 命令：`bash scripts/check.sh`
- 结果：通过（`ralph-loop check passed`）
- 诊断：结构性检查、`.ralph/bin/ralph help` 入口、`docs/requirements.md` / `docs/architecture/{overview,integrations,security}.md` 存在性、`docs/ralph` 不存在均通过。
- 未覆盖：`ralph run` 主循环未实现；`scripts/integration-test.sh` 未创建；T1 13 用例均未跑。

# 已验证与未验证

- 已验证：结构性检查（`scripts/check.sh`）；事实源之间 `RALPH_PROVIDER_CLI` / fake 五场景 / `command -v` 措辞一致（本轮同步修改后 grep 无残留）。
- 未验证：`ralph run` 主循环、adapter 契约、7 种退出原因路径、启动校验 6 用例、fake 五场景行为、UUID 校验路径、lock 获取前 `interrupted` 竞争窗口（可观察风险）——均在 T1 实施范围。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无（本轮结束后按用户指令创建 T1 启动前 checkpoint，note + commit 未生成）。
- Postmortem：无。

# 工作区状态

- 分支：`main`（仓库仅有 `300b6b7 Bootstrap ralph-loop v0.1 docs and tool skeleton` 一次提交）。
- 未提交变更：`docs/architecture/overview.md` / `docs/requirements/ralph-loop/requirements.md` / `docs/roadmap.md` / `task.md`（本轮事实源对齐）；`handoff.md` 本轮刷新。
- 外部参考：`trantor-skills cli/lib/build.ts`、`frankbria/ralph-claude-code`（均为只读输入）。

# 建议下一步

- 先完成 checkpoint（提交当前 docs/task 修订，作为 T1 启动前回滚锚点）。
- 然后执行 T1 实施步骤 1：`.ralph/lib/common.sh` 基础扩展——workspace 自定位、`load_env`、UUID 生成（含 `RALPH_UUID_FORCE_FAIL` 钩子）、ISO8601 时间戳、run_id 生成。完成后 `bash -n` + 小 REPL 级验证，再进步骤 2（flock / changed_files / JSON emit）。
- 整个 T1 按 `task.md` 的 9 步自下而上堆契约，直到 `scripts/integration-test.sh` 13 用例全绿。

# 交接摘要

- 本轮只动了 `task.md` 和三份上游文档以对齐 T1 契约（`RALPH_PROVIDER_CLI` / fake 五场景 / `api-error` 语义 / stderr 前缀 / 测试钩子）；下一轮开工点是 `.ralph/lib/common.sh` 基础扩展，**不要再改 `docs/` 或 `task.md` 的 T1 契约**，除非实施中发现新冲突。fake scenario 是五（不是四），退出原因是七（不是六），adapter 契约除三函数外必须暴露 `RALPH_PROVIDER_CLI`。
