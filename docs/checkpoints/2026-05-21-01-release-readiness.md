# 目标与约束

- 保留 v0.1.1 release candidate 收口后的稳定状态。
- 本 checkpoint 覆盖 release cleanup、真实 provider smoke 修复、`.ralph/README.md` 新手文档、skills 沉淀、postmortem、handoff 刷新。
- 约束：发布单元仍是 `.ralph/` 整个目录；Gemini 真实 full smoke 因本机 auth 缺失阻塞，不能宣称三 provider 全部真实通过。

# 范围

- `.ralph/` runtime：iteration runtime 字段清理、Codex/Gemini adapter 参数、plain heartbeat cleanup、CLI help、部署 README、TASKS 样例。
- 测试：`scripts/integration-test.sh`、`tests/fixtures/mock-gemini`、QA5 expect 文本。
- 文档：`README.md`、`docs/README.md`、`docs/architecture/*`、`docs/requirements/ralph-loop/requirements.md`、`docs/roadmap.md`、`.spec/rules/*` 中与 runtime round/release cleanup 相关内容。
- workflow：`.agents/skills/checkpoint` / `postmortem` / `ralph`，以及本次 `handoff.md`。
- postmortem：PM-0004 新增，PM-0003 更新。

# 核心变更

- Runtime 不再解析或输出 iteration 元数据；运行态统一使用 `round` / `rounds`。
- 删除 `parse_current_iteration()`，并在集成测试中断言 legacy 当前迭代声明不会进入 status/result。
- Codex adapter 改为 `--sandbox danger-full-access`，满足每轮 `git add -A && git commit` 的 `.git/` 写入要求。
- Gemini adapter 增加 `--skip-trust`，避免新 workspace trust 降级 yolo approval。
- Gemini/Codex 事件区输出回归：Gemini assistant delta、tool/result marker 在 `run -v` / `watch` 均可见。
- Plain heartbeat 增加子进程清理 trap，修复 fast plain run 后 `sleep` 短暂残留的问题。
- `.ralph/README.md` 重写为手把手新手手册，覆盖所有命令、参数、示例、provider auth、`.env`、TASKS、退出原因、日志、常见问题和安全边界。
- Skills 更新后，release/provider adapter 收口必须明确真实 smoke 状态，不能用 mock pass 代替 release-ready。

# 影响文件或模块

- `.ralph/bin/ralph`
- `.ralph/lib/run.sh`
- `.ralph/lib/tasks.sh`
- `.ralph/lib/status.sh`
- `.ralph/lib/watch.sh`
- `.ralph/lib/adapter-codex.sh`
- `.ralph/lib/adapter-gemini.sh`
- `.ralph/lib/adapter-fake.sh`
- `.ralph/PROMPT.md`
- `.ralph/README.md`
- `.ralph/TASKS.md`
- `scripts/integration-test.sh`
- `tests/fixtures/mock-gemini`
- `.agents/skills/checkpoint/*`
- `.agents/skills/postmortem/SKILL.md`
- `.agents/skills/ralph/SKILL.md`
- `docs/postmortems/README.md`
- `docs/postmortems/pm-real-provider-smoke-permission-gap.md`
- `docs/postmortems/pm-task-closure-req-traceability.md`
- `handoff.md`

# 稳定决策

- Runtime round 契约是发布态事实：不得重新引入 `iteration` / `iterations` / `iteration_name` 作为 status/result/exit-message 字段。
- Project 文档中的 `I<N>` 仅是开发归档编号，不属于 `.ralph/` 发布单元 runtime 合约。
- Codex 真实 provider 集成需要 `danger-full-access`；这是 ralph 每轮 commit 契约的结果，不是可随意降级的 UX 选择。
- Gemini 新 workspace 需要 `--skip-trust` 保持 `--approval-mode yolo`。
- Release readiness 必须区分：自动化 mock 通过、真实 provider 通过、真实 provider 被本机 auth 阻塞。

# 验证结果

- 命令：`bash -n .ralph/bin/ralph .ralph/lib/*.sh scripts/integration-test.sh tests/*.exp`
- 结果：通过
- 诊断：所有 shell/expect 脚本语法 OK。
- 真实 smoke：不适用；静态语法检查。

- 命令：`git diff --check`
- 结果：通过
- 诊断：无 whitespace error。
- 真实 smoke：不适用。

- 命令：`bash scripts/check.sh`
- 结果：通过
- 诊断：输出 `ralph-loop check passed`。
- 真实 smoke：不适用。

- 命令：`bash scripts/integration-test.sh`
- 结果：通过
- 诊断：`PASS=150 FAIL=0`；覆盖 runtime exit reasons、round 命名、status/watch、plain/sticky UX、provider mock adapters、Gemini assistant delta、heartbeat cleanup。
- 真实 smoke：mock/fake/fixture 自动化，不替代真实 provider release smoke。

- 命令：真实 Claude smoke
- 结果：通过
- 诊断：临时 workspace run_id `20260520-035742-071467e`，`exit_reason=done`，1/1 task，目标文件和任务勾选 OK，commits=2，`capture_status=ok`。
- 真实 smoke：Claude -> 通过。

- 命令：真实 Codex smoke
- 结果：通过（修复后）
- 诊断：首次 `workspace-write` 因 `.git/index.lock` 权限失败；改为 `danger-full-access` 后 run_id `20260520-040808-326dbfc`，`exit_reason=done`，1/1 task，目标文件和任务勾选 OK，commits=2，`capture_status=ok`。
- 真实 smoke：Codex -> 通过。

- 命令：真实 Gemini smoke
- 结果：阻塞
- 诊断：本机缺少 Gemini auth；无 `~/.gemini/settings.json`，且未设置 `GEMINI_API_KEY` / `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA`。加 `--skip-trust` 后仅剩 auth error，无 trust downgrade 警告。
- 真实 smoke：Gemini -> 阻塞（local auth missing）。

- 命令：`ps aux | rg 'ralph|integration-test|mock-claude|mock-codex|mock-gemini|claude|codex|gemini|sleep 17|sleep 60'`
- 结果：通过
- 诊断：未见 ralph/integration-test/mock provider/heartbeat sleep 残留；仅有常驻 Codex app server、Claude native host、VS Code。
- 真实 smoke：不适用。

# Postmortem Sweep

- 结果：已新增 + 已更新
- 关联：
  - `docs/postmortems/pm-real-provider-smoke-permission-gap.md`
  - `docs/postmortems/pm-task-closure-req-traceability.md`
- 说明：真实 provider smoke 暴露 mock 无法覆盖的 Codex sandbox 权限和 Gemini trust 行为，已新增 PM-0004；完整集成时观察到 heartbeat orphan sleep，归入 PM-0003 并新增回归测试。相关规则已提炼到 skills 和测试。

# 未验证范围与风险

- Gemini 真实 full smoke 未通过，原因是本机 auth 缺失；配置 auth 后需要重新跑真实 Gemini smoke。
- 工作树中仍存在大量历史 mode-only dirty 状态；本 checkpoint 提交应避免引入无关 mode-only 噪音，但后续审查仍可能被这些工作树权限位变化干扰。
- `.ralph/` 从已运行开发工作区复制时可能带上 ignored runtime artifacts；README 已写明复制后检查/移走。

# 下一步

- 配置 Gemini CLI auth 后，重新执行 Gemini 真实 smoke 并更新 release 结论。
- 若准备正式发布 tag，先决定是否清理工作树 mode-only 噪音，避免 release diff 审查被权限位污染。
