# Security

- 状态：已确认
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-005 / REQ-010 / NFR-SEC-001 / NFR-SEC-002 / NFR-SEC-003 / TC-STK-003）、`docs/requirements.md`（跨模块约束）、[`overview.md`](./overview.md)、[`integrations.md`](./integrations.md)。
- 范围：本文定义 Ralph harness 的安全边界：workspace 信任域、approval/sandbox 固定策略、`.ralph/.env` 解析约束、session/日志敏感信息处置、仓库边界与 secrets 禁入规则。不覆盖 provider CLI 自身的密钥管理（登录、API key 轮换），也不覆盖使用者 workspace 的代码安全审查流程。
- 变更条件：NFR-SEC-* 条目增删；新增 provider；增加 policy/白名单开关（会把"approval 写死"从稳定契约变为可配置）；支持跨 workspace 的 worker/daemon 模式。

## 信任域

- Ralph 运行前必须满足"workspace 根由脚本路径决定"（REQ-010 / TC-STK-004）。所有副作用（写文件、运行命令）预期限定在 workspace（含 worktree）内。
- 若使用者把 `.ralph/bin/` 安装到仓库根、用户主目录或容器根目录，则 approval 绕过带来的风险由使用者承担；Ralph 工具本身不检测也不拒绝此类部署。
- Ralph 不以 root 运行，不提权，不安装系统服务。per-workspace 部署意味着每个 workspace 自带工具副本，不共享全局状态。

## Approval / Sandbox 固定策略

Ralph 是无人值守的 oneshot harness，每轮都必须跑到 provider 自然退出，不允许弹出交互式 approval prompt。各 provider 的默认策略：

| provider | 绕过 approval 的 flag | 额外约束 |
|---|---|---|
| Claude | `--dangerously-skip-permissions` + `--allowedTools "Bash,Read,Edit,Write,Glob,Grep"` | 白名单固定，不做开关 |
| Codex  | `codex exec` + `--sandbox workspace-write`（等价 `--full-auto`） | 保留 Codex 自带 sandbox；禁止升级到 `danger-full-access` |
| Gemini | `--yolo`（等价 `--approval-mode=yolo`） | `yolo` 会跳过所有工具确认 |

稳定契约（NFR-SEC-002）：

- approval/sandbox 策略写死在 `adapter-<provider>.sh` 内，不通过 CLI flag、环境变量或 `.env` 开放。
- **不存在** `--approval` / `--sandbox` / `--allowedTools`（overview.md CLI 段已声明为非目标）。
- Claude 白名单取值固定 `Bash,Read,Edit,Write,Glob,Grep`，不随 `.env` 变化。
- 如未来需要 policy file 或 CI 白名单，必须通过独立需求驱动（新增 REQ/NFR），不由 session capture 或其他功能需求间接触发。

风险承担：这三种模式都会让 provider agent 直接执行本地工具。使用者在编写 `.ralph/PROMPT.md` 时对 agent 可执行的行为负责。

## `.ralph/.env` 解析约束

TC-STK-003 固定的加载规则：

- 路径写死 `.ralph/.env`；不接受 `--env-file`、`RALPH_ENV_FILE` 等覆盖入口。
- 只 export 以 `RALPH_` 开头的 key；非 `RALPH_*` 的行忽略。
- 注释 `#` 和空行忽略。
- 禁止 `source .env` 或任何等价的 shell 执行；必须逐行解析 `KEY=VALUE`，以避免 `.env` 变成任意代码执行点。
- 值两端的引号（单/双）被剥离，内部不做变量展开、不做命令替换。

这一约束来自 NFR-SEC-001：`.env` 是用户可编辑配置，不是受信代码。

## Secrets 与敏感信息

NFR-SEC-003 的禁入规则（本仓库和 `.ralph/` 部署包均适用）：

- `.ralph/.env`、使用者 API key、provider 登录态、完整凭据：**不入仓**。
- provider 原生 session 文件（`~/.claude/projects/`、`~/.codex/sessions/`、`~/.gemini/tmp/`）通常包含完整 prompts、tool outputs、命令结果，可能带敏感信息：默认**不入仓**。
- `.ralph/runs/` 及其下的 `log`、`session.*`、`chat.log`、`tools.log`、`meta.json`、`result.json` 是本地复盘材料，**默认不入仓**；使用者应在 `.ralph/.gitignore` 忽略 `runs/`、`status.json`、`lock`。
- `docs/`、`handoff.md`、`checkpoints/`、`postmortems/`、`task.md` 不得写入 secrets、完整凭据或会话 transcript；协作文档只承载结构性事实。

Ralph 工具本身不对 session 文件做脱敏，因为 provider 的 transcript 结构是 provider 内部实现，任何脱敏都可能误伤。使用者在分享 run 目录前自行审查。

## 攻击面与缓解

| 面 | 风险 | 缓解 |
|---|---|---|
| `.ralph/.env` | 注入 shell 代码 | 逐行解析 + `RALPH_` 前缀白名单（TC-STK-003） |
| `.ralph/PROMPT.md` | 恶意 prompt 驱动 agent 做越权操作 | workspace 信任域 + provider sandbox（Codex `workspace-write`） |
| provider CLI | 升级改变 flag 或 session 路径 | adapter 版本锚点 + session 采集降级为 warning（REQ-006） |
| session 文件泄露 | 提交到公共仓库 | `.ralph/.gitignore` 建议 + 本条文档显式声明不入仓 |
| 并发破坏 | 多个 `ralph run` 同时写 `runs/` | `flock` 独占 `.ralph/lock`，冲突快速退出 `locked`（REQ-012） |
| UUID 碰撞 / 预测 | 影响 Claude session 锚点 | 使用系统 `uuidgen` / `/proc/sys/kernel/random/uuid` / `python3 uuid4`，不自制随机（见 [`integrations.md#uuid-依赖`](./integrations.md#uuid-依赖)） |

## 审计与可追溯

- `context.json` 记录 `provider`、`provider_version`、`start_sha`、`env_source`，用于复盘时还原"哪一版工具、哪一个 provider 版本、对哪一个 commit、用了哪些配置来源"。
- `result.json` 记录 `exit_reason`、`iterations`、`last_error`，作为 run 级审计条目。
- `iter-xxx/meta.json` 记录单轮的 `session_id`、`session_source_path`、`session_copied_path`、`capture_status`、`capture_warning`、`error`、`changed_files`，用于追溯单轮行为。

这些字段不是合规级审计，不用做不可篡改存储；Ralph v0.1 的定位是 harness，不是合规工具。

## 非目标

- 不实现 policy 引擎、RBAC、角色分离。
- 不实现 secrets 管理（不替代 `pass` / `1Password` / `doppler` 等）。
- 不在 adapter 之外提供 approval 降级开关。
- 不做 session 文件自动脱敏或加密存储。
- 不检测使用者 workspace 的代码供应链风险（依赖扫描、SCA）。
