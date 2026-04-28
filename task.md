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

## 当前阶段：T6 — v0.1 闭环验证 + 使用指南

> 范围：用 Claude 单 provider 把 v0.1 内核（loop / TASKS 解析 / stagnation / max_iter / timeout / changed_files / done 检测 / `--effort` 抽象）在**多任务真实长链路**下整体闭环；同步交付 PROMPT.md 参考模板和使用指南；T6 入场前 adversarial review 暴露的 P0/P1 缺陷在前置子任务中修复。
> 优先级决策：T2 完成后**优先 T6**，T3/T4/T5 后置。理由见 `docs/roadmap.md#阶段重排序决策2026-04-28`。
> 不含：Codex/Gemini adapter（T3/T4）、status/watch 真实功能（T5）、ralph init / 工具运行时模板生成（requirements §非目标 line 23 + REQ-017）、conductor / role 系统 / questions hard-block 等业务域扩展（属用户 workspace 自由发挥，不入 ralph 内核）。
> 测试约束：沿用 `docs/architecture/testing.md` 隔离规则；新增真实 Claude 多轮 smoke 必须落到独立临时 workspace（如 `/tmp/ralph-t6-multi-smoke/`），不污染本仓库。
> 子任务执行顺序（依赖驱动）：T6.0 模板 → T6.1 stagnation 修 → T6.2 effort 接入 → T6.3 多轮 smoke → T6.4 边界复验 → T6.5 使用指南 → T6.6 v0.1 closure；T6.7 patch 池贯穿全程按需触发。

