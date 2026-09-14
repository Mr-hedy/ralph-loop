---
id: PM-0006
title: "把 provider CLI 的 flag 参数形状当成权限边界，未核查官方语义，文档长期声明了不存在的工具限制"
status: active
domain: "security / provider integration / documentation"
severity: "high"
affected_modules:
  - "docs/architecture/security.md"
  - "docs/architecture/integrations.md"
  - "docs/architecture/overview.md"
  - ".ralph/README.md"
  - ".ralph/lib/adapter-claude.sh"
linked_commits:
  - "pending DEV-5 权限边界文档收敛 commit (2026-09-14)"
trigger_conditions:
  - "文档把 provider CLI 的某个 flag 描述为能力边界（白名单 / 限制 / 收窄），但没有给出该 flag 的官方语义依据"
  - "同一条 provider 命令里同时存在 bypass 类 flag（`--dangerously-skip-permissions`、`--sandbox danger-full-access`）和一个在字面上看起来收敛的 flag（`--allowedTools`）"
  - "验证手段只断言「参数被传了」（mock 参数形状断言），不断言参数的实际语义效果"
failure_pattern:
  - "按 flag 名的字面含义推断语义（allowedTools → 可用工具被限定），不复核 CLI `--help` 原文和 permission mode 交互规则"
  - "把「传了 sandbox / approval 参数」当成「获得了对应的权限边界」——参数形状断言无法证伪语义误读，语义理解错误但参数传对的用例会全绿"
  - "安全文档的偏差方向是低估风险：使用者以为 agent 能力被收敛到 6 个工具，实际是全部工具直接执行，风险判断建立在错误的收敛假设上"
prevention_checks:
  - "写 provider CLI flag 语义时，凡声称「边界 / 限制 / 收窄」的段落必须附官方语义依据（CLI `--help` 原文或官方文档引文），并显式说明它与同命令内 bypass 类 flag 的交互"
  - "权限边界的 adversarial review 必须对每条「权限已收敛」的断言抽查官方语义证据；只核对参数是否被传不算通过"
---

# 把 provider CLI 的 flag 参数形状当成权限边界，未核查官方语义，文档长期声明了不存在的工具限制

## 现象

2026-09-14 DEV-5（收敛 provider 入口和权限边界文档）核对 Claude Code CLI `2.1.270` 的帮助文本与官方页面时发现：

- `claude --help` 对 `--allowedTools` 的说明是 "Comma or space-separated list of tool names to **allow**"，即 pre-approve（allow）规则。
- 官方 CLI reference 明确："**To restrict which tools are available, use `--tools` instead.**"——`--allowedTools` 不限制可用工具。
- 官方 permission modes 页面明确："**Allow rules have no effect in `bypassPermissions`.**"

而 `adapter-claude.sh` 的命令构造同时传了这两个 flag：

```bash
claude -p "$(cat "$prompt_file")" \
  --session-id "$session_id" \
  --dangerously-skip-permissions \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep" \
  --output-format stream-json --verbose
```

`--dangerously-skip-permissions` 等价于 `--permission-mode bypassPermissions`，官方权限模式表对该模式写的是 "What runs without asking: **Everything**"，适用场景标注 "Isolated containers and VMs only"。因此那个 6 项清单**自始至终没有生效**。

受影响的文档段落（DEV-5 之前）把该清单当作 Claude 的能力边界来描述：

- `docs/architecture/security.md`：approval/sandbox 表 "白名单固定，不做开关"；稳定契约 "Claude 白名单取值固定 …，不随 `.env` 变化"。
- `docs/architecture/integrations.md`：`ALLOWED_TOOLS` 固定值 "NFR-SEC-002 写死，不做开关"。
- `.ralph/README.md`：安全边界段与参数表。

## 根因

