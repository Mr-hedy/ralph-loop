# 当前目标与约束

- I1 dogfood 启动准备**已完成且通过真实 Claude smoke 验证**，等待 commit + checkpoint 后开始 T5 任务拆解。
- v0.1.1-dev：HUMAN-N 阻塞机制 + 任务前缀全大写强约束 + iteration 命名 + Provider 配置目录隔离（中立抽象）+ dogfood 模式切换（`.ralph/TASKS.md` 取代 root `task.md`）。
- 硬约束：root `task.md` 已封版（v0.1 历史），不再更新；新阶段统一用 `I` 前缀，I1 = dogfood T5（status + watch 真实功能）。

# 当前阶段与范围

- 阶段：I1 启动前置准备 + adversarial review fixes + 凭据隔离架构 — **已全部落地，未 commit**。
- 影响模块：`.ralph/`（PROMPT/TASKS/lib/bin）、`.spec/rules/`、`docs/`（requirements / architecture / roadmap / README）、`scripts/integration-test.sh`、`CLAUDE.md`/`AGENTS.md`、root `task.md`。
- 变更类型：代码 + 文档 + 测试 + 协议规范。

# 稳定决策

- **任务类型 8 类前缀**：REQ / SOL / ROADMAP / PLAN / DEV / QA / REVIEW（ralph oneshot 内 agent 执行）+ HUMAN（main agent 对话内人类协作）；前缀必须全大写英文，启动校验失败 exit 1。注：`PLAN-N` = 任务列表规划（trantor PLAN / sprint planning 同义）；`ROADMAP-N` = roadmap 阶段规划。
- **HUMAN-N 阻塞**：双重保险 — 工具层 hardcode 入口扫描 + exit 7（`blocked_by_human`）；PROMPT.md 强约束 agent 不勾不执行；解锁路径 = 普通 Claude Code 对话内人类与 main agent 协作勾选。
- **取消 SUMMARY.md**：信息已在 TASKS.md（任务事实）+ status.json（机器可读）+ 终端打印 + `exit-message.txt` 接力提示中分布；归档 = `cp .ralph/TASKS.md docs/requirements/ralph-loop/I<N>-FINAL-TASK.md`。
- **Iteration 命名**：`I<N>` 单调递增；`.ralph/TASKS.md` 顶部 `> 当前迭代: I<N>` blockquote 声明（ASCII 冒号），ralph 解析写入 `iteration_name` 字段。
- **Provider 配置目录隔离（中立抽象）**：`.env` 用 `RALPH_PROVIDER_CONFIG_DIR`，adapter source 时翻译为 provider 原生变量（Claude → `CLAUDE_CONFIG_DIR`；Codex/Gemini 在 T3/T4 落地时定义）；空值不 export（鲁棒性）；`.env` 加载支持 `~/` tilde 展开。
- **退出原因 8 种**：done / provider_failed / timeout / max_iterations / stagnated / locked / blocked_by_human(exit 7) / interrupted；启动校验失败 exit 1。
- **Escalation 两条路径**：A 路径 = `REVIEW-N [blocked-by <task>]`（ralph 内可解决）；B 路径 = HUMAN-N（需外部决策）；REVIEW 常规审查另一种格式 = `REVIEW-N: <对象> | review` 或 `| adversarial-review`，与 escalation 互斥。
- **agent-collab-kit 同步建议**已写在 `docs/requirements/ralph-loop/I1-design.md` 末尾，由用户拿去 kit 工程那边推进，本仓库不跟踪状态。

# 已完成工作

- 协议层：`.ralph/PROMPT.md` 重写（去样板自我矮化注释 + 8 类任务前缀 + HUMAN-N 段 + Escalation 两条路径 + REVIEW 两种格式 + TASKS.md 顶部声明格式约定 + exit code 表 + 前缀强约束）。
- 任务源切换：`.ralph/TASKS.md` 改为 dogfood 任务源（顶部 `> 当前迭代: I1`，四段结构）；hello world demo 挪到 `.ralph/TASKS.bak`；root `task.md` 顶部加封版 banner。
- 工具层：`.ralph/lib/tasks.sh` 加 `first_unchecked_task` / `is_blocked_by_human` / `parse_current_iteration` / `validate_task_prefixes`（启动校验全大写）；`.ralph/lib/run.sh` 加 HUMAN-N 入口扫描 + `_ralph_print_summary` 退出打印 + `iteration_name` 字段 + status.json/result.json 扩展；`.ralph/lib/common.sh` `load_env` 加 tilde 展开；`.ralph/lib/adapter-claude.sh` 加 `RALPH_PROVIDER_CONFIG_DIR → CLAUDE_CONFIG_DIR` 翻译（空值不 export）；版本号 `0.1.0` → `0.1.1-dev`。
- 文档同步：requirements.md（REQ-009 扩 + 新增 REQ-018/019/020/021/022 + SC-018-1/018-2/019-1/020-1/021-1/022-1/022-2 + §非目标 dogfood 修订）；architecture/overview.md 加 `blocked_by_human` 退出原因 + Iteration 协议段；architecture/integrations.md 加 Adapter 配置目录翻译契约段；architecture/security.md 加 tilde 展开例外 + Provider 凭据/配置目录隔离段；roadmap.md 加 T→I 编号约定 + dogfood Current State；`.spec/rules/roadmap.md` 加归档动作段；CLAUDE.md/AGENTS.md 任务类型路由 + iteration 归档约定；README.md exit_reason 7→8 + dogfood 入口 + `.env` 示例加 `RALPH_PROVIDER_CONFIG_DIR` 注释；docs/README.md 索引同步；`docs/requirements/ralph-loop/I1-design.md` 集中方案锚点（含 kit 同步建议）。
- 集成测试：`scripts/integration-test.sh` 49→52 用例（5 HUMAN-N + 3 前缀大写 + 3 tilde/翻译/空值鲁棒性）。

