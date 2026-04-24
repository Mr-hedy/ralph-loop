---
id: PM-0001
title: "Shell 脚本 macOS 兼容性 bug 在实施阶段未发现，集中在 adversarial review 阶段暴露"
status: active
domain: shell
severity: medium
affected_modules:
  - .ralph/lib/common.sh
  - .ralph/lib/adapter-fake.sh
  - .ralph/lib/run.sh
  - scripts/integration-test.sh
linked_commits:
  - pending-t1-done-commit
trigger_conditions:
  - "在 macOS 上编写 bash 脚本时使用了 Linux/GNU 专有的 CLI 或行为"
failure_pattern:
  - "同一次实施产出多个 macOS 不兼容 bug，均在 adversarial review 而非实施中发现"
prevention_checks:
  - "实施完成后立即在 macOS 上执行 bash scripts/integration-test.sh，全绿才视为本地验证通过"
  - "新增 shell 脚本时主动检查：flock CLI（不可用）、date +%s%3N（不可用）、printf 以 - 开头的值（需 '%s'）、SIGINT 在等待子进程时被 deferred"
---

# Shell 脚本 macOS 兼容性 bug 在实施阶段未发现，集中在 adversarial review 阶段暴露

## 现象

T1 实施完成后，adversarial review 集中发现 4 个同类 macOS 兼容性 bug，另有 3 个非 macOS 但与 `set -euo pipefail` 相关的 bug：

macOS 专有：
1. `flock` CLI 在 macOS 不可用（只有系统调用，没有 `/usr/bin/flock`）
2. `printf '- [ ] Task A\n'` 在 macOS `printf` 中 `-` 被识别为 flag，输出错误
3. `date +%s%3N`（毫秒格式）在 macOS BSD date 不支持
4. `kill -INT $bg_pid` 向等待子进程的 bash 发送 SIGINT 时信号被 deferred，trap 不立即触发

pipefail 相关（非 macOS 专有，但同轮发现）：
5. `count_checked` 中 `grep -c` exit 1 + `|| echo 0` 导致双输出
6. `ralph_changed_files` 管道末尾 `grep -v` 全过滤时 exit 1 导致主循环静默退出
7. `integration-test.sh` 中 `ls | wc -l | tr -d ' ' || echo 0` 双输出

## 根因

- macOS 使用 BSD 工具链（`grep`、`sed`、`date`、`printf` 等），与 Linux GNU 工具链行为有差异；macOS 没有提供 `flock` CLI。
- 实施阶段没有在 macOS 上实际运行集成测试，仅靠 `bash -n` 语法检查和代码阅读。
- `set -euo pipefail` 的边界条件（`grep -c`、管道末尾空输出、子进程信号）未在写代码时逐一确认。

## 修复

- `flock` → noclobber 子 shell + PID 文件锁（跨平台原子性）
- `printf '- [ ] ...'` → `printf '%s\n' "- [ ] ..."`
- `date +%s%3N` → `$(( $(date -u +%s) * 1000 ))`
- SIGINT deferred → 集成测试改用 `kill -TERM`，trap 同时处理 INT/TERM
- `grep -c` exit → `out="$(... | grep -c '^1 ')" || out=0`
- 管道 grep -v exit → 末尾 `|| true`
- 双输出 `|| echo` → 提取 `count_runs()` 辅助函数，先检查目录存在

## 预防检查

- 类型：automated-test
- 位置：`bash scripts/integration-test.sh`
- 通过标准：`PASS=14 FAIL=0`，实际在运行平台（macOS）上执行
- 适用范围：所有 `.ralph/lib/*.sh`、`.ralph/bin/ralph`、`scripts/*.sh` 的新增或修改

---

- 类型：manual-check（实施时检查清单）
- 位置：代码审查时逐项确认
- 通过标准：shell 脚本中无以下构造：`flock`（CLI 版本）、`date +%N` 或 `%3N`、`printf <flag-like-string>`（未加 `'%s'`）、`grep -c` 后接 `|| echo N`（用变量捕获）
- 适用范围：涉及 lock / 时间戳 / 任务计数 / signal 的 shell 代码

## 知识沉淀

- 保留在本记录：macOS vs GNU 工具差异列表（flock/date/printf/SIGINT）
- 需要提炼到 skill：无（adversarial review 是现有质量门，本次已正常工作）
- 需要提炼到 `.spec/`：无（macOS 是本项目明确目标平台，已知前提）
- 需要提炼到 `docs/`：无（不属于架构事实）
- 需要提炼到脚本或测试：`bash scripts/integration-test.sh` 已作为强制验收命令写入 `task.md` T1 验证字段；后续 adapter 实施应沿用同一命令

## 后续

- T2（Claude adapter）、T3（Codex）、T4（Gemini）实施时：每轮完成后在 macOS 上运行 `bash scripts/integration-test.sh` 后才勾选任务。
- 若未来引入 CI，优先配置 macOS runner。
