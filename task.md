# ralph-loop 开发任务

> 当前工程的开发任务事实源。工具实现位于 `.ralph/bin/` 和 `.ralph/lib/`；使用者 workspace 的 `.ralph/TASKS.md` 是运行时任务源，不与本文件混淆，也不入本仓库。

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `阻塞` 或 `需要决策`。
- 不记录需求澄清、方案备选、rejected designs 或会话流水（见 `docs/requirements/ralph-loop/requirements.md` 和 `docs/architecture/overview.md`）。
- 本文件只排**当前阶段**的任务；后续阶段在 `docs/roadmap.md` 规划，不提前写入。
- 跨任务的稳定决策必须沉淀到对应稳定文档，task.md 只引用文档锚点不重复正文，避免下个 session 失忆（见 `docs/postmortems/pm-cross-task-decision-sedimentation.md`）。沉淀归属边界：
  - **项目事实 / 项目契约 / 项目规范**（命名约定、协议步骤顺序、测试规范、安全边界等本项目的事实）→ `docs/architecture/*`
  - **agent 工作方法论 / 协作模型**（怎么写需求、怎么设计验证、怎么做 review 等通用做法）→ `.spec/rules/*`
  - 沉淀前先读目标文档自身的范围声明，不把项目事实写进 `.spec/`，也不把方法论写进 `docs/architecture/*`。

## 当前阶段：T2 — Claude Adapter

> 范围：实现 Claude provider adapter（三函数契约 + session 采集 + 错误诊断 + 派生视图）+ 单轮真实 workspace smoke。
> 横切：依赖校验框架（T2.0）、`ralph --version` / `--help` 补全（T2.6）。
> Provider 约定：T2.0 / T2.1 用 fake provider 验证机制层；T2.2-T2.5 用 mock-claude 验证 claude adapter 各分支；T2.6 用真实 claude smoke。当前阶段开发约定 `.ralph/.env` 默认 `RALPH_PROVIDER=fake`，避免误调真实 CLI。
> 测试约束：所有集成测试必须遵循 `docs/architecture/testing.md` 「测试隔离规则」段——HOME / PATH / 真实 `~/.claude/projects/` 等用户配置不得被污染，所有副作用限定在 `ralph run` 子进程或临时目录。
> 不含：Codex/Gemini adapter（T3/T4）、status/watch 真实功能（T5）、PROMPT/TASKS 模板生成、skill 封装、`ralph doctor` 子命令、provider 版本号检查（后两项在 `docs/roadmap.md` Deferred 段，T2.0 框架预留接口）。

