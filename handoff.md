# 当前目标与约束

- 目标：完成 Antigravity CLI（`agy`）接入 Ralph-Loop 协作脚手架（REQ-048 ~ REQ-053），实现 headless oneshot 驱动、流式事件监听、Native Transcript 安全采集与人话历史派生。
- 用户边界：本次执行不使用 `ralph-loop` 自举，直接由 Agent 按任务清单执行；保留 2026-09-14 历史遗留任务（DEV-4、QA-2、DEV-6、DEV-7、REQ-033）不做修改。
- 交付范围：适配器 `.ralph/lib/adapter-antigravity.sh`、主循环与事件过滤器、集成测试回归门 QA-3、核心架构/安全/集成/测试文档、`release/0.1.5` 发布单元（`release/0.1.4` 保持不可变历史归档）与真实环境 QA-4 隔离 smoke。

# 当前阶段与范围

- 阶段：Antigravity CLI 接入、`release/0.1.5` 真实隔离烟测及 Codex 后续审查修复已完成；准备提交源码、核验发布包并提交发布产物。
- 影响：`.ralph/` 核心脚本、`release/0.1.5/` 发布单元、`release/0.1.4/` 历史归档、`tests/fixtures/mock-antigravity`、`scripts/` 校验与构建脚本、`docs/` 核心文档与 `README.md`。
- 变更类型：新增 provider adapter、扩展 stream-json 事件过滤器、新增集成测试与测试替身、补齐架构与安全契约、升级版本号至 0.1.5 并生成 release 0.1.5 交付包。

# 稳定决策

- **执行模式**：Antigravity 使用 fresh oneshot headless 模式（`agy --print "$prompt" --output-format stream-json --dangerously-skip-permissions`），重定向采用共用文件描述符 `> "$log_path" 2>&1`，防止 stdout/stderr 交错写入覆盖。
- **事实源与容错**：`provider.stdout.log` 作为第一事实源（primary source of truth）；原生 transcript（`~/.gemini/antigravity-cli/brain/<session_id>/...`）按 `conversation_id` 强校验单一标识段（`^[a-zA-Z0-9_-]+$`）；通过规范化 `brain` 根目录物理路径核对会话目录身份，复制目标必须核验为非空普通文件。
- **终态与退出码严格一致**：凡 `res_status != "SUCCESS"`、存在 `denied_actions` 软拒绝或存在结构化 `error`（非空对象或非空字符串）时，强制提升 `rc=1`（REQ-029 / REQ-051），绝不放行至 `done`；已知错误写为 `terminal_status="error"`，未知状态写为 `terminal_status="unknown"`，诊断写入 `meta.json.error`。
- **符号链接安全防护**：新增 `_antigravity_safe_session_file` 函数，校验会话目录真实物理路径严格等于 `$real_brain/$session_id` 且非软链接，同时校验真实文件物理路径位于规范会话目录内且非软链接，彻底杜绝会话目录（`brain/current -> brain/other`）和文件软链接跨会话偷采。
- **错误解析双模兼容**：兼容解析对象和纯字符串形态的 `.result.error`，确保真实上游错误不导致 jq 崩溃。
- **配置隔离拦截**：Antigravity 暂无独立配置目录参数，显式设置 `RALPH_PROVIDER_CONFIG_DIR` 时在启动校验阶段直接报错退出（exit 1），防止未隔离运行。
- **发布不可变契约**：发布包遵循不可变原则（已有 `release/0.1.4/` 保持原状历史归档），新特性发布通过官方 `scripts/build-release.sh` 升级生成全新的 `release/0.1.5/`。

# 已完成工作

