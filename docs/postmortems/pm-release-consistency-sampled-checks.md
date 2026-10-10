---
id: PM-0008
title: "抽样校验使发布包与现行协作入口同时保留旧事实"
status: active
domain: "release / documentation / verification"
severity: "high"
affected_modules:
  - "docs/"
  - ".spec/"
  - ".ralph/README.md"
  - "scripts/build-release.sh"
  - "scripts/check.sh"
  - "templates/RELEASE-README.md"
  - "scripts/integration-test.sh"
  - ".agents/skills/ralph/SKILL.md"
linked_commits:
  - "a5ad531100550894b382e56d03fedea08a8476e4"
trigger_conditions:
  - "按新 .spec 布局迁移现行文档并生成 release，但只检查部分源文件和发布内容"
failure_pattern:
  - "检查命令通过，现行文档仍有旧事实，发布包仍要求读取未随包交付的文件"
prevention_checks:
  - "紧凑 UI 不能只检查 ANSI 或换行数量；发布包 PTY 画面须覆盖宽字符折行并确认重复刷新后仅一个头部"
  - "bash scripts/build-release.sh --verify 完整比对当前生成包"
  - "按 docs/testing.md 的 Release 部署验证检查新 workspace 入口、可执行权限与必读文件"
  - "按 docs/testing.md 的文档语义检查核对研究文档索引、状态、可见链接文字和正文职责"
  - "新增 provider 发布前，将 adapter 的默认会话路径、参数、终态和 history 输出逐项对照 docs/integrations.md，并运行对应集成断言"
  - "macOS 上用 /bin/bash scripts/check.sh 和 /bin/bash scripts/integration-test.sh 验证系统 Bash 3.2；安装说明不得沿用未经实现和实测支持的最低版本要求"
---

# 抽样校验使发布包与现行协作入口同时保留旧事实

## 现象

v0.1.3 整理后，`bash scripts/check.sh` 与 mock 集成测试通过，但现行 `docs/requirements.md` 仍称本仓库不使用 Ralph dogfood，`docs/architecture.md` 仍要求使用者自行创建已由 release 提供的模板。发布版 `.spec/README.md` 无条件要求读取包内不存在的 `docs/postmortems/README.md`，发布版 `.ralph/README.md` 将未入包的 `docs/security.md` 称作部署后的权威阅读入口。用户发现旧 `docs/requirements/` 目录后，进一步审查才暴露这些同类遗漏。

## 根因

- 迁移时以文件移动和局部引用替换作为完成判据，没有复查现行需求、架构和新手入口的行为陈述。
- `scripts/check.sh` 只比较 `.spec/`、部分 `.ralph/` 源文件和少数发布包特征，未从构建脚本重建完整包逐项对比，也未在全新 workspace 检查必读文件是否存在。
- 历史兼容导航页保留在部分旧目录，却移除了另一些旧目录，缺少统一的迁移终态检查。
- 新增 provider 时仅验证了代码分支和发布包字节一致性，没有把现行集成文档中的路径、参数、终态和派生字段逐项与 adapter 输出对照。

## 修复

