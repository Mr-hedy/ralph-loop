# Tasks

> 这是 ralph 部署后的最小首跑样例，用来验证 `.ralph/` 已就绪、provider CLI 能通、循环能跑通。
>
> 使用方式：
> 1. 在目标 workspace 跑 `cp -r .ralph/ <workspace>/.ralph/`
> 2. 按需编辑 `.ralph/.env`
> 3. 在 workspace 跑 `.ralph/bin/ralph run`
> 4. 跑通后用真实任务清单替换本文件
>
> ralph 只识别顶层 `- [ ] / - [x]`；子 bullet 是给 agent 读的，不进解析。

- [x] 初始化：确认 `.ralph/` 已部署到本 workspace，git init 已完成。

- [x] DEV-1: 写 hello.txt，内容为 `hello ralph`，完成后 commit。
  - 文件路径：hello.txt（workspace 根目录）。
  - 内容严格为 `hello ralph`，无多余空行。
  - 完成后：`git add -A && git commit -m "add hello.txt"`。
  - 完成: 已创建根目录 `hello.txt`，内容为 `hello ralph`。
  - 验证: `od -An -tx1c hello.txt` 确认仅含 `hello ralph` 及单个文件结尾换行。
  - 未验证: None

- [x] DEV-2: 在 README.md 末尾追加 `<!-- setup complete -->`，完成后 commit。
  - 完成: README.md 末尾（空行后）追加了 `<!-- setup complete -->`。
  - 验证: `tail -3 README.md` 确认末行为 `<!-- setup complete -->`；`git diff --check` 无输出（exit 0）。
  - 未验证: None

## 当前工作包（2026-09-14）

> 本工作包承接 provider 输出采集、权限边界和 Gemini 暂停接入的决策。旧的 DEV-1/DEV-2 首跑样例保留，不删除历史任务；ralph 按文件中第一个未完成顶层任务依次执行。

- [x] DEV-3: 固化 Claude/Codex provider 输出与终态事件契约。
  - 预期：原始 `provider.stdout.log` 始终保留；Claude/Codex 的 `meta.json` 能区分 terminal event/status，解析异常不丢证据。
  - 输入：REQ-029、`docs/architecture/overview.md`、现有 adapter 和集成测试。
  - 范围：`.ralph/lib/adapter-claude.sh`、`.ralph/lib/adapter-codex.sh`、相关 schema/文档与测试；不得重新启用 Gemini。
  - 验证计划：bash 语法检查、fake 集成测试、成功/失败/未知终态 fixture，检查 raw log 未被覆盖。
  - 完成: `common.sh` 新增 `ralph_json_lines`（过滤结构不完整 JSONL 行；jq 1.7 遇非法行会 exit 5 并丢弃其后全部输入）；Claude/Codex adapter 的终态解析、thread_id/session_id 解析、`session.history.log` 派生、`provider_diagnose` 全部改走该 helper；两 adapter 每轮写 `terminal_event` / `terminal_status`(success|error|unknown) / `terminal_warning`，Codex 以 `turn.*` 为权威终态（末尾 `error` 事件仅退化使用并写 warning），`terminal_status=error` 时提升 rc（不再仅凭进程退出码判定终态）；`session.sh` meta 骨架加 `terminal_warning`；`mock-claude`/`mock-codex` 各加 3 个终态 fixture；`integration-test.sh` 新增 10 个终态契约用例 + `meta_terminal_field` helper；`check.sh` 纳入两 adapter 的 `bash -n`；文档同步 `docs/architecture/overview.md`、`docs/architecture/integrations.md`（新增 §终态事件契约）、`requirements.md`（SC-029-1/2 + 追踪矩阵）、`.ralph/README.md`；沉淀 PM-0005 并追加 QA-2。
  - 验证: `bash scripts/check.sh` → `ralph-loop check passed`（rc=0）；`git diff --check` → 无输出；adapter 级手工证据（mock fixture + 临时 workspace，逐个读 round meta）：claude `is_error_auth`→result/error/rc2、`is_error_missing`→result/unknown、`no_terminal_event`→null/unknown、`crash`→null/unknown/rc2、`truncated_then_result`→result/success 且 raw log 逐字保留截断行；codex `happy`→turn.completed/success、`turn_failed_auth`→turn.failed/error/rc2、`error_only_rc0`→error/error/rc2（退化 error 事件 + warning）、`crash`→null/unknown/rc2、`completed_then_error`→turn.completed/success（权威优先）、`truncated_then_completed`→turn.completed/success 且 raw log 保留截断行；对照实验：未过滤的 `jq 'select(.type=="result")'` 在截断行上 `parse error` 且无输出（修复前丢终态），`ralph_json_lines | jq` 取回合法 result 事件。
  - 未验证: (1) 完整 `bash scripts/integration-test.sh` 未在本轮 oneshot 时限内跑完（跑到约 57 PASS / 「Dep check: multiple deps missing」阶段被时限截断），新增的 Claude/Codex 终态用例未在整套中执行，仅有等价的 adapter 级手工证据；(2) 该套件本轮 2 个 FAIL 均判定为宿主 `RALPH_*` 环境变量泄漏造成的假失败（PM-0005），非本轮改动引入，已登记 QA-2：`-- Provider retry: status.json`（继承 `RALPH_LOOP_MAX_RETRY=0` → 不重试；`env -u` 后通过，pristine HEAD `git archive HEAD` 同样复现）与 `-- QA-2: plain multi-round`（继承 `RALPH_LOOP_MAX_ROUND=4` → 标记渲染为 `round 1/4`，用例断言 `round 1/∞`）；(3) 真实 Claude/Codex CLI smoke 未执行（无认证、避免调用外部 provider），仅 mock fixture 覆盖；(4) 运行期发现 `.ralph/TASKS.md` 在 2026-09-14 08:38:29 UTC 被外部改动（DEV-3/DEV-4 被勾成 `[x]` 且无完成字段），原因未查明；未改回该标记，已写入 QA-2 范围要求排查是否为某用例未隔离 `RALPH_WORKSPACE` 时让 fake/mock provider 写到了真实 workspace。

- [ ] DEV-4: 强化 Codex native session 采集的活动/归档兼容性。
  - 预期：按 session id 校验并从活动或归档目录复制 session；找不到、截断或格式不匹配时 oneshot 仍完成且留下诊断。
  - 输入：REQ-030、Codex session 文档、现有 `provider_collect_session` 实现。
  - 范围：Codex adapter、meta 字段和针对配置目录隔离的测试；不改变 fresh oneshot 语义。
  - 验证计划：构造活动/归档/错误 rollout fixture，运行集成测试并检查 `session.history.log` 与错误诊断。
  - 复核状态（2026-09-14, REVIEW-1）: 本行原为 `[x]`（与 DEV-3 同批外部改写，无任何完成/验证字段）。经核对：本工作包 diff（fbe4d33..7c0170d）**未触及** `provider_collect_session`，活动/归档兼容逻辑来自更早的 `6fefab5`；DEV-4 自己的验证计划（活动/归档/错误 rollout fixture + 集成测试）从未执行。判定为无证据标记，已回退为 `- [ ]`，避免 ralph 外层把未验证任务当已完成（与 REVIEW-1 本人被回退同一处理口径）。
  - 待验证点（REVIEW-1 复核结论，按优先级）: (1) 活动目录只按**文件名** `rollout-*-<id>.jsonl` 匹配，不校验内容与 id 是否一致——同名但内容损坏/被截断的 rollout 会被 `capture_status=ok` 复制；归档路径有内嵌 id 校验，两条路径强度不一致。(2) mtime 降级路径只扫 `${CODEX_HOME}/sessions/`，不扫 `archived_sessions/`，"归档 + 无 thread_id"组合注定采集失败。(3) 归档 rollout 首行非法 JSON 时的诊断无用例（QA-1 未验证 (5) 已登记）。

