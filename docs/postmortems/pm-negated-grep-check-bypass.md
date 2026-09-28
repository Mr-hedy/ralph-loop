---
id: PM-0007
title: "取反 grep 在 set -e 下未形成可靠检查门"
status: active
domain: "build / verification"
severity: "medium"
affected_modules:
  - "scripts/check.sh"
linked_commits:
  - "pending v0.1.3 consistency cleanup"
trigger_conditions:
  - "在 set -e 脚本中把独立的 ! grep -q 当作失败断言"
failure_pattern:
  - "被禁止的文本已经出现，检查脚本仍继续并报告通过"
prevention_checks:
  - "bash scripts/check.sh 必须通过，且脚本自身不得含以 ! grep 开头的独立检查行"
---

# 取反 grep 在 set -e 下未形成可靠检查门

## 现象

`scripts/check.sh` 原有 `! grep -q "AGENTS.md" "$ROOT/README.md"`，而现行 README 合法地说明了 release 中的 `AGENTS.md`。检查脚本仍输出 `ralph-loop check passed`。最小复现 `bash -e -c '! grep -q AGENTS.md README.md; echo negative-grep-check-was-ignored'` 继续打印了尾部标记。

## 根因

Bash 对以 `!` 取反的命令不应用通常预期的 `errexit` 退出行为。原脚本把独立的 `! grep` 当作断言，却没有在命中时显式 `exit 1`。其中禁止 README 提及 `AGENTS.md` 的旧口径也已经与当前 release 入口冲突。

## 修复

- 移除过期的 `AGENTS.md` 文本禁令。
- 对仍需禁止的 `npm run check` 说明改用 `if grep -q ...; then ...; exit 1; fi`。
- 在 `scripts/check.sh` 中拒绝重新引入以 `! grep` 开头的独立检查行。

## 预防检查

- 类型：script + manual-check。
- 位置：`scripts/check.sh`。
- 通过标准：`bash scripts/check.sh` 通过；`rg -n '^[[:space:]]*![[:space:]]*grep' scripts/check.sh` 无命中。修改负向文本检查时，应验证命中路径确实使脚本非零退出。
- 适用范围：本仓库的静态检查入口；不将此案例外推为所有 shell 中的 `!` 用法都错误。

## 知识沉淀

- 保留在本记录：复现、根因和适用范围。
- 需要提炼到 skill：无。
- 需要提炼到 `.spec/`：无。
- 需要提炼到 `docs/`：本记录与 postmortem 索引。
- 需要提炼到脚本或测试：已在 `scripts/check.sh` 增加显式失败门与自检。

## 后续

- 后续增加负向静态断言时，实际运行一次应失败的输入，确认检查门具有判别力。