- 修正现行项目事实、用户控制任务生成与验收的入口说明；发布版对未入包项目文档改为条件化或明确说明仅存在于开发仓库。
- 移除旧 `docs/requirements/`、`docs/architecture/` 和 `docs/collaboration/` 导航目录；历史快照原文保留在 feature history、checkpoint 和研究文档中。
- `scripts/build-release.sh --verify` 在临时目录重建当前版本，并对包的完整文件树做比对；构建时先写临时目录，成功后才移入正式版本路径。
- `scripts/check.sh` 调用完整包比对，并拒绝旧目录重新出现。
- 后续整体审查发现发布版 TASKS 规则仍含本开发仓库专用的历史任务与检查命令，且 README 使用未安装的全局 `ralph` 命令；已将分发规则改为项目声明的入口和命令，并修正 quickstart。发布校验增加 CLI 可执行权限检查。
- v0.1.3 提交后的定向复核发现，研究回溯文档未进入文档地图且仍标为 active，方案正文保留独立审查报告段，测试文档的状态字段混入单次验证结果，部分现行链接仍显示旧文件名。字节一致性检查无法发现文档语义和职责漂移；已按现行 DOCS/ARCHITECTURE 规则修正，并在测试规范中补充人工核对点。
- v0.1.5 的 Antigravity 接入再次出现同类漂移：集成文档仍将旧 `~/.gemini/antigravity/` 写作默认 transcript 路径、称 `--effort` 不透传、把未知终态描述为 `error`，并宣称 history 包含实现未派生的 thinking。发布包字节比对和既有 173 项测试均通过，但不能发现这些说明与 adapter 不一致；同时 `run -v` / `watch` 曾把带错误的 `SUCCESS` 和未知状态显示为 `✓ result`。
- 已按实际 adapter 和 `release/0.1.5` 真实 smoke 证据修正 `docs/integrations.md` 与 `docs/security.md`，并增加双视图异常终态集成断言；完整测试达到 174 PASS / 0 FAIL。
- 2026-09-30，用户在新项目部署 0.1.6 时，agent 根据发布 README 的 `Bash 4+` 提议安装机器级新版 Bash。`git blame` 显示根 README 的该表述来自 `3e897b6a`（2026-04-29），发布 README 模板在 `a047011`（2026-09-29）继承了它；没有对应的 Bash 4 版本门槛，本机 `bash` 实际为 `/bin/bash` 3.2.57。系统 Bash 下原有完整集成测试 174 PASS / 0 FAIL，证明最低版本文档与已验证环境矛盾。发布包字节一致性只能证明错误被一致复制，不能证明依赖要求正确。
- 已将根 README、发布模板和当前 0.1.6 README 更正为 Bash 3.2+；目标机器按实际版本判断，不把本机验证外推成所有 macOS 均无需升级 Bash，其他历史发布包保持原文。新增完整发布包部署用例，核对任务、result/status 终态、计数、watch、版本与软链，避免只验证开发源码。顺带修复语法门：一次 `bash -n file1 file2 ...` 只检查首个脚本，其余成为参数；现在逐文件检查，验证 macOS 基线时显式用 `/bin/bash` 启动。
- 同日整体反向审查发现，安装冲突提醒漏了 `README.md`，架构/安全文档仍将锁实现写成 `flock`，开发 Ralph skill 仍推荐已移除的 Gemini。安装语义审查不能只看新增的 Bash 文案，也需对照包的全部顶层文件和现行入口。Git 身份还被简化为 `.git` 目录存在，Claude 目录规范化暗中依赖 `realpath`；仅在本机用普通仓库和完整工具链运行，不能覆盖这些环境差异。
- 0.1.7 修复包补齐复制前的冲突说明（保留已有项目 README），按 Git 返回并规范化的工作区根判断普通仓库/worktree 身份，Claude 改用 `cd + pwd -P` 并明确记录路径解析失败。现行锁和 provider 文档按代码纠正。Bash 支持基线由运行入口声明、发布模板从同一常量生成，静态检查核对根 README 的版本值和模板占位，并比对完整生成包。复核修复范围后，移除缺少必要性证据的版本硬拦截与 macOS 强制解释器切换，保留调用者选择；移除文档整句匹配和地图中的单轮验证记录。集成 harness 及全部 Ralph/adapter/expect 调用沿用启动 harness 的 Bash，不通过改变 PATH 达成隔离。
- 用户本轮明确要求不运行单测/集成测试，因此 0.1.7 只核对语法、静态规则、生成内容和空白；不能沿用此前 0.1.6 的 175 项通过记录证明新运行代码和修改后的测试入口已经通过行为验证。
- 2026-10-09，用户在真实 Antigravity 0.1.6 workspace 中观察到 watch 反复显示相同工具参数，看不到执行说明或结果。根因是旧工具 fixture 省略 state/output，显示层把 ACTIVE/DONE 都当作调用；紧凑事件区又不适合作为完整执行过程入口。修复目标按用户确认收敛为“让人类知道 AI 在做什么”：新增 `watch --details` 回放并跟随当前轮的文字、操作和结果，默认紧凑入口保留；仅接收实时流已有的思考，原生会话中的 thinking 不被误称为实时可见。真实使用者项目本轮不升级。
- 同日核对 `agy 1.3.2 --help` 和官方 headless 协议后，确认没有公开的思考正文输出开关；修复展示层遗漏的 `DONE.tool_info.error` 和终态 `result.response`。预防检查不能只看事件名与退出码：SC-024-6 的待复验样本必须覆盖 DONE 带错误、错误与输出并存和最终回复只出现在 result 中；本轮按用户约束仅做静态验证。

