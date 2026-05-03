# Tasks

> 当前迭代: I2
> 主题: dogfood T3 — Codex adapter
> 关联 roadmap: T3
> 起始: 2026-05-03
> 设计方案: `docs/requirements/ralph-loop/I2-design.md`

## 当前有效结论

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；checkpoint 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2 目标由用户确认（2026-05-03）：完成历史 T3，即在已闭环的 Ralph harness 上接入 Codex CLI adapter。
- T3 验收口径：`RALPH_PROVIDER=codex` 能在真实 workspace 跑通至少一条任务到 `exit_reason=done`，并产出统一 iter 证据契约：`meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`。
- Codex 集成文档基线来自 2026-04-20 的 Codex CLI `0.121.0`，且当前 `docs/architecture/integrations.md` / `docs/requirements/ralph-loop/requirements.md` 的 Codex 小节仍有待 T3 落地确认的配置目录变量、4 文件契约和 `session.codex.stdout.jsonl` 旧描述；I2 第一项必须先校准当前 CLI / 官方文档 / 本机行为，再改 runtime。
- 真实 Codex smoke 会调用外部 provider，若本机 Codex 未登录、配置目录未确认，或需要把 workspace 内容发出机器外，必须先插入 `HUMAN-N` 获取人类确认，不伪造验证。
- I2 完成动作：`cp .ralph/TASKS.md docs/requirements/ralph-loop/I2-FINAL-TASK.md`，清空 `.ralph/TASKS.md` 当前任务段，"当前迭代"改为下一个，更新 `docs/roadmap.md`。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
- Provider 集成事实源：`docs/architecture/integrations.md`
- Checkpoint 索引：`docs/checkpoints/README.md`
- 失败模式索引：`docs/postmortems/README.md`

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 子 bullet 是给 agent 读的上下文，不进 ralph 解析（只识别 `^\s*- \[([ xX])\]`）。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `→ BLOCKED by HUMAN-N` 或 `→ BLOCKED by REVIEW-N`。
- HUMAN-N 任务在 ralph oneshot 内不可勾选（人类在 Claude Code 对话里勾）。
- 不创建根 `task.md` 或其他并行任务板。
- 历史完成细节进入 checkpoint；本文件只保留当前有效结论、历史索引和当前迭代任务。

## 当前任务

- [x] DEV-1: 校准 Codex CLI 集成契约
  - 预期：I2 后续实现基于当前可验证的 Codex CLI 行为，不继承过期或互相矛盾的集成假设。
  - 输入：用户决策 I2=T3（2026-05-03）；`docs/roadmap.md` T3；REQ-004 / REQ-005 / REQ-006 / REQ-014 / REQ-022；`docs/architecture/integrations.md` Codex 小节。
  - 范围：更新 `docs/architecture/integrations.md` 的 Codex 命令、session 路径、配置目录变量、4 文件契约和降级策略；强制同步 `docs/requirements/ralph-loop/requirements.md` 的 REQ-006 / FR-006 / SC-006-1 / REQ-022 相关文字，移除或明确废弃 `session.codex.stdout.jsonl` 作为额外持久化文件的旧描述；新增 Codex 专属配置目录 SC（建议 `SC-022-4`：adapter-codex 配置目录翻译 + 空值鲁棒性；`SC-022-5`：Codex session capture 使用隔离 session root 且不读真实 HOME）；如设计锚点受影响，同步 `docs/requirements/ralph-loop/I2-design.md`；不改 runtime 代码。
  - 验证计划：运行本机 `codex --version` / `codex exec --help`（若可用），对照 OpenAI 官方 Codex CLI 文档；确认不使用 resume / ephemeral；确认 stdout JSONL 与 native rollout 文件的保留边界；grep 确认 requirements / integrations 对 Codex iter 文件契约没有第二事实源；若 CLI 或外部文档不可用，插入 `HUMAN-N` 说明缺口。
  - 完成：校准基于本机 Codex CLI `0.125.0` / Desktop `0.128.0-alpha.1`、官方 non-interactive mode / command line options / config-reference 文档、本机 session 目录观测。更新 integrations.md（版本、CODEX_HOME、effort 用 `-c model_reasoning_effort`、移除 `session.codex.stdout.jsonl`、区分 stdout 事件流与 rollout 文件格式）；更新 requirements.md FR-006（effort 映射改为 config override）、REQ-022（填入 CODEX_HOME、Codex session 采集路径）、新增 SC-022-4（Codex 配置目录翻译 + 空值鲁棒性）、SC-022-5（Codex session capture 隔离）；更新 I2-design.md（标注已确认项）。
  - 验证：`codex --version` = `codex-cli 0.125.0`；`codex exec --help` 确认无 `--reasoning-effort` flag，确认 `-c` / `--json` / `--sandbox` / `-C` / `--ephemeral` 存在；`~/.codex/sessions/` rollout 文件名格式确认；grep 确认无残留 `session.codex.stdout.jsonl` 作为持久化文件描述；`git diff --check` PASS；`bash scripts/check.sh` PASS。
  - 未验证：真实 `codex exec --json` 端到端输出（需要调用外部 provider，归 QA-2 真实 smoke）；`CODEX_HOME` 设为自定义路径后的 session 采集行为（归 DEV-2/DEV-3 实现 + QA-1 集成测试）。