- [x] T6.0：PROMPT.md + TASKS.md 参考样板（直接落 `.ralph/` 入仓）。
  - 完成：`.ralph/PROMPT.md`（74 行）+ `.ralph/TASKS.md`（11 行）入仓；`scripts/check.sh` 守卫翻转；`docs/README.md` 部署单元索引行。
  - 变更：`.ralph/PROMPT.md`（新增）、`.ralph/TASKS.md`（新增）、`scripts/check.sh`、`docs/README.md`
  - 验证：`bash scripts/check.sh` PASS；行数约束满足（PROMPT ≤120、TASKS ≤20）。
  - 目标：交付 `.ralph/PROMPT.md` 和 `.ralph/TASKS.md` 两份 provider-agnostic 参考样板，**直接放在部署单元 `.ralph/` 内入仓**（REQ-017）——使用者部署 ralph 时 `cp -r .ralph/ <workspace>/.ralph/` 一次性带走 bin/lib/PROMPT/TASKS，按需裁剪。ralph 内核**不**读取这两个文件作为内核控制信号、不自动生成、不在工具运行时改写其结构（requirements §非目标 line 23：ralph 工具运行时不 init/不生成模板。样板入仓由人工维护，不属于内核 init 路径）。两份样板配对成一组降低首次上手摩擦；详细字段语义在 T6.5 usage doc 内嵌完整 demo 解释。
  - 范围：
    - 新文件 `.ralph/PROMPT.md`，承载以下要点（每点都要 actionable、可被 LLM 当指令读）：
      - **身份澄清**：你是 ralph 外层循环的一次 iteration；外层循环是 OS 进程不是 LLM；**不要** `ScheduleWakeup` / `CronCreate` / `/loop` / `/schedule` 自己排自己；**不要** spawn 例行 subagent（subagent 只在本轮任务本身明确需要并行/隔离时用）；不要把进度注记当成"你在驱动 loop"。
      - **Procedure**（每轮）：read `.ralph/TASKS.md` → 找第一个 `- [ ]` → 执行 → 完成后改 `- [x]` → exit。**一个 task 一个 oneshot**（PROMPT 协议硬约束）。
      - **TASKS.md self-mutation 安全规则**：append-only；**禁止**删任务；**禁止**改写他人已读的任务文本；**禁止**把 `- [ ]` 直接 fake-mark 为 `- [x]`（必须真做了对应工作才勾）；可在阻塞任务**上方**插入说明性 task。
      - **退出语义**：全部 `[x]` → ralph 判 done；本轮不动 TASKS 也不改 git → 计入 stagnation；超 `--timeout` → `timeout`；超 `--max-iter` → `max_iterations`；CLI crash → `provider_failed`。这些状态由 ralph 外层判定，agent 不要主动写 exit code。
      - **每轮 Git 礼仪**：建议每完成一个 task 立即 `git add -A && git commit`；每轮开始前 `git status` 确认 clean。
      - **每轮 fresh oneshot + PROMPT 重读约定**：ralph 每轮调用都是 fresh oneshot，PROMPT.md 在每轮启动时重新读取；**可以**在 run 间编辑 PROMPT.md（影响下一轮）；**不要**期望 mid-oneshot 修改本轮看到的内容（本轮 prompt 已固化为 stdin）。
      - **不要做的事**清单：不要重构无关代码、不要重跑已经通过的测试（除非相关改动）、不要在 oneshot 内合并多个 task。
      - **附注**：业务域更复杂的循环协议（多 role / questions hard-block / conductor 看板）属于使用者扩展，本模板**只覆盖 ralph 内核要求**；外部例子可参考 trantor build PROMPT.md（外部链接形式注释）。
    - 文件顶部加注释块说明：「这是参考样板，随 `.ralph/` 部署单元一并 copy 到使用者 workspace；可按需裁剪。ralph 内核不依赖此文件存在或内容形态」。
    - 新文件 `.ralph/TASKS.md`：≤20 行最小起手示例，含 1 条带子 bullet 描述细节的任务 + 1 条单行任务 + 1 条已完成 `[x]` 任务；顶部注释说明「参考样板，随 `.ralph/` 部署。ralph 只识别顶层 `^\s*-\s+\[([ xX])\]`，子 bullet 是给 agent 读的不进解析」。
    - **本仓库 `.ralph/TASKS.md` 内容定位为纯样板**（hello-world 风格），不是本项目 dogfood 任务源——本项目开发任务事实源仍是根 `task.md`，避免双源冲突。
  - 实施步骤：
    1. 起草 `.ralph/PROMPT.md`，参考 trantor PROMPT.md 节选骨架但**全部去 trantor 化**（不出现 REQ-/PLAN-/META-/JAVA-/QA- 等 role 前缀，不出现 `.trantor/build/` 路径）。
    2. 起草 `.ralph/TASKS.md` 最小示例。
    3. `docs/README.md` 在"项目事实"或类似章节加一行说明部署单元 `.ralph/` 含 bin/lib/PROMPT/TASKS。
    4. 走查样板：每条规则可独立成立、不引用未实现的 ralph 功能（不引 `ralph status` / `ralph doctor`）。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - PROMPT 样板 ≤120 行；TASKS 样板 ≤20 行（强约束：太长 LLM 会忽略 / 干扰用户裁剪）。
    - 两份文件入仓后 `git ls-files .ralph/` 含 `bin/`、`lib/`、`PROMPT.md`、`TASKS.md`，无 `runs/` / `lock` / `status.json` / `.env`。
    - 间接验证由 T6.3 真实 smoke 完成（直接 `cp -r .ralph/ /tmp/ralph-t6-multi-smoke/.ralph/` 起 smoke，跑通即样板有效）。
  - 不做：把样板内容硬编码进 ralph 内核；TASKS 样板写复杂业务任务样例（保持极简，详细 demo 在 T6.5 usage 内嵌）；多语言版本（v0.1 中文为主）；本仓库 dogfood 跑 ralph 自己（v0.1 不做，T6 期间内核还在改，dogfood 风险大）。
  - 参考：trantor `.trantor/build/PROMPT.md`（外部参考）；REQ-001 / REQ-002 / REQ-017、requirements §非目标 line 23；`docs/architecture/overview.md` 退出原因 7 种。

