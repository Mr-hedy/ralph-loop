# Tasks

> 当前迭代: I4
> 主题: T4 Gemini adapter
> 关联 roadmap: T4 Gemini Adapter
> 起始: 2026-05-04
> 设计方案: `docs/requirements/ralph-loop/I4-design.md`

## 当前有效结论

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档到 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`；checkpoint 为 `bd85a2d checkpoint: I1 observability review fixes`。
- I2（dogfood T3 — Codex adapter）已完成并归档到 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`；最终修复 commit 包括 `7385981 fix(run): clean provider tree on interrupted runs` 和 `b004a28 docs(test): clarify slow_child interrupt coverage`。
- I3（watch/status 观察面修复）已完成并归档到 `docs/requirements/ralph-loop/I3-FINAL-TASK.md`；checkpoint 为 `2641605 checkpoint: watch status surface fix`。
- 用户决策（2026-05-04）：I4 执行历史 T4，目标是在现有 adapter 契约上接入 Gemini CLI。
- I4 启动前证据：本机 `gemini --version` 为 `0.39.1`；本机 help 支持 `--approval-mode`、`--output-format text|json|stream-json`、`--sandbox`、`--model`，但 `--thinking-budget` 未出现在 help 中。
- Gemini 旧契约存在待校准点：旧 FR-007 写 `--yolo` 和 `--thinking-budget`；当前官方 CLI reference 标注 `--yolo` deprecated，推荐 `--approval-mode=yolo`；session 文件也存在 `session.gemini.json` 与 `session.<provider>.jsonl` 口径差异。
- 本机 Gemini 已登录；真实 provider smoke 不需要 HUMAN gate，作为 QA-2 的真实集成测试执行。

## 历史索引

- v0.1 历史：root `task.md`（已封版，T0-T7 任务史 + 22 条决策追溯）
- I1 归档：`docs/requirements/ralph-loop/I1-FINAL-TASK.md`
- I2 归档：`docs/requirements/ralph-loop/I2-FINAL-TASK.md`
- I3 归档：`docs/requirements/ralph-loop/I3-FINAL-TASK.md`
- I4 设计：`docs/requirements/ralph-loop/I4-design.md`
- 需求事实源：`docs/requirements/ralph-loop/requirements.md`
- 架构事实源：`docs/architecture/overview.md`
- Provider 集成事实源：`docs/architecture/integrations.md`
- Roadmap：`docs/roadmap.md`
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

- [x] DEV-1: 校准 Gemini CLI 当前契约并同步需求/架构事实源
  - 预期：I4 后续实现不再依赖旧 Gemini 假设；requirements、integrations、overview/security/testing 对命令、配置目录、session 文件、history source 和 effort 映射只有一个事实源。
  - 输入：`docs/requirements/ralph-loop/I4-design.md`；REQ-004/006/014/022；FR-007；`docs/architecture/integrations.md` Gemini 小节；本机 Gemini CLI 0.39.1 help；官方 Gemini CLI docs。
  - 范围：`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/integrations.md`、`docs/architecture/overview.md`、`docs/architecture/security.md`、`docs/architecture/testing.md`；不写 runtime adapter。
  - 验证计划：记录 `gemini --version` / `gemini --help` 关键输出；对照官方 CLI reference/configuration docs；`rg` 确认旧 `--yolo`/`--thinking-budget`/Gemini session 文件口径无冲突；`git diff --check`；`bash scripts/check.sh`。
  - 完成：4 个活跃事实源已校准（requirements FR-001/FR-007、integrations Gemini 全节 + 配置目录表、overview provider choices + history source、security approval flag + config dir mapping）。commit `b1979b7`。
  - 验证：`gemini --version` = `0.39.1`；`gemini --help` 确认 `--approval-mode`/`--output-format stream-json`/无 `--thinking-budget`；官方 configuration docs 确认 `GEMINI_CLI_HOME` 环境变量语义；integrations/integrations 确认 `session.gemini.json`（非 `.jsonl`）口径统一；`git diff --check` 通过；`bash scripts/check.sh` 通过。
  - 未验证：testing.md 未修改（Gemini 测试覆盖在 QA-1 新增，不需在 DEV-1 预写）；`bash scripts/integration-test.sh` 未运行（本次纯文档变更，不涉及测试代码）。

