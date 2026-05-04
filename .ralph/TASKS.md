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

- [ ] DEV-1: 校准 Gemini CLI 当前契约并同步需求/架构事实源
  - 预期：I4 后续实现不再依赖旧 Gemini 假设；requirements、integrations、overview/security/testing 对命令、配置目录、session 文件、history source 和 effort 映射只有一个事实源。
  - 输入：`docs/requirements/ralph-loop/I4-design.md`；REQ-004/006/014/022；FR-007；`docs/architecture/integrations.md` Gemini 小节；本机 Gemini CLI 0.39.1 help；官方 Gemini CLI docs。
  - 范围：`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/integrations.md`、`docs/architecture/overview.md`、`docs/architecture/security.md`、`docs/architecture/testing.md`；不写 runtime adapter。
  - 验证计划：记录 `gemini --version` / `gemini --help` 关键输出；对照官方 CLI reference/configuration docs；`rg` 确认旧 `--yolo`/`--thinking-budget`/Gemini session 文件口径无冲突；`git diff --check`；`bash scripts/check.sh`。

- [ ] DEV-2: 实现 `.ralph/lib/adapter-gemini.sh` oneshot 与启动校验
  - 预期：`RALPH_PROVIDER=gemini` 能通过 provider loading 和 dependency check，按 DEV-1 校准后的 Gemini CLI 命令执行 fresh oneshot，并把 stdout/stderr 合流写入 `provider.stdout.log`。
  - 输入：DEV-1 Gemini 契约；adapter 三函数契约；Claude/Codex adapter 现有模式；REQ-004/005/014/015。
  - 范围：新增 `.ralph/lib/adapter-gemini.sh`；必要时最小更新 `.ralph/bin/ralph` help/provider choices；新增 `tests/fixtures/mock-gemini` 的最小 command-recording 场景用于本任务验证；不改 Claude/Codex 行为。
  - 验证计划：`bash -n .ralph/lib/adapter-gemini.sh .ralph/bin/ralph tests/fixtures/mock-gemini`；mock Gemini dependency check；mock 命令记录断言 model/effort/config-dir 空值鲁棒性和 approval/sandbox/output-format 参数。

- [ ] DEV-3: 实现 Gemini session capture 与 `session.history.log` 派生
  - 预期：Gemini iter 目录产出明确的 native session 副本和跨 provider 人话视图；session capture 缺失时降级为 warning，不中断 run。
  - 输入：DEV-1 session 文件契约；REQ-006/022；`provider_collect_session` 契约；Claude/Codex history 派生实现。
  - 范围：`.ralph/lib/adapter-gemini.sh` 的 `provider_collect_session` 和 Gemini history helper；扩展 DEV-2 的 `tests/fixtures/mock-gemini` session store 场景；必要的 `meta.json` 字段写入；不把 provider session 当任务完成事实。
  - 验证计划：mock Gemini session store 精确匹配 / mtime fallback / missing session 三类测试；断言 `capture_status`、`session_source_path`、native session 副本、非空或合理空的 `session.history.log`。

- [ ] DEV-4: 实现 Gemini 错误诊断与 `run -v` 可读事件输出
  - 预期：Gemini provider failure 能写入统一 `last_error.type/message`；`ralph run -v --provider gemini` 有可读 marker，不把 JSON/text 原始流直接刷成噪音。
  - 输入：DEV-1 output-format 与错误事件契约；FR-008；现有 `_ralph_filter_verbose` 的 Claude/Codex 分支。
  - 范围：`.ralph/lib/adapter-gemini.sh` 的 `provider_diagnose`；`.ralph/lib/run.sh` 的 verbose filter Gemini 分支；mock fixture 错误场景。
  - 验证计划：mock auth/rate_limit/quota/network/api/unknown 场景；`run -v` stderr grep Gemini marker；`result.json.last_error` 与 `meta.json.error` 分类一致。