- [x] T2.0：依赖校验框架。
  - 目标：启动校验阶段一次性收集所有缺失的第三方命令，按"缺什么 / 干什么用 / 怎么装"汇总打印到 stderr 后退出码 1；不逐个 fail-fast。后续 adapter 可直接挂载，无需各自实现。
  - 范围：
    - `.ralph/lib/common.sh`：新增 `ralph_require_cmd <cmd> <purpose> <install_hint> [min_version]`；缺失则追加进全局数组 `_RALPH_MISSING_DEPS`，不立即返回。`min_version` 参数预留位（本期不实现版本检查，传值会被忽略）。新增 `ralph_report_missing_deps`：若数组非空则按统一格式打印每一项（前缀 `ralph: missing dependency:`，含 cmd / purpose / install hint），最后退出码 1。安装提示统一支持 `macOS:` 和 `Linux:` 两行（手动列，不自动检测平台）。
    - 各 adapter 暴露可选函数 `provider_check_deps()`，被 source 后由 run.sh 调用以注册 provider 特定依赖。fake adapter 实现该函数：注册 `$RALPH_PROVIDER_CLI`（默认 `bash`）作为"我有自己的 CLI"声明，使原有 `RALPH_FAKE_CLI=__nonexistent__` 用例仍可通过依赖框架触发缺失报错。Claude adapter 在 T2.1 注册 `claude` 和 `jq`。
    - `.ralph/lib/run.sh`：在现有 `_ralph_startup_checks` **之前**新增依赖校验阶段：先注册公共依赖（`git`），再调用 `provider_check_deps`（若已定义），最后 `ralph_report_missing_deps`。删除 `_ralph_startup_checks` 中现有的 `command -v "$RALPH_PROVIDER_CLI"` 段（合并到依赖框架，避免重复检查 + 报错前缀不一致）。`RALPH_PROVIDER_CLI` 变量保留：仍被 context.json 写 provider_version 等逻辑使用，仅去除存在性检查。
    - `docs/architecture/overview.md`：同步更新「运行时伪代码」段，把 `validate: ... command -v "$RALPH_PROVIDER_CLI"` 替换为 `check_dependencies (git + provider_check_deps from sourced adapter)`，并明确"缺失依赖一次性聚合输出后退出"。
    - `scripts/integration-test.sh`：原 fake `command -v` 失败用例（`RALPH_FAKE_CLI=__nonexistent-xxx__`）断言改为 stderr 含 `missing dependency:` 前缀（替代原 `startup check failed:`）。
  - 实施步骤：
    1. `common.sh` 加 `_RALPH_MISSING_DEPS` 数组、`ralph_require_cmd`、`ralph_report_missing_deps`。
    2. `adapter-fake.sh` 加 `provider_check_deps`：`ralph_require_cmd "$RALPH_PROVIDER_CLI" "fake provider CLI" "test fake; override via RALPH_FAKE_CLI"`。
    3. `run.sh` 在 `_ralph_startup_checks` 之前插入依赖校验阶段；公共依赖注册 `git`；条件调用 `provider_check_deps`；调用 `ralph_report_missing_deps`。
    4. `run.sh` 删除原 `RALPH_PROVIDER_CLI` 存在性检查段（保留赋值与下游使用）。
    5. `scripts/integration-test.sh` 修改 fake 缺失 CLI 用例的断言前缀。
    6. `docs/architecture/overview.md` 同步伪代码段。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - 集成测试新增 ≥3 用例（均显式 `RALPH_PROVIDER=fake`）：
      - 公共 happy 路径（git 存在 + fake provider CLI=bash 存在）：依赖框架不输出任何 missing。
      - 子进程 PATH 隔离移除 git → stderr 含 `missing dependency: git` + 安装提示，退出 1。**测试隔离**：PATH 修改限定在 `ralph run` 子进程（`env PATH=... ralph run ...`），harness 外层 PATH 不变（见 `docs/architecture/testing.md`）。
      - 多依赖同时缺失（mock provider 注册两个不存在命令）→ 一次输出全部缺失项，验证不是 fail-fast。
    - 原 fake 缺失 CLI 用例（断言已改）继续 PASS。
  - 不做：`ralph doctor` 子命令、版本号比对、安装提示自动检测平台、依赖路径缓存。
  - 参考：`docs/requirements/ralph-loop/requirements.md` REQ-011（快速失败）、`docs/architecture/overview.md`（启动校验段）、`docs/architecture/testing.md`（测试隔离）。