- 0.1.8 反向审查发现 Codex 解析器与 mock 同时使用错误的 `output` 字段，真实命令结果实际为 `aggregated_output`；彼此自洽的 mock 不能证明外部协议正确。同时，直接覆盖 status.json 与只按日志长度判断重试，遗漏了正常运行中的写入和文件替换窗口。已按官方类型修正双视图、history 和 fixture，状态采用同目录原子替换，日志按新 inode 区分尝试，详情保留未知/未解析事件。静态语法和生成一致性仍不能证明这些行为已验证。

- 2026-10-09 发布前用户明确要求完整测试，已在系统 Bash 3.2.57 下完成 193 PASS / 0 FAIL。新增回归直接运行发布 CLI，覆盖协议源/快照变更与实际读取失败、两种 Git 对象格式、PTY 跟随/重试替换/换轮/Ctrl-C、实际状态写入并发读取；三个真实 provider 在合成 workspace 完成单任务且遵守不提交授权。此前仅静态验证的未覆盖范围由当前证据补齐，范围与原生认证准备失败记录见 `docs/testing.md`。

- 2026-10-10，用户在营销项目的 0.1.8 紧凑 watch 中发现头部不断堆积。工具结果新增完成状态和中文输出后，事件按字符数量截断，却用固定物理行数回移；宽字符实际折行增加帧高度，留下旧头部。顶/底栏未限制折行也有同类路径。既有测试只检查换行数量和头部/横线出现，193 项通过不能证明终端画面正确；真实 provider 烟测的 watch 回放为非 TTY，同样未验证该场景。
- 0.1.9 修复仅改变公共 renderer 的宽度/折行处理：事件按保守列宽截断并平整控制空白；绘制期间禁止自动折行并立即恢复，退出清理也恢复。新增 PTY 终端解释器按显示列宽与光标控制重建画面，80/120/180 列下核对重复刷新、长中文/emoji/制表符、live→finished 和退出恢复。原 0.1.8 包在新回归中复现多个头部，修复后通过。既有 0.1.8 包保留，不用改写已部署版本掩盖失败证据。

## 预防检查

2026-10-10 的 0.1.9 全量复审继续暴露同类缺口：宽字符修复未覆盖实际窗口高度，8 行窗口或过大事件区配置仍把头部滚入历史；健康灯在命令替换子 shell 中更新活动状态，日志有过内容后永久绿色；原子写入不能阻止 watch 逐字段读取不同快照；同秒快速重跑复用目录，覆盖原始 run 证据。修复分别落在公共 renderer、单帧状态读取和 lock 内 ID 分配；回归验证实际画面、活动状态变化、并发帧一致性与两次独立 run，不只核对源码字段。

Ralph skill 单独进入 0.1.9 后，构建按单文件白名单打包，项目入口显式路由，安装冲突清单加入 `.agents/`。完整比对另外核对软链类型，防止 `diff` 解引用后接受依赖包外文件的 CLI；隔离构建负例同时验证外部软链与未交付 skill 均被拒绝。其他 skills 与会话 Hook 不提前交付。

同类观察入口也要追到实际进程：watch 未自行加载 `.env`，不能继承另一 run 进程加载的 UI 配置；文本 status 与非 TTY watch 逐字段重开文件同样会混读。回归分别验证独立 watch 的文件配置与进程优先级，以及并发写入下三个观察入口的一致快照，不能只验证 TTY 路径。