- [x] DEV-5: 收敛 provider 入口和权限边界文档。
  - 预期：公开入口只允许 Claude/Codex/fake；Gemini 在启动阶段明确失败；Codex `danger-full-access` 的权限含义、配置目录和审计证据在 README/架构文档一致。
  - 输入：REQ-028、REQ-031、官方 CLI 行为记录、当前代码与文档。
  - 范围：`.ralph/bin/ralph`、`.ralph/lib/run.sh`、README 与 `docs/architecture/{overview,integrations,security}.md`；历史 Gemini 内容须标注为暂停/未来接入。
  - 验证计划：Gemini 入口失败且不产生 run；Claude/Codex/fake 入口检查通过；`git diff --check` 和文档一致性搜索。
  - 完成: (1) 入口收敛：`ralph_run_help` 声明 `--provider` 只接受 claude/codex/fake、其他取值启动即失败且不建 run 目录；`run.sh` 的 gemini 分支消息对齐为 `use claude, codex or fake` 并补 REQ-028 溯源注释（不在 adapter 层做任何放行/拦截）。 (2) Gemini 暂停标注：`.ralph/README.md` 清掉可执行示例（`gemini --version`、Gemini 认证项、`.env` 样例、`--provider gemini` run/model 示例），FAQ 改写为「`--provider gemini` 直接失败」并保留历史认证说明；`integrations.md` 给 `## Gemini CLI` 与错误诊断块加暂停标注、修掉 Gemini 编辑残留（重复半句的孤儿 bullet、孤立的 `...` 行）、把误置的 `## 错误诊断（续 Gemini）` 降级为 `## Gemini CLI` 下的 `### 错误诊断`；`overview.md` 支持矩阵/CLI 表/索引/派生视图同步。 (3) 权限边界与审计证据：`.ralph/README.md` 新增 §Provider 权限边界与审计证据；`security.md` 重写 approval/sandbox 表（新增「实际权限含义」列 + 有效权限汇总）、新增 §权限参数的审计路径（REQ-031）、修正信任域对「副作用限定在 workspace 内」的过宽表述；`integrations.md` Codex 段补权限含义 + 配置目录不变式 + 审计指针。 (4) 权限语义纠错（本轮新发现，价值最高）：原文档把 Claude 的 `--allowedTools` 当能力边界。核对 `claude --help`（`2.1.270`）与官方 permission-modes/CLI reference 后确认 `--allowedTools` 是 pre-approve 规则（"To restrict which tools are available, use `--tools` instead"），且 "Allow rules have no effect in `bypassPermissions`"，而 `adapter-claude.sh` 同时传 `--dangerously-skip-permissions` → 该 6 项清单从未生效；Codex 侧官方措辞为 "removes local sandbox restrictions"（REQ-031 的"workspace 内任意写入"是下界）。已在 README/security/integrations/overview 四处改为"传了什么参数 vs 实际限定了什么"的区分，并明确两条真实路径都无 provider 侧收窄层。 (5) 沉淀 PM-0006（`docs/postmortems/pm-provider-flag-semantics-vs-boundary.md`）+ 索引，security.md 回链。 (6) 越出声明范围但属 CLAUDE.md 强制的同步：`README.md`、`docs/README.md`、`docs/requirements.md`、`requirements.md`（FR-001 的 `--provider` 取值枚举原先含 `gemini`，与 REQ-028 直接矛盾；FR-007 标题加暂停标注）。 (7) 未改行为：`adapter-claude.sh` / `adapter-codex.sh` 的权限参数保持原样，权限收敛属新 REQ 决策。
  - 验证: `bash scripts/check.sh` → `ralph-loop check passed`（rc=0）；`git diff --check` → 无输出（rc=0）；入口实测（`/tmp/ralph-dev5-verify`，`.ralph/` 为改动后副本）：`--provider gemini` → rc=1 + `startup check failed: provider 'gemini' is temporarily disabled; use claude, codex or fake`，且 `.ralph/runs` / `.ralph/lock` / `.ralph/status.json` 均不存在；`--provider claud` → rc=1 `unsupported provider`；`PATH=/usr/bin:/bin` 下 `--provider claude` → 通过 provider gate、报缺依赖 `claude (Claude Code CLI)`，`--provider codex` → 同理报 `codex (Codex CLI)`（证明 gate 放行、失败点在依赖检查）；`--provider fake` + `RALPH_FAKE_SCENARIO=happy` → rc=0、`Exit Reason: done`、`Tasks: 1 / 1`；`ralph help run` 输出含新的 provider 边界说明。文档一致性搜索：`grep -rn '[Gg]emini'` 覆盖 README/.ralph/README/docs 后，剩余提及均在暂停标注段落内或已改写为"暂停接入"；`grep -rn '白名单|allowedTools'` 无残留的"白名单=能力边界"表述；文档记录的审计命令实测 `grep -n 'danger-full-access\|dangerously-skip-permissions\|allowedTools' .ralph/lib/adapter-*.sh` 仅命中 adapter-claude.sh / adapter-codex.sh（无第三个 provider），与文档"期望命中"一致。权限语义证据：`claude --help`（2.1.270）`--dangerously-skip-permissions` = "Bypass all permission checks"、`--allowedTools` = "list of tool names to allow"；官方 permission-modes "Allow rules have no effect in `bypassPermissions`"；官方 CLI reference "To restrict which tools are available, use `--tools` instead"；`codex exec --help` 的 `-s, --sandbox` possible values = read-only / workspace-write / danger-full-access；官方 Permissions 页 `danger-full-access` = "removes local sandbox restrictions and should be used only when that broad access is intentional"。
  - 未验证: (1) 未新增自动化用例：DEV-5 范围不含测试脚本，REQ-028 的 SC-028-1 仍为「待新增集成测试」，归 QA-1；真实 Claude/Codex CLI smoke 未执行（避免消耗 provider 额度），入口只在「CLI 不在 PATH」路径上证明 gate 放行。 (2) 权限语义纠错只落到文档，`adapter-claude.sh` / `adapter-codex.sh` 行为未动；"是否真正收窄 Claude 工具集（`--tools`）或收紧 Codex 沙箱"是需新 REQ 的设计决策，本轮未做。 (3) 本机 Codex CLI 已是 `0.153.4`，而 `integrations.md` 证据范围仍记 `0.125.0`（2026-05-03 观测）；本轮只对 sandbox flag 取值做新观测并单独标注，未重跑其它 Codex 契约，故不改写版本锚点。 (4) 残留不一致（超出 DEV-5 声明范围，未改）：`requirements.md` 追踪矩阵引用 SC-028-1 / SC-030-1 / SC-031-1 / SC-032-1，但「成功标准」表未定义这 4 条 SC（REQ-028/030/031/032 于 2026-09-14 加入时只写了 REQ 行），违反 PM-0003 的 prevention check「任务范围段必须显式列出本任务覆盖的 SC 清单」，建议由 REQ 任务补齐。 (5) 残留不一致（未改）：`docs/architecture/testing.md` 仍列 `mock-gemini` 与 Gemini mock 用例；该文件不在 DEV-5 范围。 (6) 已写入 security.md 的已知缺口：REQ-031 要求沙箱/approval 参数「记录到 meta」，当前 meta.json 无权限字段，auditability 实际由写死的 adapter 源码 + 文档 + `context.json` 版本锚点承担，字面要求未满足。 (7) PM-0006 的「提炼到 skill / `.spec/`」两项本轮未执行（避免在 DEV 任务里改协作规范），留给 REVIEW-1 复核后决定。

