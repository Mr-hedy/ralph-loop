# Ralph Loop 需求文档

## 摘要

Ralph Loop 是一个 shell-first CLI harness，用 provider CLI 的 fresh oneshot 循环驱动长任务执行。它把任务状态、运行日志、退出原因和 provider 原生 session 证据沉淀在使用者 workspace 的 `.ralph/` 下，让长任务可观察、可恢复、可复盘。

## 背景

单会话连续执行长任务会让上下文持续膨胀，模型注意力下降；用户长时间会话里的失败复盘依赖临时对话记录，缺乏可回溯证据。Ralph 把长任务组织成多轮 fresh oneshot，每轮退出时把证据写盘，下一轮重新冷启动，从根本上避免上下文飘逸，并让复盘有明确的文件级事实。

## 目标

- 用 provider CLI 的 oneshot 能力驱动长任务，避免单会话上下文膨胀。
- 让 agent 每轮从 `.ralph/TASKS.md` 挑一个未完成任务，执行到完成并勾选 `[x]`，然后退出。
- 由 harness 负责循环控制、超时、退出原因、日志和 provider 原生 session 采集。
- 支持 Claude Code、Codex CLI、Gemini CLI 三个 provider，统一 adapter 接口。
- 通过 `ralph status` 和 `ralph watch` 观察当前 run 状态。
- shell-first Bash 实现，降低部署和运行环境成本。

## 非目标

- 不实现自有 agent 推理、任务规划或代码生成。
- 不提供 `ralph init` 或任何模板生成行为；ralph 工具运行时**不**写 `.ralph/PROMPT.md` / `.ralph/TASKS.md` / `.ralph/.env`，**不**修改它们做内核控制流（仅读取 TASKS.md 顶部"当前迭代"声明和任务勾选状态作为运行依据，见 REQ-020）。使用者通过部署单元 `.ralph/`（含 PROMPT.md + TASKS.md，见 REQ-017）`cp -r` 起手，再自行裁剪/补 `.env` 等私有配置。"用户自行创建"指 user-driven，不是"必须从空白起手"。
- 不把 provider session 当作任务完成事实源；任务完成只以 `.ralph/TASKS.md` 勾选为准。
- 不默认 resume provider session；每轮都是 fresh oneshot。
- 不支持全局 `ralph` 命令；只支持 per-workspace 部署。
- 不接受 `--cwd` 参数；workspace 根由脚本路径决定。
- 不引入数据库，不依赖完整 Markdown parser。
- 不做复杂 TUI；`watch` 只做最小可用的状态刷新。
- ~~不在本仓库内做任何 `ralph-loop` 自举（本仓库是开发工程，不自用 ralph）。~~ **此条 v0.1 范围内有效；v0.1.1 起本仓库进入 dogfood 模式**（自用 ralph 驱动后续 iteration 开发，详见 I1 设计方案 `docs/requirements/ralph-loop/I1-design.md`）。runtime artifacts 由本仓库 `.gitignore` 管理（`.ralph/runs/`、`.ralph/lock`、`.ralph/status.json`、`.ralph/.env`）。

## 受众

- 维护者：在真实 workspace 中跑长任务，并据此复盘。
- coding agent 协作者：通过 Bash 工具调用 `ralph run` 驱动长任务。
- ralph 工具开发者：本仓库维护者，对照本需求迭代工具本身。

## 澄清记录

### 轮次 1（结构与边界）

- 关键议题：参考来源定位、默认值来源、任务协议、并发与 resume、provider 覆盖范围、子命令命名、`.env` 位置、cwd 策略、部署形态。
- 用户裁决：独立演进 trantor-skills 和 ralph-claude-code 仅为输入参考；`.ralph/` 仅承载工具代码与运行态产物；本仓库不自用 ralph；三 provider 都做；无 `ralph init`；子命令只用 `run/status/watch`；per-workspace 部署。

### 轮次 2（运行参数与协议）

- 关键议题：max_iter / timeout / stagnation 默认、任务解析规则、changed_files base、一个 oneshot 覆盖几个 task、PROMPT 协议、退出原因。
- 用户裁决：max_iter 默认 0、timeout 默认 0、stagnation_limit 默认 5；任务解析沿用 trantor 的 `^\s*-\s+\[([ xX])\]` 不限缩进；changed_files = `git diff --name-only <start_sha>..HEAD` ∪ `git status --porcelain`；**一个 task 一个 oneshot**（PROMPT 协议硬约束）；退出状态 6 条（含 `locked` 不产生 run）。

### 轮次 3（配置与 cwd）

- 关键议题：provider/model/effort 来源与默认值策略、cwd 如何不被 agent 幻觉污染。
- 用户裁决：`.env` 路径写死 `.ralph/.env`（相对脚本位置），只需 `RALPH_PROVIDER` 必填，其他字段留空 → 不拼 flag、走 provider 内置默认；`--effort=low|medium|high|none` 抽象，adapter 翻译；**不接受 `--cwd`**，workspace 根由脚本路径（`$script_dir/../..`）决定，ralph 启动时内部 `cd` 到 workspace 根。

### 轮次 4（交付单元 / 部署形态，2026-04-28）

- 关键议题：ralph-loop 的最终产物边界（只是脚本工具，还是含起手样板的完整部署单元）；本仓库 `.ralph/` 是否入仓 `PROMPT.md` / `TASKS.md`；如果入仓如何与原"无 ralph init"约束并存。
- 用户裁决：**ralph-loop 最终产物 = `.ralph/` 整个目录**（含 `bin/` + `lib/` + `PROMPT.md` 样板 + `TASKS.md` 样板）；部署 = `cp -r .ralph/ <workspace>/.ralph/` 一次性带走全部，使用者按需裁剪样板再补 `.env`；`.ralph/.gitignore` 删除（部署单元自身不带运行期忽略规则）；运行期产物 `runs/` / `lock` / `status.json` 与私有配置 `.env` 由使用者外层 `.gitignore` 管理；**本仓库不自跑 ralph**（轮次 1 ruling 延续），故本仓库 `.ralph/` 不会出现 runtime artifacts。
- 与轮次 1"无 ralph init"边界澄清：约束的是 ralph 工具运行时**不**写 PROMPT/TASKS/.env、**不**读取它们做内核控制流。样板入仓由人工维护、由用户驱动 `cp -r` 部署，不是 ralph init 路径，两者并存。
- 沉淀：本轮决策形式化为 REQ-017，并对 §非目标 line 23 / REQ-008 做相应澄清补丁。

## 澄清结论

- 项目背景与目标：Ralph 是 shell harness，不参与推理；用 fresh oneshot 驱动长任务，TASKS.md 是任务完成事实源。
- 目标用户与角色：维护者手敲或让 agent 通过 Bash 工具调用；ralph 工具开发者基于本需求迭代。
- 核心范围：`run/status/watch` 三子命令、TASKS.md 协议、PROMPT.md 协议、三 provider adapter、per-workspace 部署、`.env` 驱动默认值。
- 明确排除范围：init 模板生成、全局安装、`--cwd` 参数、resume、自有 agent 推理、复杂 TUI、数据库。
- 关键假设：provider CLI 在不指定 model / effort 时能用自身默认正常运行；git 可用；UUID 可通过 `uuidgen`、`/proc/sys/kernel/random/uuid`、`python3 -c uuid.uuid4()` 三者之一生成。
- 遗留风险：Gemini 的 session id 在 `-p` 模式下不稳定输出，需退化定位；Claude 的 cwd 哈希规则需随官方版本验证。

## 需求清单

