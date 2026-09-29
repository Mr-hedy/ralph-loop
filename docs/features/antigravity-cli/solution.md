# Antigravity CLI 接入方案

> 状态：已实施并已通过真实验证（2026-09-29 `release/0.1.5` 独立烟测通过）。命令、流式事件、原生 transcript 路径与配置隔离拦截均已在自动化回归与真实 smoke 中核实，发布包已正式支持 `antigravity`。

## 摘要

选用 **流式输出优先**：每轮启动全新的 `agy` headless 进程，将 stdout/stderr 原样保存为现有 round 的 `provider.stdout.log`；从其结构化事件派生 session ID、终态、错误和 `session.history.log`。原生 transcript 是经本轮身份校验后才复制的附加证据；找不到时留下采集 warning，不以其他会话或 CLI 诊断日志填充。

## 落点

- 权威需求：[`requirements.md`](./requirements.md)（REQ-048 ~ REQ-053）。
- 独立文档理由：新增 provider 涉及流式事件、原生会话、权限和配置域的真实取舍；在验证完成前，不把未确认行为写入当前已生效的 [`../../integrations.md`](../../integrations.md) 或 [`../../architecture.md`](../../architecture.md)。
- 当前支持矩阵以 `release/0.1.5` 发布包为准；本方案经真实 smoke 后已同步集成、安全、架构与使用入口。

## 需求追踪

| 需求或场景 | 方案覆盖方式 | 验证结果 |
|---|---|---|
| REQ-048、SC-048-1 | `antigravity` 映射原生 `agy`，走现有 adapter 三函数及 run 生命周期 | 已验证（QA-3 回归 + QA-4 真实 smoke 通过） |
| REQ-049、SC-049-1 | headless oneshot 固定自动批准；model/effort 有值才传 | 已验证（参数透传与真实 commit 提交通过） |
| REQ-050、SC-050-1 | 原始流为必有证据；ID、history 从流派生；原生 transcript 按 ID 尽力采集 | 已验证（0 误采回归 + `release/0.1.5` 真实 34,219 字节 transcript 采集） |
| REQ-051、SC-051-1 | 结构化终态优先，进程退出码独立校验，权限拒绝单独诊断 | 已验证（软拒绝覆盖 exit 0 + CLI 非零覆盖 SUCCESS + 截断容错通过） |
| REQ-052、SC-052-1 | 显式配置目录仅在有受支持的覆盖方式时接受 | 已验证（显式设置时快速失败，exit 1 无 run 产物） |
| REQ-053、SC-053-1 | 只在发布包部署和真实 smoke 通过后宣称正式支持 | 已验证（174 项集成测试通过 + `release/0.1.5` 独立真实部署通过） |

## 治理约束

- 保持 Ralph 的 fresh oneshot、`.ralph/TASKS.md` 完成事实源、现有 run/status/result 格式、adapter 三函数和 round 四文件契约。
- `provider.stdout.log` 保留 stdout/stderr 原始字节；解析和派生都只读。捕获失败不阻断已成功的 oneshot，但错误终态必须影响 run 结果。
- 权限策略写死在 provider adapter，不引入 `--approval` 或 `--sandbox` 的公共运行参数；原始会话可能含敏感信息，继续由 `.ralph/.gitignore` 排除版本控制。

## 研究结论与取舍

| 问题 | 决策 | 理由 | 备选及代价 |
|---|---|---|---|
| 实时过程从哪里采 | 使用 `--output-format stream-json` 的 stdout | 官方协议有 `init`、`step_update`、终态 `result`；现有 `watch` 也以 `provider.stdout.log` 为源 | 只取最终 JSON 会失去轮次运行中的工具和文本事件 |
| 原生会话从哪里采 | 以 stdout 中的 `conversation_id` 为身份锚点；仅复制经真实 smoke 确认的本轮 transcript | 官方状态行文档的 `transcript_path` 为可选字段，不能证明 headless 总会提供稳定文件 | 按 mtime 取最新文件会在并发或其他 AGY 会话存在时误采 |
| 原生会话缺失时 | `capture_status=warning/missing`，保留原始流与派生历史 | 符合现有 best-effort 契约，原始流已有完整外部事件 | 把缺失视为 run 失败会让私有存储格式变化阻断任务执行 |
| CLI `--log-file` | 不作为原生 session 来源 | 该参数属于 CLI 诊断日志覆盖；没有证据证明它是会话 transcript | 混用诊断日志会制造虚假的 session 证据 |
| token usage | 原样保留在 `result.usage` 和各 step 的 `usage`，本轮不增公共元数据字段 | 用户要求与现有 provider 等价的采集，公共汇总 schema 尚无需求 | 把 step usage 相加再与 result usage 相加会重复统计 |
| 配置域覆盖 | 只接受经官方资料和真实 smoke 验证的 AGY 原生方式；否则显式配置时启动失败 | 避免忽略 `RALPH_PROVIDER_CONFIG_DIR` 后误用默认账号 | 直接复用其他 CLI 的配置变量缺少 AGY 证据 |

