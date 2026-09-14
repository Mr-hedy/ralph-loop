# Security

- 状态：已确认
- 来源：`docs/requirements/ralph-loop/requirements.md`（REQ-005 / REQ-010 / NFR-SEC-001 / NFR-SEC-002 / NFR-SEC-003 / TC-STK-003）、`docs/requirements.md`（跨模块约束）、[`overview.md`](./overview.md)、[`integrations.md`](./integrations.md)。
- 范围：本文定义 Ralph harness 的安全边界：workspace 信任域、approval/sandbox 固定策略、`.ralph/.env` 解析约束、session/日志敏感信息处置、仓库边界与 secrets 禁入规则。不覆盖 provider CLI 自身的密钥管理（登录、API key 轮换），也不覆盖使用者 workspace 的代码安全审查流程。
- 变更条件：NFR-SEC-* 条目增删；新增 provider；增加 policy/白名单开关（会把"approval 写死"从稳定契约变为可配置）；支持跨 workspace 的 worker/daemon 模式。

## 信任域

- Ralph 运行前必须满足"workspace 根由脚本路径决定"（REQ-010 / TC-STK-004）。Ralph 自身产生的副作用（写 `runs/`、`status.json`、`lock`、调用 provider CLI）限定在 workspace（含 worktree）内。
- **provider agent 侧的副作用不在此边界内**：Codex 使用 `--sandbox danger-full-access`（见下节），其模型生成的 shell 命令不以 workspace 为界。Ralph 外层固定的是"哪个 workspace、哪份任务清单、写到哪个 run 目录"，不是 provider agent 的文件系统可达范围。
- 若使用者把 `.ralph/bin/` 安装到仓库根、用户主目录或容器根目录，则 approval 绕过带来的风险由使用者承担；Ralph 工具本身不检测也不拒绝此类部署。
- Ralph 不以 root 运行，不提权，不安装系统服务。per-workspace 部署意味着每个 workspace 自带工具副本，不共享全局状态。

## Approval / Sandbox 固定策略

Ralph 是无人值守的 oneshot harness，每轮都必须跑到 provider 自然退出，不允许弹出交互式 approval prompt。各 provider 的默认策略（REQ-031；参数取值写死在 adapter 内）：

| provider | 绕过 approval 的 flag | 实际权限含义 | 额外约束 |
|---|---|---|---|
| Claude | `--dangerously-skip-permissions` + `--allowedTools "Bash,Read,Edit,Write,Glob,Grep"` | **绕过全部 permission 检查**（等价 `--permission-mode bypassPermissions`；官方权限模式表对该模式写的是 "What runs without asking: Everything"，适用场景标注 "Isolated containers and VMs only"）。同行的 `--allowedTools` 是 pre-approve（allow）规则，**不是**工具限制：官方明确 "Allow rules have no effect in `bypassPermissions`"，且 "To restrict which tools are available, use `--tools` instead"。因此那 6 项清单在本配置下**不构成能力边界**，不得当作 Claude 的权限收敛来读 | 白名单取值固定不做开关；当前 adapter 未使用任何能真正收窄能力的机制（deny 规则 `--disallowedTools` / 工具集 `--tools`） |
| Codex  | `codex exec` + `--sandbox danger-full-access` | **移除本地沙箱限制**：模型生成的 shell 命令不再受 workspace 边界约束，以当前用户身份在整机可达范围内执行（官方措辞 "removes local sandbox restrictions"）；REQ-031 的"等同于 workspace 内任意写入权限"是这条的**下界**而非等价描述 | 为允许 oneshot 完成 `git add/commit`（`workspace-write` 会禁止写 `.git/index.lock`）；Ralph 外层固定 workspace、lock、timeout 和进程树清理 |
| Gemini | 暂停支持 | adapter 保留，公共入口不接受该 provider（REQ-028） | — |

**有效权限汇总**：Claude 与 Codex 两条在各自 CLI 的语义下都等价于"以当前用户身份无限制执行"——Ralph 不存在 provider 侧的能力收窄层。区别只在实现方式：Codex 是显式 `danger-full-access` 沙箱模式，Claude 是 bypass permission 模式 + 一个在该模式下失效的 allow 清单。

Codex 沙箱模式取值来自 `codex exec --help`（`-s, --sandbox <SANDBOX_MODE>`，possible values: `read-only, workspace-write, danger-full-access`，语义为 "Select the sandbox policy to use when executing model-generated shell commands"）；`danger-full-access` 的展开描述见官方 Permissions 文档（"removes local sandbox restrictions and should be used only when that broad access is intentional"）。官方页面**未**就该 profile 单独声明网络访问行为，因此不把"网络可用"写进契约。