- [ ] QA-1: 补齐 Gemini mock 集成测试矩阵
  - 预期：Gemini adapter 的主要路径可在无真实 Gemini 调用下稳定回归，且不会把 mock 通过误当真实 T4 完成。
  - 输入：DEV-2/3/4；`scripts/integration-test.sh` 现有 Claude/Codex adapter 测试结构；`tests/fixtures/mock-codex` 模式。
  - 范围：扩展 DEV-2/3/4 已建立的 `tests/fixtures/mock-gemini`；更新 `scripts/integration-test.sh`；更新 `docs/architecture/testing.md` 覆盖矩阵。
  - 验证计划：`bash scripts/integration-test.sh` 通过；新增用例覆盖 happy path、config-dir 或明确不翻译的空值鲁棒性、model/effort 参数、session capture、history、diagnose、dependency missing、`run -v` marker。

- [ ] REVIEW-1: Gemini mock 实现后 adversarial-review
  - 预期：在真实 provider smoke 前发现契约漂移、测试假阳性、docs 第二事实源、session 文件泄漏和安全边界问题。
  - 输入：DEV-1 ~ QA-1 的 diff；requirements/integrations/overview/testing/security；PM-0003 观察面和 mock 假设预防规则。
  - 范围：只产出 review findings 或直接修复低风险文档/测试错漏；不执行真实 Gemini smoke。
  - 验证计划：列出 P0/P1/P2 findings；若修复则重跑 `git diff --check`、`bash scripts/check.sh`、相关 integration tests；无发现时明确 remaining risk。

- [ ] HUMAN-1: 确认是否允许真实 Gemini smoke 使用本机 auth/config
  - 上下文：QA-2 需要调用真实 Gemini CLI，可能把临时 workspace 的 prompt、文件内容和工具输出发送到外部 provider。
  - 选项：
    - 选项 A：允许使用最小临时 workspace 和本机 Gemini 登录态跑真实 smoke；I4 可按 SC-004-1 完成真实验收。
    - 选项 B：暂不允许真实 Gemini 调用；I4 保持 mock 完成但不能标记 T4 真实 provider 完成。
  - 影响：决定 QA-2 是否执行，以及 I4 是否能满足 REQ-004 / SC-004-1 的真实 Gemini 验收。
  - 答（待）：

- [ ] QA-2: 真实 Gemini provider smoke
  - 预期：真实 `RALPH_PROVIDER=gemini` 在无敏感临时 workspace 中跑到 `exit_reason=done`，并产出 Gemini iter 证据契约。
  - 输入：HUMAN-1 允许后执行；DEV-1 ~ REVIEW-1 已完成；本机 Gemini CLI 0.39.1 与 auth/config 可用。
  - 范围：临时 workspace；真实 Gemini CLI；运行证据只记录 run_id、exit_reason、文件存在性和关键字段，不提交 `.ralph/runs/` 或 provider 原始 session。
  - 验证计划：`ralph run --provider gemini --max-iter ...` 跑到 `done`；检查 `result.json`、`meta.json`、`provider.stdout.log`、Gemini native session 副本、`session.history.log`；记录未验证范围和失败诊断。

- [ ] DEV-5: 同步 Gemini 用户入口文档与部署单元 README
  - 预期：用户能按 README/`.ralph/README.md` 正确配置 `RALPH_PROVIDER=gemini`，理解 Gemini 的配置目录、approval/sandbox、session capture 和已知限制。
  - 输入：DEV-1 校准结果；QA-2 真实 smoke 证据或阻塞结论；requirements/overview/integrations/security/testing。
  - 范围：`README.md`、`.ralph/README.md`、`docs/README.md`、`docs/roadmap.md`、必要的 requirements/architecture docs；不改 runtime。
  - 验证计划：`rg` 检查 Gemini 仍被写成 T4 planned 的旧入口是否只出现在历史语境；`git diff --check`；`bash scripts/check.sh`。

- [ ] REVIEW-2: I4 最终 adversarial-review 与归档准备
  - 预期：I4 在归档前没有未处理的 P0/P1 事实源漂移、测试假阳性、真实 smoke 证据缺口或用户入口误导。
  - 输入：DEV-1 ~ DEV-5、QA-1/2、HUMAN-1 答案、docs 和测试结果。
  - 范围：代码、测试、requirements、architecture、README、roadmap、`.ralph/TASKS.md`；不新增功能。
  - 验证计划：adversarial-review findings 清零或转为明确后续任务；`bash scripts/check.sh`；`bash scripts/integration-test.sh`；`git diff --check`；必要时准备 `docs/requirements/ralph-loop/I4-FINAL-TASK.md` 归档建议。
