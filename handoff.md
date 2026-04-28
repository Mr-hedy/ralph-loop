# 当前目标与约束

- 下一轮目标：执行 T6（v0.1 闭环验证 + 使用指南），按依赖顺序起手 T6.0（PROMPT.md + TASKS.md 参考样板入仓 `.ralph/`）。
- 硬约束：事实源以 `docs/requirements/ralph-loop/requirements.md`（含 REQ-017 / 轮次 4 ruling）、`docs/architecture/overview.md`、`docs/architecture/integrations.md`、`docs/architecture/security.md` 为准；`task.md` 当前阶段 T6 已拆 8 子任务（T6.0–T6.7），决策已落实文档不重新议；跨任务稳定决策仍按 PM-0002 沉淀（项目契约 → `docs/architecture/*`，方法论 → `.spec/rules/*`）。

# 当前阶段与范围

- 阶段：**T6 — v0.1 闭环验证 + 使用指南**（T2 已完成 commit `0cd99ab`；T3/T4/T5 后置）。
- 影响模块（本轮 prep 已落地）：
  - 文档：`AGENTS.md`（Project Identity 重申 ".ralph/ 整个目录是产物" + Top Rules 入仓清单）、`docs/requirements/ralph-loop/requirements.md`（轮次 4 narrative + REQ-017 + SC-017-1 + REQ-008 amend + §非目标 line 23 澄清）、`docs/roadmap.md`（T6 提前 + 阶段重排序决策段 + T6 范围段 + Current State）、`task.md`（替换 T2 块为 T6.0–T6.7 八个子任务，含全部决策）。
  - 部署单元：`.ralph/.gitignore` **删除**（部署单元自身不带运行期忽略规则）。
- 变更类型：纯文档 + 部署单元配置（删 .gitignore）；本轮**未改任何代码**（`.ralph/bin/` / `.ralph/lib/` 不动）。
- **工作区未提交**：本轮全部 prep 在工作区，等下个步骤 `/checkpoint` 落仓。

# 稳定决策

本轮新增（2026-04-28）：

- **REQ-017 交付单元 = `.ralph/` 整个目录**：含 `bin/` + `lib/` + 参考样板 `PROMPT.md` + `TASKS.md`；部署 `cp -r .ralph/ <workspace>/.ralph/` 一次性带走全部；运行期产物（runs/lock/status.json/.env）由使用者外层 `.gitignore` 管理。本仓库不自跑 ralph，故 `.ralph/` 不出现 runtime artifacts。
- **REQ-008 + REQ-017 边界**：REQ-008 改为引用 REQ-017 描述部署单元构成。
- **§非目标 line 23 边界澄清**："不提供 ralph init"约束的是 ralph 工具运行时**不**写 PROMPT/TASKS/.env、**不**读取它们做内核控制流；样板入仓由人工维护、由 `cp -r` 部署，不是 init 路径，两者并存。
- **阶段重排序**（roadmap）：T2 → T6（提前）→ T3 → T4 → T5 → T7。理由见 roadmap §阶段重排序决策。
- **T6 子任务依赖顺序**：T6.0 模板 → T6.1 stagnation 修 → T6.2 effort 接入 → T6.3 多轮 smoke → T6.4 边界复验 → T6.5 使用指南 → T6.6 v0.1 closure；T6.7 patch 池贯穿。
- **T6.1 stagnation 比对方案 = B（in-memory 哈希）**：`git ls-files -s` + `git status -z` 拼起来过 `sha256sum`；不写 `.git/refs/`、不创建 git 对象；事后"上轮改了什么"由独立 `meta.json.changed_files_iter` 字段满足。Rejected A（写 refs 偏重）/ C（创建 git 对象违契约）。
- **T6.4 stagnation 真触发用例**："等待用户在 .ralph/.env 加入 RALPH_MAGIC=1"等待型任务（最稳定），rejected"歧义任务"（Claude 可能 commit 澄清绕过）。
- **T6.4 timeout 真触发用例**：`Bash sleep 30` + `--timeout=10`（行为确定），rejected"5 万字文档"（Claude 可能拒绝/简化）。
- **adversarial review 暴露的 P0/P1 缺陷已独立为 T6.1/T6.2，不挂 T6.7**：
  - P0#1 stagnation 在长链路失效（cumulative changed_files 永远非空，stagnation_count 永远不++）→ T6.1 修
  - P0#2 `--effort` flag 在 `adapter-claude.sh` 完全没接入 → T6.2 修

继承自 T2 的稳定决策：adapter 三函数契约、退出原因 7 种、macOS 兼容（PM-0001）、`set -euo pipefail`、approval/sandbox 写死、每轮 fresh oneshot、依赖校验框架、Session 文件命名约定、cwd_hash 严格 realpath→hash 顺序、Claude JSONL tool_result schema、5xx 正则 word-boundary、ARG_MAX 900KB 防护。

# 已完成工作

T6 prep 全部落地（2026-04-28，未提交）：