- [x] T6.1：stagnation 检测语义修正 + per-iter changed_files 记录。
  - 完成：方案 B（in-memory fingerprint）实现；`run.sh` 主循环改为 fingerprint_before vs fingerprint_after；`meta.json` 字段拆为 `changed_files_total`（cumulative）+ `changed_files_iter`（per-iter）；`--stagnation-limit` flag + `RALPH_STAGNATION_LIMIT` 新增；`partial_progress` mock 场景新增；新增 2 个集成测试（partial_progress stagnation + happy stagnation_count=0）；`docs/architecture/overview.md` stagnation 段补丁。
  - 变更：`.ralph/lib/common.sh`、`.ralph/lib/run.sh`、`.ralph/lib/session.sh`、`.ralph/lib/adapter-fake.sh`、`.ralph/bin/ralph`、`scripts/integration-test.sh`、`docs/architecture/overview.md`
  - 验证：`bash scripts/check.sh` PASS；`bash scripts/integration-test.sh` 全 37 PASS（含新增 2 用例）；macOS（shasum -a 256 fallback）已在代码中覆盖。
  - 注意：PM-0003 回查——stagnation cumulative bug 已修复，T6.4 真实 Claude 触发待 T6.4 验证。
  - 目标：修复 adversarial review 暴露的 P0 缺陷——`run.sh:386` 当前用 `ralph_changed_files "$start_sha"`（**run 起点 cumulative**）作为 stagnation 判据，导致第一轮一旦改过任何文件，第二轮起 cumulative diff 永远非空，stagnation_count 永远不再 ++，stagnation 在长链路里事实上失效。同步修复 P1 缺陷：每轮 `meta.json.changed_files` 也是 cumulative，语义误导。
  - 范围：
    - `.ralph/lib/common.sh` 或 `run.sh`：新增 `ralph_changed_files_since <ref>` 或在 run.sh 主循环维护"上轮末快照 SHA + worktree fingerprint"，让 stagnation 判据改为**本轮 vs 上轮**：
      - 每轮 oneshot 结束后，先 `git add -A` snapshot 到一个 ralph 内部 ref（`refs/ralph/iter/<run_id>/<iteration>`，不影响用户分支）或纯 in-memory 记录（`prev_iter_files_sha = git stash create`-style 或 `git ls-files -s | sha256sum`）。
      - 本轮 stagnation 判据：`checked_after == checked_before && (本轮 vs 上轮的 file diff 为空)`。
      - 兼容首轮：上轮没有快照时，比对基准用 `start_sha` + run 启动时的 worktree 状态。
    - 选型已定（**方案 B：in-memory 哈希**，2026-04-28 决策）：每轮算 `git ls-files -s` + `git status -z` 拼起来过 `sha256sum`，得到一个"本轮 worktree fingerprint"存 shell 变量；下轮算同样 fingerprint 与上轮比对。**不**写 `.git/refs/`、**不**创建 git 对象。理由：(a) 保 ralph "不污染用户 git 状态"契约；(b) stagnation 只需布尔判断不需事后 inspect；(c) `git ls-files -s` 自带每个文件 blob sha，性能最好。事后"上轮到底改了什么"诉求由独立的 `changed_files_iter` 字段（现算 vs 上轮文件列表）满足，不依赖比对机制。Rejected：A（写 refs 偏重）、C（创建 git 对象即便 GC 也违契约）。
    - `meta.json.changed_files` 字段拆为两个：`changed_files_total`（cumulative since start_sha，保留诊断用）+ `changed_files_iter`（本轮 vs 上轮，新增）；写入路径在 `run.sh:408-413` 改造。
    - `docs/architecture/overview.md` 的 stagnation 判据段补丁更新，明确"本轮 vs 上轮"语义；写明选型方案与原因。
    - `tests/fixtures/mock-claude` 加场景 `partial_progress`：第 1 轮 happy（勾 1 task + 改 1 文件），第 2-N 轮 stagnation（不勾不改）。
  - 实施步骤：
    1. 选型决策（A/B/C）+ 在 `docs/architecture/overview.md` 写明。
    2. 实现 per-iter 比对函数（`common.sh` 或 `run.sh` 内部 helper）。
    3. `run.sh` 主循环改造：维护上轮快照、stagnation 判据切换、meta.json 双字段写入。
    4. mock-claude 加 `partial_progress` 场景。
    5. 集成测试新增 ≥2 用例：(a) `partial_progress` 场景 + `--stagnation-limit=2` → 验证第 1 轮成功 + 第 2/3 轮 stagnation_count 正常累加 + 第 3 轮触发 `exit_reason=stagnated`；(b) 全程 happy → stagnation_count 始终 0、不误触发。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - `bash scripts/integration-test.sh` 全 PASS（含新增 ≥2 用例）。
    - 现有 stagnation 用例（fake `stagnation` 场景）继续 PASS。
    - macOS 实测（PM-0001 约束）。
  - 不做：把 stagnation 阈值默认值改大（保持 5）；引入 stagnation 主动重试（v0.1 仍是终止）；区分 stagnation 类型（agent 卡 vs CLI 沉默）。
  - 参考：`docs/architecture/overview.md` stagnation 段、REQ-013、`run.sh:380-395`、PM-0001（macOS 兼容）、PM-0002（跨任务沉淀）、**PM-0003（本 bug 是 PM-0003 触发证据之一，T6.1 完成后回查 PM-0003 验证修复有效）**。
  - **本任务必须在 T6.4 边界复验之前完成**（否则 T6.4 stagnation 真实用例无法正确设计）。