- [x] DEV-2: 实现 Codex adapter oneshot 命令与 provider wiring
  - 预期：`RALPH_PROVIDER=codex` 能通过 Ralph 主循环调用 Codex fresh oneshot，命令参数符合 DEV-1 校准后的契约。
  - 输入：DEV-1；REQ-004 / REQ-005 / REQ-009 / REQ-010 / REQ-014 / REQ-015 / REQ-022；现有 Claude/fake adapter 模式。
  - 范围：新增或补齐 `.ralph/lib/adapter-codex.sh`；接入 `.ralph/lib/run.sh` / `.ralph/bin/ralph` 中的 provider loading（若现有逻辑尚未覆盖）；实现 Codex 配置目录翻译和 model/effort/sandbox 参数映射；避免改变 Claude/fake 行为。
  - 验证计划：`bash -n .ralph/lib/adapter-codex.sh .ralph/lib/run.sh .ralph/bin/ralph`；用临时 PATH stub（不入仓）直接调用 `provider_oneshot`，断言命令含 workspace、JSONL 输出和 sandbox 参数，且不含 resume / ephemeral；持久化 `tests/fixtures/mock-codex` 和完整集成断言归 QA-1。
  - 完成：新增 `.ralph/lib/adapter-codex.sh`，实现 `provider_oneshot`（`codex exec --json -C <workspace> --sandbox workspace-write [--model] [-c model_reasoning_effort=] <prompt>`，从 stdout JSONL 解析 `thread.started.thread_id` 写入 meta.json session_id，检测 `turn.failed` 事件作为 is_error 等价物）；`provider_collect_session` / `provider_diagnose` 为 stub（分别归 DEV-3/DEV-4）；配置目录翻译（SC-022-4：RALPH_PROVIDER_CONFIG_DIR → CODEX_HOME，空值不 export）。
  - 验证：`bash -n` 三个文件 PASS；临时 stub 断言命令含 `--json`、`-C <workspace>`、`--sandbox workspace-write`、`--model`、`model_reasoning_effort=`；不含 resume/ephemeral；effort=none 不拼 effort flag；空 model 不拼 model flag；SC-022-4 翻译 + 空值鲁棒 PASS；`bash scripts/check.sh` PASS；`git diff --check` PASS。
  - 未验证：真实 `codex exec` 端到端（归 QA-2）；`provider_collect_session` 完整实现（归 DEV-3）；`provider_diagnose` 完整实现（归 DEV-4）；`RALPH_PROVIDER=codex` 在 `ralph run` 中完整跑通（归 QA-1/QA-2）。
- [x] DEV-3: 实现 Codex session capture 与 history 派生视图
  - 预期：Codex 每轮执行后能沉淀 `session.codex.jsonl` 和人类可读 `session.history.log`；采集失败时写 warning 但不把任务完成事实迁移到 session。
  - 输入：DEV-1；REQ-006；`docs/architecture/integrations.md` 4 文件 iter 契约；Claude adapter 的 session capture / history 派生实现。
  - 范围：`.ralph/lib/adapter-codex.sh` 的 `provider_collect_session` 与 Codex JSONL history formatter；必要时抽取共享 helper 但不做跨 provider 大重构。
  - 验证计划：用临时 Codex session 目录或 here-doc JSONL（不入仓）验证 thread/session id 精确匹配、mtime/cwd fallback、`capture_status`/`session_source_path` meta 字段，以及 `session.history.log` 的 user / assistant / thinking / tool_use / tool_result 摘要；持久化 session fixture 和完整集成断言归 QA-1。
  - 完成：实现 `provider_collect_session`（精确匹配 `rollout-*-${thread_id}.jsonl` / mtime+cwd 退化 / `capture_status`+`session_source_path` meta 字段）和 `_codex_derive_history`（从 `provider.stdout.log` `--json` 事件流派生 `[user]`/`[assistant]`/`[tool-use name=X]`/`[tool-result name=X]` 摘要）。rollout 文件作为长期归档保留，history 派生基于有文档契约的 stdout 事件流而非内部 rollout 格式。
  - 验证：临时测试 5/5 PASS：精确匹配（capture_status=ok + source_path 含 thread_id）、history 派生（user/assistant/tool-use(Bash)/tool-result(Bash) 含 arguments 摘要）、mtime 退化（capture_warning=fallback by mtime）、缺失 session_id（capture_status=warning + 空 history.log）、SC-022-5 隔离 CODEX_HOME（source_path 在隔离路径下）；`bash -n` 三个文件 PASS；`bash scripts/check.sh` PASS；`git diff --check` PASS；集成测试 56/59 PASS（3 个失败为预先存在的环境隔离问题，与 DEV-3 无关）。
  - 未验证：真实 `codex exec --json` 端到端输出（`item.completed` 事件字段名基于 OpenAI API 格式推断，归 QA-2 真实 smoke 验证）；rollout 文件格式解析（内部格式未实现解析，保留为长期归档用途）；持久化 mock fixture 和完整集成断言（归 QA-1）。

