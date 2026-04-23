# 当前目标与约束

- 当前目标：实现 Ralph v0.1 的 T1——`ralph run` 骨架 + adapter 三函数契约 + fake adapter 集成测试。
- 约束：以 `docs/requirements.md`（项目级目标与跨模块约束）、`docs/requirements/ralph-loop/requirements.md`（REQ-001 ~ REQ-016）、`docs/architecture/overview.md`（CLI、运行目录、adapter 契约、退出码、方案取舍）、`docs/architecture/integrations.md`（provider 命令构造与 session 采集）和 `docs/architecture/security.md`（approval/sandbox 写死策略）为事实源；`task.md` 为当前开发任务事实源。

# 当前阶段与范围

- 阶段：实现（T1）。需求、架构和 provider 集成细节已冻结。
- 影响模块：`.ralph/bin/ralph`、`.ralph/lib/*.sh`（新增 `run.sh` / `tasks.sh` / `session.sh` / `adapter-fake.sh`，扩展 `common.sh`）、`scripts/integration-test.sh`（新增）。
- 变更类型：代码 + 集成测试。

# 稳定决策

- 22 条决策已固化，关键项：
  - 独立演进；trantor-skills 与 ralph-claude-code 仅输入参考。
  - 本仓库是 ralph 的开发工程，不自用 ralph。
  - Per-workspace 部署：使用者 workspace 自带 `.ralph/bin/` + `.ralph/lib/`；不支持全局 `ralph` 命令。
  - `.env` 路径写死 `.ralph/.env`，只读 `RALPH_*` 前缀；仅 `RALPH_PROVIDER` 必需，其他留空 = 不拼 flag。
  - 不接受 `--cwd`；workspace 根由脚本路径决定，ralph 启动时内部 `cd` 到根。
  - 每轮 fresh oneshot；不支持 resume。
  - 三 provider（Claude / Codex / Gemini）；adapter 契约 = 三函数（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`）。
  - 默认：`max_iter=0`、`timeout=0`、`stagnation_limit=5`。
  - 退出原因 7 种：`done` / `provider_failed` / `timeout` / `max_iterations` / `stagnated` / `interrupted` 写 `result.json`；`locked` 不产生 run 目录也不写 `result.json`；`interrupted` 在 lock 获取前触发时同样不产生 run 目录。
  - 启动校验清单：`PROMPT.md` / `TASKS.md` / `.env`（含 `RALPH_PROVIDER`） / git 仓库 / provider CLI 可执行；`RALPH_PROVIDER=claude` 时追加三路 UUID 可用性校验。
  - PROMPT 硬契约：一个 task 一个 oneshot。
  - approval/sandbox 写死在 adapter，不做开关；Claude 白名单固定 `Bash,Read,Edit,Write,Glob,Grep`。
  - `--effort=low|medium|high|none` 抽象，adapter 翻译。
  - Skill 封装排到 v0.1 之后（T7）。
- `docs/` 按 `.spec` 规范结构固化：`docs/requirements.md`（项目级）、`docs/requirements/ralph-loop/requirements.md`（模块级）、`docs/architecture/{overview,integrations,security}.md`、`docs/roadmap.md`；旧 `docs/ralph/` 已删除。
- 本仓库不维护 `.ralph/PROMPT.md`、`.ralph/TASKS.md`（使用者输入，非工具代码）。

# 已完成工作

- 本轮：按 `.spec` 规范重整理 `docs/`——新建 `docs/requirements.md` / `docs/architecture/overview.md` / `docs/architecture/integrations.md` / `docs/architecture/security.md`；删除 `docs/ralph/`；同步刷新 `docs/README.md` / `README.md` / `AGENTS.md` / `docs/roadmap.md` / `docs/requirements/ralph-loop/requirements.md` / `handoff.md` / `task.md` / `scripts/check.sh`。
- Adversarial review 修正 4 项：退出原因 6→7 对齐（REQ-012 / SC-012-1 / handoff / overview 表）；REQ-011 / SC-011-1 / BPF-002 追加 Claude UUID 校验；`integrations.md` Codex 错误诊断映射改写成四条互斥优先级；`task.md` T1 集成测试列出 13 个具体用例（7 退出原因 + 6 启动校验）。
- 既有骨架保留：`.ralph/bin/ralph` 仅 `help` 路由；`.ralph/lib/common.sh` 含基础函数；`scripts/check.sh` 覆盖结构性回归（已加 `docs/architecture/{overview,integrations,security}.md` 存在性与 `docs/ralph` 不存在断言）。

# 最新验证

- 命令：`bash scripts/check.sh`
- 结果：通过（`ralph-loop check passed`）
- 诊断：文档结构、`.ralph/bin/ralph help` 入口、`docs/requirements.md` / `docs/architecture/{overview,integrations,security}.md` 存在性与 `docs/ralph` 不存在检查通过。
- 未覆盖：`ralph run` 主循环未实现，无法端到端验证；T1 完成时需跑 `scripts/integration-test.sh`（尚未创建）。

# 已验证与未验证

- 已验证：结构性检查（`scripts/check.sh`）；文档相互引用路径一致（grep 全量路径替换后无残留 `docs/ralph/`）。
- 未验证：`ralph run` 主循环、adapter 契约、7 种退出原因路径、启动校验 6 用例、fake 场景驱动、UUID 校验路径（全部在 T1 范围内）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无（本轮结束后将创建 T1 启动前 checkpoint）。
- Postmortem：无。

# 工作区状态

- 分支：`main`（尚无提交，仓库未做初始 commit）。
- 未提交变更：全量（本仓库所有文件均为 untracked，含 `.agents/`、`.claude/`、`.ralph/`、`.spec/`、`docs/`、`AGENTS.md`、`CLAUDE.md`（→ AGENTS.md 符号链接）、`README.md`、`handoff.md`、`package.json`、`scripts/`、`task.md`）。
- 外部参考：`trantor-skills cli/lib/build.ts`（算法前身）、`frankbria/ralph-claude-code`（背景输入）；两者均为只读输入，不对标。

# 建议下一步

- 执行 T1：优先顺序为 `common.sh` 扩展（`.env` 解析 / workspace 自定位 / UUID fallback / flock / `git diff ∪ git status` 收集器） → `tasks.sh`（`parse_tasks` / `count_checked`） → `session.sh`（meta 读写骨架）→ `adapter-fake.sh`（`RALPH_FAKE_SCENARIO=happy|api-error|stagnation|crash`）→ `run.sh`（主循环）→ `.ralph/bin/ralph` 接 `run` 路由 → `scripts/integration-test.sh`（13 个用例）。
- 集成测试以 `task.md` T1 范围段的 13 用例清单为准，逐用例断言 `exit_reason`、`.ralph/runs/` 是否产生、`result.json` 是否存在。
- T1 完成后更新 handoff 指向 T2（Claude adapter）。

# 交接摘要

- 文档事实源刚按 `.spec` 规范完成重整理，路径已稳定；下一轮开工点是 `.ralph/lib/`，不要再改 `docs/` 结构或自举使用 ralph 驱动本仓库；退出原因是 7 种（不是 6 种），启动校验含 Claude UUID 条件项。