- [ ] T6.2：`--effort` flag 接入 Claude adapter + SC-014-1 单元测试。
  - 目标：修复 adversarial review 暴露的 P0 缺陷——`adapter-claude.sh` 完全没读 `$RALPH_EFFORT`，REQ-014（P1）+ SC-014-1（"low/medium/high 翻译为 provider 原生参数；none 或留空不传"）+ requirements §integrations Claude 节"`--effort` 翻译为 `--thinking-budget`"在 Claude adapter 中均未实现，effort 被 run.sh 写进 context.json 后丢失。
  - 范围：
    - `.ralph/lib/adapter-claude.sh` `provider_oneshot` 内：
      - 读 `${_RALPH_EFFORT:-}` 或重读 `$RALPH_EFFORT`（确认 run.sh 是否已 export 给 adapter；若未 export 则改 run.sh export `_RALPH_EFFORT`）。
      - 翻译表（与 requirements §integrations Claude 节对齐）：`low → --thinking-budget=2000`、`medium → --thinking-budget=8000`、`high → --thinking-budget=16000`、`none / 空 → 不拼 flag`。具体数值实施时确认 Claude CLI 当前版本的合法范围（参考 `claude --help`），写入注释。
      - flag 拼接位置：现有 `claude -p ... --session-id ... --output-format json` 命令行末尾追加 `${effort_flag:-}`（注意 quoting：用数组而非字符串拼接，避免空 flag 引入空参数）。
    - `docs/architecture/integrations.md` Claude 节补丁：把 effort 翻译表从"应有"改为"已实现"，写入实际数值。
    - 集成测试新增 SC-014-1 covering 用例（mock-claude 配合）：mock-claude 在收到 `--thinking-budget=<N>` 时把该值回显到 stdout JSON 的某个 debug 字段（如 `_received_flags`），测试断言：
      - `RALPH_EFFORT=low` → mock 收到 `--thinking-budget=2000`
      - `RALPH_EFFORT=medium` → mock 收到 `--thinking-budget=8000`
      - `RALPH_EFFORT=high` → mock 收到 `--thinking-budget=16000`
      - `RALPH_EFFORT=none` 或不设 → mock 未收到 `--thinking-budget` flag
  - 实施步骤：
    1. 确认 run.sh effort 是否已 export（`grep "_RALPH_EFFORT" .ralph/lib/run.sh`），未 export 则补一行。
    2. `adapter-claude.sh` 加 effort 翻译 + flag 拼接（数组方式）。
    3. mock-claude 加 `--thinking-budget` flag 解析 + 回显（不影响其他场景）。
    4. 集成测试 ≥4 用例（low/medium/high/none）。
    5. `docs/architecture/integrations.md` 同步实际数值。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - `bash scripts/integration-test.sh` 全 PASS（含新增 ≥4 用例）。
    - macOS 实测。
  - 不做：Codex / Gemini effort 翻译（T3/T4 各自处理）；effort 自动调优；超出 low/medium/high/none 的自定义值。
  - 参考：REQ-014、SC-014-1、`docs/architecture/integrations.md` Claude 节、`docs/architecture/overview.md` effort 抽象段、**PM-0003（本 bug 是 PM-0003 触发证据之一，T6.2 完成后回查 PM-0003 验证修复有效）**。