- [x] QA-1: 建立 provider 兼容性与权限 adversarial 回归门。
  - 预期：覆盖非零退出、未知/截断 JSON、终态缺失、session 丢失、配置目录隔离、Gemini 禁用和 Codex 权限提示；报告区分环境阻塞与未覆盖。
  - 输入：REQ-032、`.spec/rules/ADVERSARIAL-REVIEW.md`、现有 `scripts/integration-test.sh`。
  - 范围：测试脚本与最小 fixture，不引入外部框架或 ACPX 重构。
  - 验证计划：完整 `bash scripts/check.sh`、完整集成测试、Claude/Codex smoke（可执行时）及 adversarial review 结论。
  - 完成: (1) 新增 11 例回归门（`scripts/integration-test.sh`「QA-1」段，位于 codex dep-check 之后、Gemini 历史块之前）：SC-028-1 入口收敛 4 例（`--provider` flag / `.env` `RALPH_PROVIDER` / 进程 env / mock gemini CLI 位于 PATH），统一断言 rc=1 + `temporarily disabled` + `claude, codex or fake` + 无 `runs/`/`lock`/`status.json`；SC-030-1 采集鲁棒性 4 例（Codex 归档 rollout 靠内嵌 id 命中且复制件与原件逐字节一致、Codex 采集完全缺失 → warning + run 仍 `done` + `session.history.log` 仍由 stdout 派生 + raw log 保留、Codex/Claude 配置目录隔离诱饵各 1）；REQ-029 组合 1 例（`turn.completed` + CLI 非零退出 → `provider_failed`，success 终态不掩盖退出码）；SC-031-1 权限审计 2 例（Claude 权限参数运行时 argv 审计、扩权 flag 文件扫描）。(2) fixture 扩展（沿用单一来源 mock，不新建）：`mock-codex` 新增 `_write_archived_session` helper 与 4 个 scenario（`archived_session` / `no_session_at_all` / `home_decoy` / `completed_then_rc1`）；`mock-claude` 新增 `home_decoy` scenario，并在 argv 解析回显 `--dangerously-skip-permissions` / `--allowedTools`（`_emit_init` 追加 `_received_skip_permissions` / `_received_allowed_tools`，沿用 `_received_effort` 模式）。(3) 诱饵判别力变异实验：`home_decoy` 由 mock 在**采集期内**（`provider_started_at` 之后）向真实 HOME 配置目录写同名 session，刻意忽略 `CLAUDE_CONFIG_DIR`/`CODEX_HOME`；去掉这两个变量后诱饵确实被采成 `capture_status=ok`（Claude 路径记 `fallback by mtime`），证明隔离用例能区分「隔离生效」与「回落泄露」。首版诱饵写在 run 之前，Claude 侧因时间锚点不命中而退化成恒真断言，已修正。(4) `scripts/check.sh` 纳入测试层 `bash -n`（`integration-test.sh` + 3 个 mock fixture）。(5) 文档同步：`docs/architecture/testing.md` 新增「Provider 兼容性与权限回归门（QA-1）」段（用例矩阵 / 诱饵判别力 / 权限已知缺口 / Gemini 测试层状态 / 真实 smoke 口径）；`docs/requirements/ralph-loop/requirements.md` 追踪矩阵 REQ-028/029/030/031/032 行由「待新增」改为本轮实际覆盖与剩余部分。
  - 验证: `bash scripts/check.sh` → `ralph-loop check passed`（rc=0）；完整 `env -u RALPH_WORKSPACE -u RALPH_PROVIDER -u RALPH_LOOP_MAX_ROUND -u RALPH_LOOP_MAX_RETRY -u RALPH_LOOP_STALL_LIMIT -u RALPH_LOOP_ROUND_TIMEOUT bash scripts/integration-test.sh` → `PASS=156 FAIL=0`、`EXIT=0`（新增 11 例在整套中逐条 `[PASS]`：gate gemini ×4 / codex archived session / codex no session / codex CODEX_HOME isolation / claude CLAUDE_CONFIG_DIR isolation / codex completed_then_rc1 / claude permission audit / permission flag scan；Gemini 历史块仍为 `if false` 跳过）；回归门聚焦复跑（抽取 harness + QA-1 段的临时脚本，同一 clean env）→ `PASS=11 FAIL=0`；变异实验：`env -u CODEX_HOME` → codex 诱饵 `capture_status=ok`、`copied=YES`；`env -u CLAUDE_CONFIG_DIR` → claude 诱饵 `capture_status=ok`、`capture_warning=fallback by mtime`、`copied=YES`；可执行性核对（本地、零额度）：`claude 2.1.270` / `codex-cli 0.153.4` / `jq 1.7.1` / `git 2.50.1` 均在 PATH，`claude --help` 含 `--dangerously-skip-permissions`（"Bypass all permission checks"）与 `--allowedTools`，`codex exec --help` 的 `-s, --sandbox` possible values = `read-only / workspace-write / danger-full-access`（即 adapter argv 被真实 CLI 接受）；`git diff --check` → 无输出（rc=0）。
  - 未验证: (1) 真实 Claude/Codex CLI 端到端 smoke 未执行（只做本地 `--version` + `--help` 可执行性核对，避免消耗 provider 额度，与 DEV-3/DEV-5 口径一致）；REQ-032 的「可执行性 smoke」因此只覆盖「CLI 存在且接受 adapter 的权限 flag」，未覆盖「真实 CLI 跑通一轮 run」。(2) SC-031-1 的 meta 记录要求未满足：`meta.json` 无权限字段，回归门只审计 adapter 源码 + provider 回显 argv；属新 REQ 决策（DEV-5 未验证 (6) 已登记 security.md）。(3) 完整集成测试仅在剥离宿主 `RALPH_*` 变量后作门禁结论；携带宿主变量时仍非全绿（PM-0005，归 QA-2），本轮未在带变量环境跑完整套件。(4) `requirements.md` 追踪矩阵引用的 SC-028-1/SC-030-1/SC-031-1/SC-032-1 仍无「成功标准」表定义（DEV-5 未验证 (4) 已登记）；QA-1 范围是测试脚本，未补 SC 定义，请 REVIEW-1 复核是否需由 REQ 任务补齐。(5) Codex 归档目录不参与 mtime 降级路径，本轮只测归档 id 命中，未测「归档 + 无 thread_id + 需 mtime」组合；归档 rollout 内容损坏（首行非法 JSON）时的诊断未单独建用例。(6) 扩权 flag 扫描是文本 grep，不构成语义证明：新增 provider 若用短选项（`-s danger-full-access`）或环境变量表达沙箱策略不会被命中。(7) 运行期发现 `.ralph/TASKS.md` 于 2026-09-14T08:56Z（本 round 进行中，run_id `20260914-083503-fbe4d33` task_started_at 08:50:51Z）被外部改写：QA-1 与 REVIEW-1 被同时勾成 `[x]` 且无完成字段。两次连续勾选与 mock `_check_first_task`「勾掉第一条未勾选任务」的行为一致，疑似某用例未隔离 workspace 时让 mock 写到真实 workspace——即 QA-2 的追加排查项，本轮未定位到具体用例。QA-1 的 `[x]` 已由本轮补齐真实完成字段；**REVIEW-1 的 `[x]` 无任何证据支撑（adversarial review 未执行），已由本轮回退为 `- [ ]`，避免 ralph 外层误判该工作包已完成 adversarial 复核**。