| 需求编号 | 名称 | 描述 | 优先级 | 类型 | 来源 |
|---|---|---|---|---|---|
| REQ-001 | Fresh oneshot 循环 | `ralph run` 反复调用 provider CLI 的 fresh oneshot，每轮读 TASKS.md 挑一个未完成任务执行，直到全部完成或触发明确退出条件 | P0-必须 | 功能 | 澄清轮次 1-2 |
| REQ-002 | TASKS.md 任务协议 | `.ralph/TASKS.md` 顶层 `- [ ]` / `- [x]` checklist 是任务完成事实源；Ralph 按状态变化判断进度 | P0-必须 | 功能 | 澄清轮次 2 |
| REQ-003 | 一个 task 一个 oneshot | PROMPT.md 硬约束：每轮 oneshot 只能完成**恰好一个**未勾选任务，完成后勾 `[x]` 并退出 | P0-必须 | 协作 | 澄清轮次 2 |
| REQ-004 | 三 provider 支持 | 支持 Claude Code、Codex CLI、Gemini CLI 三个 provider 的 oneshot 命令、session 采集和错误诊断 | P0-必须 | 功能 | 澄清轮次 1 |
| REQ-005 | Adapter 抽象 | 用统一 shell 函数契约抽象 provider 差异，便于独立实现和替换 | P0-必须 | 协作 | 澄清轮次 2 |
| REQ-006 | 运行证据沉淀 | 每轮保存 `provider.stdout.log` 原始合流、provider 原生 session 副本、派生 `session.history.log` 视图、changed_files 和 meta | P0-必须 | 功能 | 澄清轮次 1 |
| REQ-007 | 状态观察 | 提供 `ralph status`（一次性快照）和 `ralph watch`（持续刷新）两个子命令读取当前 run 状态，仅供人类维护者使用；agent oneshot 不调用 watch（自然不进 agent 工具路径，PROMPT.md 不引导）。具体边界见 REQ-023（status）/ REQ-024（watch） | P1-重要 | 功能 | 澄清轮次 1 / I1 扩展 2026-05-01 |
| REQ-008 | Per-workspace 部署 | 每个使用者 workspace 自带完整 `.ralph/` 部署单元（构成见 REQ-017：`bin/ralph` + `lib/*` + `PROMPT.md` + `TASKS.md` + `TASKS.bak` 部署样例）；不支持全局 `ralph` 命令 | P0-必须 | 约束 | 澄清轮次 3 |
| REQ-009 | .env 驱动默认值 | 从 `.ralph/.env` 读取 `RALPH_*` 前缀的默认参数；`RALPH_PROVIDER` 必需，其他留空即不传 flag。值以 `~/` 开头时安全展开为 `${HOME}/...`（路径类变量友好）。`.env` 不经 shell 解析，禁止 `source` 或命令替换。中立变量 `RALPH_PROVIDER_CONFIG_DIR`（见 REQ-022）由 adapter 翻译为各 provider 原生环境变量。 | P0-必须 | 功能 | 澄清轮次 3 / I1 dogfood 扩展（2026-04-30）|
| REQ-010 | 工作目录自定位 | workspace 根由 ralph 脚本路径决定（`$script_dir/../..`），ralph 启动时内部 `cd` 到该目录；不接受 `--cwd` 参数 | P0-必须 | 约束 | 澄清轮次 3 |
| REQ-011 | 快速失败校验 | 启动时校验 `.ralph/PROMPT.md`、`.ralph/TASKS.md`、`.ralph/.env`（含 `RALPH_PROVIDER`）、git 仓库、provider CLI 可执行；当 `RALPH_PROVIDER=claude` 时同时校验 UUID 生成器可用（TC-INT-003 三路至少一路成功）；任一缺失立即退出 | P0-必须 | 功能 | 澄清轮次 3 |
| REQ-012 | 明确退出原因 | 每次 `ralph run` 退出必须写明退出原因。v0.1：7 种（`done` / `provider_failed` / `timeout` / `max_iterations` / `stagnated` / `locked` / `interrupted`，`locked` 不产生 run 目录，不写 `result.json`；`interrupted` 在 lock 获取前触发时同样不产生 run 目录）。v0.1.1 新增第 8 种 `blocked_by_human`（见 REQ-018） | P0-必须 | 功能 | 澄清轮次 2 / I1 扩展 2026-04-30 |
| REQ-013 | Stagnation 保护 | 连续 N 轮 TASKS 勾选数不变且 changed_files 为空时触发 `stagnated` 退出，默认 N=5 | P1-重要 | 功能 | 澄清轮次 2 |
| REQ-014 | Effort 抽象 | `--effort=low\|medium\|high\|none` 由 adapter 翻译到各 provider 原生参数；留空不传 | P1-重要 | 功能 | 澄清轮次 3 |
| REQ-015 | Provider 绑定 | `--provider` 或 `RALPH_PROVIDER` 在 `ralph run` 启动时绑定，运行中不切换；写入 `status.json` 和 `provider.meta` | P0-必须 | 约束 | 澄清轮次 1 |
| REQ-016 | Skill 封装（后置） | 后续封装 `ralph-loop` skill，负责在使用者 workspace 初始化 `.ralph/` 结构并正确构造 `ralph run`；不进入 v0.1 范围 | P2-期望 | 协作 | 澄清轮次 3 |
| REQ-017 | 交付单元 = `.ralph/` 整个目录 | ralph-loop 项目的最终产物是 `.ralph/` 整个目录，含 `bin/ralph`、`lib/*.sh`、`PROMPT.md`（循环协议，本仓库自用 + 部署）、`TASKS.md`（dogfood 任务源 + 部署后由使用者改写）、`TASKS.bak`（hello world 部署样例参考，不被 ralph 识别）。部署方式 = `cp -r .ralph/ <workspace>/.ralph/` 一次性带走全部，使用者把 `TASKS.bak` 重命名为 `TASKS.md` 即可首跑。运行期产物（`runs/`、`lock`、`status.json`）和私有配置（`.env`）由本仓库及使用者外层 `.gitignore` 管理（忽略 `.ralph/runs/`、`.ralph/lock`、`.ralph/status.json`、`.ralph/.env`）。**v0.1 阶段本仓库 `.ralph/` 不含 runtime artifacts；v0.1.1 起本仓库进入 dogfood 模式，会产生 runtime artifacts 但同样按 `.gitignore` 管理**（§非目标 line 30 已更新）。| P0-必须 | 约束 | 澄清轮次 4（2026-04-28）/ I1 dogfood 扩展（2026-04-30）|
| REQ-018 | HUMAN-N 人工阻塞机制 | TASKS.md 第一个未勾选任务前缀是 `HUMAN-` 时，ralph 工具层在每轮启动前扫描发现 → 不调用 provider，直接以 `blocked_by_human`（exit code 7）退出。agent 在 ralph oneshot 内不得勾选或执行 `HUMAN-N` 任务（PROMPT.md 强约束）；普通 Claude Code 对话里不受此约束。机制目的：让 agent 优雅退出，把需求层决策交还给人类，避免猜测/伪装勾选。| P0-必须 | 功能 | I1 设计方案 2026-04-30 |
| REQ-019 | 退出接力打印 | `ralph run` 退出时（任意 exit_reason）向 stderr 打印格式化总结，含 `run_id` / `iteration_name` / `exit_reason` / `iterations` / 任务进度 / 阻塞点（如有）/ 接力提示（基于 exit_reason 的下一步建议）；同时落到 `.ralph/runs/<run_id>/exit-message.txt` 方便人类复制粘贴给 main agent。| P1-重要 | 功能 | I1 设计方案 2026-04-30 |
| REQ-020 | Iteration 命名约定 | `.ralph/TASKS.md` 顶部声明 `> 当前迭代: I<N>`，ralph 启动时解析并写入 `status.json.iteration_name` 和 `result.json.iteration_name`。Iteration 完成时按归档约定 `cp .ralph/TASKS.md docs/requirements/<module>/I<N>-FINAL-TASK.md` 沉淀不可变快照。命名采用单一 `I` 前缀（v0.1 历史 `T0-T7` 保留作为 release 范围内的历史命名，不延续）。| P1-重要 | 协作 | I1 设计方案 2026-04-30 |
| REQ-021 | 任务类型路由 | `.ralph/TASKS.md` 任务前缀决定 agent mindset 和参考的 `.spec/` 规范段，约定 7 类（REQ / SOL / ROADMAP / PLAN / DEV / QA / REVIEW）+ HUMAN（见 REQ-018）。`PLAN-N` = 任务列表规划（与 trantor PLAN / 业界 sprint planning 同义；产出 `.ralph/TASKS.md` 当前迭代任务列表）；`ROADMAP-N` = Roadmap 阶段规划（版本切分 / 优先级 / 验收口径）。**ralph 工具内核不解析前缀**，前缀仅作为 prompt 层 agent 自检入口；默认无前缀视为 DEV。详见 `.ralph/PROMPT.md`「任务类型」段。| P1-重要 | 协作 | I1 设计方案 2026-04-30 / 命名对齐 2026-05-01 |
| REQ-022 | Provider 配置目录隔离（中立抽象）| `.ralph/.env` 引入中立变量 `RALPH_PROVIDER_CONFIG_DIR`，由 ralph load_env 加载（含 `~/` tilde 展开），由 adapter 在 source 时翻译为 provider 原生环境变量（Claude → `CLAUDE_CONFIG_DIR`；Codex → `CODEX_HOME`；Gemini 在 T4 落地时定义）。变量为空或未设时 adapter **不**做 export（鲁棒性约束，避免空值干扰 provider 默认行为）。子进程 env 继承走 bash 默认行为，无需 `provider_oneshot` 显式注入。**adapter session 采集路径必须感知该变量**：Claude `provider_collect_session` 用 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd_hash>/<session_id>.jsonl` 定位 session 文件，不可 hardcode `$HOME/.claude/projects/`（否则隔离账号下 session 全部丢失或错误 fallback 到主账号 session — I1 dogfood 2026-05-01 暴露的 P0 bug）；Codex `provider_collect_session` 用 `${CODEX_HOME:-$HOME/.codex}/sessions/` 定位 rollout 文件。用例：本仓库 dogfood 时通过该变量切换到独立账号 config dir，避免占用 main agent 的 Claude usage limit；Linux/Windows 用户也能用同一抽象。详见 `docs/architecture/integrations.md` §Adapter 配置目录翻译契约 + §Claude Session 机制 + §Codex Session 机制 + `docs/architecture/security.md` §Provider 凭据 / 配置目录隔离。 | P1-重要 | 协作 | I1 dogfood 扩展 2026-04-30 / I1 dogfood P0 fix 2026-05-01 / I2 DEV-1 校准 2026-05-03 |
| REQ-023 | `ralph status` 边界 | 一次性读取 `.ralph/status.json` 并打印；默认 plain text（含全部字段：`run_id` / `run_dir` / `workspace` / `provider` / `model` / `effort` / `started_at` / `updated_at` / `iteration` / `iteration_name` / `state` / `tasks_total` / `tasks_checked` / `exit_reason` / `last_error`），`--json` flag 切换为 status.json 原始 JSON 透传；status.json 不存在时输出"无运行中/已结束的 run"并 exit 0；不支持 `--run <id>` 历史浏览（已结束 run 由用户直接读 `runs/<id>/result.json`）。 | P1-重要 | 功能 | I1 dogfood 2026-05-01 |
| REQ-024 | `ralph watch` 边界 | TTY 周期刷新（**固定 2 秒**，不暴露 `--interval` flag）；默认仅渲染下方 sticky 状态条（status.json 关键字段）；`-v` / `--verbose` flag 启用上方 tail 区域（实时尾追当前 iter log = `runs/<run_id>/iterations/iter-NNN/provider.stdout.log`，文件不存在时区域留空）；`ralph run` 在 provider oneshot 启动前必须把 `status.json.iteration` 更新到当前 iter 并创建当前 `provider.stdout.log`，保证 watch 不会盯 `iter-000` 或上一轮；run 自然结束（`state=finished`）后 watch **不自动退出**，最后一帧保留并继续刷新；status.json 中 `run_id` 变化时（仅 `-v` 模式下）插入 separator 行并切换 tail 目标到新 run；仅 Ctrl-C 退出，退出时清屏；非 TTY（pipe / redirect）输出一次 one-line watch bar 后退出，不打印 `ralph status` 的详细字段；彩色按 `isatty(stdout) && [ -z "$NO_COLOR" ]` 自动检测，sticky bar 状态字段按 exit_reason 分类上色（`done` / `running` 绿，`provider_failed` / `timeout` / `max_iterations` / `stagnated` 红，`blocked_by_human` / `locked` / `interrupted` 黄）；agent oneshot 不调用 watch（人类专用观察工具）；时间戳渲染为本地时间 + 时区偏移（Q1 双层时间格式：JSON 文件 ISO UTC，人类输出本地）。 | P1-重要 | 功能 | I1 dogfood 2026-05-01 / -v flag 2026-05-02 / active iter fix 2026-05-04 / watch surface fix 2026-05-04 |
| REQ-025 | `ralph run` 进度可见性 | run 主循环默认（无 `-v`）向 stderr 输出**进度 marker**：启动 banner（`[HH:MM:SS] ralph <ver> | run <id> | <iter_name> | tasks <c>/<t> done | provider <p>`）+ 每 iter 启停两行（`iter N/M → <task summary>` 和 `iter N/M ✓ done | tasks <c>/<t> | iter <dur> | run <dur>`）；provider oneshot 长时间未返回时每 60 秒输出 heartbeat（elapsed、`provider.stdout.log` bytes/lines、`tail -f` 路径），`RALPH_PROGRESS_HEARTBEAT_SEC=0` 可关闭。`-v` / `--verbose` flag 启用 live tail：fork tail -f provider.stdout.log，过滤 Claude stream-json / Codex JSONL events 输出到 stderr（`💭 thinking` / `💬 text` / `🔧 tool_use` / `⏎ result` 行内标记）。stdout 默认 silent（CI 友好）；stderr 承载所有进度信息。时间戳本地时间。 | P1-重要 | 功能 | I1 dogfood 2026-05-02 / I2 Codex live tail + heartbeat 2026-05-03 |
| REQ-026 | 双层时间格式 | JSON 事实文件（`status.json` / `result.json` / `iter-NNN/meta.json` / `context.json`）保留 ISO 8601 UTC 时间戳（`2026-05-02T01:10:08Z`），便于跨时区机器解析与排序；人类终端输出（`ralph status` plain text、`ralph watch` sticky bar、`ralph run` 进度 marker、退出 `exit-message.txt`）渲染为本地时间 + 时区偏移（`2026-05-02 09:10:08 +0800`），通过 `ralph_iso_to_local_display` helper。 | P1-重要 | 协作 | Q1 决策 2026-05-02 |

## 优先级说明

| 优先级 | 含义 |
|---|---|
| P0-必须 | 缺失则 v0.1 不可用 |
| P1-重要 | v0.1 强烈建议实现 |
| P2-期望 | v0.1 之后纳入 |
| P3-可选 | 资源允许时考虑 |

## 用户场景

### US-001：维护者手动跑一轮长任务

- 触发：维护者准备好 `.ralph/PROMPT.md`、`.ralph/TASKS.md`、`.ralph/.env`，在 workspace 内 shell 执行 `.ralph/bin/ralph run`。
- 输入：TASKS.md 含多条未勾选任务、PROMPT.md 含协议说明、.env 指定 `RALPH_PROVIDER=codex`。
- 预期结果：ralph 循环调用 codex oneshot，每轮 agent 勾选一条任务并退出；直到全部勾选，ralph 以 `done` 退出，`.ralph/runs/<id>/result.json` 写入结果。
- 验收：TASKS.md 全部 `[x]`；`result.json` 的 `exit_reason=done`；`iterations/` 下有每轮的 log 和 session 副本。

### US-002：coding agent 通过 Bash 工具驱动 ralph

- 触发：coding agent（如 Claude Code）用 Bash 工具执行 `/abs/path/.ralph/bin/ralph run`。
- 输入：agent 可能在任意 cwd 调用（agent 用过 `cd` 子目录）。
- 预期结果：ralph 根据脚本路径自动定位 workspace，内部 `cd` 到 workspace 根，和手动调用行为一致。
- 验收：`status.json` 中 `workspace` 字段等于脚本父目录的父目录；run 能正常产生。

### US-003：run 中途失败复盘

- 触发：某轮 provider 退出码非 0，或连续 5 轮无进展。
- 输入：已产生的 `iterations/iter-xxx/` 目录。
- 预期结果：`result.json.exit_reason` 明确（`provider_failed` / `stagnated`），`last_error.type` 给出分类（`quota` / `auth` / `rate_limit` / `network` / `unknown`）；`session.<provider>.*` 保留原生证据。
- 验收：人工打开 `result.json` 即能判断退出类型；打开 `session.history.log` 即能读到跨 provider 的人类可读对话/工具摘要。

### US-004：并发冲突

- 触发：同一 workspace 已有 `ralph run` 运行中，维护者再次调用 `ralph run`。
- 输入：`.ralph/lock` 文件存在。
- 预期结果：第二次调用以 `locked` 退出，不创建新 run 目录，不影响已有 run。
- 验收：第二次退出码对应 `locked`；`.ralph/runs/` 没有新产物。

### US-005：启动校验失败

- 触发：workspace 缺少 `.ralph/PROMPT.md` 或 `.ralph/TASKS.md` 或 `.ralph/.env` 或不是 git 仓库。
- 输入：不完整的 workspace。
- 预期结果：立即退出，stderr 明确指出缺哪个文件或条件。
- 验收：没有 run 目录产生；退出信息可机读（有固定错误前缀）。

## 成功标准

| 标准编号 | 绑定需求 | 标准描述 | 度量方式 | 目标值 | 验证方法 |
|---|---|---|---|---|---|
| SC-001-1 | REQ-001 | `ralph run` 在全部顶层 checklist 勾选后以 `done` 退出 | `result.json.exit_reason` | `done` | 集成测试：预置 TASKS.md + fake provider，跑 `ralph run` |
| SC-001-2 | REQ-001 | 每一轮都是 fresh oneshot，不传 resume flag | provider CLI 调用参数 | 不含 `--resume` / `--continue` / `codex resume` | 审计 adapter 命令构造代码 |
| SC-002-1 | REQ-002 | TASKS.md 顶层 checklist 解析匹配 `^\s*-\s+\[([ xX])\]` 不限缩进 | 解析函数单元测试 | 用例全通过 | 单元测试（对应 trantor parseTasks 用例） |
| SC-003-1 | REQ-003 | PROMPT.md 模板包含"一个 task 一个 oneshot"协议段落 | PROMPT.md 示例文本 | 含"恰好一个未勾选任务" | 文档 + 示例 review |
| SC-004-1 | REQ-004 | 三 provider 各自跑通一次 smoke run（至少一条 task 完成） | 真实 provider CLI | 三个 `exit_reason=done` | 手工集成验证，结果附在 T2/T3/T4 完成 PR |
| SC-005-1 | REQ-005 | adapter 契约稳定为三函数：`provider_oneshot` / `provider_collect_session` / `provider_diagnose` | 接口文档 + fake adapter | 三函数签名一致 | fake provider smoke test |
| SC-006-1 | REQ-006 | 每轮产出 `provider.stdout.log`、`meta.json`、`session.history.log`；provider 原生 `session.<provider>.jsonl` 采集成功时存在，采集失败时写 `capture_status=warning` 但 loop 继续 | `iterations/iter-xxx/` 目录 | 核心证据每轮齐全；session 副本 best-effort | 集成测试 |
| SC-007-1 | REQ-007 | `ralph status` 与 `ralph watch` 子命令均能从 `ralph` CLI 入口启动（`ralph status` exit 0 / `ralph watch` 进入刷新循环直到 Ctrl-C） | exit code + stdout/TTY 行为 | 子命令可用 | 集成测试 + 手工验证 |
| SC-008-1 | REQ-008 | ralph 通过 `${BASH_SOURCE[0]}` 解析出 workspace 根为 `.ralph/` 的父目录 | 启动日志 + `status.json.workspace` | 路径匹配 | 单元测试 + 集成测试 |
| SC-009-1 | REQ-009 | `.env` 中未设或留空的 `RALPH_MODEL` / `RALPH_EFFORT` / `RALPH_MAX_ITER` / `RALPH_TIMEOUT`，对应 flag 不拼进 oneshot 命令 | 构造出的命令行字符串 | flag 缺席 | 单元测试 |
| SC-010-1 | REQ-010 | 在任意 cwd 执行 `/abs/path/.ralph/bin/ralph run`，ralph 进程最终 cwd 为 `/abs/path` | `pwd` 或 `status.json` | 路径一致 | 集成测试 |
| SC-011-1 | REQ-011 | 缺 PROMPT.md / TASKS.md / .env / 非 git 仓库 / provider CLI 不可执行任一条件，ralph 立即退出且不创建 run 目录；`RALPH_PROVIDER=claude` 且三路 UUID 生成全失败时同样快速失败 | 退出码 + `.ralph/runs/` 状态 | 快速失败 | 集成测试 6 个用例（5 个核心条件 + Claude UUID 路径） |
| SC-012-1 | REQ-012 | 7 种退出原因（`done` / `provider_failed` / `timeout` / `max_iterations` / `stagnated` / `interrupted` / `blocked_by_human`）都能写入 `result.json.exit_reason`；`locked` 不产生 run 目录、不写 `result.json`，合计 8 种 | `result.json` + `.ralph/runs/` 状态 | 全覆盖 | 集成测试（各触发一次） |
| SC-012-2 | REQ-012 | 单轮 `timeout` 或 lock 后 `interrupted` 退出时清理 provider oneshot 进程树，不遗留真实 provider 子进程继续运行 | fake provider 启动外部 child 并触发 timeout / SIGTERM | `exit_reason=timeout` 或 `interrupted` 且 child pid 已退出 | 集成测试（进程探针） |
| SC-013-1 | REQ-013 | 连续 5 轮无勾选变化且 changed_files 空 → `stagnated` 退出 | `result.json.exit_reason` | `stagnated` | 集成测试：用 fake provider 模拟空转 |
| SC-014-1 | REQ-014 | `--effort=low\|medium\|high` 翻译为各 provider 原生参数；`none` 或留空不传 | 构造的命令行 | flag 匹配或缺席 | 单元测试 |
| SC-015-1 | REQ-015 | `status.json` 和 `provider.meta` 都记录本轮 provider；run 生命周期内不变更 | 文件字段 | 一致 | 集成测试 |
| SC-017-1 | REQ-017 | `.ralph/` 整个目录可通过 `cp -r .ralph/ <workspace>/.ralph/` 一次性部署到独立 workspace 并跑通 `ralph run` 到 `exit_reason=done` | 部署后 workspace 的 `.ralph/runs/<id>/result.json` | `done` 且无依赖外部脚本 | T6.3 真实多轮 smoke |
| SC-018-1 | REQ-018 | TASKS.md 第一个未勾选任务前缀是 `HUMAN-` → ralph 不调 provider，立即以 `blocked_by_human` / exit code 7 退出；HUMAN-N 任务勾 `[x]` 后正常进入下一轮 | `result.json.exit_reason` + 退出码 + iter 目录是否存在 | exit 7 / no iter dir；勾掉后 done | 集成测试 2 用例（blocked_by_human 触发 + cleared）+ 1 断言（不调 provider 验证 iter 目录不创建） |
| SC-018-2 | REQ-018, REQ-021 | 任务前缀格式校验：非全大写英文（如 `Dev-1`、`dev-1`）触发启动失败 exit 1 | 启动退出码 + stderr 错误前缀 | exit 1 / `startup check failed: TASKS.md task prefixes must be UPPERCASE` | 集成测试 |
| SC-019-1 | REQ-019 | `.ralph/runs/<run_id>/exit-message.txt` 在 lock 获取后的所有 exit_reason 下生成，包含 exit_reason、iteration_name、接力提示等字段（`startup_failed` / `locked` 不产生 run 目录因此无文件） | 文件存在 + 文本 grep | 含关键字段 | 集成测试（HUMAN-N 用例覆盖：含 `blocked_by_human` 和 iteration_name 关键字） |
| SC-020-1 | REQ-020 | TASKS.md 顶部 `> 当前迭代: I<N>` 声明被解析并写入 `result.json.iteration_name`；冒号必须 ASCII `:`（全角不识别） | `result.json.iteration_name` | 等于声明值 | 集成测试 |
| SC-021-1 | REQ-021 | `.ralph/PROMPT.md` 含 7 类任务前缀（REQ/SOL/PLAN/TASK/DEV/QA/REVIEW）+ HUMAN 共 8 类的路由表、HUMAN-N 触发条件、agent 行为约束、REVIEW-N 两种用法（escalation `[blocked-by]` vs 常规 `\| review` / `\| adversarial-review`） | PROMPT.md 文本 | 段落齐全 | 文档 review |
| SC-022-1 | REQ-022 | `load_env` 加载 `.env` 含 `RALPH_PROVIDER_CONFIG_DIR=~/foo` 时，进程 env 中的值是 `${HOME}/foo`（tilde 已展开） | 进程 env / `bash -c 'source common.sh; load_env ...; echo $RALPH_PROVIDER_CONFIG_DIR'` | 等于 `${HOME}/foo` | 集成测试 |
| SC-022-2 | REQ-022 | `adapter-claude.sh` source 时，若 `RALPH_PROVIDER_CONFIG_DIR` 非空 → export `CLAUDE_CONFIG_DIR` 等于该值；若为空或未设 → `CLAUDE_CONFIG_DIR` 保持未设 | 子 shell env | 翻译正确 / 鲁棒性正确 | 集成测试（2 用例：translate + empty robustness） |
| SC-022-3 | REQ-022 | `provider_collect_session` 用 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<cwd_hash>/` 定位 session；CLAUDE_CONFIG_DIR 设为自定义路径时，session 从该路径采集，且 `$HOME/.claude/projects/` 不被读取 | iter meta.json `session_source_path` 字段 + `$HOME/.claude/projects/` 内容快照 | source 路径在 custom dir 下 / `$HOME/.claude/projects/` 无 jsonl 写入 | 集成测试（CLAUDE_CONFIG_DIR aware capture 用例） |
| SC-022-4 | REQ-022 | `adapter-codex.sh` source 时，若 `RALPH_PROVIDER_CONFIG_DIR` 非空 → export `CODEX_HOME` 等于该值；若为空或未设 → `CODEX_HOME` 保持未设 | 子 shell env | 翻译正确 / 鲁棒性正确 | 集成测试（2 用例：translate + empty robustness） |
| SC-022-5 | REQ-022 | Codex `provider_collect_session` 用 `${CODEX_HOME:-$HOME/.codex}/sessions/` 定位 rollout 文件；CODEX_HOME 设为自定义路径时，session 从该路径采集，且 `$HOME/.codex/sessions/` 不被读取 | iter meta.json `session_source_path` 字段 + `$HOME/.codex/sessions/` 内容快照 | source 路径在 custom dir 下 / `$HOME/.codex/sessions/` 无 jsonl 写入 | 集成测试（CODEX_HOME aware capture 用例） |
| SC-022-6 | REQ-022 | `adapter-gemini.sh` source 时，若 `RALPH_PROVIDER_CONFIG_DIR` 非空 → export `GEMINI_CLI_HOME` 等于该值；若为空或未设 → `GEMINI_CLI_HOME` 保持未设 | 子 shell env | 翻译正确 / 鲁棒性正确 | 集成测试（2 用例：translate + empty robustness） |
| SC-022-7 | REQ-022 | Gemini `provider_collect_session` 用 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/*.json` 定位 session；GEMINI_CLI_HOME 设为自定义路径时，session 从该路径采集 | iter meta.json `session_source_path` 字段 | source 路径在 custom dir 下 | 集成测试（GEMINI_CLI_HOME aware capture 用例） |
| SC-023-1 | REQ-023 | `ralph status` plain text 输出包含 status.json 全部 15 字段（`run_id` / `run_dir` / `workspace` / `provider` / `model` / `effort` / `started_at` / `updated_at` / `iteration` / `iteration_name` / `state` / `tasks_total` / `tasks_checked` / `exit_reason` / `last_error`） | stdout grep 关键字段名 | 字段齐全 | 集成测试 |
| SC-023-2 | REQ-023 | `ralph status --json` 输出与 `.ralph/status.json` 文件内容字节一致（透传） | `diff <(ralph status --json) .ralph/status.json` | 完全一致 | 集成测试 |
| SC-023-3 | REQ-023 | `.ralph/status.json` 不存在时 `ralph status` exit 0 + stdout 含"无运行" / "no run" 关键文案；不报错、不创建任何文件 | 退出码 + stdout grep + 文件系统检查 | exit 0 / 提示文案 / 无副作用 | 集成测试 |
| SC-024-1 | REQ-024 | `ralph watch` 默认屏幕 = 下方 sticky 状态条；`ralph watch -v` 屏幕 = 上方 tail 当前 iter log + 下方 sticky 状态条（status.json 字段） | 终端录屏 + 手工观察 | 默认不刷详细 log；`-v` 双区域布局正确 | 手工验证 |
| SC-024-2 | REQ-024 | `watch -v` 检测 status.json `run_id` 变化时插入 separator 行（如 `─── new run: <new_run_id> ───`）并切换 tail 目标到新 run 的 iter log；provider oneshot 运行中 `status.json.iteration` 指向当前 iter，`watch -v` 能读到当前 `provider.stdout.log` | 双 run 触发 + active slow provider | separator 出现 + tail 切换；长 oneshot 运行中 tail 当前 iter 不为空 | 集成测试（mock 修改 status.json 切换 run_id + fake slow provider）+ 手工验证 |
| SC-024-3 | REQ-024 | run 进入 `state=finished` 后 watch 不自动退出，sticky bar 持续显示最终 `exit_reason`，仅 Ctrl-C 退出（退出时清屏） | 手工验证 + 进程存活检查 | 不自退出 / Ctrl-C 干净退出 | 手工验证 |
| SC-024-4 | REQ-024 | watch 在非 TTY 环境（如 `ralph watch \| cat`）输出一次 one-line watch bar 后退出，不打印 `workspace:` / `run_dir:` 等 status 详情字段 | 退出码 + 输出行为 | exit 0 / 单行紧凑 watch 输出 / 无 status 详情字段 | 集成测试 |
| SC-024-5 | REQ-024 | sticky bar 状态字段按 `isatty + NO_COLOR` 自适应上色：`state=running` / `exit_reason=done` 绿；`provider_failed` / `timeout` / `max_iterations` / `stagnated` 红；`blocked_by_human` / `locked` / `interrupted` 黄；`NO_COLOR=1` 或非 TTY 输出时不上色 | 终端录屏（含 8 类 exit_reason）+ `NO_COLOR=1` 验证 | 颜色映射正确 / 降级正确 | 手工验证 |
| SC-025-1 | REQ-025 | `ralph run` 默认 stderr 输出启动 banner、每轮 iter 启停 marker；长 provider oneshot 输出 still-running heartbeat；stdout 保持 silent | stderr/stdout 捕获 | stderr 含 `ralph <version> \| run`、`iter N/M →`、`iter N/M ✓ done`；长 oneshot 含 `still running` + `provider.stdout.log`；stdout 为空 | 集成测试 / dogfood 验证 |
| SC-025-2 | REQ-025 | `ralph run -v` live tail 会把 Claude stream-json / Codex JSONL / Gemini stream-json events 过滤成人类可读 marker | stderr grep | Claude happy / Codex happy / Gemini happy 路径含 `⚙ session` / `💬` / `✓ result` 至少一种；error 路径含 `❌ error` | 集成测试 |
| SC-025-3 | REQ-025 | `ralph run -v` 中断或退出时清理 live tail 相关进程，不遗留 `tail -f provider.stdout.log` | 进程表检查 | 退出后无指向本 run 的 `tail -f provider.stdout.log` | 进程探针 / 手工验证 |
| SC-026-1 | REQ-026 | 人类终端输出将 ISO UTC 时间渲染为本地时间 + 时区偏移 | plain text grep | `YYYY-MM-DD HH:MM:SS +ZZZZ` | 集成测试（status plain text） |
| SC-026-2 | REQ-026 | JSON 事实文件保持 ISO 8601 UTC 时间戳 | JSON grep/jq | `started_at` / `updated_at` 等字段为 `...Z` | 集成测试（status --json / run artifacts） |

## 业务流程

### BPF-001：典型 run 循环

- 关联需求：REQ-001、REQ-002、REQ-003、REQ-006、REQ-011、REQ-012、REQ-013
- 涉及角色：维护者 / coding agent、ralph harness、provider CLI、coding agent 循环
- 触发条件：维护者或 coding agent 执行 `.ralph/bin/ralph run`
- 主流程：
  1. 解析 `${BASH_SOURCE[0]}` 得到 workspace 根，`cd` 到根
  2. 读 `.ralph/.env`，解析 `RALPH_*` 字段
  3. 校验 PROMPT.md / TASKS.md / .env / git 仓库 / provider CLI 可执行
  4. 获取 `.ralph/lock`（`flock` 或等价机制），冲突则退出 `locked`
  5. 生成 `run_id`，创建 `.ralph/runs/<run_id>/`，记录 `start_sha`
  6. 写 `status.json` 初始状态
  7. 进入循环：
     - 解析 TASKS.md；全部勾选 → 退出 `done`
     - 拼 oneshot 命令：`provider_oneshot <prompt_file> <log> <meta_dir>`
     - 执行 provider CLI，捕获 stdout/stderr 到 `iter-xxx/provider.stdout.log`
     - `provider_collect_session` 采集原生 session，派生 `session.history.log` 视图
     - `provider_diagnose` 分析错误类别
     - 收集 `changed_files`，写 `iter-xxx/meta.json`
     - 判断 stagnation、max_iterations、timeout、provider 失败、中断等退出条件
  8. 写 `result.json` 和 TASKS.md 快照
  9. 释放 lock
- 异常分支：
  - 启动校验失败 → REQ-011 快速失败
  - lock 冲突 → 退出 `locked`，不产生 run 目录
  - provider CLI 退出码非 0 → 退出 `provider_failed`，记录错误诊断
  - 单轮超时 → 退出 `timeout`
  - 用户 Ctrl-C → 退出 `interrupted`
  - session capture 失败 → 只记录 warning，loop 继续
- 输入：`.ralph/PROMPT.md`、`.ralph/TASKS.md`、`.ralph/.env`、git 状态
- 输出：`.ralph/runs/<run_id>/*`、更新后的 `.ralph/TASKS.md`、`.ralph/status.json`
- 业务规则：
  - TASKS.md 是任务完成唯一事实源
  - session 只是复盘证据，不参与完成判定
  - stagnation 双重判据：TASKS 勾选数不变 ∧ changed_files 空

### BPF-002：快速失败启动校验

- 关联需求：REQ-011
- 涉及角色：ralph harness
- 触发条件：`ralph run` 启动
- 主流程：依次检查 `.ralph/PROMPT.md` / `.ralph/TASKS.md` / `.ralph/.env`（解析后 `RALPH_PROVIDER` 非空） / `.git/`（git 仓库） / `command -v <provider-cli>`（CLI 名由 adapter 暴露的 `RALPH_PROVIDER_CLI` 变量提供） / 当 `RALPH_PROVIDER=claude` 时追加 UUID 生成器可用性（`uuidgen` → `/proc/sys/kernel/random/uuid` → `python3 -c uuid.uuid4()` 三路之一可用） → 任一失败立即 stderr 报错、非零退出码、不进入 run 流程
- 异常分支：多个缺失时报告第一个
- 输入：workspace 文件状态
- 输出：stderr 错误信息、退出码
- 业务规则：启动校验失败不产生 run 目录

## 功能需求

### FR-001：`ralph run` 命令

- 来源需求：REQ-001、REQ-009、REQ-010、REQ-012、REQ-013、REQ-015
- 关联流程：BPF-001、BPF-002
- 用户故事：作为维护者，我希望用 `.ralph/bin/ralph run` 驱动一轮长任务循环，以便让 agent 按 TASKS.md 顺序处理任务并沉淀证据。
- 输入：
  - CLI flag：`--provider=<claude|codex|gemini|fake>`、`--model=<name>`、`--effort=<low|medium|high|none>`、`--max-iter=N`、`--timeout=SEC`（均可选；Gemini adapter 由 I4 实现）
  - 环境变量：`RALPH_PROVIDER` / `RALPH_MODEL` / `RALPH_EFFORT` / `RALPH_MAX_ITER` / `RALPH_TIMEOUT`
  - 文件：`.ralph/.env`（`RALPH_*` 字段）
- 输出：
  - `.ralph/runs/<run_id>/{context.json, result.json, TASKS.md, iterations/*}`
  - 更新后的 `.ralph/TASKS.md`
  - `.ralph/status.json`
  - 退出码映射退出原因
- 业务规则：
  - 优先级：CLI flag > 进程 env > `.env` > adapter 内置默认
  - `--provider` 缺失且 `.env` `RALPH_PROVIDER` 为空 → 启动校验失败
  - 其他字段缺失 → 不传 flag，provider 走自身默认
  - `--max-iter=0` 表示不限，`--timeout=0` 表示单轮不限时

### FR-002：`ralph status` 命令

- 来源需求：REQ-007、REQ-023
- 关联流程：BPF-001（读取）
- 用户故事：作为维护者，我希望一次性查看当前 run 状态，以便判断 agent 现在在做什么或上一次运行的退出原因。
- 输入：`.ralph/status.json`（若存在）；可选 flag `--json`
- 输出：单次打印到 stdout 后退出 0
  - 默认 plain text：人类可读格式，含 status.json 全部 15 字段（`run_id` / `run_dir` / `workspace` / `provider` / `model` / `effort` / `started_at` / `updated_at` / `iteration` / `iteration_name` / `state` / `tasks_total` / `tasks_checked` / `exit_reason` / `last_error`）；任务进度渲染为 `<checked> / <total> checked`
  - `--json`：原样透传 status.json 文件内容（字节一致）
- 业务规则：
  - status.json 不存在 → stdout 输出"无运行中/已结束的 run"提示，exit 0，不创建任何文件
  - 不解析 session、不做错误诊断、不读 result.json
  - 不支持 `--run <id>` 历史浏览；已结束 run 由用户直接读 `.ralph/runs/<id>/result.json`
  - 仅供人类维护者使用；agent oneshot 可调用但不强制

### FR-003：`ralph watch` 命令

- 来源需求：REQ-007、REQ-024
- 关联流程：BPF-001（读取）
- 用户故事：作为维护者，我希望默认用紧凑 sticky bar 观察当前 run 状态，需要时用 `-v` 额外查看 agent 实时输出，发现 stagnation / PROMPT 协议歧义 / 长任务卡顿。
- 输入：`.ralph/status.json`、`.ralph/runs/<run_id>/iterations/iter-NNN/provider.stdout.log`
- 输出：默认 TTY sticky bar；`-v` 为 TTY 双区域刷新；非 TTY 为一次 one-line watch bar
  - 默认：sticky 状态条（最少含 `run_id` 截断 / `iteration` / `tasks_checked/total` / `state` / `exit_reason` / `provider`）
  - `-v` 上方：当前活跃 iter log 的 `tail -f` 等价输出（agent stdout 实时滚动）；log 文件不存在时该区域留空
  - 刷新间隔：固定 2 秒（不暴露 `--interval` flag）
- 业务规则：
  - run 自然结束（`state=finished`）后**不自动退出**，最后一帧保留并继续刷新（sticky bar 显示最终 `exit_reason`）
  - `-v` 模式下 status.json 中 `run_id` 变化时插入 separator 行（如 `─── new run: <new_run_id> ───`），并切换 tail 目标到新 run 的 iter log
  - `-v` 模式下 iter 内部切换（iter-001 → iter-002）时 tail 目标自动切换到新 iter log
  - 仅 Ctrl-C 退出，退出时清屏
  - 非 TTY 环境（pipe / redirect / `isatty(stdout)=false`）输出一次 one-line watch bar 后退出；详细字段由 `ralph status` 提供
  - 彩色按 `isatty(stdout) && [ -z "$NO_COLOR" ]` 自适应；sticky bar 状态字段按 exit_reason 上色：
    - `state=running` 或 `exit_reason=done` → 绿
    - `exit_reason` ∈ {`provider_failed`, `timeout`, `max_iterations`, `stagnated`} → 红
    - `exit_reason` ∈ {`blocked_by_human`, `locked`, `interrupted`} → 黄
    - `NO_COLOR=1` 或非 TTY → 不上色
  - `-v` 上方 tail 区域不主动上色，原样透传 provider 输出（agent 自带的颜色码保留）
  - 不做复杂 TUI、不做 session 解析、不做变更诊断、不做交互键位（除 Ctrl-C）
  - **仅供人类维护者使用**；agent oneshot 不调用 watch（PROMPT.md 不引导，自然不进 agent 工具路径）

### FR-004：TASKS.md 解析

- 来源需求：REQ-002
- 关联流程：BPF-001
- 用户故事：作为 ralph，我需要从 TASKS.md 稳定识别顶层 checklist 状态。
- 输入：TASKS.md 文本
- 输出：顶层任务列表，每项含 `{ line, checked: bool, title }`
- 业务规则：
  - 正则 `^\s*-\s+\[([ xX])\]`，`space` 为未完成，`x` / `X` 为完成
  - 不限缩进（深层缩进也视为顶层任务；解析子项不在 v0.1 范围）
  - 全部勾选 → `done`

### FR-005：Claude adapter

- 来源需求：REQ-004、REQ-005、REQ-006、REQ-014
- 关联流程：BPF-001
- 用户故事：作为 ralph，我需要把 oneshot 调用翻译成 Claude CLI 命令，并采集 session 证据。
- 输入：prompt 文本、runtime 参数
- 输出：oneshot 退出码、`iter-xxx/provider.stdout.log`、`iter-xxx/session.claude.jsonl`、派生 `session.history.log`、错误诊断类别
- 业务规则：
  - 固定 flag：`--dangerously-skip-permissions`、`--allowedTools "Bash,Read,Edit,Write,Glob,Grep"`、`--output-format json`、`--session-id <预分配 UUID>`
  - 可选 flag（有值才拼）：`--model`、`--effort`（Claude CLI 原生直通，T6.2 实测；`none`/空 → 不拼）
  - session 路径定位：`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`，encoded-cwd = realpath 后非 `[A-Za-z0-9-]` 字符替换为 `-`
  - 错误诊断：`is_error: true` → 按 `result` 关键字分 `auth` / `quota` / `concurrency` / `api`

### FR-006：Codex adapter

- 来源需求：REQ-004、REQ-005、REQ-006、REQ-014
- 关联流程：BPF-001
- 输入/输出：同上
- 业务规则：
  - 命令：`codex exec --json -C <workspace> --sandbox workspace-write <prompt>`
  - 可选 flag：`--model`、`-c model_reasoning_effort=<value>`（effort 通过 config override 传递，值 `low|medium|high`；`none` 或留空不传）
  - session 定位：从 stdout JSONL 取 `thread.started.thread_id`，在 `${CODEX_HOME:-$HOME/.codex}/sessions/` 下递归匹配 `rollout-*-<thread_id>.jsonl`
  - 错误诊断：`turn.failed.error.message` 优先，`error` 事件和 stderr 非 JSON 行作为回退；关键字匹配 `auth` / `rate_limit` / `quota` / `network` / `api` / `unknown`

### FR-007：Gemini adapter

- 来源需求：REQ-004、REQ-005、REQ-006、REQ-014
- 关联流程：BPF-001
- 输入/输出：同上
- 业务规则：
  - 命令：`gemini -p <prompt> --approval-mode=yolo --output-format stream-json`
  - 可选 flag：`--model`；`--sandbox`（adapter 可选启用）
  - effort 暂不传递（Gemini CLI 无 `--thinking-budget` flag；`thinkingBudget` 为 `settings.json` 内部配置，不暴露 CLI 入口；`none` 或留空不传）
  - session 定位：按 mtime 取 `${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/<project-identifier>/chats/*.json` 中最新文件；`<project-identifier>` 由 `~/.gemini/projects.json` 映射，Ralph 不自行计算或拼接
  - 错误诊断：`--output-format stream-json` 模式下从 stdout 事件流诊断；退化时依赖 exit code + stderr 关键字

### FR-008：错误诊断

- 来源需求：REQ-006
- 关联流程：BPF-001
- 用户故事：provider 退出码 0 不代表成功，需要二次诊断。
- 输入：stdout / stderr / session 文件
- 输出：`{ type: auth|quota|rate_limit|network|concurrency|api|unknown, message: <原始 message> }`，写入 `iter-xxx/meta.json.error` 和 `result.json.last_error`
- 业务规则：诊断不中断循环，但带错轮次计入 stagnation

## 非功能需求

| 编号 | 类别 | 描述 | 指标或目标值 | 测量方法 | 来源 |
|---|---|---|---|---|---|
| NFR-REL-001 | 可靠性 | 同一 workspace 内 `ralph run` 不可并发；第二次以 `locked` 退出 | 只有一个活跃 run | 并发测试 | REQ-012 |
| NFR-REL-002 | 可靠性 | session capture 失败不得中断 run；只写 warning | `capture_status=warning` 但 loop 继续 | 集成测试：删除 session 目录模拟失败 | REQ-006 |
| NFR-REL-003 | 可靠性 | 启动校验失败不产生 run 目录，不改写 TASKS.md | `.ralph/runs/` 目录无新增 | 集成测试 | REQ-011 |
| NFR-SEC-001 | 安全 | 不把 API key、完整 token 或敏感配置写入 log、session、meta、result | 产物文件内容审查 | 人工 review + grep 关键字 | 全局风险 |
| NFR-SEC-002 | 安全 | 每个 provider 的 approval/sandbox 策略写死在 adapter 里，不做开关 | adapter 源代码 | code review | 澄清轮次 2 |
| NFR-OBS-001 | 可观察性 | 每轮 provider stdout/stderr 全量落盘；不丢失 | `iter-xxx/provider.stdout.log` 非空 | 集成测试 | REQ-006 |

## 约束

| 编号 | 类别 | 约束描述 | 来源依据 | 是否可协商 |
|---|---|---|---|---|
| TC-STK-001 | 技术选型 | shell-first Bash 实现；不引入包管理器、编译步骤、数据库或额外 runtime | 澄清轮次 1 | 否（v0 阶段） |
| TC-STK-002 | 技术选型 | Per-workspace 部署；每个 workspace 自带 `.ralph/bin/ralph` + `.ralph/lib/*`；不支持全局安装 | 澄清轮次 3 | 否 |
| TC-STK-003 | 技术选型 | `.env` 路径写死 `.ralph/.env`（相对 ralph 脚本位置），不接受其他路径 | 澄清轮次 3 | 否 |
| TC-STK-004 | 技术选型 | `--cwd` 参数不暴露；workspace 根由脚本路径决定，ralph 启动时内部 `cd` 到根 | 澄清轮次 3 | 否（v0 阶段） |
| TC-STK-005 | 技术选型 | adapter 契约 = shell 函数契约（`provider_oneshot` / `provider_collect_session` / `provider_diagnose`），三文件实现，`source` 动态载入 | 澄清轮次 2 | 是（新增 provider 时扩展） |
| TC-INT-001 | 集成 | 依赖 git CLI；workspace 必须是 git 仓库 | 澄清轮次 2（changed_files 依赖） | 否 |
| TC-INT-002 | 集成 | 依赖 Claude Code / Codex CLI / Gemini CLI 原生二进制；不封装 provider API | REQ-004 | 否 |
| TC-INT-003 | 集成 | UUID 生成按 `uuidgen` → `/proc/sys/kernel/random/uuid` → `python3 -c uuid.uuid4()` 顺序 fallback；三者全失败则报错 | `docs/architecture/integrations.md#uuid-依赖` | 否 |
| TC-REG-001 | 合规/安全 | `.ralph/runs/`、`.ralph/lock`、`.ralph/status.json` 不入仓；`.ralph/PROMPT.md` / `.ralph/TASKS.md` / `.ralph/.env` 由使用者决定是否入仓（默认由 `.ralph/.gitignore` 控制） | 使用者 workspace 约定 | 是 |

## 假设

- provider CLI 在不指定 `--model` / `--effort` 时能用自身默认跑 oneshot 正常退出（Claude `claude -p`、Codex `codex exec`、Gemini `gemini -p` 均如此）。
- agent 在 oneshot 内会遵守 PROMPT.md 约定"一个 task 一个 oneshot"；stagnation 和 max_iter 是兜底。
- Claude `~/.claude/projects/` 的 cwd 哈希规则在当前官方版本稳定；若未来变更，按版本分支处理。
- Gemini `-p` 模式下 session id 不稳定输出，退化按 mtime 定位最新 session 文件（I4 DEV-1 校准：Gemini CLI 无 `--thinking-budget` flag，effort 暂不传递）。

## 边缘情况

- TASKS.md 为空或无顶层 checklist → 启动立即 `done` 退出（无任务可做视为完成）。
- TASKS.md 所有项已勾选 → 启动立即 `done` 退出，不产生 iteration。
- `.env` 中 `RALPH_PROVIDER` 拼写错误（如 `claud`）→ adapter 加载失败，快速失败退出。
- provider CLI 在 PATH 中不可执行 → REQ-011 启动校验失败。
- 单轮 agent 勾选多条任务（违反 PROMPT 协议）→ ralph 不惩罚；下一轮继续，session 记录留痕。
- 单轮 agent 未勾选任何任务 → 本轮计入 stagnation。
- git 仓库存在但 `HEAD` 为裸初始化（无提交）→ `start_sha` 为空，`changed_files` 退化为仅 `git status --porcelain`。
- `.ralph/lock` 存在但持有进程已死（stale lock）→ v0.1 直接视为冲突退出 `locked`；使用者手动清理（后续版本可做 stale 检测）。

## 待澄清

- 是否要支持 dry-run（校验通过但不真正调 provider）以便 CI 使用，排到 v0.2 讨论。

## 已知开放点（实现细节级，不进 REQ）

以下事项在 I1 实施过程中按业界惯例处理；如 dogfood 中触发问题再升级为 REQ：

- **窄终端降级**：sticky bar 在终端宽度 < 80 列时截断长字段（如 `run_id` 显示前 12 位 + `...`）；不做硬约束。
- **`--interval` flag**：v0.1.1 范围内不暴露，固定 2 秒。如 dogfood 中真出现"2s 不够用"再加 flag 并升级 REQ-024。
- **iter log 暂未生成的瞬间**：watch 启动时若 `runs/<run_id>/iterations/iter-NNN/provider.stdout.log` 尚未创建（ralph 刚启动、第一个 iter 还未开始），tail 区域留空；文件出现后自动开始尾追，无占位文案。

## 追踪矩阵

| 上游 | 下游覆盖 | 验证 | 状态 |
|---|---|---|---|
| REQ-001 | SC-001-1, SC-001-2, BPF-001, FR-001 | 集成测试 | 完整 |
| REQ-002 | SC-002-1, BPF-001, FR-004 | 单元测试 | 完整 |
| REQ-003 | SC-003-1, BPF-001 | 文档 review + 示例 | 完整 |
| REQ-004 | SC-004-1, FR-005, FR-006, FR-007 | 手工 smoke | 完整 |
| REQ-005 | SC-005-1, TC-STK-005 | fake adapter smoke | 完整 |
| REQ-006 | SC-006-1, BPF-001, FR-005-007, FR-008, NFR-OBS-001, NFR-REL-002 | 集成测试 | 完整 |
| REQ-007 | SC-007-1, FR-002, FR-003 | 集成测试 + 手工验证 | 完整（边界细节由 REQ-023/024 接管） |
| REQ-022 | SC-022-1, SC-022-2, SC-022-3, SC-022-4, SC-022-5, SC-022-6, SC-022-7, FR-005, FR-006 | 集成测试 + adapter 翻译契约 + session 采集路径 | 完整（I1 dogfood 2026-05-01 暴露 SC-022-3 P0 bug 并修复；I2 DEV-1 2026-05-03 新增 SC-022-4/5 Codex 专属配置目录 SC；I4 DEV-5 2026-05-04 新增 SC-022-6/7 Gemini 专属配置目录 SC）|
| REQ-023 | SC-023-1, SC-023-2, SC-023-3, FR-002 | 集成测试 | 完整 |
| REQ-024 | SC-024-1, SC-024-2, SC-024-3, SC-024-4, SC-024-5, FR-003 | 集成测试 + 手工验证 | 完整（HUMAN-1 已验证）|
| REQ-025 | SC-025-1, SC-025-2, SC-025-3 | run 主循环 progress markers + heartbeat + -v live tail 集成测试 / 进程探针 | 完整 |
| REQ-026 | SC-026-1, SC-026-2 | 双层时间格式 helper + status/watch/exit-message 应用 | 完整 |
| REQ-008 | SC-008-1, TC-STK-002 | 单元 + 集成测试 | 完整 |
| REQ-009 | SC-009-1, FR-001, TC-STK-003 | 单元测试 | 完整 |
| REQ-010 | SC-010-1, TC-STK-004 | 集成测试 | 完整 |
| REQ-011 | SC-011-1, BPF-002, NFR-REL-003 | 集成测试 5 用例 | 完整 |
| REQ-012 | SC-012-1, SC-012-2, BPF-001, FR-001, NFR-REL-001 | 集成测试各触发一次 + timeout/interrupted 进程探针 | 完整 |
| REQ-013 | SC-013-1, BPF-001 | 集成测试 | 完整 |
| REQ-014 | SC-014-1, FR-005-007 | 单元测试 | 完整 |
| REQ-015 | SC-015-1, FR-001 | 集成测试 | 完整 |
| REQ-016 | — | 延后到 v0.1 之后 | 延后 |
| REQ-017 | SC-017-1 | T6.0 落样板入仓 + T6.3 真实 smoke 验证 `cp -r` 部署链路 | 完整（待 T6 闭环验证） |

## 变更影响

- 上游需求变更时必须同步检查 `docs/architecture/overview.md`（PROMPT 协议、adapter 契约、退出码表）、`docs/architecture/integrations.md`（provider 细节）、`docs/architecture/security.md`（approval/sandbox 与 secrets 边界）、`docs/roadmap.md`（阶段划分）、`task.md`（当前任务）。
- adapter 接口签名变更 → 三个 provider 实现 + fake adapter + T1 集成测试同步。
- 退出码或 `result.json` schema 变更 → `FR-002/FR-003` 消费端、`scripts/check.sh`、复盘用文档同步。

## 质量检查

- [x] 没有实现方案泄漏到需求正文（adapter 具体 bash 结构落在 `docs/architecture/overview.md`）。
- [x] 每个目标至少对应一个 `REQ-*` 或用户场景。
- [x] P0/P1 `REQ-*` 至少有一个 `SC-*`。
- [x] `SC-*` 有度量方式、目标值和验证方法。
- [x] `BPF-*` 覆盖核心流程、角色、输入、输出和异常分支。
- [x] `FR-*`、`NFR-*`、`TC-*` 都有来源依据。
- [x] 成功标准技术无关（SC 层只描述行为和文件产物）。
- [x] 高影响待澄清项已延后（dry-run 排到 v0.2；watch sticky bar 细节由 I1 REQ-023/024 收敛）。
