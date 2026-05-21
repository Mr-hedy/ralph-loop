---
id: PM-0004
title: "Mock provider 集成通过但真实 provider 权限/信任边界不一致，发布前 smoke 才暴露"
status: active
domain: "release / provider integration"
severity: "high"
affected_modules:
  - ".ralph/lib/adapter-codex.sh"
  - ".ralph/lib/adapter-gemini.sh"
  - "scripts/integration-test.sh"
  - "docs/architecture/integrations.md"
  - "docs/requirements/ralph-loop/requirements.md"
linked_commits:
  - "pending release cleanup commit"
trigger_conditions:
  - "provider adapter 的命令参数涉及 sandbox、approval、trust 或 git 写权限"
  - "mock fixture 只断言参数形状或事件流，不执行真实 provider CLI"
  - "发布前才在新 workspace 用真实 provider 跑 cp -r 部署 smoke"
failure_pattern:
  - "mock provider happy path 全绿，但真实 provider 的 sandbox 不允许写 `.git/index.lock`，导致 ralph 的每轮 commit 契约失败"
  - "mock provider 没有建模新 workspace trust 行为，真实 Gemini CLI 在未跳过 trust 时把 yolo approval 降级回 default"
  - "把自动化集成测试通过误当成 release-ready，缺少真实 provider smoke 的环境和阻塞证据分层"
prevention_checks:
  - "发布前必须在临时 git workspace 执行真实 provider smoke：`cp -r .ralph/ <tmp>/.ralph/`，至少一条任务完成、产生 commit、`exit_reason=done`、`capture_status=ok`"
  - "adapter 修改 sandbox / approval / trust / session capture 时，mock 测试必须断言关键参数，同时真实 smoke 必须覆盖至少一个 commit 写入"
  - "真实 smoke 失败时先分类：产品缺陷、provider 认证缺失、本机环境缺失；只有产品缺陷修复后才能声明 release-ready"
---

# Mock provider 集成通过但真实 provider 权限/信任边界不一致，发布前 smoke 才暴露

## 现象

2026-05-20 发布回归时，自动化集成测试已全绿，但真实 provider smoke 发现两类 mock 未覆盖问题：

1. Codex 使用 `--sandbox workspace-write` 时，agent 能改 workspace 文件，但执行 `git add -A` 会失败，错误为无法创建 `.git/index.lock`，`Operation not permitted`。这直接破坏 ralph oneshot 协议的每轮 commit 契约。
2. Gemini 在新 workspace 下不带 `--skip-trust` 时，会把 `--approval-mode yolo` 降级为默认 approval。真实命令加上 `--skip-trust` 后不再出现 trust downgrade 警告，但本机 Gemini 认证未配置，完整 smoke 仍被 auth 阻塞。

## 根因

- mock fixture 证明了 Ralph 的 run loop、日志采集和 JSON/session 解析路径，但不能证明真实 provider 的权限模型、workspace trust 策略和认证前置条件。
- adapter 的 sandbox/approval 参数属于外部 CLI 稳定合约，不能只靠 mock 断言“传了某个 flag”来证明 release-ready。
- 发布收口前没有把“真实 provider smoke”列为必须完成的验证类型，导致 Codex 权限问题直到用户要求真实验证后才暴露。

## 修复

- Codex adapter 改为 `--sandbox danger-full-access`，因为 ralph 协议要求 provider 在每轮内执行 `git add -A && git commit`，真实 Codex CLI 的 `workspace-write` 不满足 `.git/` 写入需求。
- Gemini adapter 增加 `--skip-trust`，避免新 workspace trust 降级 approval mode。
- `scripts/integration-test.sh` 增加 mock 回归断言：Codex 必须收到 `danger-full-access`，Gemini 必须收到 `--skip-trust`。
- `docs/architecture/integrations.md` 和 `docs/requirements/ralph-loop/requirements.md` 同步记录真实 smoke 结论和命令契约。

## 预防检查

- 类型：`manual-check`
- 位置：release closeout / provider adapter 变更收口。
- 通过标准：
  - Claude / Codex / Gemini 分别在临时 git workspace 执行真实 smoke。
  - 每个可认证 provider 至少完成 1 条任务、写入目标文件、勾选任务、产生 commit、`result.json.exit_reason=done`。
  - round 目录存在 `provider.stdout.log`、provider native session 文件和 `session.history.log`；`meta.json.capture_status=ok`。
  - 对无法认证的 provider，必须记录具体 auth 阻塞，而不是记为通过。
- 适用范围：所有 provider adapter 命令参数、session capture、approval/sandbox/trust 策略、release readiness 判断。

---

- 类型：`automated-test`
- 位置：`scripts/integration-test.sh`
- 通过标准：
  - Codex happy path 断言 mock 收到 `--sandbox danger-full-access`。
  - Gemini happy path 断言 mock 收到 `--skip-trust`。
  - 三 provider mock happy path 仍产生 `capture_status=ok` 和 `session.history.log`。
- 适用范围：防止 adapter 命令参数静默回退。

## 知识沉淀

- 保留在本记录：真实 provider smoke 与 mock 集成测试之间的能力边界。
- 需要提炼到 skill：有，checkpoint/postmortem/task-loop 类收口流程必须区分 mock pass 与真实 release smoke；涉及 provider adapter 的 release 结论必须声明真实 smoke 状态。
- 需要提炼到 `.spec/`：暂不新增；当前 `.spec/rules/adversarial-review.md` 已要求不要把退出码 0 或日志误当端到端成功。
- 需要提炼到 `docs/`：已更新 integrations / requirements；`.ralph/README.md` 增加 provider 认证与命令使用说明。
- 需要提炼到脚本或测试：已更新 `scripts/integration-test.sh` 的关键参数断言；真实 smoke 仍保留为手工 release gate。

## 后续

- 配置本机 Gemini auth 后，重新执行 Gemini 真实 smoke，并把结果写入 release 验证结论。
- 若未来要完全自动化 release gate，需要新增独立脚本生成临时 workspace、复制 `.ralph/`、按 provider 跑真实 smoke；该脚本必须显式处理认证缺失为 blocked，而不是 failed/pass 混淆。