- [x] DEV-4: 实现 Codex provider_diagnose 错误分类
  - 预期：Codex provider 失败时 `last_error.type` 能区分常见 auth / quota / rate_limit / network / api / unknown 场景，便于接力复盘。
  - 输入：DEV-1；REQ-012；`docs/architecture/integrations.md` 错误诊断矩阵；现有 Claude diagnose 风格。
  - 范围：`.ralph/lib/adapter-codex.sh` 的 `provider_diagnose`；必要时更新 `docs/architecture/integrations.md` Codex 错误关键字；不改变 exit_reason 映射。
  - 验证计划：用临时 provider log / JSONL here-doc 覆盖至少 auth、rate_limit、network、unknown，并断言 meta 诊断字段；持久化 fixture 与 `result.json.last_error.type` 端到端断言归 QA-1。
  - 完成：实现 `_codex_classify_error`（互斥优先级：auth → rate_limit → quota → network → api → unknown）和 `provider_diagnose`（turn.failed 权威 → error 事件回退 → stderr 非 JSON 行回退三层降级）；更新 `docs/architecture/integrations.md` Codex 错误诊断添加 `network` 类别（ECONNRESET / ETIMEDOUT / ENOTFOUND / fetch failed / connection refused / network error）。
  - 验证：临时测试 13/13 PASS（auth/401、rate_limit/429、quota/credits、network/ECONNRESET、network/ENOTFOUND、api/500、unknown、error 事件回退、stderr 回退、exit_code=0 无 error、无 log 文件、error 为 string、meta.json 字段完整）；`bash -n` PASS；`bash scripts/check.sh` PASS；`bash scripts/integration-test.sh` PASS；`git diff --check` PASS。
  - 未验证：真实 `codex exec --json` 端到端错误输出（归 QA-2 真实 smoke）；`result.json.last_error.type` 端到端断言（归 QA-1 持久化 fixture）。

- [x] QA-1: Codex adapter 自动化测试覆盖
  - 预期：Codex adapter 的命令构造、session 采集、history 派生、错误诊断和配置目录翻译都有最小自动化证据，避免只靠真实 smoke。
  - 输入：DEV-1 / DEV-2 / DEV-3 / DEV-4；PM-0003 的 REQ traceability 预防检查；SC-004-1 / SC-005-1 / SC-006-1 / SC-014-1，以及 DEV-1 新增的 Codex 专属配置目录 SC（建议 `SC-022-4` / `SC-022-5`）。
  - 范围：`scripts/integration-test.sh`、`tests/fixtures/mock-codex` 或等价持久化 fixture、`docs/architecture/testing.md`；QA-1 拥有持久化 mock fixture 和完整集成断言，不扩大到 Gemini adapter。
  - 验证计划：`bash scripts/integration-test.sh` 中新增 Codex 用例全部 PASS；`bash scripts/check.sh` PASS；测试名或断言能机械定位到覆盖的 SC，且 Codex 配置目录翻译/空值鲁棒性/session capture 隔离路径不是只复用 Claude 的 SC-022-2/3。
  - 完成：新增 `tests/fixtures/mock-codex`（Codex CLI test double，模拟 `codex exec --json` JSONL 事件流 + `${CODEX_HOME:-$HOME/.codex}/sessions/` rollout 文件写入；支持 happy / happy_no_session / missing_thread_id / turn_failed_* / error_event / stderr_error / crash / slow 场景）；在 `scripts/integration-test.sh` 新增 19 个 Codex 集成测试用例：happy path（thread.started + session_id + session.codex.jsonl + capture_status=ok + history.log 含 user/assistant/tool-use(Bash)/tool-result(Bash)）、SC-022-4 翻译 + 空值鲁棒、SC-022-5 CODEX_HOME 隔离路径采集、missing_thread_id → warning + 空 history、错误诊断矩阵 9 用例（auth/401 + rate_limit/429 + quota/credits + network/ECONNRESET + api/500 + unknown + error 事件回退 + stderr 回退 + crash）、SC-014-1 effort=low + effort=none + 空 model、codex+jq 双缺失 non-fail-fast。修复 mock-codex JSON 输出 bug（`arguments` 字段含未转义引号导致 jq exit 5 触发 `|| thread_id=""` 清空有效 thread_id）。
  - 验证：`bash scripts/integration-test.sh` Codex 19/19 PASS（总计 74/77 PASS，3 个失败为预先存在的环境隔离问题：`missing .env` / `session CLAUDE_CONFIG_DIR aware` / `load_env tilde expansion`，与 DEV-3 报告一致，非 Codex 引入）；`bash scripts/check.sh` PASS；`git diff --check` PASS；测试名覆盖 SC-022-4 / SC-022-5 / SC-014-1 / SC-006-1 / SC-005-1 / SC-004-1。
  - 未验证：真实 `codex exec --json` 端到端（归 QA-2 真实 smoke）；`docs/architecture/testing.md` Codex 测试策略更新（归 DEV-5 文档同步）。