- [ ] T6.3：3+ 条 task 真实多轮 smoke + 证据保全。
  - 目标：在临时 workspace 用真实 Claude CLI 跑通一个含 ≥3 条独立任务的 TASKS.md，全程 `exit_reason=done`，验证 T6.0 模板有效 + T6.1 stagnation 修正 + T6.2 effort 接入在真实链路下不出回归。
  - 前置：T6.0 / T6.1 / T6.2 必须完成。
  - 范围：
    - smoke workspace（`/tmp/ralph-t6-multi-smoke/`）：
      - `git init` 后单步部署：`cp -r <repo>/.ralph/ /tmp/ralph-t6-multi-smoke/.ralph/`（一次性带走 bin/lib/PROMPT/TASKS）。
      - 在 smoke workspace 内**裁剪** `.ralph/TASKS.md`：替换 T6.0 样板里的 hello-world 任务为 3 条独立小任务（实施时定稿）：(a) 写 `hello.txt` 含 "hello ralph"；(b) 在 `README.md` 加一行 changelog；(c) 写 `notes/architecture.md` 描述假项目结构。每条都要改/写一个文件。
      - 新建 `.ralph/.env`：`RALPH_PROVIDER=claude`、`RALPH_EFFORT=low`（验证 effort 接入）。`.ralph/PROMPT.md` 直接用 T6.0 样板不改。
    - 执行 `.ralph/bin/ralph run` 一次性跑通；不带 `--max-iter` / `--timeout`（让 done 自然触发）。
    - 证据收集：
      - `result.json`：`exit_reason=done`、`iterations` ≥ 3、`last_error=null`。
      - 每个 `iter-NN/meta.json`：`session_id` 非空、`capture_status=ok`、`exit_code=0`、`error=null`、**`changed_files_iter` 仅含本轮变更**（验证 T6.1 修正）、`changed_files_total` 累积变更。
      - 每个 `iter-NN/`：`session.claude.jsonl` 存在、`chat.log` / `tools.log` 非空。
      - smoke 后 workspace 内 3 个目标文件存在且内容合理。
    - **证据保全**（修复 adversarial review P1#4）：
      - smoke 结束**先 copy artifacts 到 `docs/checkpoints/<date>-t6.3-multi-smoke.md` 草稿**（含 result.json 全文 + 每轮 meta.json 关键字段 + run_id + Claude CLI 版本号），再清 /tmp。
      - task.md 完成证据段引用 checkpoint 文件路径，不重复贴全量 JSON。
  - 实施步骤：
    1. 准备临时 workspace（脚本化命令记录在 task.md 完成段，便于复跑）。
    2. 跑 smoke；如失败，定位是模板问题（回 T6.0 修）、内核问题（落 T6.7）、还是 effort/stagnation 修正回归（回 T6.1/T6.2）。
    3. 收集证据 → checkpoint 草稿 → 清理 /tmp。
  - 验证计划：
    - run 完成后 `.ralph/runs/<run_id>/result.json` 满足上述断言（基于 checkpoint 草稿）。
    - macOS 实测（PM-0001 约束）。
    - HOME / PATH / `~/.claude/projects/` 隔离自检通过。
  - 不做：性能基准、并发 run、长链路（>10 task）压测、跨 provider smoke（T3/T4 后再做）。
  - 参考：`docs/architecture/overview.md`、`docs/architecture/integrations.md`、T2.6 单轮 smoke 经验、`docs/checkpoints/README.md`。

- [ ] T6.4：边界场景在真实 Claude 下复验。
  - 目标：T1 fake adapter 验过的兜底逻辑（stagnation / max_iter / timeout）在**真实 Claude 长链路**下重新各触发一次，确认假设仍成立；任一不成立则就地补丁（计入 T6.7）。
  - 前置：T6.1 stagnation 修正必须完成（否则 stagnation 用例设计无法成立）。
  - 范围：
    - **Stagnation 真触发**：构造 TASKS.md 含 2 条任务——第 1 条 happy（agent 能完成），第 2 条**等待型不可完成任务**：`- [ ] 等待用户在 .ralph/.env 加入 RALPH_MAGIC=1，然后继续`。设计要点：agent 没办法自己加这个 env（PROMPT.md 模板禁止 fake-mark `[x]`、PROMPT 也提示不要重构无关配置），最稳定的"agent 卡住不动"路径——比"歧义任务"更可控（歧义任务 agent 可能 commit 澄清文件导致 stagnation 不触发）。验证 `--stagnation-limit=2` 时第 3-4 轮触发 `exit_reason=stagnated`、`result.json.stagnation_rounds` ≥ 2。**此用例依赖 T6.1 修正——cumulative changed_files 时代下永远不触发**。
    - **max_iter 真触发**：用 happy 风格的 5 条 task TASKS.md + `--max-iter=2`；验证第 2 轮后 `exit_reason=max_iterations`，TASKS 仍有未勾选。
    - **timeout 真触发**：构造一条任务要求 agent 在 oneshot 内调用 `Bash sleep 30`（PROMPT.md 模板未禁 sleep，行为确定）+ `--timeout=10`（10 秒）；验证 `exit_reason=timeout`，timeout 路径的 collect/diagnose 已正常落 meta（T2 adversarial review 修过的路径，复验仍生效）。**Rejected 设计**："请生成 5 万字的文档"——Claude 可能拒绝/简化导致 10 秒内返回，timeout 不触发。
    - 每个用例独立临时 workspace；证据按 T6.3 同样规则保全到 `docs/checkpoints/<date>-t6.4-boundaries.md`，task.md 引用文件路径。
  - 实施步骤：
    1. 三个 workspace 各跑一次（顺序执行，避免相互干扰）。
    2. 任一失败 → 定位是任务设计问题还是内核 bug；后者写 T6.7 patch。
    3. 证据汇总 → checkpoint。
  - 验证计划：
    - 三个 `exit_reason` 各触发一次。
    - `.ralph/status.json` 在退出后内容符合（finished + 对应 reason）。
  - 不做：interrupted（SIGINT）/ locked（并发 run）真实验证——T1 fake 已充分；provider_failed 已在 T2.6 通过 mock-claude 全分类验过。
  - 参考：`docs/architecture/overview.md` 退出原因段、T1 fake 集成测试用例、`docs/postmortems/`。