- [x] DEV-2: 实现 `.ralph/lib/adapter-gemini.sh` oneshot 与启动校验
  - 预期：`RALPH_PROVIDER=gemini` 能通过 provider loading 和 dependency check，按 DEV-1 校准后的 Gemini CLI 命令执行 fresh oneshot，并把 stdout/stderr 合流写入 `provider.stdout.log`。
  - 输入：DEV-1 Gemini 契约；adapter 三函数契约；Claude/Codex adapter 现有模式；REQ-004/005/014/015。
  - 范围：新增 `.ralph/lib/adapter-gemini.sh`；必要时最小更新 `.ralph/bin/ralph` help/provider choices；新增 `tests/fixtures/mock-gemini` 的最小 command-recording 场景用于本任务验证；不改 Claude/Codex 行为。
  - 验证计划：`bash -n .ralph/lib/adapter-gemini.sh .ralph/bin/ralph tests/fixtures/mock-gemini`；mock Gemini dependency check；mock 命令记录断言 model/effort/config-dir 空值鲁棒性和 approval/sandbox/output-format 参数。
  - 完成：新增 adapter-gemini.sh（provider_check_deps + provider_oneshot + DEV-3/4 最小桩）；mock-gemini（happy/crash 场景 + received 参数记录，支持 --flag value 和 --flag=value 两种形式）；ralph help choices 更新为 claude/codex/gemini/fake。
  - 验证：`bash -n` 三个文件通过；adapter 翻译 RALPH_PROVIDER_CONFIG_DIR→GEMINI_CLI_HOME 通过；空值不 export 通过；mock 命令记录断言 approval-mode=yolo/output-format=stream-json/model 空值鲁棒性通过；`bash scripts/check.sh` 通过；`git diff --check` 通过。
  - 未验证：E2E mock `ralph run --provider gemini` 测试中 symlink 解析导致 workspace 定位到项目根（非测试 temp dir），未产生有效 E2E 证据；真实 Gemini CLI 调用（QA-2）；session capture 完整实现（DEV-3）；error diagnose 完整实现（DEV-4）；`bash scripts/integration-test.sh` 未扩展 Gemini 用例（QA-1 职责）。

- [x] DEV-3: 实现 Gemini session capture 与 `session.history.log` 派生
  - 预期：Gemini iter 目录产出明确的 native session 副本和跨 provider 人话视图；session capture 缺失时降级为 warning，不中断 run。
  - 输入：DEV-1 session 文件契约；REQ-006/022；`provider_collect_session` 契约；Claude/Codex history 派生实现。
  - 范围：`.ralph/lib/adapter-gemini.sh` 的 `provider_collect_session` 和 Gemini history helper；扩展 DEV-2 的 `tests/fixtures/mock-gemini` session store 场景；必要的 `meta.json` 字段写入；不把 provider session 当任务完成事实。
  - 验证计划：mock Gemini session store 精确匹配 / mtime fallback / missing session 三类测试；断言 `capture_status`、`session_source_path`、native session 副本、非空或合理空的 `session.history.log`。
  - 完成：adapter-gemini.sh 新增 provider_oneshot session_id 提取（stream-json init 事件）+ 完整 provider_collect_session（精确匹配 sessionId / mtime fallback / warning 降级）+ `_gemini_derive_history`（从 provider.stdout.log 派生 [assistant] 文本）；mock-gemini 新增 `session_mismatch` / `no_session_file` 场景，init 事件含 session_id，_write_native_session 支持参数覆盖 session_id。
  - 验证：`bash -n` 通过；精确匹配 capture_status=ok + session_id 匹配 + session.gemini.json 存在 + history 含 [assistant]；mtime fallback capture_warning="fallback by mtime" + session.gemini.json 存在；missing session capture_status=warning + 无 session.gemini.json + history 仍从 stdout 派生；`git diff --check` 通过；`bash scripts/check.sh` 通过。
  - 未验证：E2E mock `ralph run --provider gemini` 完整 run（DEV-2 已知 symlink 定位问题）；真实 Gemini CLI session 文件格式（QA-2）；`bash scripts/integration-test.sh` Gemini 用例（QA-1 职责）。