- `[x] DEV-8`：探查 Antigravity 会话落盘结构，建立单一来源测试替身 `tests/fixtures/mock-antigravity`，覆盖 10 种仿真场景并纳入静态检查。
- `[x] DEV-9`：实现 `.ralph/lib/adapter-antigravity.sh`，实现 4 大函数契约（`provider_check_deps`、`provider_oneshot`、`provider_collect_session`、`provider_diagnose`），支持多目录（IDE/CLI）智能 fallback 与流式日志人话派生。
- `[x] DEV-10`：更新 CLI 入口 `.ralph/bin/ralph`、`run.sh` 门禁放行 `antigravity`，并在 `run.sh` 与 `watch.sh` 扩展对 AGY NDJSON 事件的解析展示。
- `[x] QA-3`：在 `scripts/integration-test.sh` 增加 QA-3 专项回归测试（8 个测试用例全部 PASS），覆盖参数审计、0 误采、软拒绝、截断坏行容错与配置拦截。
- `[x] DEV-11`：将 adapter 与 mock 纳入 `build-release.sh` 与 `check.sh`；更新 `README.md`、`.ralph/README.md`、`docs/architecture.md`、`docs/integrations.md`、`docs/security.md` 与 `docs/testing.md`。
- `[x] QA-4`：在临时隔离 Git workspace 中调用系统真实 `agy 1.2.12` CLI 成功运行单任务并生成 commit（`2abb2b9`）；在干净目录部署 `release/0.1.4/.` 验证自包含性与可用性。
- `[x] REVIEW-2`：按 `.spec/rules/ADVERSARIAL-REVIEW.md` 结合复现得出 6 项审查问题，全面立项开展 FIX-1 ~ FIX-3 修复。
- `[x] FIX-1`：修复未知终态退出码提升（非 SUCCESS 强制 rc=1）、`session_id` 路径穿越校验与规范路径核验、重定向共用描述符 `2>&1`、纯字符串 error 事件解析兼容（jq 双模）与会话复制普通文件严格检查。
- `[x] FIX-2`：在 `mock-antigravity` 与 `integration-test.sh` 增加 5 组针对性回归测试（未知状态提升、路径穿越防护、字符串错误提取、交错写入保护、会话复制异常降级），全量测试提升至 169 项全部通过。
- `[x] FIX-3`：将版本号升级至 `0.1.5`，还原 `release/0.1.4` 归档，官方构建全新的 `release/0.1.5/`，收口 `docs/README.md` 与 `docs/requirements.md` 中的接入状态至“已确认/已支持”。
- `[x] FIX-4`：全面闭环 Codex 审查提出的所有边界与契约问题：
  1. 结构化错误判定：按错误字段结构（是否存在非 null 且 key 数 >0 的对象或非空字符串）判定 `has_error`，无论 `message` 是否为空，只要存在错误对象均置 `terminal_status="error"` 并提升 `rc=1`；在 `provider_diagnose` 增加对 `err_type` 的结构提取与空消息兜底处理，确保准确归类写入 `meta.json.error`；
  2. 会话目录/文件符号链接防御：新增 `_antigravity_safe_session_file` 函数，以规范化的 `brain` 根目录物理路径为基准（`realpath "$brain_dir"`），校验真实会话目录物理路径严格等于 `$real_brain/$session_id` 且非软链接，同时校验真实文件路径位于会话目录内，杜绝会话目录软链接（`brain/current -> brain/other`）和文件软链接跨会话偷采；
  3. 需求标准编号对齐：将自动化用例统一对齐到权威需求 `docs/features/antigravity-cli/requirements.md` 中的 `SC-051-1`（终态判定）与 `SC-050-1`（0 次跨会话误采）；
  4. 扩展 `mock-antigravity`（`typed_empty_message_error` 与 `symlink_session_dir`）并补齐 4 项防回归断言，全量集成测试达到 173 PASS / 0 FAIL；
  5. 清除文档中“待实施”残留，同步版本至 0.1.5 并重建校验 `release/0.1.5/`。
- Codex 2026-09-29 再审：修正 `run -v` 与 `watch` 在 AGY `SUCCESS` 携带错误或未知终态时显示 `✓ result` 的误导；新增 SC-051-1 双视图回归断言，并同步需求、方案、测试与交接文档的当前事实。

# 最新验证

- `bash scripts/check.sh`：待当前源码修复同步到 `release/0.1.5/` 后复验；上一候选包曾通过。
- `bash scripts/build-release.sh --verify`：待当前源码修复同步到 `release/0.1.5/` 后复验；上一候选包曾通过。
- `bash scripts/integration-test.sh`：通过，`PASS=174 FAIL=0`（覆盖终态、双视图展示、软拒绝、空消息错误、文件与目录软链接等场景）。
- `git diff --check`：通过，无空白异常。
- **Release 0.1.5 真实环境端到端部署验证（无 Mock 全链路实跑）**：
  - 在全新隔离 Git 测试工作区（`.tmp/real-agy-0.1.5-smoke`）部署 `release/0.1.5/.`，由系统真实登录的 `agy 1.2.13` 驱动 `ralph run` 执行。
  - **任务推进**：真实驱动 `DEV-1: 实现 string_utils.py 并完成单测验证`，`agy` 自动创建 `string_utils.py` 与 `test_string_utils.py`、执行 `python3 -m unittest -v`（2 tests ok）、按 `.spec/rules/TASKS.md` 规范将 `.ralph/TASKS.md` 打钩为 `[x]` 并补充完成/验证记录、自动创建 `.gitignore` 过滤缓存、自动提交 Git commit（`51c379c`）。
  - **Loop 终态**：任务全部勾选后，Ralph 自然收敛以 `exit_reason: done` 退出，退出码 0，耗时 1m19s。
  - **数据采集完备性**：会话 ID 为 `93dd7c2b-116a-444f-adf0-2ef7bc633652`，经 `_antigravity_safe_session_file` 规范根目录物理路径核验通过，成功采集到 33KB 原生 transcript（`session.antigravity.jsonl`），派生 11KB 结构化人类历史（`session.history.log`），`meta.json` 记录 `capture_status: "ok"`、`terminal_status: "success"`、`exit_code: 0`、精确变更文件与前后任务状态（`0/1 -> 1/1`）。

# 已验证与未验证

- 已验证：Antigravity adapter 代码与契约、事件流解析、错误诊断矩阵、174 项自动化回归测试、此前 `release/0.1.5` 候选包的独立隔离环境真实模型 smoke、Codex 审查发现的边界与安全问题修复。
- 未验证：当前事件展示修复后的发布包尚待重新生成与逐字节核验，未重复执行真实 AGY smoke；超长时间运行下的上游大模型配额耗尽处理未实测（QA-3 mock 已验证重试调度）。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无新建。
- Postmortem：已查阅既有 postmortems；本次捕获的所有设计与边界缺陷已沉淀为自动化集成测试（共 9 项针对性回归门），形成长效防回归机制。

# 工作区状态

- 分支：`main`。
- 源码和文档待首次提交；`release/0.1.5/` 待按最新源码重新生成并进行第二次提交。以 `git status` 为准确认提交状态。

# 建议下一步

- 完成二次 adversarial-review；提交源码与文档，重新生成并验证 `release/0.1.5/`，最后提交发布产物。
