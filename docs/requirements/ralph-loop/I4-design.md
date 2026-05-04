# I4 设计方案 — T4 Gemini Adapter

> 状态：已确认，待实施
> 创建：2026-05-04
> 角色：I4 启动前的设计方案锚点；实施过程如需改变稳定契约，应先更新需求或架构事实源
> 与 `I4-FINAL-TASK.md` 关系：I4 完成时 cp `.ralph/TASKS.md` 归档为 `I4-FINAL-TASK.md`，本文保留为启动前方案

## 背景与目标

- I3（watch/status 观察面修复）已完成并归档为 `docs/requirements/ralph-loop/I3-FINAL-TASK.md`。
- 用户决策（2026-05-04）：下一轮规划历史 T4，目标是在已闭环的 Ralph harness 上接入 Gemini CLI adapter。
- I4 不重做 run loop、TASKS 协议、status/watch、Claude adapter 或 Codex adapter；只在现有 adapter 契约下补齐 Gemini provider。

## 当前证据

- 本机 Gemini CLI 可用：`gemini --version` 输出 `0.39.1`。
- 本机 `gemini --help` 显示 `-p/--prompt`、`--model`、`--sandbox`、`--approval-mode default|auto_edit|yolo|plan`、`--yolo`、`--resume`、`--list-sessions`、`-o/--output-format text|json|stream-json`。
- 官方 `google-gemini/gemini-cli` CLI reference 当前说明 `--output-format` 支持 `text` / `json` / `stream-json`，并标注 `--yolo` deprecated，推荐 `--approval-mode=yolo`：https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md
- 官方 configuration 文档说明 command-line arguments 优先级最高，并记录 non-interactive `--prompt`、`--output-format`、`--resume`、`--sandbox` 等行为：https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/configuration.md

## 范围

- 新增 `.ralph/lib/adapter-gemini.sh`，实现稳定三函数：
  - `provider_oneshot`
  - `provider_collect_session`
  - `provider_diagnose`
- 接入 `RALPH_PROVIDER=gemini` 的 provider loading、启动校验、provider metadata 与状态记录。
- 按当前 Gemini CLI 行为构造 fresh oneshot 命令，不使用 resume，不复用历史 session。
- 收敛 Gemini iter 证据契约，至少包含：
  - `meta.json`
  - `provider.stdout.log`
  - Gemini native session 副本（文件扩展名由 DEV-1 校准：当前 docs 存在 `session.gemini.json` vs `session.<provider>.jsonl` 口径差异）
  - `session.history.log`
- 明确 `RALPH_PROVIDER_CONFIG_DIR` 对 Gemini 是否翻译为 `GEMINI_CLI_HOME` 或其他原生变量；若默认不翻译，必须同步 REQ-022 和 integrations，避免第二事实源。
- 明确 effort 抽象到 Gemini 的真实映射。当前 `gemini --help` 未显示 `--thinking-budget` flag；DEV-1 必须校准是 CLI flag、settings override、环境变量，还是 I4 暂不支持 effort 传递。
- 补充 mock 自动化测试和至少一次真实 Gemini provider smoke。

## 非范围

- 不实现 `ralph init`、全局安装、数据库或复杂 TUI。
- 不改变 `.ralph/TASKS.md` 作为任务完成事实源的判定。
- 不把 provider session 当成完成事实；session 只用于复盘证据。
- 不默认 resume Gemini session。
- 不改 Claude / Codex 已稳定行为，除非 DEV-1 发现共享 adapter 契约必须调整，并先通过 REVIEW/HUMAN 明确。

## 关键风险

- Gemini CLI 当前版本与仓库旧基线不完全一致：`--yolo` 已被官方 CLI reference 标记为 deprecated；I4 不能直接按旧 FR-007 的 `gemini -p <prompt> --yolo` 实施。
- Gemini session 文件路径和文件格式历史上不稳定；`docs/architecture/integrations.md` 已提示不应自行计算 `<project_hash>`，但仍需要用本机 0.39.1 校准真实 session store。
- `--output-format stream-json` 支持存在，但事件 schema、session id 是否出现在 stdout、错误事件形态尚未在本仓库验证。
- 真实 Gemini smoke 会调用外部 provider，可能把临时 workspace 内容发送到机器外；执行前必须有人类确认使用本机 auth/config 和最小无敏感 workspace。

## 验收口径

- `bash scripts/check.sh` 通过。
- `bash scripts/integration-test.sh` 通过，且含 Gemini adapter 的 mock 覆盖。
- `git diff --check` 通过。
- requirements / integrations / overview / README 对 Gemini 命令、配置目录隔离、session 文件契约、history source、错误诊断口径一致。
- mock 测试覆盖 model/effort/config-dir 空值鲁棒性、session capture、history 派生、错误诊断、dependency check。
- 真实 Gemini smoke 在临时 workspace 中跑到 `result.json.exit_reason=done`，并确认 iter 目录包含 Gemini 证据契约与非空 `session.history.log`。
- 若真实 Gemini CLI 授权、网络、配置目录或用户批准受阻，必须通过 `HUMAN-N` 明确阻塞，不允许把 mock 通过包装成 T4 完成。

## 当前任务源

- I4 的可执行任务清单在 `.ralph/TASKS.md`。
- I4 完成后归档为 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`。