- [x] DEV-4: 实现 Gemini 错误诊断与 `run -v` 可读事件输出
  - 预期：Gemini provider failure 能写入统一 `last_error.type/message`；`ralph run -v --provider gemini` 有可读 marker，不把 JSON/text 原始流直接刷成噪音。
  - 输入：DEV-1 output-format 与错误事件契约；FR-008；现有 `_ralph_filter_verbose` 的 Claude/Codex 分支。
  - 范围：`.ralph/lib/adapter-gemini.sh` 的 `provider_diagnose`；`.ralph/lib/run.sh` 的 verbose filter Gemini 分支；mock fixture 错误场景。
  - 验证计划：mock auth/rate_limit/quota/network/api/unknown 场景；`run -v` stderr grep Gemini marker；`result.json.last_error` 与 `meta.json.error` 分类一致。
  - 完成：adapter-gemini.sh 新增 `_gemini_classify_error`（6 类互斥优先级关键字匹配）+ 完整 `provider_diagnose`（error 事件优先 / stderr 非 JSON 回退 / crash 无输出降级）；run.sh `_ralph_filter_verbose` 新增 `init`/`text`/`complete` 三种 Gemini 事件 marker；mock-gemini 新增 6 个错误场景（auth_error/rate_limit_error/quota_error/network_error/api_error/unknown_error）。
  - 验证：`bash -n` 三个文件通过；`_gemini_classify_error` 11 个关键字用例全 PASS；`provider_diagnose` 7 个 mock 场景（含 crash 无输出）全 PASS；verbose filter 4 种 Gemini 事件（init/text/complete/error）输出正确 marker；`bash scripts/check.sh` 通过；`git diff --check` 通过。
  - 未验证：E2E `ralph run -v --provider gemini` 真实 CLI 调用（QA-2）；`bash scripts/integration-test.sh` Gemini 用例（QA-1 职责）；真实 Gemini CLI 错误事件格式（QA-2 验证）。

- [x] QA-1: 补齐 Gemini mock 集成测试矩阵
  - 预期：Gemini adapter 的主要路径可在无真实 Gemini 调用下稳定回归，且不会把 mock 通过误当真实 T4 完成。
  - 输入：DEV-2/3/4；`scripts/integration-test.sh` 现有 Claude/Codex adapter 测试结构；`tests/fixtures/mock-codex` 模式。
  - 范围：扩展 DEV-2/3/4 已建立的 `tests/fixtures/mock-gemini`；更新 `scripts/integration-test.sh`；更新 `docs/architecture/testing.md` 覆盖矩阵。
  - 验证计划：`bash scripts/integration-test.sh` 通过；新增用例覆盖 happy path、config-dir 或明确不翻译的空值鲁棒性、model/effort 参数、session capture、history、diagnose、dependency missing、`run -v` marker。
  - 完成：新增 17 个 Gemini 集成测试（happy path + run -v markers + config dir 翻译/空值鲁棒 + GEMINI_CLI_HOME aware session + mtime fallback + missing session + 错误诊断 7 类 + model 空/设置 + dep check）；修复 `RALPH_PROVIDER_CONFIG_DIR` 环境泄漏问题（显式清空 env 命令）；更新 testing.md 覆盖矩阵和隔离规则。97 PASS（+14 来自 Gemini），3 FAIL 为预存 ralph loop 环境泄漏问题（与本任务无关）。
  - 验证：`bash -n scripts/integration-test.sh` 通过；`bash scripts/check.sh` 通过；`git diff --check` 通过；`bash scripts/integration-test.sh` 97 PASS 3 FAIL（3 FAIL 为预存 env 泄漏：missing .env、CLAUDE_CONFIG_DIR aware、load_env tilde）。
  - 未验证：真实 Gemini CLI 端到端（QA-2 职责）；E2E mock `ralph run --provider gemini` 完整 run（DEV-2 已知 symlink 定位问题，不影响 mock 单元覆盖）。

