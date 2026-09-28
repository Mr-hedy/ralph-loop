# 当前目标与约束

- 目标：按最新版 `.spec/` 整理现行项目文档、协作契约与生成包的一致性，统一整个项目的版本。
- 用户边界：用户决定何时建立任务清单、派发 Ralph，以及何时要求 Main Agent 按指定范围验收；Ralph oneshot 可根据执行现场追加任务并按验证结果勾选。验收发现返工先与用户沟通，再追加任务。
- 本轮不实施 Hook、Skills、后台托管或自动验收；用户明确要求 `.ralph/TASKS.md` 完全不变，包括其中的旧文档路径。被忽略的本地 `.ralph/runs/`、`status.json`、真实 `.env` 暂保留，发布包不得包含这些运行数据。

# 当前阶段与范围

- 阶段：现行事实源与 release v0.1.3 一致性整理及整体 adversarial review 已完成，准备整体提交。
- 影响：`.spec/` Review/TASKS 指导、`.ralph/PROMPT.md` 与 README、Ralph 退出提示、根入口、`docs/` 现行需求/架构位置、`scripts/build-release.sh`、`scripts/check.sh`、集成测试版本断言及 `release/0.1.3/`。
- 变更类型：文档迁移、协作契约澄清、版本与生成包、静态检查、测试维护和退出提示文字；不改变 Ralph 主循环与 provider adapter 的执行逻辑。

# 稳定决策

- `.spec/rules/TASKS.md` 指导任务写作，不决定清单创建、派发或勾选时机；当前 dogfood 工作包的既有记录不批量改写。
- Ralph `done` 只表示执行终态。Main Agent 对整轮产物的验收由用户提出诉求后按约定范围启动；局部 Review 不声明整个工作包通过。
- 现行文档使用 `docs/features/<feature>/requirements.md`、`docs/features/vibecoding-collaboration/solution.md` 及 `docs/` 根级 architecture/security/integrations/testing；Ralph I1–I5 历史文件位于 `docs/features/ralph-loop/history/`，旧 `docs/requirements/`、`docs/architecture/` 和 `docs/collaboration/` 目录已移除。
- 项目与 Ralph CLI、release 使用同一版本 `0.1.3`；`release/0.1.1` 和 `release/0.1.2` 作为历史产物保留，`release/0.1.3` 仅从源文件生成。

# 已完成工作

- 更新 `.spec/README.md`、`.spec/rules/REVIEW.md`、`.spec/rules/TASKS.md`，区分自身交付物质量检查与用户触发的 Ralph 产物验收。
- 同步 `docs/features/vibecoding-collaboration/requirements.md`、`solution.md`、`docs/requirements.md` 和 `docs/architecture.md` 的触发、范围与返工契约。
- 迁移现行 Ralph 需求与协作需求到 `docs/features/`，迁移项目级架构、集成、安全、测试到 `docs/` 根级；Ralph I<N> 设计和归档原文移入 `docs/features/ralph-loop/history/`，`docs/README.md` 已更新。旧目录导航页已移除，历史快照仍保留原文。
- 将早期 `docs/collaboration/rules/TASK.md` 原文移到 `docs/research/task-protocol-legacy-2026-04.md`；旧路径已移除。
- 源码版本改为 `0.1.3`；构建脚本从源码读取版本、拒绝覆盖已有 release，先在临时目录生成后移入正式路径，并支持 `--verify` 完整重建比对；输出 `.env.example`。`scripts/check.sh` 校验目录布局、完整发布包、软链与运行数据排除。
- `release/0.1.3/` 已由 `bash scripts/build-release.sh` 生成；Hook 与 Skills 未入包；`.ralph/TASKS.md` 未改变。
- 审查发现 `scripts/check.sh` 中独立 `! grep` 断言在 `set -e` 下没有形成失败门，已修正并新增 PM-0007 与脚本自检。
- 用户要求的 adversarial review 发现旧事实、发布包必读路径缺失和旧目录策略不一致；已修正现行需求/架构/使用入口、移除旧导航目录，发布版对未入包项目文档作条件说明；PM-0008 记录根因与预防检查。`.spec` Review/Adversarial Review 的返工输出规则已补齐用户决定边界。
- 整体复审又清理了随包分发的 TASKS 规则里开发仓库专用的历史记录和检查命令，修正 README 的本地 CLI 调用示例；`.spec` 中验证与方案记录仅在已有对应任务时写入任务源，归档仅由用户触发。构建脚本不再因本地存在 `.codex/` 就提前将未实施 Hook 配置带入包；发布校验检查 CLI 可执行权限。PM-0008 已补充这一轮同类遗漏。