研究依据：[AGY Headless 协议](https://www.antigravity.google/docs/cli/headless/)、[AGY 状态行字段](https://www.antigravity.google/docs/cli/statusline/)、[AGY CLI 诊断日志说明](https://www.antigravity.google/docs/enterprise)。

## 选定方案

### 1. 每轮启动

- 新增 Antigravity adapter，提供现有 `provider_check_deps`、`provider_oneshot`、`provider_collect_session`、`provider_diagnose` 契约。
- `provider_oneshot` 从既有 prompt 文件构造一个 `agy --print <prompt> --output-format stream-json --dangerously-skip-permissions` 调用；model/effort 有值才附加，`none` 不传。沿用现有大 prompt 参数上限保护。
- 不传 `--continue`、`--conversation` 或 `--input-format stream-json`：Ralph 每轮新起一个进程和会话，不在一个 AGY 进程内追加多轮 prompt。
- 继续由 Ralph 负责 round timeout 和进程树清理；不依赖 AGY 自身的 `--print-timeout` 默认值。

### 2. 数据采集映射

| AGY 数据 | Ralph 落点 | 处理规则 |
|---|---|---|
| 完整 stdout/stderr | `round-NNN/provider.stdout.log` | 先原样落盘；stderr 与 NDJSON 混合时，仅在读取侧过滤合法事件行 |
| `init.conversation_id` 或事件顶层 `conversation_id` | `meta.json.session_id` | 本轮唯一身份锚点；缺失则记录采集 warning，不猜其他会话 ID |
| `step_update` 中的 `agent_response.text_delta` | `session.history.log`、`watch`/`run -v` 人类视图 | 按事件顺序拼接增量文本，避免把 ACTIVE 与 DONE 内容重复打印 |
| `step_update` 中的 `tool_name`、`tool_info`、`subagent_info` | `session.history.log`、终端事件摘要 | 保留可解释的工具、结果和子 agent 摘要；完整参数及输出仍以原始 log 为准 |
| 末尾 `result.status`、`result.error`、权限拒绝信息 | `meta.json.terminal_*`、`meta.json.error`、run 级 `last_error` | `SUCCESS` 且无拒绝/错误才是成功终态；`ERROR` 等失败状态为 error；无有效末尾事件为 unknown；进程非零仍按失败处理 |
| `result.usage` 和 step usage | `provider.stdout.log` | 保留原始字段，不新增 token 汇总字段；fresh oneshot 的最终 usage 按本次会话解释，不与 step usage 累加 |
| 经核实的本轮原生 transcript | `session.antigravity.jsonl`、`meta.json.session_source_path/session_copied_path/capture_status` | 只接受路径或内容与本轮 `conversation_id` 可核对的文件；没有可靠文件时不创建假副本 |

从 `provider.stdout.log` 派生 `session.history.log`，即使原生 transcript 缺失也尽量提供人类视图。现有 `_ralph_filter_verbose` 主要识别 `.type`，AGY 使用 `.event`；实施时必须增加 AGY 映射，否则 `watch` 虽在增长，事件区却可能为空。原始流里未出现的 user prompt、thinking 或工具细节不得在派生视图中补造。

### 3. 终态与故障

- `result` 事件的 `status` 是 AGY 的结构化终态；进程退出码单独记录。二者冲突时保留两种证据并按失败处理，不把 exit 0 当作完成证明。
- `denied_actions` 的精确字段位置和形态以 `agy 1.2.12` 的真实 fixture 校准；一旦有工具被拒，不能把该轮标成正常成功。错误信息优先取结构化 `result.error`，再取工具错误和 stderr；类别映射沿用现有 `auth`、`quota`、`rate_limit`、`network`、`concurrency`、`api`、`unknown`。
- 不存在可解析的末尾 `result`，或事件被截断时，记录 `terminal_status=unknown` 和原因；原始 log 不重写，后续合法事件仍可解析。
- 会话副本未找到只影响 `capture_status/capture_warning`，不覆盖 AGY 终态或任务判定。

## 边界与兼容性

- 受影响：Ralph provider 入口与新 adapter、终端事件过滤、mock fixture 与集成测试、构建发布包、`docs/integrations.md`、`docs/security.md`、`docs/architecture.md`、`docs/testing.md` 及 README 支持矩阵。
- 不改变 Claude/Codex adapter、既有 round 元数据字段或 `result.json` schema；`session.antigravity.jsonl` 仅在经校验的原生文件存在时出现。
- `RALPH_PROVIDER_CONFIG_DIR` 未设置时不新增 AGY 配置变量；显式设置且无已验证映射时，在创建 run 目录前报错。后续若验证出原生映射，再在 adapter 中实现并测试隔离。
- 发布包从源构建，不能仅因开发工程里出现 adapter 就更新当前正式支持声明。

## 风险与验证方向

| 风险场景 | 影响 | 验证或处理 |
|---|---|---|
| headless 进程未写出可复制 transcript | 缺少原生会话副本 | 真实 smoke 检查本轮 `conversation_id` 与本地文件；若无可靠文件，记录 warning，并在支持说明中写清覆盖范围 |
| 其他 AGY 会话同时运行 | mtime 搜索可能错采 | 只接受 ID 校验命中；多候选 fixture 必须做到 0 次误采 |
| AGY 返回 0 但工具被拒 | 任务可能未执行 | 权限拒绝 fixture、真实修改文件及 Git 提交 smoke；终态不得误判成功 |
| stderr 混入或单行截断 | 解析器漏掉后续合法终态 | 保留原始 log 字节，使用逐行合法 JSON 读取并测试截断后合法事件 |
| AGY 升级改变事件或本地存储 | 诊断或会话采集退化 | `context.json.provider_version` 锚定版本；未知事件走 warning，回归 fixture 随真实版本更新 |
| 原始会话或工具输出带敏感信息 | 本地证据泄露 | 继续 Git 忽略 `runs/`，发布包排除运行态，分享前人工审查；不承诺自动脱敏 |

真实 smoke 必须在隔离 Git workspace 检查：`agy` 版本、headless 事件样例、权限生效、文件修改和提交、会话 ID、原生 transcript 候选、配置目录行为；再验证生成的 `release/<version>/`，并运行项目完整检查与既有 provider 回归。已于 2026-09-28 在隔离 workspace 成功执行真实 AGY oneshot 并完成全套验证：1 round 自然完成（done）、文件修改与 git commit 生成、按 ID 精准采集真实原生 transcript（19,970 字节）、配置目录拦截与发布包全新部署均已通过。

## 拒绝方案

- **原生 session 优先、stdout 仅回退**：AGY headless transcript 的稳定路径尚未确认，会让最基本的观察与诊断依赖私有存储结构。
- **按 mtime 取最新会话**：并发或其他 workspace 的 AGY 活动可产生错误归属，违背 REQ-050。
- **复制 `--log-file` 指向的 CLI 日志冒充 session**：诊断日志不等于对话 transcript，会误导复盘。
- **新增跨 provider token 汇总 schema**：超出本轮等价采集范围，并需要所有 provider 与消费端一起迁移。

## 决策

- 原始流为必有证据；原生 transcript 是身份校验后的 best-effort 附加证据。
- `agy` 使用 fresh headless oneshot 与固定自动批准权限；Ralph 保持既有轮次控制和任务完成事实源。
- 先用真实 AGY smoke 校准原生 transcript、权限拒绝字段和配置目录行为，再冻结实现细节与正式支持声明。