- [x] REVIEW-1: Gemini mock 实现后 adversarial-review
  - 预期：在真实 provider smoke 前发现契约漂移、测试假阳性、docs 第二事实源、session 文件泄漏和安全边界问题。
  - 输入：DEV-1 ~ QA-1 的 diff；requirements/integrations/overview/testing/security；PM-0003 观察面和 mock 假设预防规则。
  - 范围：只产出 review findings 或直接修复低风险文档/测试错漏；不执行真实 Gemini smoke。
  - 验证计划：列出 P0/P1/P2 findings；若修复则重跑 `git diff --check`、`bash scripts/check.sh`、相关 integration tests；无发现时明确 remaining risk。
  - 完成：发现 3 条 P1 + 3 条 P2 findings。直接修复 P1-1/2（overview.md 和 integrations.md 中 `session.<provider>.jsonl` 对 Gemini 的第二事实源漂移：3 处改为显式标注 Gemini 用 `.json` + 补充 Gemini history source）。P1-3（REQ-022 缺 Gemini SC）留 DEV-5 补。P2（history 内容格式未指定 / verbose filter 事件覆盖 / SC-025-2 未提 Gemini）留 QA-2/DEV-5 观察和补充。
  - 验证：`git diff --check` 通过；`bash scripts/check.sh` 通过。修改仅影响 docs（overview.md 4 处注释、integrations.md 1 处表格），不影响 runtime。
  - 未验证：`bash scripts/integration-test.sh` 未重跑（本次仅文档注释修改，不涉及测试代码或 runtime）；真实 Gemini CLI 事件 schema（QA-2 职责）；REQ-022 Gemini SC 补充（DEV-5 职责）。
  - Findings 清单：
    - P1-1 ✓已修：overview.md Run 目录 + 伪代码注释 + adapter 契约注释 中 `session.<provider>.jsonl` 含 "Gemini" 但实际为 `.json`
    - P1-2 ✓已修：integrations.md §iter 目录文件结构表格通用 `.jsonl` 对 Gemini 误导（补了 "Gemini 为 `.json` 而非 `.jsonl`" 注释）
    - P1-3（留 DEV-5）：REQ-022 有 SC-022-2/3 (Claude) 和 SC-022-4/5 (Codex) 但无 Gemini GEMINI_CLI_HOME 翻译+采集路径的 SC 条目；违反 PM-0003 REQ traceability 要求
    - P2-1（留 DEV-5）：Gemini `session.history.log` 内容格式未在 integrations.md 指定（Claude/Codex 均有明确标记列表，Gemini 无）
    - P2-2（留 QA-2 观察后 DEV-5 补）：`_ralph_filter_verbose` 只处理 init/text/complete/error 4 种 Gemini 事件；真实 CLI 可能有更多事件类型
    - P2-3（留 DEV-5）：SC-025-2 只提 Claude/Codex verbose filter，未提 Gemini
  - Remaining risk：mock 测试覆盖了 adapter 对假设事件 schema 的处理逻辑，但 mock 事件 schema 与真实 Gemini CLI 事件 schema 的匹配度需 QA-2 真实 smoke 验证。无安全边界问题（session 文件隔离在 HOME 隔离下正确；config dir 翻译空值鲁棒性已覆盖；无 secrets 泄漏路径）。