# 最新验证

- 命令：`bash scripts/check.sh && bash scripts/integration-test.sh`
- 结果：通过（check PASS，integration 52/52 PASS）
- 命令：临时 workspace 跑 `~/.claude-glm/` 真实 Claude RT1 + RT2 smoke
- 结果：
  - **T1 默认账号 done**：exit 0 / 4 轮 / 3/3 任务 / 67s
  - **T2 默认账号 HUMAN-N 拦截**：exit 7 / 0 iter
  - **RT1 ~/.claude-glm/ done**：exit 0 / 4 轮 / 3/3 任务 / 105s；session jsonl 落 `~/.claude-glm/projects/`，main agent 的 `~/.claude/projects/` 未被污染（CLAUDE_CONFIG_DIR 切换 100% 生效硬证据）
  - **RT2 ~/.claude-glm/ HUMAN-N 拦截**：exit 7 / 0 iter / `~/.claude-glm/projects/` 未含本次 session（未调 claude 硬证据）
- 诊断：v0.1.1-dev 在真实 Claude provider + 独立账号 config dir 下行为完全符合预期，无 regression。

# 已验证与未验证

- 已验证：内核 HUMAN-N 拦截、退出打印、status/result.json 字段扩展、前缀全大写校验、tilde 展开、adapter 翻译、空值鲁棒性、真实 Claude done 路径、真实 Claude HUMAN-N 拦截路径、`CLAUDE_CONFIG_DIR` 子进程继承生效（session 路径硬证据）。
- 未验证：真实 Claude 在面对**真实需求歧义**时是否主动写 HUMAN-N（需要刻意构造模糊任务才能触发，dogfood I1 中暴露）；多轮 dogfood 完整流程（HUMAN 触发 → 人介入 → 解锁 → 继续）；Codex / Gemini 翻译契约（T3 / T4 落地时实现）；Linux 用户的 `CLAUDE_CONFIG_DIR` 行为（macOS 用户已验证）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：尚无（本轮工作落地后立即创建本会话第一个 checkpoint）。最近已 commit 的稳定锚点：`docs/checkpoints/2026-04-28-06-v0.1-release.md`（commit `3e897b6 T6 done`）。
- Postmortem：本轮无新增、无更新；adversarial review 暴露的所有可观察风险已修复（M1/M2/M3 必须修复全过；O1-O7 已处理或接受；无系统性失败模式产生）。

# 工作区状态

- 分支：`main`
- 工作区：dirty（16 文件 modified + 2 文件 untracked），见 `git status -s`：
  - 协议/工具：`.ralph/{PROMPT.md,TASKS.md,bin/ralph,lib/{adapter-claude,common,run,tasks}.sh}`
  - 文档：`AGENTS.md`、`README.md`、`docs/{README.md,architecture/{integrations.md,overview.md,security.md},requirements/ralph-loop/requirements.md,roadmap.md}`、`.spec/rules/roadmap.md`、`task.md`
  - 测试：`scripts/integration-test.sh`
  - 新增：`.ralph/TASKS.bak`、`docs/requirements/ralph-loop/I1-design.md`
- 临时 workspace（不入仓，验证证据）：
  - T1: `/var/folders/.../ralph-i1-smoke-T1-XXXXXX.2um11tCbX7`
  - T2: `/var/folders/.../ralph-i1-smoke-T2-XXXXXX.kDG6Le1aa8`
  - RT1: `/var/folders/.../ralph-i1-rt1-glm-XXXXXX.SryIeZH4mv`
  - RT2: `/var/folders/.../ralph-i1-rt2-glm-XXXXXX.FJyCN0ggUz`
- main agent 的 `~/.claude/` 未被任何 smoke 污染（已验证）。

# 建议下一步

1. `/checkpoint` 创建本会话第一个 checkpoint，note 记录 I1 prep + adversarial fixes + provider config dir 抽象闭环。
2. commit 本轮全部变更（建议 message：`I1 prep + adversarial fixes + provider config dir abstraction`）。
3. （独立动作）拆解 T5 任务到 `.ralph/TASKS.md` 当前任务区，准备启动 I1 dogfood 第一次 `ralph run`。
4. （后置）把 `docs/requirements/ralph-loop/I1-design.md` 末尾的"对 agent-collab-kit 的同步建议"拿去 kit 工程推进 template 同步。

# 交接摘要

- I1 dogfood 启动前置已全部落地并经真实 Claude smoke 双路径验证（默认账号 + ~/.claude-glm/ 独立账号），核心证据 = session jsonl 路径切换硬证据；下一步只需 checkpoint + commit + T5 任务拆解，即可开始 dogfood 第一次 `ralph run`。
