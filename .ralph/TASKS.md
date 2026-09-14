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

- [x] DEV-4: 强化 Codex native session 采集的活动/归档兼容性。
  - 预期：按 session id 校验并从活动或归档目录复制 session；找不到、截断或格式不匹配时 oneshot 仍完成且留下诊断。
  - 输入：REQ-030、Codex session 文档、现有 `provider_collect_session` 实现。
  - 范围：Codex adapter、meta 字段和针对配置目录隔离的测试；不改变 fresh oneshot 语义。
  - 验证计划：构造活动/归档/错误 rollout fixture，运行集成测试并检查 `session.history.log` 与错误诊断。

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
  - 输入：REQ-032、`.spec/rules/adversarial-review.md`、现有 `scripts/integration-test.sh`。
  - 范围：测试脚本与最小 fixture，不引入外部框架或 ACPX 重构。
  - 验证计划：完整 `bash scripts/check.sh`、完整集成测试、Claude/Codex smoke（可执行时）及 adversarial review 结论。
  - 完成: (1) 新增 11 例回归门（`scripts/integration-test.sh`「QA-1」段，位于 codex dep-check 之后、Gemini 历史块之前）：SC-028-1 入口收敛 4 例（`--provider` flag / `.env` `RALPH_PROVIDER` / 进程 env / mock gemini CLI 位于 PATH），统一断言 rc=1 + `temporarily disabled` + `claude, codex or fake` + 无 `runs/`/`lock`/`status.json`；SC-030-1 采集鲁棒性 4 例（Codex 归档 rollout 靠内嵌 id 命中且复制件与原件逐字节一致、Codex 采集完全缺失 → warning + run 仍 `done` + `session.history.log` 仍由 stdout 派生 + raw log 保留、Codex/Claude 配置目录隔离诱饵各 1）；REQ-029 组合 1 例（`turn.completed` + CLI 非零退出 → `provider_failed`，success 终态不掩盖退出码）；SC-031-1 权限审计 2 例（Claude 权限参数运行时 argv 审计、扩权 flag 文件扫描）。(2) fixture 扩展（沿用单一来源 mock，不新建）：`mock-codex` 新增 `_write_archived_session` helper 与 4 个 scenario（`archived_session` / `no_session_at_all` / `home_decoy` / `completed_then_rc1`）；`mock-claude` 新增 `home_decoy` scenario，并在 argv 解析回显 `--dangerously-skip-permissions` / `--allowedTools`（`_emit_init` 追加 `_received_skip_permissions` / `_received_allowed_tools`，沿用 `_received_effort` 模式）。(3) 诱饵判别力变异实验：`home_decoy` 由 mock 在**采集期内**（`provider_started_at` 之后）向真实 HOME 配置目录写同名 session，刻意忽略 `CLAUDE_CONFIG_DIR`/`CODEX_HOME`；去掉这两个变量后诱饵确实被采成 `capture_status=ok`（Claude 路径记 `fallback by mtime`），证明隔离用例能区分「隔离生效」与「回落泄露」。首版诱饵写在 run 之前，Claude 侧因时间锚点不命中而退化成恒真断言，已修正。(4) `scripts/check.sh` 纳入测试层 `bash -n`（`integration-test.sh` + 3 个 mock fixture）。(5) 文档同步：`docs/architecture/testing.md` 新增「Provider 兼容性与权限回归门（QA-1）」段（用例矩阵 / 诱饵判别力 / 权限已知缺口 / Gemini 测试层状态 / 真实 smoke 口径）；`docs/requirements/ralph-loop/requirements.md` 追踪矩阵 REQ-028/029/030/031/032 行由「待新增」改为本轮实际覆盖与剩余部分。
  - 验证: `bash scripts/check.sh` → `ralph-loop check passed`（rc=0）；完整 `env -u RALPH_WORKSPACE -u RALPH_PROVIDER -u RALPH_LOOP_MAX_ROUND -u RALPH_LOOP_MAX_RETRY -u RALPH_LOOP_STALL_LIMIT -u RALPH_LOOP_ROUND_TIMEOUT bash scripts/integration-test.sh` → `PASS=156 FAIL=0`、`EXIT=0`（新增 11 例在整套中逐条 `[PASS]`：gate gemini ×4 / codex archived session / codex no session / codex CODEX_HOME isolation / claude CLAUDE_CONFIG_DIR isolation / codex completed_then_rc1 / claude permission audit / permission flag scan；Gemini 历史块仍为 `if false` 跳过）；回归门聚焦复跑（抽取 harness + QA-1 段的临时脚本，同一 clean env）→ `PASS=11 FAIL=0`；变异实验：`env -u CODEX_HOME` → codex 诱饵 `capture_status=ok`、`copied=YES`；`env -u CLAUDE_CONFIG_DIR` → claude 诱饵 `capture_status=ok`、`capture_warning=fallback by mtime`、`copied=YES`；可执行性核对（本地、零额度）：`claude 2.1.270` / `codex-cli 0.153.4` / `jq 1.7.1` / `git 2.50.1` 均在 PATH，`claude --help` 含 `--dangerously-skip-permissions`（"Bypass all permission checks"）与 `--allowedTools`，`codex exec --help` 的 `-s, --sandbox` possible values = `read-only / workspace-write / danger-full-access`（即 adapter argv 被真实 CLI 接受）；`git diff --check` → 无输出（rc=0）。
  - 未验证: (1) 真实 Claude/Codex CLI 端到端 smoke 未执行（只做本地 `--version` + `--help` 可执行性核对，避免消耗 provider 额度，与 DEV-3/DEV-5 口径一致）；REQ-032 的「可执行性 smoke」因此只覆盖「CLI 存在且接受 adapter 的权限 flag」，未覆盖「真实 CLI 跑通一轮 run」。(2) SC-031-1 的 meta 记录要求未满足：`meta.json` 无权限字段，回归门只审计 adapter 源码 + provider 回显 argv；属新 REQ 决策（DEV-5 未验证 (6) 已登记 security.md）。(3) 完整集成测试仅在剥离宿主 `RALPH_*` 变量后作门禁结论；携带宿主变量时仍非全绿（PM-0005，归 QA-2），本轮未在带变量环境跑完整套件。(4) `requirements.md` 追踪矩阵引用的 SC-028-1/SC-030-1/SC-031-1/SC-032-1 仍无「成功标准」表定义（DEV-5 未验证 (4) 已登记）；QA-1 范围是测试脚本，未补 SC 定义，请 REVIEW-1 复核是否需由 REQ 任务补齐。(5) Codex 归档目录不参与 mtime 降级路径，本轮只测归档 id 命中，未测「归档 + 无 thread_id + 需 mtime」组合；归档 rollout 内容损坏（首行非法 JSON）时的诊断未单独建用例。(6) 扩权 flag 扫描是文本 grep，不构成语义证明：新增 provider 若用短选项（`-s danger-full-access`）或环境变量表达沙箱策略不会被命中。(7) 运行期发现 `.ralph/TASKS.md` 于 2026-09-14T08:56Z（本 round 进行中，run_id `20260914-083503-fbe4d33` task_started_at 08:50:51Z）被外部改写：QA-1 与 REVIEW-1 被同时勾成 `[x]` 且无完成字段。两次连续勾选与 mock `_check_first_task`「勾掉第一条未勾选任务」的行为一致，疑似某用例未隔离 workspace 时让 mock 写到真实 workspace——即 QA-2 的追加排查项，本轮未定位到具体用例。QA-1 的 `[x]` 已由本轮补齐真实完成字段；**REVIEW-1 的 `[x]` 无任何证据支撑（adversarial review 未执行），已由本轮回退为 `- [ ]`，避免 ralph 外层误判该工作包已完成 adversarial 复核**。

