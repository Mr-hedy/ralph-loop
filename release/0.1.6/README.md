# Ralph Loop 0.1.6

Ralph Loop 是放在 Git 项目里的 AI 开发任务循环工具。你准备任务清单并选择一个已经登录的 provider CLI；Ralph 每轮启动一次独立的 CLI 调用，记录过程与结果，直到任务完成、失败或需要人来处理。

本目录是可直接部署的完整发布包。下面的步骤面向使用者；更细的参数和运行机制见 [`.ralph/README.md`](.ralph/README.md)。

## 能做什么

| 能力 | 使用方式或产物 |
|---|---|
| 多轮执行 | `ralph run` 按 `.ralph/TASKS.md` 中第一个未完成顶层任务运行；每轮是 fresh oneshot，不复用上一轮会话 |
| Provider 接入 | Claude Code CLI、Codex CLI、Antigravity CLI（命令 `agy`）；`fake` 仅供测试 |
| 进度观察 | `ralph status` 查看快照，`ralph watch` 实时观察；`ralph run -v` 在终端显示事件 |
| 停止与恢复 | 任务全部勾选后结束；遇到超时、provider 失败、轮次或无进展限制时留下明确状态与本地证据，可修复后再次运行 |
| 数据采集 | 每次 run 保存总结；每轮保存元数据、原始输出和可读历史，安全采集成功时另存 provider 原生会话副本 |
| 协作规范 | `.spec/` 提供需求、方案、测试和审查规则；`AGENTS.md` 是待按实际项目填写的 agent 入口模板 |

Ralph 不负责替你确定需求、生成初始任务清单或审核最终产物。使用者和主 agent 先确定项目事实及任务；执行后仍应验收代码、测试和提交。

## 使用前准备