- [x] T2.1：Claude adapter 骨架 + 命令构造 + session_id 生成 + mock-claude 单一来源。
  - 目标：实现 `adapter-claude.sh` 三函数契约——`provider_oneshot` 完整实现，`provider_collect_session` / `provider_diagnose` 空实现（T2.2/T2.3 落实）；session_id 在 adapter 内生成并写回 meta.json；stdout JSON 拆为独立文件供后续 diagnose 解析；同步建立 `tests/fixtures/mock-claude` 作为后续所有 claude 测试的**单一 mock 来源**（T2.5 在同一文件扩展场景，不另起炉灶；见 PM-0002）。
  - 范围：
    - 新文件 `.ralph/lib/adapter-claude.sh`：
      - 设置 `RALPH_PROVIDER_CLI=claude`。
      - `provider_check_deps()`：注册 `claude`（"Claude Code CLI"，安装提示 `npm install -g @anthropic-ai/claude-code`）、`jq`（"parse Claude JSON output"，`macOS: brew install jq` / `Linux: apt install jq`）。
      - `provider_oneshot(prompt_file, log_path, iter_dir)`：
        - 用 `ralph_uuid` 生成 session_id；通过 `update_meta_jq` 写入 `$iter_dir/meta.json` 的 `session_id` 字段（jq `--arg` 原地重写，比 sed 稳健，见 `docs/architecture/overview.md` meta.json 写入约定段）。
        - 构造命令：`claude -p "$(cat $prompt_file)" --session-id "$session_id" --dangerously-skip-permissions --allowedTools "Bash,Read,Edit,Write,Glob,Grep" --output-format json`。
        - stdout → `$iter_dir/session.claude.stdout.json`（命名遵循 `docs/architecture/integrations.md` 「Session 文件命名约定」段，前缀 `session.<provider>.` 与 Codex/Gemini 对齐）。stderr → `$log_path`；同时把 stdout/stderr 合流也 tee 进 `$log_path`（保持 T1 log 全量约定）。
        - 返回 claude CLI 的退出码（用 `rc=0; ... || rc=$?` 防御 `set -euo pipefail`）。
      - `provider_collect_session()` / `provider_diagnose()`：空实现 + 注释指明 T2.2 / T2.3 完成。
    - `.ralph/lib/run.sh`：调整 `init_meta` 调用顺序——目前 `init_meta` 在 `provider_oneshot` 之后会覆盖 adapter 写入的 session_id。改为：在 `provider_oneshot` **之前**调用 `init_meta` 建立骨架（exit_code 与 duration_ms 用占位 0，后续用 jq 补正），让 adapter 写入有效。
    - `.ralph/lib/session.sh`：新增 `update_meta_jq <iter_dir> <jq_filter> [jq_args...]`：通用 jq 原地重写 helper（写 tmp + mv），处理 string / object / array 等所有复杂值。`update_meta_field` 保留作为标量数字/null 的轻量路径（fake adapter 用，避免 fake 强依赖 jq）。
    - 新文件 `tests/fixtures/mock-claude`（**mock-claude 单一来源**）：claude CLI 的测试替身骨架，本任务实现：
      - shebang + `set -euo pipefail`。
      - 解析 `--session-id <uuid>` flag 取 session_id 供后续场景使用。
      - `case "$RALPH_MOCK_CLAUDE_SCENARIO" in ...` 分发框架（本任务实现 `happy`，T2.5 扩展全场景）。
      - happy 场景：写 stdout JSON `{"is_error":false,"result":"done","session_id":"<uuid>"}`；按 cwd_hash 规则写入 `$HOME/.claude/projects/<hash>/<session_id>.jsonl`（最小 fixture 内容）；exit 0。
      - cwd_hash 实现严格遵循 `docs/architecture/integrations.md`「Claude Session 机制」段步骤顺序（**先 realpath 再字符替换**），并在脚本顶部注释引用文档锚点。
  - 实施步骤：
    1. 新建 `adapter-claude.sh`，定义 `RALPH_PROVIDER_CLI` + `provider_check_deps`。
    2. `session.sh` 新增 `update_meta_jq` helper。
    3. `run.sh` 调整 init_meta 顺序 + 用 update_meta_jq 补 exit_code / duration_ms 事后回填。
    4. 实现 `adapter-claude.sh` 的 `provider_oneshot`：UUID → meta jq 写入 session_id → 命令构造 → 双重重定向 → 返回码捕获。
    5. `provider_collect_session` / `provider_diagnose` 写空实现 + TODO 注释。
    6. 新建 `tests/fixtures/mock-claude` 骨架 + happy 场景。
  - 验证计划：
    - `bash scripts/check.sh` 通过（含 `bash -n adapter-claude.sh`、`bash -n tests/fixtures/mock-claude`）。
    - 集成测试加 ≥1 用例（`RALPH_PROVIDER=claude` + mock-claude happy + HOME 隔离）→ `session.claude.stdout.json` 内容是 mock 输出；`meta.json.session_id` 是合法 UUID 格式；`result.json.exit_reason=done`。
    - 原 14 个 fake 用例 + T2.0 用例继续全 PASS。
  - 不做：session 文件查找（T2.2）、错误诊断（T2.3）、派生视图（T2.4）、完整 mock-claude 多场景（T2.5）。
  - 参考：`docs/architecture/integrations.md`（Claude 节、Session 文件命名约定）、`docs/architecture/security.md`（approval/sandbox 写死）、`docs/architecture/testing.md`（测试隔离 + 单一来源）。