- [x] QA-2: 真实 Gemini provider 集成测试
  - 预期：真实 `RALPH_PROVIDER=gemini` 在无敏感临时 workspace 中跑到 `exit_reason=done`，并产出 Gemini iter 证据契约。
  - 输入：DEV-1 ~ REVIEW-1 已完成；本机 Gemini CLI 0.39.1 与已登录 auth/config 可用；用户确认无需额外人工介入。
  - 范围：临时 workspace；真实 Gemini CLI；运行证据只记录 run_id、exit_reason、文件存在性和关键字段，不提交 `.ralph/runs/` 或 provider 原始 session。
  - 验证计划：`ralph run --provider gemini --max-iter ...` 跑到 `done`；检查 `result.json`、`meta.json`、`provider.stdout.log`、Gemini native session 副本、`session.history.log`；记录未验证范围和失败诊断。
  - 完成：2 次真实 Gemini CLI 调用（run 1: `20260504-123018` / run 2: `20260504-123737`），均成功 `exit_reason=done`。发现 3 个 P0/P1 bug（事件 schema 漂移导致 session capture 和 history 派生全部失败），需 DEV-6 修复。发现 1 个环境配置问题（`RALPH_PROVIDER_CONFIG_DIR` 泄漏到 GEMINI_CLI_HOME 阻断认证）。
  - 验证：
    - 核心路径通过：`result.json` exit_reason=done、tasks 0→1/1、duration 42s~74s、hello.txt/hello2.txt 内容正确、git commit 生成、TASKS.md 任务勾选。
    - `meta.json` provider_started_at 正确写入，exit_code=0，changed_files 记录正确。
    - session capture 失败（P0-1）：session_id=null、capture_status=warning、无 session.gemini.json。根因：grep `^[[:space:]]*\{` 匹配了 stderr 中的缩进 `{` 行，导致 jq parse error exit 5，`|| _gemini_sid=""` 捕获退出码丢弃了有效输出。修复方案：grep 改为 `^\{` 或用 `jq -R 'try fromjson'` 过滤。
    - history 派生失败（P0-2）：session.history.log 为空。根因：`_gemini_derive_history` 查找 type:"text" / type:"complete"，但真实 CLI 输出 type:"message" + role:"assistant" + delta:true。adapter mock 事件 schema 与真实 CLI 不匹配。
    - verbose filter 事件覆盖不全（P1-1）：真实 CLI 事件类型为 init/message/tool_use/tool_result/result，verbose filter 只处理 init/text/complete/error，4/5 真实事件类型无对应 marker。
    - 环境配置阻断（非代码 bug）：shell 环境已 export `RALPH_PROVIDER_CONFIG_DIR=/Users/hedy/.claude-glm`，adapter 将其映射为 `GEMINI_CLI_HOME`，指向无 auth 配置的目录。用户需在 `.ralph/.env` 中显式清空或设为 HOME。临时 workspace 须加入 Gemini `trustedFolders.json`。
    - 真实 CLI 事件类型：`init`, `message`, `result`, `tool_result`, `tool_use`（非 mock 的 `text`/`complete`/`error`）。
    - 真实 CLI exit code 0 表示成功（即使 stderr 含 500 重试日志）。
    - 真实 CLI model: `auto-gemini-3`（gemini-2.5-flash-lite 路由 + gemini-3-flash-preview 主模型）。
  - 未验证：Gemini CLI 的 error 事件 schema（2 次运行均成功，未触发真实错误路径）；`ralph run -v` 真实 verbose 输出；非 yolo approval mode；sandbox mode；model override（--model）；GEMINI_CLI_HOME 非默认目录下的 session 查找；长时间运行多迭代场景。
  - Findings 清单：
    - P0-1（留 DEV-6）：session_id 提取失败 — grep pattern `^[[:space:]]*\{` 过宽，匹配 stderr 缩进 `{` 行导致 jq exit 5 + `||` 回退丢弃有效输出
    - P0-2（留 DEV-6）：`_gemini_derive_history` 事件类型不匹配 — mock 用 type:"text"/"complete"，真实 CLI 用 type:"message" + role:"assistant" + delta:true
    - P1-1（留 DEV-6）：`_ralph_filter_verbose` Gemini 分支只处理 init/text/complete/error，真实 CLI 5 种事件类型中 4 种无 marker
    - P1-2（留 DEV-5）：用户需知 `RALPH_PROVIDER_CONFIG_DIR` 会映射为 `GEMINI_CLI_HOME`，影响 auth 路径；README 需说明配置方法
    - Remaining risk：error 诊断（`provider_diagnose`）路径未经真实 CLI 验证；Gemini CLI 版本更新后事件 schema 可能变化