- **roadmap 重排序**：T6 提前到 T2 之后；T1 范围段（已过期）删除；T6 范围段新增（覆盖需求 / 交付 / 退出条件 / 非范围）；Current State 同步至 T2 完成 + T6 当前阶段。
- **requirements 补丁**：轮次 4 narrative（交付单元 / 部署形态决策记录）；REQ-017 + SC-017-1 + 验收 traceability 行；REQ-008 amend；§非目标 line 23 澄清"用户自行创建"语义。
- **AGENTS.md（CLAUDE.md）改造**：Project Identity 加 "项目最终产物 = .ralph/ 整个目录"；Top Rules 把 PROMPT/TASKS 从"不入仓"清单移到"入仓样板"，明确 runs/lock/status.json/.env 由外层 .gitignore 处理。
- **task.md T2 段下线**（commit `0cd99ab` 已落仓 T2，task.md 不保留历史）；T6 段拆 8 子任务，全部决策落实文档：
  - T6.0：PROMPT.md + TASKS.md 入仓 `.ralph/`
  - T6.1：stagnation 语义修正（方案 B）+ per-iter changed_files
  - T6.2：`--effort` 接入 Claude adapter + SC-014-1 unit test
  - T6.3：3+ task 真实多轮 smoke + 证据保全到 checkpoint 草稿
  - T6.4：边界场景在真实 Claude 复验（等待型 stagnation / sleep timeout / max_iter）
  - T6.5：usage doc + 完整 TASKS demo + no-retry 提示 + workspace .gitignore 建议
  - T6.6：v0.1 closure（版本号 0.1.0-dev → 0.1.0 + 最终 checkpoint + handoff 刷新）
  - T6.7：patch 池（adversarial review 已知项已独立，不重复挂）
- **`.ralph/.gitignore` 删除**：部署单元自身不带运行期忽略规则。

# 最新验证

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：`ralph-loop check passed`；`grep "REQ-23"` 全清；`grep "REQ-017"` 在 task.md / roadmap / requirements 三方一致；本轮纯文档变更无代码改动，未跑 `bash scripts/integration-test.sh`（不必要）。

# 已验证与未验证

- 已验证：跨 doc coherence（CLAUDE.md / requirements / roadmap / task.md 互相一致）；REQ-017 + SC-017-1 + traceability 三方对齐；T6 子任务依赖顺序无环；adversarial review F1/F2/F3 三个缝合点全补；`bash scripts/check.sh` 通过；`git diff --check` 无空白错误。
- 未验证：T6.0–T6.7 任一子任务的实施成果（**这是下一轮的工作**）；`.ralph/PROMPT.md` 内容是否能让 Claude 真实跟住协议（T6.3 间接验证）；REQ-017 部署链路 `cp -r .ralph/ <workspace>/.ralph/` 在 workspace 外跑通（T6.3 实证 SC-017-1）；T6.1 stagnation 修后 fake adapter 现有用例是否回归（T6.1 内验证）；T6.2 effort 翻译数值（low/medium/high → thinking-budget=2000/8000/16000）是否符合当前 Claude CLI 合法范围（T6.2 实施时查 `claude --help` 确认）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：上一锚点 commit `0cd99ab` "T2 done: Claude adapter, integration tests, version/help, smoke"。本轮 prep checkpoint 在本次 handoff 后通过 `/checkpoint` 创建（**尚未落仓**）。
- Postmortem：**新增 PM-0003**（任务收口 adversarial review 缺乏 REQ traceability + 现实条件外推，导致 T2 漏检 stagnation cumulative bug + effort flag 漏接入）。命中并引用既有 PM-0001（macOS shell 兼容）、PM-0002（跨任务决策沉淀）。T6.1/T6.2 完成后回查 PM-0003 验证修复。

# 工作区状态

- 分支：`main`
- 工作区：有未提交文件（T6 prep 全量改动）
  - Deleted: `.ralph/.gitignore`
  - Modified: `AGENTS.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/roadmap.md`、`task.md`
  - Untracked: 无
- 最近 commit：`0cd99ab T2 done`（T2 全部改动已落仓）
- 无额外 worktree。

# 建议下一步

1. `/checkpoint` 创建 T6 prep 锚点，把 prep 全量改动 commit 落仓（含 .gitignore 删除）。
2. 进入下一会话起手 T6.0：起草 `.ralph/PROMPT.md`（≤120 行，参考 `/Users/hedy/Develop/code/trantor-project/trantor-skills/.trantor/build/PROMPT.md` 提炼但去 trantor 化）+ `.ralph/TASKS.md`（≤20 行 hello-world 起手示例）+ `docs/README.md` 索引。
3. 进入下一阶段时先读 `task.md` T6 段 → `docs/roadmap.md` T6 范围 → `docs/requirements/ralph-loop/requirements.md` 轮次 4 + REQ-017。

# 交接摘要

T6 prep 全部落地未提交（roadmap 重排序 + REQ-017 交付单元形式化 + T6 八子任务拆分 + adversarial review F1/F2/F3 修补）；本轮纯文档无代码改动；下一步 `/checkpoint` 落仓后从 T6.0 起草 `.ralph/PROMPT.md` + `.ralph/TASKS.md` 样板。