- [ ] T6.5：使用指南 + 模板入口文档 + TASKS 示例。
  - 目标：交付 `docs/usage.md`（或扩 `README.md` quickstart 段，二选一），让一个新使用者照着把 workspace 准备好并跑通首轮；同步把 `.ralph/` 部署单元（含 PROMPT.md / TASKS.md 样板）的 copy 路径写清楚；内嵌一份完整 TASKS.md demo 解释字段语义（修复 adversarial review P1#5）。
  - 范围：
    - 评估归属（实施时一次性决策）：单独 `docs/usage.md` vs 扩 `README.md` quickstart 段。判据：若 quickstart ≤80 行能讲清，并入 README；否则独立文件。
    - 内容大纲（无论归属）：
      - 前置依赖：bash 4+、git、jq、Claude CLI（按 provider 列；版本提示）。
      - 部署：`cp -r <ralph-loop-repo>/.ralph/ <your-workspace>/.ralph/` —— 一次性带走 bin/lib/PROMPT/TASKS 四份。
      - workspace 配置：用户自建 `.ralph/.env`（最小示例 `RALPH_PROVIDER=claude`，可选 `RALPH_EFFORT=low/medium/high/none`、`RALPH_MAX_ITER=N`、`RALPH_TIMEOUT=SEC`、`RALPH_MODEL=<name>`，含默认值说明 `max_iter=0 / timeout=0 / stagnation_limit=5`）；按需裁剪 `.ralph/TASKS.md`（部署带过来的样板含 hello-world 示例 + 顶层 `- [ ]` 解析说明，子 bullet 是给 agent 读的）；按需裁剪 `.ralph/PROMPT.md`（部署带过来的样板已含循环协议骨架）。
      - workspace `.gitignore` 建议：`.ralph/runs/`、`.ralph/lock`、`.ralph/status.json`、`.ralph/.env`（运行期产物 + 私有配置不入用户仓库）。
      - 首跑：`cd <workspace> && ./.ralph/bin/ralph run`，预期产出 `.ralph/runs/<run_id>/`。
      - 证据查看：直接 `cat .ralph/status.json` / `cat .ralph/runs/<run_id>/result.json` / `ls .ralph/runs/<run_id>/iter-*/`（status/watch 子命令未实现，明示 v0.1 用直接读文件）。
      - 退出原因 7 种速查表（与 `--help` 内容一致；引用 `docs/architecture/overview.md` 锚点）。
      - **v0.1 行为提醒**（修复 adversarial review P2#9）：provider_failed 一次失败即终止整 run，不自动重试（v0.1 不实现 retry，未来版本可能加）；transient API 抖动建议 `ralph run` 重启即可（lock 已释放）。
      - 常见问题：依赖缺失、Claude session 找不到走 mtime fallback、stagnation 误判 / 调高 `--stagnation-limit`。
    - `docs/README.md` 同步：加 usage.md 和 templates/PROMPT.md 索引。
  - 实施步骤：
    1. 评估归属决策 + 写主体内容。
    2. 引用 T6.0 模板路径、T6.3 smoke 命令模式（不贴 transcript）。
    3. `docs/README.md` 索引同步。
  - 验证计划：
    - `bash scripts/check.sh` 通过。
    - 找一个空目录按文档照抄一遍能跑到 `exit_reason=done`（用 T6.3 同等任务集 mini 版即可，不必单独 smoke）。
    - 文档体量 ≤200 行（usage.md 单文件）或 quickstart 段 ≤80 行（README 内嵌）。
  - 不做：架构深入解释（架构走 `docs/architecture/`）；provider CLI 安装详解（链到上游官方文档）；多 provider 对照（T3/T4 后扩）。
  - 参考：`docs/architecture/overview.md`、`docs/architecture/integrations.md`、T6.0 模板、T6.3 smoke 步骤、REQ-009（.env 默认值）。