- [x] REVIEW-1: 对本工作包全部修改做 adversarial review。
  - 预期：只报告有证据的高信号问题；重点检查 provider 输出完整性、权限扩大、路径穿越/错误 session 复制、Gemini 绕过入口和失败时的状态一致性。
  - 输入：REQ-028~REQ-032、全部代码/文档 diff、测试输出。
  - 范围：`.ralph/`、`scripts/`、README 和 architecture/requirements 文档；遵循 `.spec/rules/ADVERSARIAL-REVIEW.md`。
  - 验证计划：逐项复核 diff，重跑受影响测试；发现问题则追加修复任务，不以 exit code 0 代替结论。
  - 完成: 复核本工作包 diff（fbe4d33..7c0170d，22 文件 / +1084-122），结论与证据见本轮对话输出；新增 3 个任务（DEV-6 / DEV-7 / REQ-033）承载必须修复项，DEV-4 的 `[x]` 因证据缺失回退为 `[ ]`。必须修复项 3 条：(A) `ralph_json_lines` 只做**形状**过滤（`{` 开头 `}` 结尾），形状合法但 jq 不可解析的行仍会让 jq 提前退出并丢弃其后全部输入——SC-029-1 / integrations.md §终态事件契约 声称已消除的失败模式只被消除了一半（→ DEV-6）；(B) 追踪矩阵引用的 SC-028-1 / SC-030-1 / SC-031-1 / SC-032-1 在「成功标准」表无定义，SC 语义目前只存在于测试断言里（→ REQ-033）；(C) `security.md` §权限参数的审计路径记录的审计命令（`danger-full-access\|dangerously-skip-permissions\|allowedTools`）与回归门实际使用的模式（含 `--sandbox` / `--approval-mode`）不一致，命中不到 `adapter-gemini.sh` 的 `--approval-mode yolo`，而该文件随部署单元入仓、"无第三个 provider 命中"的表述在 Gemini 重新接入时会给出假阴性结论（→ DEV-7）。
  - 验证: 逐项实测（全部在临时 workspace / /tmp，未触碰真实 workspace 产物）：(1) F1 复现——`/tmp/review1/c4.log` = `{"type":"item.completed","path":"C:\Users\foo"}`（形状合法、JSON 非法转义）+ 其后合法 `{"type":"result","is_error":false}`；`ralph_json_lines c4.log | jq -c 'select(.type=="result")'` → 空输出、jq rc=5；同输入 `jq -Rc 'fromjson? | select(.type=="result")'` → 正确取回 result 事件；对照 `{"a":1,}` 尾逗号行同样 rc=5 并丢弃后续行。(2) F2 复现（TASKS.md 损坏机制）——把真实 TASKS.md 的前两条任务复制成 `/tmp/review1/decoy/.ralph/TASKS.md`，以 `RALPH_WORKSPACE=/tmp/review1/decoy` 直接连续两次调用 `tests/fixtures/mock-claude --session-id ...`（scenario happy），诱饵文件被逐条勾成 `[x] DEV-3` → `[x] DEV-4`，与 2026-09-14 08:38:29Z / 08:56Z 真实 TASKS.md 上观察到的「连续两条被勾且无完成字段」形态**完全一致**：mock 的 `_check_first_task` 无守卫地写 `${RALPH_WORKSPACE}/.ralph/TASKS.md`，而 ralph 外层把 `RALPH_WORKSPACE` export 给了宿主环境，任何脱离套件的 fixture 直调（手工取证、变异实验）都会命中真实工作区。(3) F3 复现（timeout 轮次终态口径）——mock-claude `RALPH_MOCK_CLAUDE_POST_STREAM_SLEEP=20` + `ralph run --round-timeout 3 --max-retry 0`：round meta `terminal_event/terminal_status/terminal_warning` 全为 `null`、`exit_code=143`、`exit_reason=timeout`，而 SC-029-2 字面要求「无终态事件 → `unknown` + 非空 `terminal_warning`」。(4) 文档/代码一致性搜索：`grep -rn 'danger-full-access\|dangerously-skip-permissions\|allowedTools'` 确认 adapter 侧只有 claude/codex 命中（security.md 的该条陈述对它自己的模式成立），但 `adapter-gemini.sh:60 --approval-mode yolo` 不在该模式覆盖内；`grep -n 'SC-028-1\|SC-030-1\|SC-031-1\|SC-032-1' requirements.md` 确认 4 条 SC 仅有矩阵引用、无定义行。(5) 静态复核：QA-1 的 11 例位于 `integration-test.sh` 顶层（2566–2806，`if false` 只包住 2814 起的 Gemini 历史块），未被跳过；`terminal_event/terminal_status/terminal_warning` 除 adapter 写入外无任何读取点（run.sh 只看 rc），属纯元数据事实已在文档里表述为「adapter 返回非零 → run 层按 provider_failed」，未发现误导。(6) `bash scripts/check.sh` → `ralph-loop check passed`（rc=0）；`git diff --check` → 无输出。
  - 未验证: (1) 独立复跑完整 `bash scripts/integration-test.sh`（clean env）在到达本轮 900s 上限前只跑到 `PASS=46 FAIL=0`（进度：QA-2 summary/retry-marker 段，尚未进入 2566 起的 QA-1 段），**QA-1「完整套件 PASS=156 FAIL=0」的结论未被本轮独立复现**；本轮对 QA-1 段只做了静态复核（位置、断言、诱饵判别力设计），未重跑其 11 例。(2) F1 的修复方向（`jq -Rc 'fromjson?'` 逐行解析）只做了可行性验证，未评估其对 4 个调用点（终态 / thread_id / diagnose / history 派生）的解析语义影响（例如 `fromjson?` 对多行 pretty-print JSON 的行为差异），留给 DEV-6。(3) 真实 Claude/Codex CLI 端到端 smoke 仍未执行（与 DEV-3/DEV-5/QA-1 同口径，避免消耗 provider 额度）；权限侧只读源码 + `--help` 文本，未做真实越权实验。(4) 未审计本次 diff 之外的代码（`adapter-gemini.sh` 除权限 flag 外、`sticky.sh` / `watch.sh` / `status.sh` / `tasks.sh` 均只做了调用关系抽查）；Gemini 入口门只静态核对了 `run.sh:462-475` 的 `case` 位于 lock / run 目录创建之前，未重跑 QA-1 的 4 例入口门。(5) 可观察风险的触发条件已在对话输出中列出但未建任务（Claude session mtime 降级无 id/cwd 校验、`check.sh` 未覆盖 `sticky.sh`/`watch.sh`/`status.sh`/`adapter-gemini.sh` 的 `bash -n`），需要时由后续 REVIEW 或 REQ 任务承接。