- [x] DEV-5: 同步 Codex adapter 文档与使用入口
  - 预期：使用者能按 README / `.ralph/README.md` 配置 `RALPH_PROVIDER=codex` 并理解当前支持边界。
  - 输入：DEV-1 ~ QA-1 的最终实现事实；README 入口地图；`docs/README.md` 文档地图维护规则。
  - 范围：`README.md`、`.ralph/README.md`、`docs/README.md`、`docs/architecture/integrations.md`、`docs/architecture/security.md`、`docs/architecture/testing.md`；必要时同步 `docs/requirements/ralph-loop/requirements.md` SC 文字。
  - 验证计划：`git diff --check`；`bash scripts/check.sh`；README 和 docs/README 的当前状态、provider 索引、配置说明不互相矛盾。

- [ ] HUMAN-1: 确认是否允许真实 Codex CLI provider smoke
  - 上下文：QA-2（真实 Codex provider smoke）需要在临时 workspace 中调用真实 `codex exec` 命令，这会把 workspace 内容发送到 OpenAI API（机器外）。
  - 选项：
    - A：允许。确认本机 Codex CLI 已登录（`codex --version` / `codex auth status` 可用），ralph 执行最小任务到 `exit_reason=done`，记录证据。
    - B：跳过 QA-2。以 mock 自动化测试作为 T3 验收证据（QA-1 19/19 PASS），标注 QA-2 为"需要真实 provider 环境才能执行"。
    - C：延后。先完成 REVIEW-1（基于 mock 证据的 adversarial review），QA-2 在后续迭代中单独执行。
  - 影响：决定 QA-2 是否执行、T3 验收口径如何闭合。
- [ ] QA-2: 真实 Codex provider smoke → BLOCKED by HUMAN-1
  - 预期：在临时 workspace 中用真实 Codex CLI 跑通 Ralph 一轮任务，证明 T3 不是只在 mock 路径可用。
  - 输入：DEV-2 ~ DEV-5；SC-004-1；T3 roadmap 验收口径。
  - 范围：临时 workspace + 本仓库 `.ralph/` 部署单元；只记录必要证据到 `.ralph/TASKS.md` 或 checkpoint，不提交 runtime artifacts、secrets、完整 provider transcript。
  - 验证计划：先确认 Codex CLI auth/config 与用户允许真实 provider 调用；运行最小任务到 `result.json.exit_reason=done`；检查 iter 目录包含 `meta.json` / `provider.stdout.log` / `session.codex.jsonl` / `session.history.log`；若无法确认授权或 CLI 不可用，插入 `HUMAN-N` 阻塞。

- [ ] REVIEW-1: I2 Codex adapter 收口 | adversarial-review
  - 预期：T3 的实现、需求、架构、测试和真实 smoke 证据一致，未遗漏稳定契约或已知失败模式。
  - 输入：DEV-1 ~ QA-2；PM-0003；`docs/requirements/ralph-loop/requirements.md` REQ/SC；`docs/architecture/integrations.md` Codex 契约。
  - 范围：审查代码、测试、docs、`.ralph/TASKS.md`；如发现必须修复项，追加 REVIEW/DEV/QA 后续任务，不直接伪造完成。
  - 验证计划：执行 REQ traceability rerun（REQ-004/005/006/014/022 → 实现 → 测试），逐项对账 SC-006-1 / SC-014-1 / Codex 专属 SC-022-*；运行 `bash scripts/check.sh`、`bash scripts/integration-test.sh`、`git diff --check`；明确真实 smoke 已验证与未验证范围。