- [ ] T6.6：v0.1 closure（版本号 + checkpoint + handoff）。
  - 目标：T6.0–T6.5 全闭环后做 v0.1 release closure 动作：版本号从 `0.1.0-dev` → `0.1.0`、最终 checkpoint 落仓、handoff 更新到 v0.1 完成态。
  - 前置：T6.0–T6.5 全部 `[x]`。
  - 范围：
    - `.ralph/bin/ralph` 顶部版本常量：`RALPH_VERSION="0.1.0-dev"` → `RALPH_VERSION="0.1.0"`。
    - 集成测试 `ralph --version` 用例断言对应更新（从含 `0.1.0-dev` 改为含 `0.1.0`）。
    - `docs/roadmap.md` Current State 同步：T6 完成、v0.1 release 标记；T3/T4/T5 进入下阶段候选。
    - 最终 checkpoint：`docs/checkpoints/<date>-v0.1-release.md`，引用 T6.3/T6.4 的子 checkpoint，汇总 v0.1 全部能力清单 + 已知限制（含 T6 patch 池吸收的内容）。
    - `handoff.md` 刷新为"v0.1 已发布，等待用户决定 T3（Codex）/ T4（Gemini）/ T5（status/watch）/ T7（skill 封装）方向"。
  - 实施步骤：
    1. 改版本号 + 测试断言。
    2. 全量 `bash scripts/check.sh && bash scripts/integration-test.sh` 验收。
    3. 写最终 checkpoint + 更新 roadmap。
    4. 刷新 handoff。
  - 验证计划：
    - 全量测试 PASS。
    - `ralph --version` 输出 `ralph 0.1.0 (<sha>)`。
    - checkpoint / roadmap / handoff 三方一致。
  - 不做：发版到外部包管理器（v0.1 仅本仓库）；CHANGELOG（信息已在 checkpoint，不重复）；tag/release（用户决策是否打 git tag）。
  - 参考：`docs/checkpoints/README.md`、`docs/roadmap.md`、handoff 协议（`.spec/`）。

- [ ] T6.7：内核 patch 池（按需触发，贯穿 T6.0–T6.6）。
  - 目标：T6 各子任务跑出来的内核 bug / 假设不成立 / 文档偏差，在此项内**就地补丁**修复；不预先扩功能、不引入新设计。adversarial review 已识别的 P0/P1 缺陷已分别独立为 T6.1/T6.2/T6.3/T6.5，**不**重复挂在 T6.7。
  - 范围：
    - 子项命名：`T6.7.<n>:<one-line>` append 到本任务下。
    - 每个子项包含：触发证据（来自哪个 T6 子任务）、根因、最小修复、验证（新增/修改集成测试或人工 smoke）、是否需 postmortem。
    - 跨任务稳定决策（如发现新的 shell 兼容性陷阱）继续按 PM-0002 规则沉淀到 `docs/architecture/*` 或 `.spec/rules/*`。
  - 实施步骤：（按需）
  - 验证计划：每个子项闭环后再勾 `[x]`；T6.7 顶层在所有子项闭环、且 T6.0–T6.6 不再产生新 patch 时勾 `[x]`。
  - 不做：本任务**不**承载 T3/T4/T5 工作；T6 闭环过程中冒出来的 nice-to-have 列入 `docs/roadmap.md` Deferred 或下阶段，不挂在 T6.7。
  - 参考：`docs/postmortems/README.md`、`docs/postmortems/pm-cross-task-decision-sedimentation.md`。