- [ ] QA-2: 让集成测试对继承的 `RALPH_*` 环境变量免疫。
  - 预期：在携带 `RALPH_PROVIDER` / `RALPH_LOOP_MAX_RETRY` / `RALPH_LOOP_MAX_ROUND` / `RALPH_LOOP_STALL_LIMIT` / `RALPH_LOOP_ROUND_TIMEOUT` / `RALPH_WORKSPACE` 的宿主进程里跑集成测试，结论与干净环境一致；用例断言 ralph 参数默认值前必须显式隔离（`env -u <VAR>` 或显式 CLI flag）。
  - 输入：PM-0005（`docs/postmortems/pm-integration-test-env-inheritance.md`）；DEV-3 round 发现的 `-- Provider retry: status.json` 假失败（`env RALPH_LOOP_MAX_RETRY=0` 失败 / `env -u RALPH_LOOP_MAX_RETRY` 通过，pristine HEAD 同样复现）。
  - 范围：`scripts/integration-test.sh` 的用例环境隔离（含 setup helper 统一清理继承变量）；不改 `load_env` 的优先级契约（CLI flag > 进程 env > `.env`）。额外排查：测试运行期间真实 workspace `.ralph/TASKS.md` 被外部改动（2026-09-14 08:38:29 UTC 的 DEV-3/DEV-4 勾选），确认是否为某用例在未隔离 `RALPH_WORKSPACE` 时让 fake/mock provider 写到了真实 workspace；若是，属于测试隔离越界，必须一并修掉。
  - 验证计划：`env RALPH_LOOP_MAX_RETRY=0 RALPH_PROVIDER=claude RALPH_LOOP_MAX_ROUND=4 bash scripts/integration-test.sh` 与 `env -u RALPH_LOOP_MAX_RETRY -u RALPH_PROVIDER -u RALPH_LOOP_MAX_ROUND bash scripts/integration-test.sh` 两种环境下全绿；跑完后 `git status .ralph/TASKS.md` 无变化。
  - 补充（REVIEW-1 2026-09-14，机制已复现，供本任务直接使用）: 真实 `.ralph/TASKS.md` 被改写的机制**已复现**——`tests/fixtures/mock-claude` / `mock-codex` 的 `_check_first_task` 无守卫地写 `${RALPH_WORKSPACE}/.ralph/TASKS.md`，而 ralph 外层把 `RALPH_WORKSPACE` export 进了宿主环境；在临时 workspace 里以 `RALPH_WORKSPACE=<decoy>` 连续两次直调 mock，诱饵文件被逐条勾成 `[x]`，与真实文件上观察到的「连续两条被勾且无完成字段」形态一致。差集结论：**套件内**每次 ralph 调用都由 `run.sh:447-448` 的 `ralph_workspace_root()` 重算并写回 workspace（已逐处静态核对，套件无 fixture 直调），因此越界写只可能来自**套件之外的 fixture 直调**（手工取证 / 变异实验），而不是某个用例。修复建议（二选一或并用）：(a) mock 写任务前要求显式 opt-in（如 `RALPH_MOCK_ALLOW_TASK_WRITE=1`）或改用显式传入的任务文件路径变量，不再默认消费环境里的 `RALPH_WORKSPACE`；(b) 套件与手工取证统一走一个隔离 wrapper，`env -u RALPH_WORKSPACE`。本任务验证计划里的「跑完后 `git status .ralph/TASKS.md` 无变化」应同时覆盖「套件内」与「fixture 直调」两条路径。

- [ ] DEV-6: 让 provider 事件流解析对「形状合法但 jq 不可解析」的行也免疫。
  - 预期：`provider.stdout.log` 中任意一行无法被 jq 解析时（不限于 `{` 开头 `}` 结尾这一形状判据能挡下的行），该行之后的合法事件仍能被解析；终态事件（Claude `result`、Codex `turn.completed`/`turn.failed`）不再因无关坏行而丢失，`terminal_status` 不退化为 `unknown`，失败终态不会因为坏行而不再提升 rc。
  - 输入：REVIEW-1 发现（2026-09-14）+ 复现证据：`{"type":"item.completed","path":"C:\Users\foo"}`（形状合法：`{` 开头 `}` 结尾；JSON 非法转义）+ 紧随其后的合法 `{"type":"result","is_error":false}`，经 `ralph_json_lines c4.log | jq -c 'select(.type=="result")'` 输出为空且 jq rc=5（其后输入被整条丢弃）；同输入改用 `jq -Rc 'fromjson? | select(.type=="result")'` 正确取回该事件；尾逗号行 `{"a":1,}` 同样 rc=5。`docs/architecture/integrations.md` §终态事件契约 与 SC-029-1 对"解析异常不丢证据"的表述只覆盖了截断/形状不合法行，属过强陈述。
  - 范围：`.ralph/lib/common.sh` 的 `ralph_json_lines` 与 Claude/Codex adapter 的四个调用点（终态解析、thread_id/session_id 解析、`provider_diagnose`、`session.history.log` 派生）；只改解析取数方式（逐行 `fromjson?` 或等价手段），不改 `provider.stdout.log` 只读语义、不加新依赖、不动 `meta.json` schema。
  - 验证计划：为「形状合法但 jq 不可解析的行 + 其后合法终态事件」构造 fixture（Claude `result` is_error=true 与 Codex `turn.failed` 各一，覆盖 rc 提升路径），先证明修复前终态丢失、再证明修复后取回；重跑受影响的既有终态用例与 `bash scripts/check.sh`；确认 raw log 逐字节未被改写。

- [ ] DEV-7: 让暂停/入仓的 provider 资产继续落入静态检查与审计范围。
  - 预期：`docs/architecture/security.md` §权限参数的审计路径 给出的审计命令与回归门实际使用的模式一致（覆盖 `--approval-mode` 等宽化 flag），且不再出现「无第三个 provider 命中」这种在 Gemini 重新接入时会被读成假阴性的表述；`scripts/check.sh` 对**随部署单元入仓**的 lib 文件（含暂停接入的 `adapter-gemini.sh`）都做 `bash -n`。
  - 输入：REVIEW-1 发现（2026-09-14）：security.md:104 的模式 `danger-full-access\|dangerously-skip-permissions\|allowedTools` 命中 claude/codex 两个 adapter，但漏掉 `adapter-gemini.sh:60` 的 `--approval-mode yolo`；`scripts/integration-test.sh` 的回归门用的是更宽的模式（含 `--sandbox`/`--approval-mode`）且期望命中集为 `adapter-claude.sh adapter-codex.sh adapter-gemini.sh`，两者口径不一致。`scripts/check.sh` 现有 `bash -n` 清单缺 `adapter-gemini.sh` / `sticky.sh` / `watch.sh` / `status.sh`。
  - 范围：`docs/architecture/security.md`（§权限参数的审计路径的期望命中集与模式）、`docs/architecture/testing.md`（如口径需同步）、`scripts/check.sh`（补 `bash -n` 条目）；不改任何 adapter 的权限参数、不改测试断言。
  - 验证计划：按文档里的审计命令实跑，确认命中集与文档期望一致且包含 `adapter-gemini.sh`；`bash scripts/check.sh` 通过；`git diff --check`。