- 系统有 Bash 4+、Git、`jq`。目标目录是 Git 仓库。
- 至少安装并登录一个 provider：`claude`、`codex` 或 `agy`。可用 `claude --version`、`codex --version`、`agy --version` 检查计划使用的命令。
- 准备好允许 agent 工作的项目副本。三家真实 provider 均使用无人值守权限参数，工具调用会以当前用户身份执行，文件系统访问不受项目目录限制。权限细节见 [`.ralph/README.md` 的权限章节](.ralph/README.md#provider-权限边界与审计证据)。

## 从零部署

以下命令在**全新**项目目录执行；请把路径换成实际发布包路径。

```bash
cd /path/to/your/project
git init                         # 已是 Git 仓库时省略
cp -R /path/to/ralph-loop/release/0.1.6/. ./
./.ralph/bin/ralph --version
```

目标项目已有 `AGENTS.md`、`CLAUDE.md`、`.ralph/`、`.spec/` 或 `docs/` 时，先把发布包复制到临时目录，逐项人工合并，避免覆盖已有项目事实和任务。不要直接复制开发仓库中的 `.ralph/`，它属于开发仓库自己的运行环境。

部署后先阅读并补齐 `AGENTS.md`，按实际项目维护 `docs/README.md`，需要协作规范时阅读 `.spec/README.md`。`CLAUDE.md` 是指向 `AGENTS.md` 的软链接。

## 配置与首次运行

复制 [`.ralph/.env.example`](.ralph/.env.example) 为 `.ralph/.env`，选择一个 provider。例如使用 Antigravity：

```bash
cp .ralph/.env.example .ralph/.env
printf '\nRALPH_PROVIDER=antigravity\n' >> .ralph/.env
```

也可以将最后一行设为 `RALPH_PROVIDER=claude` 或 `RALPH_PROVIDER=codex`。`.ralph/.env` 是本地私有配置，由 `.ralph/.gitignore` 忽略；不要提交凭据。配置优先级为命令行参数、进程环境变量、`.ralph/.env`、内置默认值。

Claude 和 Codex 可用 `RALPH_PROVIDER_CONFIG_DIR` 指向已登录的独立配置目录，分别传给 `CLAUDE_CONFIG_DIR` 与 `CODEX_HOME`。Antigravity 使用 `agy` 的默认登录态；选用它时不要设置非空 `RALPH_PROVIDER_CONFIG_DIR`，否则启动检查会失败。模型、推理强度、轮次、超时与重试等配置在 `.env.example` 中有注释。

根据已确认的需求，在 [`.ralph/TASKS.md`](.ralph/TASKS.md) 的“当前任务”下填写顶层任务。例如：

```markdown
## 当前任务

- [ ] DEV-1: 实现字符串反转函数，添加并运行单元测试，完成后提交变更。
- [ ] QA-1: 检查边界输入并记录验证结果，完成后提交变更。
```

顶层 `- [ ]` 表示待办，`- [x]` 表示完成。每轮处理一个顶层任务；`HUMAN-N:` 放在第一个未完成任务时会停止并等待人处理。发布包自带的任务清单是空模板，未填写任务时不会启动 provider。

确认任务和工作目录后运行：

```bash
./.ralph/bin/ralph run
```

临时覆盖 provider 或限制单任务轮数的示例：

```bash
./.ralph/bin/ralph run --provider codex --max-round 3 --round-timeout 600
```

用 `./.ralph/bin/ralph run --help` 查看全部选项。Ralph 的任务协议要求 agent 完成任务后更新清单并创建 Git commit；请在运行前检查任务文字和项目规则是否允许这些操作。

## 查看进度和结果

```bash
./.ralph/bin/ralph status
./.ralph/bin/ralph status --json
./.ralph/bin/ralph watch
```

在另一个终端运行 `watch` 可实时观察；`Ctrl+C` 只退出观察界面。终端内需要 provider 事件时可使用 `./.ralph/bin/ralph run -v`。

运行结束后查看 `.ralph/runs/<run_id>/result.json` 和 `exit-message.txt`；每轮证据在 `rounds/round-NNN/`。其中 `meta.json` 保存终态、耗时、错误和采集状态，`provider.stdout.log` 保存原始输出，`session.history.log` 是便于阅读的历史；`session.<provider>.jsonl` 仅在原生会话安全采集成功时出现。采集失败可能只是 warning，应结合 `result.json`、任务清单、测试和 Git 提交判断实际结果。

常见 `exit_reason`：

| 原因 | 含义 | 下一步 |
|---|---|---|
| `done` | 清单中的任务全部完成 | 验收变更、测试和提交 |
| `blocked_by_human` | 需要人类决策或触及轮次/无进展限制 | 阅读 `exit-message.txt` 与当前任务，处理阻塞后重跑 |
| `provider_failed` | provider 命令或终态报错 | 查看本轮 `meta.json` 和 `provider.stdout.log`，修复原因后重跑 |
| `timeout` | 单轮超过超时限制 | 检查任务粒度或调整超时，再重跑 |
| `locked` | 同一 workspace 已有 run | 等待现有 run 或检查锁状态 |
| `startup_failed` | 配置、依赖或 provider 校验失败 | 按终端错误信息修正配置 |

本地 `.ralph/runs/`、`.ralph/status.json`、`.ralph/lock` 不进入发布包，也不应提交到使用者仓库。日志和原生会话可能含有 prompts、工具输出和敏感信息，分享前需自行检查。

## 发布包内容与升级

| 路径 | 用途 |
|---|---|
| `.ralph/bin/ralph`、`.ralph/lib/` | CLI 与 provider adapter |
| `.ralph/PROMPT.md`、`.ralph/TASKS.md` | 每轮工作协议与空任务模板 |
| `.ralph/.env.example`、`.ralph/README.md` | 配置示例与详细手册 |
| `.spec/` | 协作规则和文档模板 |
| `AGENTS.md`、`CLAUDE.md` | 项目 agent 入口模板及软链接 |
| `docs/README.md` | 项目过程文档地图模板 |

升级已有 workspace 时，先备份并逐项比较新旧发布包。保留已有 `.ralph/TASKS.md`、`.ralph/.env`、项目 `AGENTS.md`、`.spec/` 定制和 `docs/` 事实源；按需更新 CLI、adapter、协议与模板。升级后运行 `./.ralph/bin/ralph --version`，再用一个小任务验证实际行为。

## 版本更新记录

| 版本 | 主要变化 |
|---|---|
| **0.1.6** | 移除旧的 Gemini CLI adapter 与测试替身，统一当前 provider 入口；完善配置示例、发布包使用指南和版本记录。 |
| **0.1.5** | 接入 Antigravity CLI；采集运行事件与原生 transcript，完善错误判定、会话路径校验和真实端到端验证。 |
| **0.1.4** | 对齐文档规则与发布包版本。 |
| **0.1.3** | 修订 Codex adapter、运行入口与协作规范，并同步发布包。 |
| **0.1.2** | 更新版本化发布包与构建检查；部署内容与 0.1.1 基本相同。 |
| **0.1.1** | 建立早期版本化部署包，包含 Ralph 运行单元和协作规范。 |

本文件由开发仓库 `templates/RELEASE-README.md` 随发布包生成。使用者项目中的 README 在部署后可按项目实际情况维护。
