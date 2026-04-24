# 目标与约束

- 保留 Ralph v0.1 T1 开工前契约对齐完成、实际 `.ralph/lib/` 代码动工前的稳定锚点。
- 承接 `docs/checkpoints/2026-04-24-01-t1-ready.md`；本 checkpoint 叠加了"T1 9 步拆解 + adversarial review 四项契约修正"，未来若回退到 T1 规划阶段应以本 checkpoint 为起点比对，不要退回 01。

# 范围

- 当前任务拆解：`task.md`。
- 架构契约对齐：`docs/architecture/overview.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/roadmap.md`。
- 会话续接：`handoff.md`。

# 核心变更

- T1 任务拆解：把"T1：实现 ralph run 骨架 + adapter 契约 + fake adapter"在 `task.md` 中细化为 9 步实施清单（common.sh 基础 → common.sh 运行时 → tasks.sh → session.sh → adapter-fake.sh → run.sh → ralph bin → integration-test.sh → check.sh 补充），给每步绑定交付边界。
- Adversarial review 四项必须修复，全部落到事实源：
  1. `api-error` 场景语义冲突：原 task.md "api-error → provider_failed" 与架构 "provider_failed = provider CLI 退出码非 0" 冲突（`is_error:true + exit 0` 不退循环）。重新定义 `api-error` 为"exit 非零 + stderr 含 api 错误关键字"，同时触发 `provider_failed` + `last_error.type=api`；同步 `overview.md` 待落实段 + `roadmap.md` T1 段。
  2. Fake 场景不足覆盖 7 退出原因：补 `slow` 场景（`RALPH_FAKE_SLEEP` 驱动 `timeout` 用例），`max_iterations` 用 `happy` + `--max-iter=1` + 多 TASK 触发；fake 共 5 场景（happy / stagnation / crash / api-error / slow）。
  3. Provider CLI 校验与 fake 冲突：新增 adapter 契约条款——adapter 载入后必须定义全局变量 `RALPH_PROVIDER_CLI`，`run.sh` 用它做 `command -v` 校验，消除 provider 名到 CLI 名的硬编码耦合；fake 默认设为 `bash`，接受 `RALPH_FAKE_CLI` 覆盖。同步 `overview.md` adapter 契约段 + 伪代码 validate 行 + `requirements.md` BPF-002。
  4. Claude UUID 三路全失败难以在集成测试中可靠模拟：加 `RALPH_UUID_FORCE_FAIL=1` 测试钩子作为启动校验失败用例触发机制。
- 固定契约补充：启动校验 stderr 前缀 `ralph: startup check failed:`；主循环 `rc=0; provider_oneshot ... || rc=$?` 以免被 `set -euo pipefail` 中断；`trap SIGINT/SIGTERM` 按 lock 前 / lock 后分派 `interrupted`。
- `handoff.md` 刷新：稳定决策段列出 T1 实施契约全量，下一轮开工点指向 `common.sh` 基础扩展，明确"不要再改 docs 或 task.md 的 T1 契约"。

# 影响文件或模块

- 新增：`docs/checkpoints/2026-04-24-02-t1-scope-refined.md`。
- 修改：`task.md`（T1 拆解 + 契约修正）、`docs/architecture/overview.md`（adapter 契约 + 伪代码 + 待落实）、`docs/requirements/ralph-loop/requirements.md`（BPF-002）、`docs/roadmap.md`（T1 fake 五场景）、`handoff.md`（稳定决策 + 下一步）。
- 不变：`.ralph/bin/ralph` 仅 `help` 路由；`.ralph/lib/common.sh` 基础函数；`scripts/check.sh` 结构性断言；`.ralph/lib/{run.sh,tasks.sh,session.sh,adapter-fake.sh}` 仍未创建（T1 实施范围）。

# 稳定决策

- T1 实施契约（本 checkpoint 前后冻结）：
  - Adapter 契约 = 三函数（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`）+ 全局变量 `RALPH_PROVIDER_CLI`；run.sh 不做 provider 名到 CLI 名的硬编码映射。
  - Fake 五场景：`happy` / `stagnation` / `crash` / `api-error`（exit 非零 + api 关键字）/ `slow`（`RALPH_FAKE_SLEEP`）。
  - 测试钩子：`RALPH_UUID_FORCE_FAIL=1` 触发 UUID 三路校验失败；`RALPH_FAKE_CLI` 覆盖 `RALPH_PROVIDER_CLI`。
  - 启动校验顺序：PROMPT.md → TASKS.md → .env（含 `RALPH_PROVIDER`） → `.git/` → `command -v "$RALPH_PROVIDER_CLI"` → （仅 claude）UUID 三路；固定 stderr 前缀 `ralph: startup check failed:`，首个失败立即退出。
  - 主循环对 adapter 非零返回用 `rc=0; ... || rc=$?` 捕获；`trap SIGINT/SIGTERM` 按 lock 前 / 后分派。
- 退出原因 7 种、Claude 白名单 `Bash,Read,Edit,Write,Glob,Grep`、approval/sandbox 写死、per-workspace 部署、`.env` 只读 `RALPH_*` 不 `source`、每轮 fresh oneshot 等 22 条决策继承自 01-t1-ready，不再重述。

# 验证结果

- 命令：`bash scripts/check.sh`
- 结果：通过（`ralph-loop check passed`）
- 诊断：文档结构、`.ralph/bin/ralph help`、`docs/architecture/{overview,integrations,security}.md` 存在性、`docs/ralph` 不存在均通过；修改后 grep 未发现 `command -v <provider>` 旧措辞残留，`api-error → provider_failed` 冲突已消除。`git diff --check` 未跑（纯文档文本修订，无冲突标记风险）。

# Postmortem Sweep

- 结果：无需要新增。
- 关联：无。
- 说明：本轮 adversarial review 发现的四项冲突（api-error 语义、fake 场景不足、CLI 校验硬编码、UUID 测试钩子缺失）都是 T1 契约从"需求层抽象描述"落到"可执行测试编排"时一次性显式化的设计间隙，属于 review 质量门正常产出；已在同一会话内沿 `.spec/rules/adversarial-review.md` 修正并同步事实源，不构成可复用 agent 行为失败模式，不沉淀为 postmortem。

# 未验证范围与风险

- 所有 T1 代码路径（`common.sh` 扩展 / `run.sh` / `tasks.sh` / `session.sh` / `adapter-fake.sh` / `.ralph/bin/ralph run`）均未实现；`scripts/integration-test.sh` 未创建；13 用例（7 退出原因 + 6 启动校验）尚未跑通。
- 可观察风险：lock 获取前 `interrupted` 竞争窗口在集成测试中难稳定复现，T1 仅强测 lock 后分支，前分支接受为可观察风险。
- `docs/architecture/testing.md` 仍缺，计划在 `scripts/integration-test.sh` 成形后沉淀。

# 下一步

- 按 `task.md` T1 实施步骤 1 启动：`.ralph/lib/common.sh` 基础扩展（workspace 自定位 / `load_env` / UUID 生成 + `RALPH_UUID_FORCE_FAIL` 钩子 / 时间戳 / run_id），完成后 `bash -n` + 小范围验证再进步骤 2（flock / changed_files / JSON emit）。
- 直到 `bash scripts/integration-test.sh` 13 用例全绿后才勾选 T1；勾选时更新 `handoff.md` 指向 T2（Claude adapter），按需再创建新 checkpoint。