- [ ] REVIEW-1: 对本工作包全部修改做 adversarial review。
  - 预期：只报告有证据的高信号问题；重点检查 provider 输出完整性、权限扩大、路径穿越/错误 session 复制、Gemini 绕过入口和失败时的状态一致性。
  - 输入：REQ-028~REQ-032、全部代码/文档 diff、测试输出。
  - 范围：`.ralph/`、`scripts/`、README 和 architecture/requirements 文档；遵循 `.spec/rules/adversarial-review.md`。
  - 验证计划：逐项复核 diff，重跑受影响测试；发现问题则追加修复任务，不以 exit code 0 代替结论。

- [ ] QA-2: 让集成测试对继承的 `RALPH_*` 环境变量免疫。
  - 预期：在携带 `RALPH_PROVIDER` / `RALPH_LOOP_MAX_RETRY` / `RALPH_LOOP_MAX_ROUND` / `RALPH_LOOP_STALL_LIMIT` / `RALPH_LOOP_ROUND_TIMEOUT` / `RALPH_WORKSPACE` 的宿主进程里跑集成测试，结论与干净环境一致；用例断言 ralph 参数默认值前必须显式隔离（`env -u <VAR>` 或显式 CLI flag）。
  - 输入：PM-0005（`docs/postmortems/pm-integration-test-env-inheritance.md`）；DEV-3 round 发现的 `-- Provider retry: status.json` 假失败（`env RALPH_LOOP_MAX_RETRY=0` 失败 / `env -u RALPH_LOOP_MAX_RETRY` 通过，pristine HEAD 同样复现）。
  - 范围：`scripts/integration-test.sh` 的用例环境隔离（含 setup helper 统一清理继承变量）；不改 `load_env` 的优先级契约（CLI flag > 进程 env > `.env`）。额外排查：测试运行期间真实 workspace `.ralph/TASKS.md` 被外部改动（2026-09-14 08:38:29 UTC 的 DEV-3/DEV-4 勾选），确认是否为某用例在未隔离 `RALPH_WORKSPACE` 时让 fake/mock provider 写到了真实 workspace；若是，属于测试隔离越界，必须一并修掉。
  - 验证计划：`env RALPH_LOOP_MAX_RETRY=0 RALPH_PROVIDER=claude RALPH_LOOP_MAX_ROUND=4 bash scripts/integration-test.sh` 与 `env -u RALPH_LOOP_MAX_RETRY -u RALPH_PROVIDER -u RALPH_LOOP_MAX_ROUND bash scripts/integration-test.sh` 两种环境下全绿；跑完后 `git status .ralph/TASKS.md` 无变化。