- [x] T2.2：Session 文件采集 + cwd_hash 定位 + 降级 + setup_claude_workspace helper。
  - 目标：实现 `provider_collect_session` 完整版：按 cwd_hash 规则在 `~/.claude/projects/<hash>/<session_id>.jsonl` 精确定位 → 复制 → 写 meta.json 路径字段；找不到走 mtime 降级扫描；最终都失败写 `capture_status=warning` + `capture_warning`。同步建立 `setup_claude_workspace` 测试 helper（HOME 隔离）作为**单一测试基础设施来源**，T2.5 在此基础上扩展场景，避免重复造（见 PM-0002）。
  - 范围：
    - `.ralph/lib/adapter-claude.sh`：填充 `provider_collect_session(iter_dir)`：
      - **cwd_hash 严格步骤顺序**（来自 `docs/architecture/integrations.md` Claude Session 机制段）：**先** `realpath` 解析 symlink → **再** 把所有非 `[A-Za-z0-9-]` 字符替换为 `-`（`sed 's/[^A-Za-z0-9-]/-/g'`）。顺序写反对 symlink workspace 会算错 hash 找不到 session 文件，无错误信息难排查（见 PM-0002）。
      - workspace 路径源：从 `_RALPH_WORKSPACE`（run.sh 已设置）。
      - 精确匹配：从 `$iter_dir/meta.json` 读 session_id（用 jq）→ 检查 `$HOME/.claude/projects/<hash>/<session_id>.jsonl`；存在则 `cp` 为 `$iter_dir/session.claude.jsonl`，用 `update_meta_jq` 更新 `session_source_path` / `session_copied_path` / `capture_status=ok`。
      - 降级：在 `$HOME/.claude/projects/<hash>/` 下扫描所有 `.jsonl`，按 mtime 取大于 iter 起始时间戳的最新文件；命中则 `capture_status=ok` + `capture_warning="fallback by mtime"`。
      - 全部失败：`capture_status=warning` + `capture_warning="session file not found"`，但不影响 run 流程。
    - macOS 兼容：`stat` 与 `find -newer` 的语义在 BSD/GNU 不同，需在 macOS 实测；优先用 `find` 而非 `stat`（参考 PM-0001）。
    - `scripts/integration-test.sh`：建立 `setup_claude_workspace` helper（**单一来源**，T2.5 扩展不另建）：
      - 复制部署 + 写 `.ralph/.env`（`RALPH_PROVIDER=claude`）+ 把 `tests/fixtures/mock-claude` 软链到 workspace 内 `tests-bin/` 目录，仅在 `ralph run` 子进程通过 `env PATH=...` 注入 PATH 头部（不污染 harness 外层 PATH）。
      - **HOME 隔离**：`export HOME="$tmpdir/home"; mkdir -p "$HOME/.claude/projects/"`，避免污染真实 `~/.claude/projects/`（强制要求，见 `docs/architecture/testing.md`）。
  - 实施步骤：
    1. `_claude_cwd_hash <path>` 子函数（顶部注释引用 integrations.md 锚点说明严格 realpath → hash 顺序）。
    2. 精确路径定位 + 复制 + meta 写入（用 `update_meta_jq`）。
    3. mtime 降级扫描（macOS BSD `find` 语法兼容）。
    4. 三种 capture_status 路径的 meta.json 写入。
    5. `scripts/integration-test.sh` 建立 `setup_claude_workspace` helper。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - 集成测试用例（`RALPH_PROVIDER=claude` + mock-claude 配合，需 T2.5 扩展场景；本任务可以先用临时直接调用 `provider_collect_session` 的方式验证函数级，T2.5 接入 end-to-end）：
      - happy：mock 在 isolated `$HOME/.claude/projects/<hash>/<session_id>.jsonl` 写入 → 复制成功，capture_status=ok。
      - 降级：mock 写入 mtime 新但 UUID 不匹配 → 命中 fallback，capture_warning="fallback by mtime"。
      - missing：mock 不写 session 文件 → capture_status=warning。
    - macOS 实测三个用例均通过。
    - **测试隔离自检**（每次集成测试结束）：跑测试前后 `ls ~/.claude/projects/` 数量不变（HOME 隔离生效）。
  - 不做：session 内容解析或脱敏；session 文件入仓；跨 cwd_hash 目录的扫描。
  - 参考：`docs/architecture/integrations.md`（Claude session 机制 + cwd_hash 严格顺序）、`docs/postmortems/pm-shell-macos-compat.md`、`docs/postmortems/pm-cross-task-decision-sedimentation.md`、`docs/architecture/testing.md`（测试隔离 + 单一来源）。