UI 配置进一步验证前导零、非法阈值及表达式输入：只接受受限十进制数，非法值回到默认值，避免配置进入 Shell 算术求值。完整复验曾出现一次紧凑画面 Ctrl-C 超时，独立画面与 32 次随机中断未复现；不能把后续单次通过当作根因消失。共享 renderer 改为保留 Ctrl-C 输入，在 builtin 边界触发原有 INT trap，减少前台 helper 对键盘中断的时机影响；PTY 回归另外核对自动折行、输入标志和原中断键均恢复。排障同时证实旧清理逻辑的小数 `read -t` 在系统 Bash 3.2 报错但被隐藏；按既有 min=0/time=0 终端设置使用普通非阻塞 read，避免未验证的参数兼容性假设。持续刷新的 run/watch 显式启用键盘轮询，单次 renderer 调用保持原生 SIGINT；清理先关闭轮询，避免 run 中断后最终摘要绘制读取已恢复为规范模式的终端。实际 run -v 回归同时核对退出码、最终产物、锁和 provider 子进程清理。该修改不改变外层宿主的后台托管机制。

- 类型：script + manual-check。
- 位置：`scripts/build-release.sh --verify`、`scripts/check.sh`、`docs/testing.md` §Release 部署验证和文档规则验证。
- 通过标准：生成包与从源文件重建的包完全一致且 CLI 可执行；复制到临时 Git workspace 后 CLI/fake smoke 通过；发布入口要求立即读取的路径存在或明确为按需创建/开发仓库专有；随包分发的规则不要求使用者运行开发仓库专用脚本；现行文档地图、状态、链接显示文字和正文职责经人工核对一致。
- 适用范围：`.spec/`、`.ralph/`、模板、构建脚本、release 或文档事实源路由变化。
- Bash 兼容检查：在 macOS 执行 `/bin/bash --version`、`command -v bash`、`/bin/bash scripts/check.sh`、`/bin/bash scripts/integration-test.sh`。通过标准为逐文件语法检查、安装文档基线与发布包完整比对通过，系统 Bash 部署用例及完整集成测试无失败；不得将该证据扩大为真实 provider 或 Linux/Windows 已验证。
- 安装语义检查：将复制命令前的冲突清单与包的顶层文件逐项对照（特别是 `README.md`）；将 skill 的可执行 provider 示例与 CLI 支持矩阵对照；锁机制和附加工具依赖说明对照代码。Bash 支持基线取自 `.ralph/bin/ralph`，不能在发布说明中独立猜测；验证入口须尊重调用者选定的解释器，已验证版本不自动成为新的运行硬拦截，版本检查不绑定整句文案。验证被用户限制时，记录本次未运行项，旧版本测试结果只保留为历史证据。
- 新增 provider 时，人工逐项对照 `adapter-<provider>.sh`、事件过滤器与 `docs/integrations.md`：实际默认路径及 fallback 顺序、model/effort 传参、终态三态、原生会话校验、人话历史实际输出。可用 `rg -n 'base_dirs|--effort|terminal_status|derive_history' .ralph/lib/adapter-antigravity.sh` 定位实现，再检查文档对应段落；异常终态在 `run -v` 和 `watch` 的显示由 `scripts/integration-test.sh` 的 SC-051-1 断言守护。
- 执行可观察性检查按 `docs/testing.md` 的 SC-024-6 口径：区分原始流、原生会话和显示摘要，样本必须覆盖工具状态及结果；以人类能否看到当前操作与结果作为通过标准，不能只检查事件非空或去重数量。未运行的详情入口验证须明确记录；当前可复现门为 `tests/release-regressions.sh` 和 `tests/watch-details-pty.py`，由完整集成入口调用。

## 知识沉淀

- 保留在本记录：遗漏链条、根因和适用范围。
- 需要提炼到 skill：0.1.9 的 Ralph skill 已纳入宿主与 provider 分离、原生后台托管和运行证据规则；其他动作 skills 与 Hook 仍待后续完善。
- 需要提炼到 `.spec/`：已把验收返工的用户决策边界贯穿 Review 与 adversarial review 输出规则。
- 需要提炼到 `docs/`：现行需求、架构、测试规范和文档地图已同步。
- 需要提炼到脚本或测试：发布包完整比对已进入 `scripts/check.sh`。

## 后续

- 0.1.8 三个真实 provider 的单任务 smoke 已验证，记录见 `docs/testing.md`；0.1.9 本轮未重新调用模型，完整 Main Agent skill 协作演练仍需单独验证，fake 部署回归不证明该交互链路。
- 用户要求 `.ralph/TASKS.md` 完全不变，其中的旧文档路径仍是未来执行前需由人核对的已知限制。