- 直接原因：文档编写时按 flag 名的字面含义（"allowed tools"）推断语义，未核对 CLI `--help` 原文，也未核对 allow 规则与 `bypassPermissions` 的交互规则。
- 系统性原因：PM-0004 建立的预防机制只到"参数形状"层——`scripts/integration-test.sh` 断言 mock 收到了 `danger-full-access` / `--skip-trust`。形状断言能防止**参数静默回退**，但无法证伪**语义误读**：一个语义被理解错、参数却确实传对了的用例会全绿。PM-0004 的预防检查因此在本类问题上被证明不充分。
- 偏差方向：本次偏差是**低估**风险（文档声明的边界比真实边界窄），不是越权。但它直接违反 REQ-031 的"默认权限策略不得被隐式扩大"精神——文档宣称了一个不存在的收敛层，使用者的风险判断因此建立在错误前提上。

## 修复

- `docs/architecture/security.md`：approval/sandbox 表新增"实际权限含义"列，逐条区分"传了什么参数"与"实际限定了什么"；新增"有效权限汇总"，说明 Claude 与 Codex 两条真实路径都等价于"以当前用户身份无限制执行"，Ralph 不存在 provider 侧的能力收窄层；稳定契约补"不存在 provider 侧能力收窄层"条目，并注明要真正收窄需改用 `--tools` / 回到 `workspace-write`，必须走新 REQ。
- `docs/architecture/integrations.md`、`docs/architecture/overview.md`、`.ralph/README.md`：同步同一结论，并补官方引文语。
- `.ralph/lib/adapter-claude.sh` **行为未改**：本轮只纠正事实描述，不动稳定权限契约（NFR-SEC-002）。"是否真的收窄工具集"是需要单独 REQ 的设计决策。

## 预防检查

- 类型：`manual-check`
- 位置：任何描述 provider CLI flag 语义的文档变更（`docs/architecture/integrations.md`、`docs/architecture/security.md`、`.ralph/README.md`、requirements 的 FR-005 / FR-006 / FR-007）。
- 通过标准：
  - 凡声称"边界 / 限制 / 收窄"的段落，必须给出官方语义依据（CLI `--help` 原文或官方文档引文），并说明它与同命令内 bypass 类 flag 的交互。
  - 拿不到官方依据时，只能写"传了什么参数"，不得写"限定了什么能力"。
  - 本次已按此标准落地：`security.md` 记录了 `claude --help` 原文（`2.1.270`）、"Allow rules have no effect in `bypassPermissions`"、"To restrict which tools are available, use `--tools` instead"、Codex `codex exec --help` 的 sandbox 取值清单，以及官方 Permissions 页对 `danger-full-access` 的措辞。
- 适用范围：任何 provider adapter 命令参数、approval / sandbox / trust 策略、权限边界文档。

- 类型：`manual-check`（review gate）
- 位置：涉及权限边界的 adversarial review（REVIEW-N）。
- 通过标准：reviewer 对每条"权限已收敛"的断言抽查至少一条官方语义证据；只核对"参数是否被传"不算通过。
- 适用范围：provider adapter 变更、权限策略变更、release closeout。

## 知识沉淀

- 保留在本记录：参数形状断言与语义核查之间的能力边界——"传对了参数"不等于"得到了预期的边界"。
- 需要提炼到 skill：有，本轮未执行。应在 adversarial review 流程中固化"权限边界断言必须附官方语义证据"。
- 需要提炼到 `.spec/`：有，本轮未执行（避免在 DEV 任务里改协作规范）。建议在 `.spec/rules/adversarial-review.md` 增加一条：安全默认值 / 权限边界类断言必须附官方语义证据，参数形状断言不构成证据。
- 需要提炼到 `docs/`：已更新 `security.md`、`integrations.md`、`overview.md`、`.ralph/README.md`（DEV-5，2026-09-14）。
- 需要提炼到脚本或测试：暂无自动化手段能证伪"语义误读"（mock 只能证明参数形状），因此本条保持 `manual-check`；不要为它硬造形同虚设的自动化断言。

## 后续

- REVIEW-1 复核本条目结论，并决定是否把"权限边界断言必须附官方语义证据"写进 `.spec/rules/adversarial-review.md`。
- 若决定真正收窄 Claude 可用工具（改用 `--tools`）或收紧 Codex 沙箱（回到 `workspace-write` 并重新解决 `.git/index.lock` 写入），需新增 REQ 并按 NFR-SEC-002 的同一流程审查。
