# ralph-loop 开发任务

> 当前工程的开发任务事实源。工具实现位于 `.ralph/bin/` 和 `.ralph/lib/`；使用者 workspace 的 `.ralph/TASKS.md` 是运行时任务源，不与本文件混淆，也不入本仓库。

## 规则

- 顶层 `- [ ]` 是未完成任务，顶层 `- [x]` 是已完成任务。
- 只有完成实现并完成匹配验证后，才能勾选任务。
- 阻塞时保持未勾选，并写明 `阻塞` 或 `需要决策`。
- 不记录需求澄清、方案备选、rejected designs 或会话流水（见 `docs/requirements/ralph-loop/requirements.md` 和 `docs/architecture/overview.md`）。
- 本文件只排**当前阶段**的任务；后续阶段在 `docs/roadmap.md` 规划，不提前写入。

## 当前任务

- [x] 完成 ralph-loop v0.1 需求澄清并固化产物。
  - 完成：`docs/requirements.md` 承载项目级目标和跨模块约束、`docs/requirements/ralph-loop/requirements.md` 承载 REQ-001 ~ REQ-016、`docs/architecture/overview.md` 承载 CLI 契约和方案取舍、`docs/architecture/integrations.md` 承载三家 provider 集成细节、`docs/architecture/security.md` 承载 approval/sandbox 与 secrets 边界、`docs/roadmap.md` 按 T1→T7 划分、`task.md` 只留 T1 当前任务。
  - 变更：`docs/requirements.md`、`docs/requirements/ralph-loop/requirements.md`、`docs/architecture/overview.md`、`docs/architecture/integrations.md`、`docs/architecture/security.md`、`docs/roadmap.md`、`task.md`。
  - 验证：`bash scripts/check.sh` 通过。

- [ ] T1：实现 ralph run 骨架 + adapter 契约 + fake adapter。
  - 预期：`ralph run` 能在 per-workspace 部署下运行主循环，通过 fake adapter 跑通 `done` / `stagnated` / `provider_failed` / `locked` / 启动校验失败的集成测试。
  - 参考：`docs/requirements/ralph-loop/requirements.md`（REQ-001/002/005/006/008/009/010/011/012/013/015）、`docs/architecture/overview.md`（伪代码、CLI、运行目录、adapter 契约、退出原因、stagnation）、`docs/architecture/integrations.md`（provider 细节参考，T1 不落地真实 adapter）、`docs/architecture/security.md`（approval/sandbox 写死策略）、`docs/roadmap.md#t1-范围当前阶段`。
  - 范围：
    - `.ralph/bin/ralph` 增加 `run` 子命令路由；`status` / `watch` 继续不实现
    - `.ralph/lib/common.sh`：扩展 `.env` 解析（只读 `RALPH_*`、不 `source`）、workspace 自定位（`${BASH_SOURCE[0]}` → `..` → `..`）、UUID 生成 fallback、lock 获取释放（`flock`）、`git diff ∪ git status` 收集器
    - `.ralph/lib/tasks.sh`：parse_tasks（`^\s*-\s+\[([ xX])\]`）、count_checked、check_by_line
    - `.ralph/lib/session.sh`：meta.json 读写、派生视图骨架（fake 场景走空实现）
    - `.ralph/lib/run.sh`：主循环（启动校验 → lock → run 目录 → 循环 → 退出原因 → result.json + TASKS.md 快照）
    - `.ralph/lib/adapter-fake.sh`：三函数契约；`RALPH_FAKE_SCENARIO` 选场景（happy / api-error / stagnation / crash）
    - 集成测试脚本：在 `.ralph/lib/` 外新建 `scripts/integration-test.sh`（或类似入口），逐用例覆盖以下 13 个用例：
      - 退出原因（7 个）：`done` / `provider_failed` / `timeout` / `max_iterations` / `stagnated` / `locked` / `interrupted`
      - 启动校验失败（6 个）：缺 `PROMPT.md` / 缺 `TASKS.md` / 缺 `.env`（或 `RALPH_PROVIDER` 空） / 非 git 仓库 / provider CLI 不可执行（fake adapter 的 `command -v` mock）/ Claude UUID 三路全失败（仅 `RALPH_PROVIDER=claude` 路径）
      - 每个用例断言：`exit_reason`（或启动校验时的 stderr 前缀）、`.ralph/runs/` 是否产生 run 目录、`result.json` 是否存在
      - `adapter-fake.sh` 的 `RALPH_FAKE_SCENARIO` 场景对照：`happy` → `done`；`api-error` → `provider_failed`；`stagnation` → `stagnated`；`crash` → `provider_failed`（非 0 退出码路径）
  - 不做：任何真实 provider 实现（T2-T4）、`status` / `watch` 子命令（T5）、PROMPT/TASKS 模板生成、skill 封装
  - 验证计划：
    - `bash scripts/check.sh`
    - `bash scripts/integration-test.sh`（覆盖上述用例，需明确记录每个用例的预期 `exit_reason` 和产物断言）
    - 若本机无法真实跑 fake adapter 的个别子场景（例如 stale lock 清理），明确列在完成说明里