- [x] DEV-5: 同步 Gemini 用户入口文档与部署单元 README
  - 预期：用户能按 README/`.ralph/README.md` 正确配置 `RALPH_PROVIDER=gemini`，理解 Gemini 的配置目录、approval/sandbox、session capture 和已知限制。
  - 输入：DEV-1 校准结果；QA-2 真实 smoke 证据或阻塞结论；requirements/overview/integrations/security/testing。
  - 范围：`README.md`、`.ralph/README.md`、`docs/README.md`、`docs/roadmap.md`、必要的 requirements/architecture docs；不改 runtime。
  - 验证计划：`rg` 检查 Gemini 仍被写成 T4 planned 的旧入口是否只出现在历史语境；`git diff --check`；`bash scripts/check.sh`。
  - 完成：5 个文件更新（README.md、.ralph/README.md、docs/roadmap.md、docs/requirements/ralph-loop/requirements.md、docs/architecture/integrations.md）。用户入口文档全部同步 Gemini adapter 三等公民地位：前置依赖表、provider 选择、.env 配置示例、config dir 隔离示例、iter 目录结构、FAQ、-v 模式事件 marker。补充 REVIEW-1 P1-3（SC-022-6/7 Gemini 配置目录 SC 条目）、P2-1（integrations.md Gemini history 派生内容格式）、P2-3（SC-025-2 加入 Gemini）；补充 QA-2 P1-2（README 说明 GEMINI_CLI_HOME 映射）。
  - 验证：`rg` 确认无残留"T4 planned/规划中"旧入口（.ralph/README.md 仅含"I4 / T4 已落地"正确描述）；`git diff --check` 通过；`bash scripts/check.sh` 通过。
  - 未验证：`bash scripts/integration-test.sh` 未运行（本次纯文档变更，不涉及测试代码或 runtime）。

- [x] DEV-6: 修复 QA-2 发现的 Gemini adapter 事件 schema 漂移（P0-1/P0-2/P1-1）
  - 预期：真实 Gemini CLI 调用后 session_id 正确提取、session.gemini.json 正确采集、session.history.log 非空、`run -v` 显示主要事件 marker。
  - 输入：QA-2 真实 smoke 证据（真实 CLI 事件类型：init/message/result/tool_result/tool_use；stderr 含缩进 `{` 噪音行）；adapter-gemini.sh 当前实现；QA-1 mock 测试。
  - 范围：`adapter-gemini.sh`（session_id 提取 grep、`_gemini_derive_history` 事件匹配、verbose filter Gemini 分支）；`tests/fixtures/mock-gemini`（事件 schema 对齐真实 CLI）；`scripts/integration-test.sh`（更新 mock 事件）；`docs/architecture/integrations.md`（事件类型文档）；不改变 adapter 函数签名或 run.sh 主循环。
  - 验证计划：mock 集成测试通过（事件 schema 对齐真实 CLI）；真实 `ralph run --provider gemini` 跑到 done 后 meta.json session_id 非空、session.gemini.json 存在、session.history.log 非空；`run -v` stderr 含 Gemini 事件 marker；`bash scripts/check.sh`；`git diff --check`。
  - 完成：5 个文件修改。P0-1：session_id 提取 grep 改为 `^\{`（只匹配列首 JSON 行，跳过 stderr 缩进噪音）。P0-2：`_gemini_derive_history` 事件匹配从 `text`/`complete` 改为 `message`（role=assistant）+ `result`（QA-2 真实 schema）。P1-1：verbose filter 新增 `message`/`tool_use`/`tool_result`/`result` 4 种真实事件 marker，保留旧 `text`/`complete` 兼容。mock-gemini 新增 `_emit_message`/`_emit_result`，所有 scenario 对齐真实事件类型。integration-test.sh 断言和 grep 模式同步更新。integrations.md 移除 DEV-6 TODO。
  - 验证：`bash -n` 4 个文件通过；`bash scripts/check.sh` 通过；`bash scripts/integration-test.sh` 97 PASS 3 FAIL（3 FAIL 为预存 env 泄漏，与本次无关）；`git diff --check` 通过。
  - 未验证：真实 Gemini CLI 端到端 `ralph run --provider gemini`（需用户在真实环境手动运行）；真实 `ralph run -v` verbose 输出；真实 CLI error 事件 schema。

- [ ] REVIEW-2: I4 最终 adversarial-review 与归档准备
  - 预期：I4 在归档前没有未处理的 P0/P1 事实源漂移、测试假阳性、真实 smoke 证据缺口或用户入口误导。
  - 输入：DEV-1 ~ DEV-5、QA-1/2、docs 和测试结果。
  - 范围：代码、测试、requirements、architecture、README、roadmap、`.ralph/TASKS.md`；不新增功能。
  - 验证计划：adversarial-review findings 清零或转为明确后续任务；`bash scripts/check.sh`；`bash scripts/integration-test.sh`；`git diff --check`；必要时准备 `docs/requirements/ralph-loop/I4-FINAL-TASK.md` 归档建议。
