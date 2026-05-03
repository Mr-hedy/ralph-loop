# I2 设计方案 — T3 Codex Adapter

> 状态：已确认，待实施
> 创建：2026-05-03
> 角色：I2 启动前的设计方案锚点；实施过程如需改变稳定契约，应先更新需求或架构事实源
> 与 `I2-FINAL-TASK.md` 关系：I2 完成时 cp `.ralph/TASKS.md` 归档为 `I2-FINAL-TASK.md`，本文保留为启动前方案

## 背景与目标

- I1（dogfood T5 — Status + Watch 真实功能）已完成并归档为 `docs/requirements/ralph-loop/I1-FINAL-TASK.md`。
- 用户决策（2026-05-03）：I2 执行历史 T3，目标是在已闭环的 Ralph harness 上接入 Codex CLI adapter。
- I2 不重做 run loop、TASKS 协议、status/watch 或 Claude adapter；只在现有 adapter 契约下补齐 Codex provider。

## 范围

- 新增或补齐 `.ralph/lib/adapter-codex.sh`，实现稳定三函数：
  - `provider_oneshot`
  - `provider_collect_session`
  - `provider_diagnose`
- 接入 `RALPH_PROVIDER=codex` 的 provider loading、启动校验、provider metadata 与状态记录。
- 按当前 Codex CLI 行为构造 fresh oneshot 命令，不使用 resume，不使用 ephemeral session。
- 沉淀统一 iter 证据契约：
  - `meta.json`
  - `provider.stdout.log`
  - `session.codex.jsonl`
  - `session.history.log`
- 实现 Codex 配置目录隔离变量翻译。DEV-1 已确认：Codex 原生环境变量为 `CODEX_HOME`（默认 `~/.codex`），adapter 将 `RALPH_PROVIDER_CONFIG_DIR` 翻译为 `CODEX_HOME`。
- 同步 `docs/requirements/ralph-loop/requirements.md` 与 `docs/architecture/integrations.md` 的 Codex 契约，消除 `session.codex.stdout.jsonl` 等旧描述造成的第二事实源（DEV-1 已完成）。
- 为 Codex 配置目录隔离补充专属 SC（SC-022-4 / SC-022-5），并由 I2 自动化测试覆盖；不能用 Claude 专属的 SC-022-2/3 替代 Codex 验收。
- effort 通过 `-c model_reasoning_effort=<value>` 传递（DEV-1 确认：无 `--reasoning-effort` flag）。
- 补充 mock 自动化测试和至少一次真实 Codex provider smoke。

## 非范围

- 不实现 Gemini adapter（T4）。
- 不引入 `ralph init`、全局安装、数据库或复杂 TUI。
- 不改变 `.ralph/TASKS.md` 作为任务完成事实源的判定。
- 不把 provider session 当成完成事实；session 只用于复盘证据。
- 不默认 resume Codex session。

## 关键风险

- ~~`docs/architecture/integrations.md` 的 Codex 小节基线来自 2026-04-20，Codex CLI 可能已变化；实施前必须刷新本机 CLI help 和官方文档证据。~~ DEV-1 已校准（2026-05-03）：版本 0.125.0，确认 `CODEX_HOME` / `model_reasoning_effort` / `--json` stdout 事件格式 / rollout 文件格式。
- ~~当前 Codex 小节仍写有 `session.codex.stdout.jsonl`，与全局 4 文件 iter 契约存在潜在冲突；I2 DEV-1 必须先收敛该契约，再写 runtime。~~ DEV-1 已移除该旧描述。
- 现有 SC-022-2/3 是 Claude 专属；I2 DEV-1 已新增 SC-022-4（Codex 配置目录翻译）/ SC-022-5（Codex session capture 隔离）。
- 真实 Codex smoke 会调用外部 provider，可能把临时 workspace 内容发送到机器外；执行前需要确认 auth/config 与用户允许范围。

## 验收口径

- `bash scripts/check.sh` 通过。
- `bash scripts/integration-test.sh` 通过，且含 Codex adapter 的 mock 覆盖。
- `git diff --check` 通过。
- requirements / integrations 对 Codex iter 文件契约一致，不保留会误导实现的额外持久化文件描述；Codex 配置目录翻译、空值鲁棒性和 session capture 隔离路径有专属 SC 与测试证据。
- 真实 Codex smoke 在临时 workspace 中跑到 `result.json.exit_reason=done`，并确认 iter 目录包含统一 4 文件证据契约。
- 若真实 Codex CLI 不可用或授权不明确，必须通过 `HUMAN-N` 明确阻塞，不允许把 mock 通过包装成 T3 完成。

## 当前任务源

- I2 的可执行任务清单在 `.ralph/TASKS.md`。
- I2 完成后归档为 `docs/requirements/ralph-loop/I2-FINAL-TASK.md`。