- [x] T2.3：Claude 错误诊断矩阵。
  - 目标：实现 `provider_diagnose` 完整版：从 `session.claude.stdout.json` 解析 `is_error` 与 `result` 字段，按矩阵分类为 `auth` / `rate_limit` / `quota` / `api` / `concurrency` / `unknown`，写入 meta.json `error` 对象；run.sh 的 `provider_failed` 路径据此填充 `result.json.last_error.type`。
  - 范围：
    - `.ralph/lib/adapter-claude.sh`：填充 `provider_diagnose(iter_dir)`：
      - 用 `jq` 读 `session.claude.stdout.json` 的 `.is_error` 和 `.result`（缺失字段安全降级）。
      - 关键字按以下互斥优先级匹配 `result`（case-insensitive），命中第一条即止：
        1. `tool_use_concurrency` → `concurrency`
        2. `unauthor` / `401` / `invalid api key` → `auth`
        3. `429` / `rate.?limit` / `too many requests` → `rate_limit`
        4. `quota` / `credits exhausted` / `billing` → `quota`
        5. `5xx` / `api` 其他 → `api`
        6. 兜底 → `unknown`
      - `is_error=true`：按矩阵分类。`is_error=false` 但 provider exit_code 非零（CLI 自身 crash）：归 `unknown`。`is_error=false` 且 exit_code=0：error=null。
      - 写 meta.json `error` 对象 `{type, message, raw}`：用 `update_meta_jq` + `--argjson` 一次性整段重写（**禁用 sed 拼装对象**，避免引号/逗号/嵌套边界问题——这是 T2.1 引入 `update_meta_jq` 的根本原因）。message 取 result 的截断片段，raw 保留 result 原文（≤500 字符）。
    - `run.sh`：现 `provider_failed` 分支已读 meta.json error.type 填 last_error_json；若 message 字段当前硬编码为 "provider exited with code $rc"，改为优先使用 meta.json error.message。
  - 实施步骤：
    1. `_claude_classify_error <text>` 纯函数（输入字符串 → 输出分类标签）。
    2. jq 解析 stdout JSON + 字段降级。
    3. meta.json error 对象写入（`update_meta_jq` + `--argjson`）。
    4. run.sh `last_error_json` 改读 meta.json message 字段。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - 集成测试 ≥6 用例（mock-claude 模拟，依赖 T2.5 扩展场景）：
      - is_error+unauthor → last_error.type=auth
      - is_error+429 → rate_limit
      - is_error+quota → quota
      - is_error+5xx → api
      - is_error+tool_use_concurrency → concurrency
      - exit≠0 且无 stdout JSON → unknown
  - 不做：自动重试、auth 错误自动登录引导、错误分类后影响下一轮 session 处理（fresh oneshot 默认已满足 concurrency 重置）。
  - 参考：`docs/architecture/integrations.md`（错误诊断节）、`docs/architecture/overview.md`（错误诊断类别）。

- [x] T2.4：chat.log / tools.log 派生视图。
  - 目标：从 `session.claude.jsonl` 派生 `chat.log` 与 `tools.log`，**严格遵循 `docs/architecture/overview.md` 派生视图段** schema（chat.log 含 `[user] / [assistant] / [tool-result name=X]` 三类带 timestamp 段，tool-result 文本截 2000 字符；tools.log 每行 `<timestamp> <tool_name> <brief_input> <brief_output_or_status>`）；不自定义 schema。
  - 范围：
    - `.ralph/lib/adapter-claude.sh`：在 `provider_collect_session` 末尾新增 `_claude_derive_views(iter_dir)`，capture_status=ok 时调用：
      - `chat.log`：从 `session.claude.jsonl` 用 jq 流式过滤 user / assistant / tool_result 三类，按 overview.md 格式输出（`[role] <timestamp>\n<content>\n\n`），tool-result content 截 2000 字符。
      - `tools.log`：jq 过滤 tool_use 配对 tool_result，按 overview.md 格式每行输出；input/output 截 80 字符。
      - 输入字段名对齐 Claude 实际 jsonl schema（T2.6 真实 smoke 拿到 fixture 后微调）；若实际字段与预期不符，**只补丁更新本任务实现**，不偏离 overview.md schema。
    - 找不到 session 文件（capture_status=warning）时，chat.log/tools.log 写空文件保持文件存在性约定。
  - 实施步骤：
    1. 准备 jsonl fixture：从 T2.6 真实 smoke 截取，或人工构造覆盖 user/assistant/tool_use/tool_result 各一条的最小样本，存 `tests/fixtures/claude-session-sample.jsonl`。
    2. `_claude_derive_chat`：jq 过滤三类消息按 overview.md 格式输出。
    3. `_claude_derive_tools`：jq 配对 tool_use + tool_result。
    4. 接入 `provider_collect_session` 末尾。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - 集成测试：mock-claude 写入预制 jsonl fixture（含 1 user / 1 assistant / 1 tool_use+tool_result）→ chat.log 含 3 段（含 tool-result 段）、tools.log 含 1 行。
    - missing session 用例：chat.log/tools.log 文件存在但内容为空。
    - T2.6 真实 smoke 后 spot-check 派生视图与 overview.md schema 一致。
  - 不做：HTML/Markdown 渲染、内容脱敏、跨 iter 合并视图、自定义 schema。
  - 参考：`docs/architecture/overview.md`（派生视图段）、`docs/architecture/integrations.md`（统一采集输出）。