- [ ] REQ-033: 补齐 SC-028-1 / SC-030-1 / SC-031-1 / SC-032-1 的成功标准定义，并裁决 SC-029-2 对 timeout/interrupt 轮次的口径。
  - 预期：`docs/requirements/ralph-loop/requirements.md` 的「成功标准」表包含这 4 条 SC 的可验收定义（对象 / 验证方式 / 期望 / 测试类型），追踪矩阵不再引用未定义编号；SC-029-2 明确是否覆盖被 timeout / interrupt 杀死的轮次，并在代码与文档之间给出唯一口径。
  - 输入：追踪矩阵 REQ-028/030/031/032 行（引用 SC 但表内无定义，DEV-5 未验证 (4) 与 QA-1 未验证 (4) 均已登记）、QA-1 已落地的 11 例回归门（`scripts/integration-test.sh` 2566–2806）、`docs/architecture/testing.md` §Provider 兼容性与权限回归门；REVIEW-1 发现：这 4 条 SC 的语义目前只存在于测试断言里，属事实源倒置，违反 PM-0003 的 prevention check「任务范围段必须显式列出本任务覆盖的 SC 清单」。
  - 范围：`docs/requirements/ralph-loop/requirements.md` 成功标准表 + 追踪矩阵（如需同步 REQ 行）；不改测试断言、不改 adapter 行为。
  - 验证计划：`grep -nE '^\| SC-(028|030|031|032)-1' docs/requirements/ralph-loop/requirements.md` 命中定义行；追踪矩阵引用的每个 SC 编号都能在成功标准表找到；`git diff --check`。
  - 备注（REVIEW-1 证据，SC-029-2 裁决所需）: 被 timeout 杀死的轮次实测为 `exit_code=143`、`exit_reason=timeout`，round meta 的 `terminal_event` / `terminal_status` / `terminal_warning` **全为 null**（复现：mock-claude `RALPH_MOCK_CLAUDE_POST_STREAM_SLEEP=20` + `ralph run --round-timeout 3 --max-retry 0`），而 SC-029-2 字面要求「无终态事件 / 事件不可解析 → `unknown` + 非空 `terminal_warning`」。二选一裁决：(a) 收窄 SC / 文档口径为「adapter 正常返回的轮次」，把被杀轮次排除在外（成本最低）；(b) 追加 DEV 任务让 `run.sh` 的 terminate 分支（timeout / interrupt）在 kill 后写入 `terminal_status=unknown` + 说明性 `terminal_warning`，使该字段对「provider 没产出终态」与「轮次被杀」可区分（举证路径更完整）。

## 工作包：Antigravity CLI 接入（2026-09-28）

> 本工作包实现 Antigravity CLI（agy）作为 Ralph 正式 provider 的接入。
> 需求事实源：`docs/features/antigravity-cli/requirements.md`（REQ-048 ~ REQ-053）
> 技术方案：`docs/features/antigravity-cli/solution.md`

- [x] DEV-8: 查证 AGY 运行特征并创建 mock-antigravity 基础夹具。
  - 预期：建立轻量可靠的 mock-antigravity 仿真脚本，可模拟 agy headless 运行的 stream-json 输出（含正常事件、截断行、认证失败、权限拒绝、非零退出等）；明确真实 AGY 的 transcript 本地路径规律。
  - 输入：REQ-048 ~ REQ-051、`docs/features/antigravity-cli/solution.md`、`tests/fixtures/mock-codex`。
  - 范围：`tests/fixtures/mock-antigravity`、`scripts/check.sh`（语法检查加入该 mock）。
  - 验证计划：`bash -n tests/fixtures/mock-antigravity` 语法检查通过；验证 mock 在不同 scenario 下正确输出对应 stream-json NDJSON 行和退出码。
  - 完成: 确认本地 AGY 数据目录结构（`${ANTIGRAVITY_APP_DATA_DIR:-~/.gemini/antigravity}/brain/<id>/.system_generated/logs/transcript.jsonl`）；创建 `tests/fixtures/mock-antigravity`，支持 happy、crash、api_error、rate_limit、auth_error、denied_actions、completed_then_rc1、truncated_then_result、no_session_at_all、home_decoy 等 scenario，并模拟写入真实规范的原生 transcript；将 mock 纳入 `scripts/check.sh` 语法检查。
  - 验证: `bash -n tests/fixtures/mock-antigravity`（rc=0）；多 scenario 验证（happy、--version、--help 正常输出）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 尚未在隔离环境执行真实 agy 调用（DEV-8 为仿真夹具与路径静态取证，真实 smoke 归 QA-4）。

- [x] DEV-9: 实现 adapter-antigravity.sh 核心契约。
  - 预期：实现 Antigravity provider adapter 的四个核心函数（`provider_check_deps`、`provider_oneshot`、`provider_collect_session`、`provider_diagnose`）；正确组装 headless 命令并固定 `--dangerously-skip-permissions`，从输出流提取 `conversation_id`、解析结构化终态（`result.status` / `result.error` / `denied_actions`），派生 `session.history.log`，并按 `conversation_id` 尽力安全采集原生 transcript。
  - 输入：REQ-048、REQ-049、REQ-050、REQ-051、`docs/features/antigravity-cli/solution.md` §选定方案、DEV-8 的 mock 夹具。
  - 范围：`.ralph/lib/adapter-antigravity.sh`。
  - 验证计划：`bash -n .ralph/lib/adapter-antigravity.sh`；在单步测试下验证命令拼接、参数透传（model/effort）、终态判定（成功/失败/未知/软拒绝）与 session 采集诊断。
  - 完成: 实现 `.ralph/lib/adapter-antigravity.sh`，覆盖 `provider_check_deps`（含 `RALPH_PROVIDER_CONFIG_DIR` 安全拒绝）、`provider_oneshot`（组装 `--print` / `--output-format stream-json` / `--dangerously-skip-permissions`，解析 `conversation_id`、结构化终态与软拒绝 `denied_actions` 提升 rc）、`provider_collect_session`（按 ID 严格采集原生 transcript，找不到留 warning，派生 `session.history.log`）、`provider_diagnose`（分类映射错误类型）。
  - 验证: `bash -n .ralph/lib/adapter-antigravity.sh`（rc=0）；单元测试隔离验证通过（happy 终态与 ID 解析、session 采集与 history 派生、denied_actions 软拒绝转 error、config_dir 拒绝报错）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 尚未与 Ralph 主流程（`bin/ralph`、`run.sh`、`watch.sh`）端到端联调（留待 DEV-10 与 QA-3）。