Claude 侧结论核查于 Claude Code CLI `2.1.270` 的 `claude --help`（"`--dangerously-skip-permissions` Bypass all permission checks"；"`--allowedTools` ... list of tool names to allow"）与官方权限模式 / CLI reference 页面（"Allow rules have no effect in `bypassPermissions`"；"To restrict which tools are available, use `--tools` instead"）。该误读的失败模式与预防检查见 [`PM-0006`](../postmortems/pm-provider-flag-semantics-vs-boundary.md)。

稳定契约（NFR-SEC-002）：

- approval/sandbox 策略写死在 `adapter-<provider>.sh` 内，不通过 CLI flag、环境变量或 `.env` 开放。
- **不存在** `--approval` / `--sandbox` / `--allowedTools`（overview.md CLI 段已声明为非目标）。
- Claude `--allowedTools` 取值固定 `Bash,Read,Edit,Write,Glob,Grep`，不随 `.env` 变化；但如上表所述，该清单在 `--dangerously-skip-permissions` 下不生效，**不构成工具限制**。
- Codex 沙箱模式固定 `danger-full-access`，不随 `.env` 变化；`RALPH_PROVIDER_CONFIG_DIR` 只改变 Codex 读取的配置/凭据目录（→ `CODEX_HOME`），不改变沙箱模式。
- **不存在** provider 侧能力收窄层。若要真正限制 Claude 可用工具（改用 `--tools`）或恢复沙箱（Codex 改 `workspace-write`），必须先新增 REQ 并按 NFR-SEC-002 的同一流程审查，不能靠 `.env` 或 flag 顺带调整。
- 如未来需要 policy file 或 CI 白名单，必须通过独立需求驱动（新增 REQ/NFR），不由 session capture 或其他功能需求间接触发。

风险承担：这三种模式都会让 provider agent 直接执行本地工具。使用者在编写 `.ralph/PROMPT.md` 时对 agent 可执行的行为负责；运行 Ralph 前不应让 workspace 处于"agent 越界写入会造成不可接受损失"的状态。

## `.ralph/.env` 解析约束

TC-STK-003 固定的加载规则：

- 路径写死 `.ralph/.env`；不接受 `--env-file`、`RALPH_ENV_FILE` 等覆盖入口。
- 只 export 以 `RALPH_` 开头的 key；非 `RALPH_*` 的行忽略。
- 注释 `#` 和空行忽略。
- 禁止 `source .env` 或任何等价的 shell 执行；必须逐行解析 `KEY=VALUE`，以避免 `.env` 变成任意代码执行点。
- 值两端的引号（单/双）被剥离，内部不做变量展开、不做命令替换。
- **Tilde 展开例外**：值以 `~/` 开头的（如 `~/.claude-glm`）安全地展开为 `${HOME}/...`；不接受 `~user/` 形式（避免引入用户名查找的风险）。这是为了让路径类变量（`RALPH_PROVIDER_CONFIG_DIR` 等）在 `.env` 里能用 home-relative 写法。

这一约束来自 NFR-SEC-001：`.env` 是用户可编辑配置，不是受信代码。

## Provider 凭据 / 配置目录隔离

REQ-022 引入的中立抽象：

- ralph 内核中立变量 `RALPH_PROVIDER_CONFIG_DIR`：在 `.env` 里声明，由 ralph load_env 解析（含 tilde 展开）+ export。
- 每个 adapter 在 source 时把它翻译为 provider 原生环境变量（详见 `integrations.md` §Adapter 配置目录翻译契约）：
  - `adapter-claude.sh` → `CLAUDE_CONFIG_DIR`
  - `adapter-codex.sh` → `CODEX_HOME`
  - `adapter-gemini.sh` → `GEMINI_CLI_HOME`（I4 DEV-1 校准；官方 configuration 文档明确该变量改变 Gemini CLI 的根目录，CLI 在该目录下创建 `.gemini/`）。**Gemini 暂停接入**（REQ-028），该翻译目前不可达：公共入口在 source adapter 之前就拒绝 `gemini`，条目保留供未来重新接入。
- **鲁棒性约束**：变量未设或值为空时**不**做翻译 export，避免空值干扰 provider 默认行为。
- 子进程 env 继承走 bash 默认行为（fork+exec），无需 adapter 在每次调用时重设。
- 凭据值（API key / OAuth token）**不**写入 status.json / result.json / 任何运行证据。
- 隔离用例：本仓库 dogfood 时 `.ralph/.env` 设 `RALPH_PROVIDER_CONFIG_DIR=~/.claude-<sub-account>`，让 ralph 子进程用独立账号跑，不占主 Claude Code 会话的 usage limit。

## Secrets 与敏感信息

NFR-SEC-003 的禁入规则（本仓库和 `.ralph/` 部署包均适用）：

