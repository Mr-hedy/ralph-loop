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

- [x] T1：实现 ralph run 骨架 + adapter 契约 + fake adapter。
  - 完成：`ralph run` 在 per-workspace 部署下运行主循环；fake adapter 五场景全实现；14 个集成用例（7 退出原因 + 6 启动校验 + api-error 变体）全通过。
  - 变更：`.ralph/lib/common.sh`（workspace 自定位、load_env、UUID、时间戳、run_id、lock、changed_files、JSON emit）、`.ralph/lib/tasks.sh`（parse_tasks / count_checked / count_total）、`.ralph/lib/session.sh`（meta.json 骨架 + 派生视图 stub）、`.ralph/lib/adapter-fake.sh`（五场景 + RALPH_PROVIDER_CLI）、`.ralph/lib/run.sh`（启动校验 → lock → 主循环 → 退出分派 → result.json）、`.ralph/bin/ralph`（run 路由 + flag 解析）、`scripts/integration-test.sh`（mock workspace + 14 用例）、`scripts/check.sh`（新 lib 文件 bash -n + integration-test 存在性）。
  - 验证：`bash scripts/check.sh` → pass；`bash scripts/integration-test.sh` → PASS=14 FAIL=0。
  - 注意：macOS 上 `kill -INT` 对等待子进程的 bash 无效（信号被 deferred）；interrupted 用例改用 `kill -TERM`，trap 同时处理 INT/TERM。`flock` 命令在 macOS 不可用，改用 noclobber + PID 文件锁。
  - 参考：`docs/requirements/ralph-loop/requirements.md`（REQ-001/002/005/006/008/009/010/011/012/013/015）、`docs/architecture/overview.md`（伪代码、CLI、运行目录、adapter 契约、退出原因、stagnation）、`docs/architecture/integrations.md`（provider 细节参考，T1 不落地真实 adapter）、`docs/architecture/security.md`（approval/sandbox 写死策略）、`docs/roadmap.md#t1-范围当前阶段`。
  - 范围：
    - `.ralph/bin/ralph`：增加 `run` 子命令路由；解析 CLI flag（`--provider` / `--model` / `--effort` / `--max-iter` / `--timeout`），按 `CLI flag > 进程 env > .env > 默认` 合并；`status` / `watch` 继续不实现。
    - `.ralph/lib/common.sh`：扩展 `.env` 逐行解析（只读 `RALPH_*`、剥离值两端引号、不 `source`）、workspace 自定位（`${BASH_SOURCE[0]}` → `..` → `..`）、UUID 生成 fallback（`uuidgen` → `/proc/sys/kernel/random/uuid` → `python3 -c uuid.uuid4()`；支持 `RALPH_UUID_FORCE_FAIL=1` 测试钩子）、ISO8601 时间戳、run_id 生成、`flock -xn` 封装、`git diff ∪ git status` 变更收集器（并过滤 `.ralph/`）、最小 JSON emit helpers。
    - `.ralph/lib/tasks.sh`：`parse_tasks`（正则 `^\s*-\s+\[([ xX])\]`）、`count_checked`、`count_total`；ralph 本身不修改 TASKS.md，解析输出仅供主循环判定。
    - `.ralph/lib/session.sh`：`meta.json` 读写骨架、`chat.log` / `tools.log` 派生视图 stub；fake 场景写 `capture_status=ok` + 空/占位派生视图即可。
    - `.ralph/lib/run.sh`：主循环（启动校验 → lock → run 目录 + context.json + status.json → 循环 → stagnation / max_iter / timeout / provider 退出判定 → result.json + TASKS.md 快照 → 释放 lock）；adapter 调用用 `rc=0; provider_oneshot ... || rc=$?` 捕获非零 rc，避免被 `set -euo pipefail` 中断；`trap` 捕获 `SIGINT` / `SIGTERM`，按当前阶段（lock 前 / lock 后）决定 `interrupted` 是否产生 run 目录。
    - `.ralph/lib/adapter-fake.sh`：三函数契约 + 载入后设置 `RALPH_PROVIDER_CLI="${RALPH_FAKE_CLI:-bash}"` 供启动校验 `command -v` 使用；`RALPH_FAKE_SCENARIO` 选场景：
      - `happy`：勾选第 1 条未勾选任务（修改使用者 TASKS.md 原地替换一条 `- [ ]` → `- [x]`），`exit=0`；多轮仍可用以驱动 `done` / `max_iterations`。
      - `stagnation`：不改 TASKS.md、不改 git，`exit=0`，连续空转；用于 `stagnated`。
      - `crash`：`exit=非零`，无结构化错误；`provider_diagnose` 归类 `unknown`；用于 `provider_failed`。
      - `api-error`：`exit=非零` + stderr 含 `api` 错误关键字；`provider_diagnose` 归类 `api`；仍走 `provider_failed` 路径（配合 `error.type=api` 断言）。
      - `slow`：`sleep` 远超 `--timeout`；用于 `timeout`（如 `RALPH_FAKE_SLEEP=5` + `--timeout=1`）。
    - `scripts/integration-test.sh`：在临时目录搭建 mock workspace（复制或软链 `.ralph/bin/` + `.ralph/lib/`，写 `.ralph/PROMPT.md` / `TASKS.md` / `.env`，`git init` + 首轮 commit），按 13 个用例逐一执行并断言：
      - 退出原因（7）：
        - `done` → `happy` + 单条 TASK
        - `provider_failed` → `crash`（另加 `api-error` 变体用例断言 `result.json.last_error.type=api`）
        - `timeout` → `slow` + `--timeout=1`
        - `max_iterations` → `happy` + `--max-iter=1` + TASKS 两条
        - `stagnated` → `stagnation`（`--max-iter=0` 默认，`stagnation_limit=5`）
        - `locked` → 后台起一个持有 lock 的 ralph（或 `flock` 占位脚本），再调 `ralph run`
        - `interrupted` → 后台跑 `slow` + 外部 `kill -INT`（仅覆盖 lock 获取后分支；lock 前分支列为可观察风险）
      - 启动校验失败（6）：缺 `PROMPT.md` / 缺 `TASKS.md` / 缺 `.env`（或 `RALPH_PROVIDER` 空） / 非 git 仓库 / `RALPH_FAKE_CLI=__nonexistent-xxx__` 触发 `command -v` 失败 / `RALPH_PROVIDER=claude` + `RALPH_UUID_FORCE_FAIL=1` 触发三路 UUID 校验失败。
      - 每用例断言：
        - 启动校验用例：stderr 前缀 `ralph: startup check failed:`（run.sh 写死的固定前缀），非零退出码，`.ralph/runs/` 无新增目录。
        - 退出原因用例：`result.json.exit_reason` 匹配预期；`locked` 和 lock 前 `interrupted` 无 `result.json`、无 run 目录；其余 6 个有 run 目录 + `result.json`。
  - 不做：任何真实 provider 实现（T2-T4）、`status` / `watch` 子命令（T5）、PROMPT/TASKS 模板生成、skill 封装。
  - 实施步骤（建议顺序，自下而上堆契约）：
    1. `common.sh` 基础扩展：workspace 自定位、`load_env`、UUID 生成（含 `RALPH_UUID_FORCE_FAIL`）、时间戳、run_id。
    2. `common.sh` 运行时扩展：`flock` 封装、`changed_files` 收集、最小 JSON emit。
    3. `tasks.sh`：`parse_tasks` / `count_checked` / `count_total`，单测（可内联到 `scripts/check.sh` 或 integration-test.sh 里用桩样本跑）。
    4. `session.sh`：`meta.json` 读写骨架、派生视图 stub。
    5. `adapter-fake.sh`：五场景 + `RALPH_PROVIDER_CLI` 暴露。
    6. `run.sh`：启动校验（固定 stderr 前缀） → lock → 主循环 → 退出分派 → result.json。
    7. `.ralph/bin/ralph`：`run` 路由 + flag 解析 + 优先级合并。
    8. `scripts/integration-test.sh`：mock workspace helper + 13 用例 + 汇总退出码。
    9. `scripts/check.sh` 补充：对新 lib 文件 `bash -n`、对 `scripts/integration-test.sh` 存在性断言。
  - 验证计划：
    - `bash scripts/check.sh`
    - `bash scripts/integration-test.sh`（13 用例逐一断言 `exit_reason` / run 目录 / `result.json` / stderr 前缀）
    - 若本机无法可靠模拟某个子场景（例如 lock 获取前的 `interrupted` 竞争窗口），在完成说明里列出并纳入可观察风险。