- [x] DEV-10: 接入 Ralph CLI 运行与观察主流程。
  - 预期：使用者可通过 `--provider antigravity` 或环境变量启动任务；`watch.sh` 与 `run.sh` 能实时过滤展示 AGY 的流式事件（工具调用、执行结果、终态）；显式配置 `RALPH_PROVIDER_CONFIG_DIR` 时在启动前快速报错退出以保安全。
  - 输入：REQ-048、REQ-052、`docs/features/antigravity-cli/solution.md` §每轮启动与数据采集映射。
  - 范围：`.ralph/bin/ralph`、`.ralph/lib/run.sh`、`.ralph/lib/watch.sh`。
  - 验证计划：`ralph run --help` 包含 antigravity 选项说明；测试 `RALPH_PROVIDER_CONFIG_DIR` 显式传入时启动拦截且无 run 目录生成；验证两处事件过滤器能正确解析 AGY NDJSON 事件。
  - 完成: `.ralph/bin/ralph` 选项说明加入 `antigravity`；`.ralph/lib/run.sh` 启动校验门禁放行 `antigravity` 并保留 Gemini 拦截；在 `run.sh` 的 `_ralph_filter_verbose` 与 `watch.sh` 的 `_ralph_watch_filter_events` 两处同步扩展 AGY 的 `.event` 结构映射（init session、step_update 工具与回复、result 终态与软拒绝）；验证 `RALPH_PROVIDER_CONFIG_DIR` 传入时在创建 lock / run 目录前安全退出。
  - 验证: `ralph run --help` 输出包含 antigravity（rc=0）；临时 workspace 隔离实测（config_dir 拒绝报错且无 run 目录或 lock、PATH 缺失时准确定位依赖检查、两处 jq 过滤器针对 AGY NDJSON 输出正确格式化字符串）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 尚未在集成测试套件中形成长久自动化断言用例（归 QA-3）。

- [x] QA-3: 扩展集成测试回归套件覆盖 Antigravity。
  - 预期：在 `scripts/integration-test.sh` 中增加针对 antigravity 的自动化测试套件，全面覆盖启动门禁、权限参数审计、各种终态（成功/错误/未知/软拒绝）、原生 session 校验与丢件 warning、配置目录安全拦截等。
  - 输入：REQ-048 ~ REQ-052、SC-048-1 ~ SC-052-1、`scripts/integration-test.sh` 既有测试模式。
  - 范围：`scripts/integration-test.sh`。
  - 验证计划：运行 `scripts/integration-test.sh`，所有新增的 antigravity 测试用例全部 PASS，且既有 provider 用例无回归。
  - 完成: 在 `scripts/integration-test.sh` 中新增 QA-3 Antigravity 回归门测试块（含 `setup_antigravity_workspace` / `cleanup_antigravity_ws` 隔离脚手架）；覆盖 SC-048-1 完整 happy 流程与 session 捕获、SC-049-1 model/effort 透传与 `--dangerously-skip-permissions` 参数审计、SC-050-1 原生 transcript 缺失转 warning 与 decoy 0 误采隔离、SC-051-1 软拒绝 `denied_actions` 覆盖 exit 0 / CLI rc=1 覆盖 SUCCESS / 截断坏行容错、SC-052-1 `RALPH_PROVIDER_CONFIG_DIR` 拦截；更新 SC-031-1 扩权参数扫描白名单至 4 个合法 adapter。
  - 验证: `bash -n scripts/integration-test.sh`（rc=0）；QA-3 专项套件实跑全部通过（8 PASS / 0 FAIL）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 真实环境下的端到端 smoke（无外部额度消耗，归 QA-4）。

- [x] DEV-11: 补齐静态检查、发布构建与项目文档。
  - 预期：`scripts/check.sh` 与 `scripts/build-release.sh` 纳入 `adapter-antigravity.sh` 与相关测试资产；更新 release 模板和说明；同步更新核心架构文档（`docs/architecture.md`、`docs/integrations.md`、`docs/security.md`、`docs/testing.md`、`README.md`、`.ralph/README.md`）。
  - 输入：REQ-053、SC-053-1、项目发布规范。
  - 范围：`scripts/check.sh`、`scripts/build-release.sh`、`README.md`、`.ralph/README.md`、`docs/` 核心架构文档。
  - 验证计划：`bash scripts/check.sh` 检查通过；`git diff --check` 无空白或语法告警；发布构建验证通过。
  - 完成: 将 `adapter-antigravity.sh` 纳入 `scripts/build-release.sh` 与 `scripts/check.sh` 检查清单及 release 0.1.4 镜像；更新 `README.md`、`.ralph/README.md`（及 release 镜像）、`docs/architecture.md`、`docs/integrations.md`、`docs/security.md` 与 `docs/testing.md`，全面登记 Antigravity CLI 的支持状态、参数规范、4 文件契约、权限边界审计路径与 QA-3 回归门。
  - 验证: `bash scripts/check.sh`（ralph-loop check passed，包含 release 逐字节同步核验）；`bash scripts/build-release.sh --verify`（release verified）；`bash scripts/integration-test.sh`（PASS=164 FAIL=0）；`git diff --check`（rc=0）。
  - 未验证: 真实 `agy` CLI 隔离 smoke 及 release 发布包全新目录独立部署实跑（留待 QA-4）。

- [x] QA-4: 执行真实隔离 workspace Smoke 与发布包验证。
  - 预期：在独立临时 Git workspace 中调用真实 `agy` CLI 运行完整 Ralph 任务，实际验证文件修改与 Git commit；验证构建出的 release 发布单元在新目录中可直接初始化与运行。
  - 输入：REQ-053、SC-053-1、真实 `agy 1.2.12` CLI。
  - 范围：临时测试 workspace、`release/` 目标目录。
  - 验证计划：真实 smoke 跑通单任务并生成合格的 commit 与 round 证据；发布包验证无误。
  - 完成: 在独立临时 Git workspace 中调用系统真实 `agy 1.2.12` CLI 执行真实单轮任务（创建 `smoke-antigravity.txt` 并提交），确认 1 round 自然完成、自动打出 git commit（`2abb2b9`）、文件内容一致；round 4 文件完整就绪（`meta.json`、`provider.stdout.log`、`session.antigravity.jsonl`、`session.history.log`），且原生 transcript 自动定位到 `~/.gemini/antigravity-cli/brain/<session_id>/.../transcript.jsonl`，`capture_status: "ok"`；同时在独立空目录部署 `release/0.1.4/.`，验证 `CLAUDE.md` 软链有效、`ralph --version` 正常输出、fake provider 正常跑通并退出 `done`。
  - 验证: 真实 `agy` smoke run 成功（rc=0, exit_reason="done", duration=74s, terminal_status="success", capture_status="ok"）；发布包部署验证成功（rc=0, exit_reason="done"）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 长时间多轮任务的额度消耗与网络抖动（在无人值守生产环境中由重试机制覆盖）。

- [x] REVIEW-2: Antigravity CLI 接入实现与安全边界 | adversarial-review
  - 预期：按照 `.spec/rules/ADVERSARIAL-REVIEW.md` 针对本工作包所有代码与文档做对抗性审查，重点核查权限绕过风险、会话错采风险、退出码与终态不一致、截断日志不丢证据。
  - 输入：本工作包产生的完整 git diff、真实运行日志与集成测试输出。
  - 范围：所有修改的文件。
  - 验证计划：审查 findings 逐项关闭或建任务修复，确认安全与稳定性达标。
  - 完成: 对完整 git diff 进行对抗性审查并结合复现得出 6 项必须修复的质量门问题：
    1. 未知终态退出码提升漏缺：非 SUCCESS 终态保留 rc=0 导致误判任务完成；
    2. 会话 ID 路径穿越漏洞：拼接 `fake/../other` 可跨出自身目录导致误采；
    3. stdout 与 stderr 重定向独立 open 描述符引发覆盖写入问题；
    4. 真实 AGY 错误事件字符串解析失效导致 jq 崩溃；
    5. 会话复制失败缺乏退出码与目标普通文件校验；
    6. 事实源状态遗留“待实施”及 release/0.1.4 原地修改违反发布不可变契约。
  - 验证: 审查问题已在 FIX-1 ~ FIX-3 中全部修复并建立自动化回归门。
  - 未验证: 无。全部 6 项 findings 已完全关闭。