- [x] T2.5：集成测试扩展（mock-claude 全场景 + claude adapter 端到端）。
  - 目标：在 T2.1 建立的 `tests/fixtures/mock-claude` **单一文件**上扩展全部场景（不另起炉灶）；在 T2.2 建立的 `setup_claude_workspace` helper 上扩展用例（不另起炉灶）；总 PASS 数从 14 扩展到 ≥29。
  - 范围：
    - `tests/fixtures/mock-claude` 扩展场景（T2.1 已有 happy 骨架）：
      - `is_error_auth` / `is_error_rate` / `is_error_quota` / `is_error_api` / `is_error_concurrency`：写对应关键字 stdout JSON（`is_error=true` + result 含相应关键词）；exit 0。
      - `crash`：exit 1，无 stdout。
      - `missing_session`：stdout 正常，但不写 session 文件。
      - `mtime_fallback`：stdout 正常，写一个文件名 UUID 不匹配但 mtime 新的 jsonl 到对应 cwd_hash 目录。
      - cwd_hash 与 adapter 一致（**严格 realpath → hash 顺序**）。
    - `scripts/integration-test.sh`：
      - 在 T2.2 已建立的 `setup_claude_workspace` helper 上**直接扩展**支持新场景所需初始化（不新建 helper）。
      - 用例集补齐到 ≥7：claude_happy（T2.1）/ is_error_auth / is_error_concurrency / crash / missing_session（T2.2 已覆盖）/ mtime_fallback（T2.2 已覆盖）/ dep_missing_jq。
      - **`claude_dep_missing_jq` 用例 PATH 隔离**（关键测试隔离要求，见 `docs/architecture/testing.md`）：构造一个不含 jq 的 PATH（如 `mkdir tmpbin; ln -s /usr/bin/{git,bash,...} tmpbin/`），用 `env PATH="$tmpbin" ralph run` 启动子进程；harness 外层 PATH 不动，仍能用 jq 做断言。验证 stderr 含 `missing dependency: jq`，退出 1。
      - 每用例断言：result.json.exit_reason、result.json.last_error.type（错误用例）、meta.json.capture_status / capture_warning（session 用例）、chat.log / tools.log 存在。
    - PASS 总数对账：原 14 + T2.0 ≥3 + T2.1 ≥1 + T2.2 ≥3 + T2.3 ≥6 + T2.5 补 ≥2 = ≥29。
  - 实施步骤：
    1. mock-claude 在 T2.1 骨架上加场景分发（不重写整文件）。
    2. setup_claude_workspace helper 在 T2.2 基础上扩展（不新建 helper）。
    3. 用例补齐 + PATH 隔离实现。
    4. 总 PASS 数对账。
    5. **测试隔离自检**：跑完后验证 `~/.claude/projects/`、harness PATH、其他用户配置全部未变。
  - 验证计划：
    - `bash scripts/integration-test.sh` PASS ≥29，FAIL=0。
    - macOS 实测全 PASS（PM-0001 约束）。
    - 测试隔离自检通过。
  - 不做：真实 claude CLI 调用（T2.6）、网络相关测试、性能测试。
  - 参考：T1 fake adapter 集成测试模式、`docs/postmortems/pm-shell-macos-compat.md`、`docs/postmortems/pm-cross-task-decision-sedimentation.md`、`docs/architecture/testing.md`。

