---
id: PM-0005
title: "集成测试继承 dogfood 进程的 RALPH_* 环境变量，产生与代码无关的假失败"
status: active
domain: "verification / test harness"
severity: "medium"
affected_modules:
  - "scripts/integration-test.sh"
  - "scripts/check.sh"
linked_commits:
  - "pending: DEV-3 round 登记 QA-2 任务"
trigger_conditions:
  - "在 ralph dogfood 环境（ralph oneshot 内）或任何已导出 RALPH_* 变量的 shell 里运行 `bash scripts/integration-test.sh`"
  - "用例不显式传 CLI flag，依赖 ralph 的参数默认值做断言"
failure_pattern:
  - "`load_env` 的优先级契约是 CLI flag > 进程 env > `.env`，因此父进程导出的 `RALPH_PROVIDER` / `RALPH_LOOP_MAX_RETRY` / `RALPH_LOOP_MAX_ROUND` / `RALPH_LOOP_STALL_LIMIT` / `RALPH_LOOP_ROUND_TIMEOUT` 会覆盖用例预设；同一份代码在 dogfood 环境失败、在干净环境通过"
  - "失败被误读成产品回归（“上一步改坏了 retry”），实际是测试宿主环境泄漏"
prevention_checks:
  - "在继承 RALPH_* 的环境与干净环境下各跑一次完整集成测试，结论必须一致：`env RALPH_LOOP_MAX_RETRY=0 RALPH_PROVIDER=claude RALPH_LOOP_MAX_ROUND=4 bash scripts/integration-test.sh` 与 `env -u RALPH_LOOP_MAX_RETRY -u RALPH_PROVIDER bash scripts/integration-test.sh` 同为全绿"
  - "用例断言默认值时必须显式隔离环境（`env -u <VAR>` 或显式传 flag），不得依赖宿主未导出 RALPH_* 变量"
---

# 集成测试继承 dogfood 进程的 RALPH_* 环境变量，产生与代码无关的假失败

## 现象

2026-09-14 DEV-3 round 中，`-- Provider retry: status.json` 用例在 dogfood 环境（本 oneshot 的 shell）稳定失败：
`[FAIL] retry (status.json): retry_count=0, next_retry_at=null`。

同一用例在干净环境稳定通过。round 的其余用例不受影响，容易让人误判为"本次改动引入了 retry 回归"。

## 根因

- 本机 ralph runtime 给 oneshot 进程导出了 `RALPH_PROVIDER=claude`、`RALPH_LOOP_MAX_RETRY=0`、`RALPH_LOOP_MAX_ROUND=4`、`RALPH_LOOP_STALL_LIMIT=2`、`RALPH_LOOP_ROUND_TIMEOUT=900`、`RALPH_WORKSPACE=<repo>`。
- 该用例只传 `--provider fake` + `RALPH_LOOP_RETRY_SCHEDULE="5 5"`，把重试次数留给默认值（`RALPH_LOOP_MAX_RETRY` 默认 3）。
- `load_env` 的优先级契约让进程 env 覆盖 `.env` 与默认值 → 实际 `max_retry=0` → 第一轮失败后不再重试 → `retry_count` 永远为 0。
- 定位证据：同一份工作树，`env RALPH_LOOP_MAX_RETRY=0` 跑出 `retry_count=0`，`env -u RALPH_LOOP_MAX_RETRY` 跑出 `retry_count=1`；并用 `git archive HEAD` 的纯净副本复现失败，确认与本轮代码改动无关。

## 修复

- 本轮不修：这是测试宿主隔离问题，横跨全部依赖默认值的用例，按任务边界登记为 QA-2。
- DEV-3 的验证结论据此区分"环境阻塞的假失败"与"本轮改动引入的失败"，避免把假失败计入产物质量。

## 预防检查

- 类型：`automated-test`
- 位置：`scripts/integration-test.sh`（QA-2 实施后建议同时接入 `scripts/check.sh`）
- 通过标准：继承 RALPH_* 的环境与干净环境下完整集成测试结论一致（同为全绿）；出现差异即判失败。
- 适用范围：所有集成/端到端用例，尤其是断言 ralph 参数默认值的用例。

## 知识沉淀

- 保留在本记录：dogfood 宿主环境会向被验证系统注入 RALPH_* 变量，验证结果必须先排除该变量影响。
- 需要提炼到 skill：无（ralph skill 已要求区分环境阻塞与真实失败）。
- 需要提炼到 `.spec/`：无。
- 需要提炼到 `docs/`：无（本节即记录）。
- 需要提炼到脚本或测试：QA-2 —— 用例显式隔离继承的 RALPH_* 变量，并增加双环境一致性检查。

## 后续

- QA-2 实施后，把双环境一致性检查挂到 `scripts/check.sh` 或 CI 入口。
- 若后续新增依赖 ralph 默认值的用例，需同步补 `env -u` 隔离，否则同类假失败会重现。