# 最新验证

- `./.ralph/bin/ralph --version`：通过，输出 `ralph 0.1.3 (9618f88)`；commit 部分是执行时 HEAD。
- `bash scripts/check.sh`：通过，输出 `ralph-loop check passed`。
- `env -u RALPH_WORKSPACE -u RALPH_PROVIDER -u RALPH_LOOP_MAX_ROUND -u RALPH_LOOP_MAX_RETRY -u RALPH_LOOP_STALL_LIMIT -u RALPH_LOOP_ROUND_TIMEOUT bash scripts/integration-test.sh`：第一次 `PASS=155 FAIL=1`，唯一失败为写死 `0.1.1` 的版本断言；修正后的最新完整复跑为 `PASS=156 FAIL=0`，已覆盖历史文档迁移与 Ralph 退出提示修改。
- 活跃文档本地 Markdown 链接检查：31 个文件，0 个缺失；`git diff --check` 与 `git diff --cached --check`：通过；新 `REVIEW-N: [blocked-by ...]` 标题被现有前缀校验接受。
- 再次调用 `bash scripts/build-release.sh`：按设计拒绝覆盖现有 `release/0.1.3`，exit 1；包内无 `.ralph/runs/`、`status.json`、`lock`、真实 `.env`、`.codex/` 或 `.agents/`。
- `bash scripts/build-release.sh --verify`：通过，完整文件树与生成内容一致且 CLI 可执行；把 `release/0.1.3/` 复制到临时 Git workspace 后，`ralph --version` 与 fake 单任务 `done` smoke 通过，退出提示明确区分执行结束和用户验收。

# 已验证与未验证

- 已验证：现行源文件和生成包完整一致、版本一致、模板无顶层任务、软链和 CLI 入口、临时部署 fake smoke、完整 mock 集成回归；本仓库 `.ralph/TASKS.md` 无 diff。
- 未验证：真实 Claude/Codex provider smoke；将发布包复制到另一个新 workspace 的完整人机协作演练；Hook 与 Skills 实现不在本轮范围。历史归档、checkpoint 和 `.ralph/TASKS.md` 内的旧路径按原文保留，不再保证直接解析，需通过 `docs/README.md` 的现行地图查找。

# Checkpoint 与 Postmortem 状态

- Checkpoint：无，本轮未创建稳定锚点。
- Postmortem：已读 `docs/postmortems/README.md`；新增 PM-0007（`pm-negated-grep-check-bypass.md`）与 PM-0008（`pm-release-consistency-sampled-checks.md`），分别记录静态检查假通过、抽样发布校验遗漏旧事实及其预防门。版本测试硬编码失败已由动态断言修复，未达到独立 postmortem 阈值。

# 工作区状态

- 分支：`main`；本次整理前的基线提交：`9618f88 release: build 0.1.2 and tighten spec checks`。
- 本次改动包含现行 docs 迁移、Ralph 历史归档迁移、源文件修改、`release/0.1.3/` 新生成包及本 handoff，整体提交交付。被忽略的本地运行记录仍保留。

# 建议下一步

- 后续由用户决定何时启动新任务清单或 Ralph；若要求清理被忽略的本地运行记录，先确认具体保留范围。

# 交接摘要

- 当前权威版本和部署包为 `0.1.3`；Ralph 完成不自动触发 Main Agent 整轮验收，用户决定验收时机与范围；旧项目文档目录已移除，历史快照与本仓库 TASKS 内旧路径按原文保留。