- [x] T2.6：真实 Claude smoke + `--version` / `--help` 补全 + 文档收尾。
  - 目标：真实 `claude` CLI 跑一轮单条 task 验证 T2.1-T2.5 端到端；补全 `ralph --version` 和全部 `--help` 输出，使工具看起来用起来都专业；如发现 docs 与实际有偏差做补丁级更新。
  - 范围：
    - **真实 Claude smoke**：
      - 临时 workspace（`/tmp/ralph-claude-smoke/`）准备：`git init` + 简单 `.ralph/PROMPT.md` + `.ralph/TASKS.md`（一条 task：例 "在 README.md 加一行 Hello"）+ `.ralph/.env`（`RALPH_PROVIDER=claude`）。
      - 执行 `RALPH_PROVIDER=claude .ralph/bin/ralph run`。
      - 验证：result.json.exit_reason=done + meta.json.session_id 非空 + meta.json.capture_status=ok + session.claude.jsonl 复制成功 + chat.log/tools.log 非空且符合 overview.md schema。
      - 证据贴 task.md 完成段：result.json + meta.json 关键字段（不贴 transcript 全文，不入仓 run 目录）+ Claude CLI 版本号。
    - **`ralph --version` / `-v` 新增**：
      - `.ralph/bin/ralph` 顶层新增 `--version` / `-v` flag：输出 `ralph 0.1.0-dev (<git short sha>)`，退出 0。版本号在脚本顶部硬编码常量；git short sha 用 `git rev-parse --short HEAD 2>/dev/null || echo unknown`。
    - **`--help` 补全**：
      - `ralph --help` / `ralph -h`：顶层命令列表 + 子命令简介 + 整体用法示例 ≥2。
      - `ralph run --help`：所有 flag 详解 + 默认值 + 对应环境变量名 + 优先级（CLI > env > .env > 默认）+ 退出原因 7 种速查表 + 运行目录布局简示 + 命令示例 ≥3。
      - `ralph help <subcommand>` 与 `<subcommand> --help` 等价。
      - `ralph status` / `ralph watch`（无 flag）：从"报错退出 1"统一改为"输出占位 help + 提示未实现，退出 0"，让所有未实现命令行为一致专业；help 文本明确写"v0.1 未实现，roadmap T5 落地"。
      - `ralph status --help` / `ralph watch --help`：同上占位 help。
      - 集成测试加 ≥4 用例：`ralph --version` exit 0 + 含 `0.1.0-dev`、`ralph --help` exit 0、`ralph run --help` exit 0 + 含关键 flag 名、`ralph status` exit 0 + 含 "v0.1 未实现"。
    - **docs 偏差修正**：若真实 smoke 暴露 `integrations.md` Claude 节、`overview.md` 派生视图 schema 或 cwd_hash 规则与实际不符，补丁级更新。
    - **roadmap 同步检查**：`docs/roadmap.md` Deferred 段已加入 `ralph doctor` + 版本检查项；本任务确认其仍准确（如 smoke 暴露其他延后项一并补登）。
  - 实施步骤：
    1. 真实 smoke：手动准备 workspace + 跑一轮 + 收集证据。
    2. `ralph --version` 实现 + 集成测试 +1。
    3. `--help` 补全 ralph bin（含 status/watch 行为统一）+ 集成测试用例 +3。
    4. 偏差修正（如有）。
    5. 全量 `bash scripts/check.sh && bash scripts/integration-test.sh` 验收。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - `bash scripts/integration-test.sh` PASS ≥33、FAIL=0。
    - 真实 smoke 证据贴 task.md。
  - 不做：性能基准、多 task 长链路 smoke（T6 v0.1 release）、Codex/Gemini 对应 smoke。
  - 参考：`docs/roadmap.md`、`docs/architecture/integrations.md`、`docs/architecture/overview.md`。
  - 完成证据（2026-04-27，claude 2.1.119）：
    - run_id: `20260427-121516-ef055eb`；exit_reason: done；iterations: 2；duration: 30s；last_error: null。
    - meta.json: session_id=2b768224-b3bf-4809-a5c1-a0c9135dc537；capture_status=ok；exit_code=0；error=null。
    - session.claude.jsonl 复制成功；chat.log 含 `[user]`/`[assistant]`/`[tool-result name=*]` 段；tools.log 含工具调用行。
    - smoke-output.txt 内容为 `ralph smoke ok`（任务完成）。
    - schema 修正：真实 Claude JSONL 中 tool_result 封装在 `type:"user"` 消息（非 `type:"tool"`），内层 content 为字符串；已修正 `_claude_derive_chat` / `_claude_derive_tools` 及 fixture/mock-claude，PASS 仍 34。