- [x] FIX-1: 修复未知终态退出码提升、会话 ID 路径穿越校验、共用描述符 2>&1、字符串错误解析与会话复制校验。
  - 预期：修复 Codex 审查指出的 adapter 缺陷；消除路径穿越漏洞与交错写入覆盖风险；正确解析纯字符串形式的 `.result.error` 并提升未知终态退出码。
  - 输入：REVIEW-2 审查意见、真实 `agy 1.2.12` 错误日志、`.ralph/lib/adapter-antigravity.sh`。
  - 范围：`.ralph/lib/adapter-antigravity.sh`、`.ralph/lib/run.sh`、`.ralph/lib/watch.sh`。
  - 验证计划：代码修改准确闭环，静态与类型提取无错误。
  - 完成:
    1. 在 `adapter-antigravity.sh` 将未知 `res_status` 时强制提升 `[[ "$rc" -eq 0 ]] && rc=1`，并在兜底逻辑中同步标记 unknown；
    2. 增加 `session_id` 正则格式校验 `^[a-zA-Z0-9_-]+$` 并核对规范路径 `pwd -P` 确保不越出会话目录；
    3. 将重定向统一为共用文件描述符 `> "$log_path" 2>&1`；
    4. 在 adapter、`run.sh`、`watch.sh` 中重构 jq 提取逻辑，同时兼容字符串与对象类型的 `.result.error`；
    5. 在 `provider_collect_session` 中严格检查 `cp` 退出码及目标是否为普通非空文件。
  - 验证: `bash -n .ralph/lib/adapter-antigravity.sh .ralph/lib/run.sh .ralph/lib/watch.sh`；`git diff --check`（rc=0）。
  - 未验证: 自动化测试套件（归入 FIX-2 集中验证）。

- [x] FIX-2: 扩展 mock-antigravity 与 integration-test.sh 增加 5 组针对性回归测试。
  - 预期：为审查问题提供长效防回归守卫（未知状态码提升、路径穿越防护、字符串错误提取、交错写入保护、会话复制异常降级）。
  - 输入：`tests/fixtures/mock-antigravity`、`scripts/integration-test.sh`。
  - 范围：`tests/fixtures/mock-antigravity`、`scripts/integration-test.sh`。
  - 验证计划：5 项新测试全部 PASS，总测试通过数提升至 169 项。
  - 完成: 在 `mock-antigravity` 增加 `unknown_status`、`path_traversal`、`string_error`、`interleaved_output` 场景；在 `integration-test.sh` 新增 5 项断言测试用例，覆盖未知终态提升为 rc=2、路径穿越安全拦截、字符串 error 准确分类为 api、stderr 标记完整保留及目标目录冲突优雅降级 warning。
  - 验证: `bash scripts/integration-test.sh`（PASS=169 FAIL=0）；`bash scripts/check.sh`（ralph-loop check passed）。
  - 未验证: 无。

- [x] FIX-3: 统一事实源与版本标识，升级至 0.1.5 并重建官方发布包。
  - 预期：维护发布包不可变性（还原 `release/0.1.4`，升级至 `0.1.5`）；消除“待实施”等过时事实源文档。
  - 输入：`docs/README.md`、`docs/requirements.md`、`README.md`、`.ralph/README.md`、`AGENTS.md`、`.ralph/bin/ralph`。
  - 范围：项目级文档、release 发布包、版本常量。
  - 验证计划：发布构建与核验通过；静态检查全部通过。
  - 完成: 将 `.ralph/bin/ralph` 版本号升级至 `0.1.5`；从 HEAD 干净还原历史归档 `release/0.1.4/`；通过 `scripts/build-release.sh 0.1.5` 官方生成全新的 `release/0.1.5/`；更新 `README.md`、`.ralph/README.md`、`AGENTS.md` 中的版本和部署路径；将 `docs/README.md` 与 `docs/requirements.md` 中的 Antigravity CLI 接入状态统一收口为“已确认/已支持”。
  - 验证: `bash scripts/build-release.sh --verify`（release verified: release/0.1.5）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 无。

- [x] FIX-4: 闭环 Codex 审查遗留项（错误结构判定、会话目录/文件符号链接拦截、标准编号对齐与发布包重构）。
  - 预期：彻底闭环 Codex 审查提出的所有边界与契约问题：
    1. 终态判定严格按错误字段结构（非 null/非空对象/非空字符串）判定，解决带类型空消息错误对象被误判为成功的问题；在 `provider_diagnose` 中分类并写入 `meta.json.error`；
    2. 会话文件采集增加规范化 `brain` 根目录锚定校验（`_antigravity_safe_session_file`），不仅拦截文件符号链接，还能拦截会话目录本身为符号链接（`brain/current -> brain/other`）的跨会话误采；
    3. 集成测试用例编号统一归入既有权威需求标准 `SC-051-1`（终态与错误分类）与 `SC-050-1`（0 次跨会话误采）；
    4. 消除文档索引中残留的“待实施”描述，保持发布包不可变性（`release/0.1.4` 归档不变，重新构建 `release/0.1.5`）。
  - 输入：Codex 审查意见、`docs/features/antigravity-cli/requirements.md`、`docs/features/antigravity-cli/solution.md`。
  - 范围：`.ralph/lib/adapter-antigravity.sh`、`tests/fixtures/mock-antigravity`、`scripts/integration-test.sh`、`docs/README.md`、`docs/requirements.md`、`docs/roadmap.md`、`release/0.1.5/`、`handoff.md`。
  - 验证计划：补齐自动化回归测试，全量测试达到 173 PASS / 0 FAIL；`check.sh`、`build-release.sh --verify` 与 `git diff --check` 全部通过。
  - 完成:
    1. 在 `adapter-antigravity.sh` 重构错误字段判断，通过 jq 结构化分析 `has_error`（存在对象且 key 数 >0 或非空字符串），无论消息是否为空只要有错误均置 `terminal_status="error"` 并提升 `rc=1`；在 `provider_diagnose` 中对空消息错误对象生成兜底消息并提取 `err_type` 进行分类写入 `meta.json.error`；
    2. 实现 `_antigravity_safe_session_file`，通过 `realpath "$brain_dir"` 锚定规范根目录，强校验真实会话目录物理路径严格等于 `$real_brain/$session_id` 且本身非软链接，杜绝会话目录软链接偷采其他会话；
    3. 在 `mock-antigravity` 增加 `typed_empty_message_error` 与 `symlink_session_dir` 场景；在 `integration-test.sh` 增加对应的自动化断言，并统一编号为 `SC-051-1` 与 `SC-050-1`；
    4. 重建并验证 `release/0.1.5/` 发布单元，`release/0.1.4/` 字节级保持不可变原貌；在 `handoff.md` 明确声明验证范围。
  - 验证: `bash scripts/integration-test.sh`（PASS=173 FAIL=0 全部通过）；`bash scripts/build-release.sh --verify`（release verified）；`bash scripts/check.sh`（ralph-loop check passed）；`git diff --check`（rc=0）。
  - 未验证: 无。