- `.ralph/.env`、使用者 API key、provider 登录态、完整凭据：**不入仓**。
- provider 原生 session 文件（`~/.claude/projects/`、`~/.codex/sessions/`；Gemini 的 `~/.gemini/tmp/` 暂停接入，见 REQ-028。隔离模式下路径由 `RALPH_PROVIDER_CONFIG_DIR` 翻译后的 provider 原生变量决定）通常包含完整 prompts、tool outputs、命令结果，可能带敏感信息：默认**不入仓**。
- `.ralph/runs/` 及其下的 `provider.stdout.log`、`session.*`、`session.history.log`、`meta.json`、`result.json` 是本地复盘材料，**默认不入仓**；使用者应在 `.ralph/.gitignore` 忽略 `runs/`、`status.json`、`lock`。
- `docs/`、`handoff.md`、`checkpoints/`、`postmortems/`、`task.md` 不得写入 secrets、完整凭据或会话 transcript；协作文档只承载结构性事实。

Ralph 工具本身不对 session 文件做脱敏，因为 provider 的 transcript 结构是 provider 内部实现，任何脱敏都可能误伤。使用者在分享 run 目录前自行审查。

## 攻击面与缓解

| 面 | 风险 | 缓解 |
|---|---|---|
| `.ralph/.env` | 注入 shell 代码 | 逐行解析 + `RALPH_` 前缀白名单（TC-STK-003） |
| `.ralph/PROMPT.md` | 恶意 prompt 驱动 agent 做越权操作 | workspace 信任域 + Ralph 运行边界（Codex 使用 `danger-full-access`，风险由使用者承担） |
| provider CLI | 升级改变 flag 或 session 路径 | adapter 版本锚点 + session 采集降级为 warning（REQ-006） |
| session 文件泄露 | 提交到公共仓库 | `.ralph/.gitignore` 建议 + 本条文档显式声明不入仓 |
| 并发破坏 | 多个 `ralph run` 同时写 `runs/` | `flock` 独占 `.ralph/lock`，冲突快速退出 `locked`（REQ-012） |
| UUID 碰撞 / 预测 | 影响 Claude session 锚点 | 使用系统 `uuidgen` / `/proc/sys/kernel/random/uuid` / `python3 uuid4`，不自制随机（见 [`integrations.md#uuid-依赖`](./integrations.md#uuid-依赖)） |

## 审计与可追溯

- `context.json` 记录 `provider`、`provider_version`、`start_sha`、`env_source`，用于复盘时还原"哪一版工具、哪一个 provider 版本、对哪一个 commit、用了哪些配置来源"。
- `result.json` 记录 `exit_reason`、`rounds`、`last_error`，作为 run 级审计条目。
- `round-NNN/meta.json` 记录单轮的 `session_id`、`session_source_path`、`session_copied_path`、`capture_status`、`capture_warning`、`terminal_event` / `terminal_status` / `terminal_warning`、`error`、`changed_files`，用于追溯单轮行为。
- `round-NNN/provider.stdout.log` 是 provider 原始输出，未清洗未改写，是终态判定和错误诊断的唯一事实源（REQ-029）。

### 权限参数的审计路径（REQ-031）

权限参数是 adapter 内的**静态常量**，不随 run、`.env`、CLI flag 变化，因此当前**不落 per-run 证据文件**。可审计路径是：

1. 读部署副本里的 adapter 源码，确认实际生效的 flag：
   ```bash
   grep -n 'danger-full-access\|dangerously-skip-permissions\|allowedTools' .ralph/lib/adapter-*.sh
   ```
   期望命中 `adapter-claude.sh` 的 `--dangerously-skip-permissions` + `--allowedTools "Bash,Read,Edit,Write,Glob,Grep"`，以及 `adapter-codex.sh` 的 `--sandbox danger-full-access`，且无第三个 provider 命中。
2. 用 `context.json.provider_version` + `env_source` 锚定"哪一版 provider CLI、哪些配置来源"；`RALPH_PROVIDER_CONFIG_DIR` 只影响配置目录翻译（Claude → `CLAUDE_CONFIG_DIR`，Codex → `CODEX_HOME`），不影响沙箱模式。

**已知缺口**：REQ-031 要求沙箱/approval 参数"记录到 meta"，而当前 meta.json **没有**对应的权限字段，auditability 由上表的写死源码 + 本文档 + `context.json` 版本锚点共同承担。若未来权限参数需要按 run 变化，必须先在 meta.json 增加字段并升级本节契约。

这些字段不是合规级审计，不用做不可篡改存储；Ralph v0.1 的定位是 harness，不是合规工具。

## 非目标

- 不实现 policy 引擎、RBAC、角色分离。
- 不实现 secrets 管理（不替代 `pass` / `1Password` / `doppler` 等）。
- 不在 adapter 之外提供 approval 降级开关。
- 不做 session 文件自动脱敏或加密存储。
- 不检测使用者 workspace 的代码供应链风险（依赖扫描、SCA）。
