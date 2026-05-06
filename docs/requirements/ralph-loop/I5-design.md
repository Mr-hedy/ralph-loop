# I5 设计方案 — run / watch sticky 输出 + per-task round + env 重组

> 状态：已确认，待实施
> 创建：2026-05-05
> 角色：I5 启动前的设计锚点；实施过程如需改变稳定契约，应先更新需求或架构事实源
> 与 `I5-FINAL-TASK.md` 关系：I5 完成时 cp `.ralph/TASKS.md` 归档为 `I5-FINAL-TASK.md`，本文保留为启动前方案

## 背景与目标

- I4 已完成（Gemini adapter 接入），归档 `docs/requirements/ralph-loop/I4-FINAL-TASK.md`。
- 当前 REQ-024 / REQ-025 的 watch / run 输出契约只规定"单行 sticky bar + 逐行追加事件 marker"，信息密度低，长任务里观察 agent 状态不直观。
- 参考 `trantor-skills` 的 `cli/commands/build-watch.ts` 已实现的"上方滚动事件流 + 底部多行 sticky bar"双区域方案，用户判断 trantor 视觉密度 + 信息层次比 ralph 现状强很多，决定按相同心智模型重做 ralph 的 run / watch 样式。
- I5 同时承载几项配套重构：iter → round 改名（消歧 dogfood iteration 概念）、env 分组重命名（明确 provider/loop/ui 归属）、防死循环机制 per-task 化、`.ralph/.gitignore` 自包含。
- I5 不重做 run loop 的核心结构、TASKS 协议、provider adapter；只重做"输出层 + 防死循环逻辑 + 配置接口"。

## 关键决策（已对齐）

### 1. 总布局：10 行紧凑 sticky 块（仅 sticky 模式）

```
[HH:MM:SS] ralph 0.2 · tasks N/M · round 12 · provider claude · elapsed H:MM:SS    ← 顶栏（1 行）
─────────────────────────────────────────────────────────────────────────────────  ← 横线（1 行）
[ts] event 1                                                                        ┐
[ts] event 2                                                                        │
[ts] event 3                                                                        │ 事件流（6 行，可配置）
[ts] event 4                                                                        │
[ts] event 5                                                                        │
[ts] event 6                                                                        ┘
─────────────────────────────────────────────────────────────────────────────────  ← 横线（1 行）
● round 2/∞ · stall 1/5 · ⠹ HH:MM:SS · → DEV-1 任务名（动态截断，超长尾巴 ...）        ← 底栏（1 行）
```

- 总 **10 行紧凑块**：顶栏 1 + 横线 1 + 事件流 6 + 横线 1 + 底栏 1
- 事件流高度由 `RALPH_UI_STICKY_EVENT_LINES` 覆盖（默认 6），总块高度 = `EVENT_WINDOW + 4`
- **纯 append 模式**：不进 alternate screen、不 CLEAR、不设 ANSI scroll region
- 首帧顺序 print 10 行；后续帧用 `\033[<STICKY_LINES>A` 回到块顶 + 逐行 `\033[K` 重写
- 上方保留 shell 之前的内容；鼠标滚轮往上能看到跑 ralph 之前的 shell 历史
- 退出时不擦除——sticky 块 10 行作为命令输出留在屏幕上，shell prompt 在下方继续

### 2. 命令矩阵

ralph 主要使用场景是 **agent 调用 `ralph run`**，其次是**人类 watch**。命令设计按"默认行为匹配主要用户"原则：

| 命令 | 输出形态 | 主要用户 |
|------|---------|---------|
| `ralph run` | plain（追加式纯文本） | agent / CI |
| `ralph run -v` | sticky 三段式 10 行 | 人类（直接终端跑） |
| `ralph watch` | sticky 三段式 10 行（同 `run -v`） | 人类（另一个终端观察） |

`ralph watch -v` flag **删除**——watch 几乎只有人类用，没有 plain 需求；agent 不需要 watch 一个 run（它自己拿到 run 的 stdout）。

`ralph run -v` 和 `ralph watch` 共用同一套 sticky renderer。差异：
- 数据源：`run -v` 自驱动 + 自渲染；`watch` 被动读 `status.json` + tail `provider.stdout.log`
- 退出：`run -v` 跑完退出；`watch` 不退出，最后一帧持续刷新等 Ctrl+C
- 历史回放：`watch` attach 时只显示当前一帧（顶栏 + 事件区从 log tail 最近 N 条 + 底栏），不回放已结束 round 的总结行

**Ctrl+C 语义分流**（PLAN 阶段必须实现两套 trap 路径）：
- `ralph run -v` Ctrl+C → 中断当前 round + 写 exit_reason=interrupted + 退出
- `ralph watch` Ctrl+C → 仅退出 watch（不影响后台 run）

### 3. plain 模式（ralph run 默认 / 非 TTY fallback）

agent 通过 stdout 字节流消费输出，sticky 模式的 ANSI 控制码 + 高频刷新对 agent 是噪音 + context 浪费。`ralph run`（无 `-v`）默认走 plain 模式：

- 追加式纯文本，每行独立可 grep，无 ANSI 控制码（`NO_COLOR=1` 或非 TTY 时无颜色）
- **只打 ralph 自己的 marker**：启动 banner、round 启停、60s heartbeat、退出总结
- **不打 agent 内部事件**（tool / chat / thinking / error）——这些事件完整写在 `runs/<run_id>/rounds/round-NNN/provider.stdout.log`，main agent 排障时按需 `grep` / `tail` 精准取
- **无 spinner，无秒级 elapsed 刷新**——避免无信息变化刷屏 main agent context
- 长 round 期间每 60s 一行 heartbeat
- 输出形态示例（4 round / 9 分钟 run ≈ 15 行，详见根目录 `ralph-plain-poc.sh`）

**TTY 检测自动降级**：`ralph run -v` 但 stdout 不是 TTY → 自动 fallback plain，避免 log 文件被 ANSI 污染。`ralph watch` 同理。

判定逻辑：
```
use_sticky = is_tty(stdout) && [ -z "$NO_COLOR" ]
if cmd == "run":
    use_sticky = use_sticky && verbose_flag
elif cmd == "watch":
    use_sticky = use_sticky
```

### 4. 顶栏 / 底栏 / 事件区 字段

#### 顶栏（1 行）

```
[HH:MM:SS] ralph 0.2 · tasks N/M · round 12 · provider claude · elapsed H:MM:SS
```

- `[HH:MM:SS]`：ralph run 启动时刻，本地时间，无 +HHMM 后缀
- `ralph 0.2`：版本号（dim gray 弱化）
- `tasks N/M`：当前未勾 / 总任务数
- `round 12`：**整个 run 的全局 round 总数**（不带上限，全局无 max）
- `provider claude`：provider 名（不带 model；ralph 不可靠知道 CLI 默认 model）
- `elapsed H:MM:SS`：整个 run 运行时长，**小时进制**（>24h 继续累加，不进位天）
- 字段分隔符：`·` (U+00B7)
- 不放：`run_id`（太长去 `ralph status`）、`iteration_name`（dogfood 才有）、`model`、`workspace`、`state`

#### 底栏（1 行）

```
● round 2/∞ · stall 1/5 · ⠹ HH:MM:SS · → DEV-1 任务名（动态截断，超长尾巴 ...）
```

- `●` 健康灯（详见 §5）
- `round N/∞`：**当前 task 已用 round 数 / 单 task 上限**（`/∞` = 无限，来自 `RALPH_LOOP_MAX_ROUND`）
- `stall N/M`：**当前 task 连续无进展 round 数 / 上限**（来自 `RALPH_LOOP_STALL_LIMIT`，默认 5）；颜色变化：
  - 默认色：`stall 0/5` ~ `stall N/5`（N < limit-2）
  - AMBER（`\033[38;5;178m`）：接近上限（N >= limit-2 且 N < limit），如 `stall 3/5` / `stall 4/5`
  - RED：触发上限（N == limit），如 `stall 5/5`，会同步触发 HUMAN 自动插入和 exit blocked_by_human
- `⠹ HH:MM:SS`：Braille spinner（8 帧 200ms 一切）+ 当前 round 持续时间
- `→ DEV-1 任务名`：第一个未勾 task 的 ID + 描述，**动态按可见列宽截断**（中文字符按 2 列计算），超长尾巴用 `...`（不是 `…`）
- 不放 changed_files / last_event 等——保持简洁
- 窄终端降级顺序：任务名压缩 → 隐藏 spinner 秒数 → 只剩 `● round N/∞ · stall N/M`
- 底栏永远 1 行，绝不换行

#### 事件区（6 行硬限）

- tail -f 风格 append；新事件从底部冒，老事件被向上推
- 6 行硬限；超出 6 行的事件被卷出，**直接消失**（事件历史在 `provider.stdout.log` 完整保留）
- tool 事件单行：`[ts] 🔧 Edit lib/sticky.sh:142 (+3 -1)`
- chat 事件**截断到 `term_cols - 1`**，不允许换行
- 事件不足 6 个时前面用空行补齐保持高度稳定

### 5. 健康灯（三态）

| 字符颜色 | 触发条件 | 含义 |
|---------|---------|------|
| 🟢 绿 ● | `RALPH_UI_HEALTH_GREEN_SEC`（默认 60s）内 stdout 字节有变化 | healthy |
| 🟡 黄 ● | `GREEN_SEC` ~ `RED_SEC` 之间无变化 | idle（thinking 中常见，注意与底栏 stall 字段区分） |
| 🔴 红 ● | `RALPH_UI_HEALTH_RED_SEC`（默认 300s）+ 无变化 | critical（大概率卡了） |
| ✓ 绿 | exit_reason=done | run / round 完成 |
| ✗ 红 | exit_reason=provider_failed / timeout / blocked_by_human (max_round/stall 触发) | 失败 |
| ⏸ 黄 | exit_reason=interrupted | 暂停 |

健康灯**只看 `provider.stdout.log` 字节增长**（最便宜、不依赖 stream-json schema）。`RED_SEC` 不会主动 kill 进程，只是视觉警告。

`RALPH_LOOP_ROUND_TIMEOUT` 是另一回事——测的是 round 总执行时长（从启动算），触发会 **kill 进程** + exit_reason=timeout。两者关系：

| 变量 | 测什么 | 行为 | 默认 |
|------|-------|------|------|
| `RALPH_UI_HEALTH_RED_SEC` | 距离最后一次 stdout 变化的静默时长 | 仅视觉警告变红 | 300s |
| `RALPH_LOOP_ROUND_TIMEOUT` | 单 round 总执行时长 | 强制 kill 进程 | 0 (无限) |

推荐关系：`HEALTH_RED < ROUND_TIMEOUT`（先视觉预警再强杀）。README 中说明，不强制约束。

### 6. per-task round 计数

ralph 内部新增维护 `_RALPH_CURRENT_TASK_ID` + `_RALPH_CURRENT_TASK_TRY`：

每个 round 开始前：
- 解析 `.ralph/TASKS.md` 拿第一个未勾 task ID
- 与 `_RALPH_CURRENT_TASK_ID` 比较：
  - 相同 → `_RALPH_CURRENT_TASK_TRY += 1`
  - 不同（task 切换或勾完了）→ `_RALPH_CURRENT_TASK_ID = 新 ID`，`_RALPH_CURRENT_TASK_TRY = 1`

底栏的 `round N/∞` 显示 `_RALPH_CURRENT_TASK_TRY`。`∞` 来自 `RALPH_LOOP_MAX_ROUND`（默认 0=无限）。

全局 round 计数（即原 `iteration` 变量）保留，仍写 status.json，仍用于 stall 判断（per-task 化后含义见下）和顶栏 `round 12` 字段。

### 7. 防死循环：双保险 + 自动插 HUMAN

**机制 1：`RALPH_LOOP_MAX_ROUND`（单 task 硬上限，默认 0=无限）**
- 同一 task 试了 N 次（不管有没有进展）→ 触发
- 用途：agent 在改文件但就是不勾 task（反复重构同一处）

**机制 2：`RALPH_LOOP_STALL_LIMIT`（单 task 连续无进展上限，默认 5）**
- 同一 task 连续 N 次 round 都没勾 + 没改文件 → 触发
- 用途：agent 看到 task 完全不动手（task 描述太模糊）

**任一触发的处理**（统一）：

ralph 自动在 `.ralph/TASKS.md` 当前 task **前面**插入一行 HUMAN-N task，然后 `exit_reason=blocked_by_human` 退出：

```markdown
- [x] REQ-1
- [ ] HUMAN-1: DEV-1 卡住，请检查任务描述
  - 触发：DEV-1 连续 5 次 round 未完成（stall 5/5）
  - 已耗时：12:34
  - 建议：检查描述是否清晰 / 是否需要拆分 / 是否需要补充 context
  - 修复后：勾掉本行让 ralph run 继续
- [ ] DEV-1 实现 watch sticky bar 的多行布局逻辑
- [ ] QA-1
```

HUMAN task 的 name **简短**（一句话总结），结构化字段在缩进子项里。

修复路径：人工编辑 → 改 DEV-1 描述 → 勾掉 HUMAN-1 → 重跑 `ralph run`。

**不引入新 exit_reason**：复用现有 `blocked_by_human`。删除现有 `max_iterations` exit_reason（全局 max 取消）。

### 8. iter → round 改名（breaking，无 alias）

dev 阶段直接重构，不留兼容 alias。涉及面：

**用户可见层**：
- CLI flag：`--max-iter` → `--max-round`，`--timeout` → `--round-timeout`
- 文档 / UI 文案：所有 "iter" → "round"
- `status.json` / `result.json` / `meta.json` 字段：`iteration` → `round`，`iterations` → `rounds`
- 文件路径：`runs/<run_id>/iterations/iter-NNN/` → `runs/<run_id>/rounds/round-NNN/`

**内部实现层**：bash 函数 / 局部变量也随之改名（不留歧义代码）。

### 9. env 分组重命名

按 `provider_` / `loop_` / `ui_` / `internal` 四组：

| 分类 | 旧名 | 新名 | 默认 |
|------|------|------|------|
| **provider** | `RALPH_PROVIDER` | `RALPH_PROVIDER` | claude |
| | `RALPH_MODEL` | `RALPH_PROVIDER_MODEL` | (CLI 默认) |
| | `RALPH_EFFORT` | `RALPH_PROVIDER_EFFORT` | (CLI 默认) |
| | `RALPH_PROVIDER_CONFIG_DIR` | `RALPH_PROVIDER_CONFIG_DIR` | (provider 默认) |
| **loop** | `RALPH_MAX_ITER` | （删除，全局无 max） | — |
| | `RALPH_TIMEOUT` | `RALPH_LOOP_ROUND_TIMEOUT` | 0 |
| | `RALPH_STAGNATION_LIMIT` | `RALPH_LOOP_STALL_LIMIT` | 5 |
| | （新增） | `RALPH_LOOP_MAX_ROUND`（单 task） | 0 |
| **ui**（新组） | — | `RALPH_UI_STICKY_EVENT_LINES` | 6 |
| | — | `RALPH_UI_HEALTH_GREEN_SEC` | 60 |
| | — | `RALPH_UI_HEALTH_RED_SEC` | 300 |
| **internal**（不宣传） | `RALPH_VERBOSE` | `RALPH_VERBOSE` | 0 |

CLI flag 同步：`--max-round` / `--round-timeout` / `--stall-limit` 等。

### 10. flag / env 接口约定

**对外只暴露 flag，不主动宣传 env**：

| Flag | 说明 |
|------|------|
| `ralph run` | 默认 plain 模式 |
| `ralph run -v` / `--verbose` | 启用 sticky TUI（人类视图） |
| `ralph watch` | 始终 sticky TUI（无 flag） |
| `--max-round N` | 同 `RALPH_LOOP_MAX_ROUND` |
| `--round-timeout N` | 同 `RALPH_LOOP_ROUND_TIMEOUT` |
| `--stall-limit N` | 同 `RALPH_LOOP_STALL_LIMIT` |
| `--provider <name>` | 同 `RALPH_PROVIDER` |
| `--model <name>` | 同 `RALPH_PROVIDER_MODEL` |
| `--effort <level>` | 同 `RALPH_PROVIDER_EFFORT` |

env 是实现层的传值机制；用户在 `.env` 里写 env 仍然生效（`load_env` 会加载），但 README / 文档优先讲 flag。

理由：模式开关是"命令的一次性选择"，flag 自然贴合；env 在 `.env` 设过会"粘住"所有 `ralph run`，容易出意外。

### 11. `-v` 的实现层次（不影响 provider 调用）

`-v` 是**纯渲染层开关**，不改变 ralph 与 provider CLI 的调用契约：

| 维度 | 不开 -v | 开 -v |
|------|---------|-------|
| provider CLI 命令 | `claude --print < prompt` 等 | **完全相同** |
| stdout 重定向 | 写到 `round-NNN/provider.stdout.log` | **完全相同** |
| log 文件内容 | 完整 stream-json | **完全相同** |
| ralph 自己的 stdout/stderr | plain 追加 marker | sticky 三段式 TUI |
| 事件流数据源 | 不显示 | 后台 fork `tail -f log_path`，过滤 stream-json → marker 喂给事件区 |

事件源永远是 log 文件，`-v` 只决定要不要把这些事件实时拉出来渲染。

### 12. `.ralph/.gitignore` 自包含

ralph 是部署单元，`.ralph/` 自带 `.gitignore`，**用户工程根 `.gitignore` 不再需要管 ralph 内部**。

新建 `.ralph/.gitignore`：
```gitignore
# ralph 部署单元自带，cp -r .ralph 时跟随生效
runs/
lock
status.json
.env
```

工程根 `.gitignore` 删除现有的 4 行 `.ralph/*` 规则。

### 13. 实现技术（bash + cursor_up + stty + trap）

**进入 sticky 模式**（enter_layout）：
1. `stty -echo -icanon` noecho + cbreak（防误按破坏布局），保存原 stty
2. `\033[?25l` hide cursor

**渲染一帧**（render_frame）：
1. 刷新终端尺寸 `stty size`
2. 非首帧：保存光标 `\033[s` → `\033[<STICKY_LINES>A` 回块顶
3. 顺序 print：顶栏 + 横线 + 6 行事件（每行 `\033[K` + 内容） + 横线 + 底栏
4. 非首帧：恢复光标 `\033[u`

**退出**（cleanup，trap INT/TERM/EXIT 三处）：
1. 排空 stty buffer 中堆积的按键
2. 还原原 stty
3. `\033[?25h` show cursor + `\033[0m` reset 颜色
4. **不擦除 sticky 块**——保留作为命令输出，shell prompt 在下方继续

## 关键约束（物理事实）

### scrollback 行为

纯 append + cursor_up 重绘方案：
- **首次 render 之前的 shell 内容完整保留在 scrollback**——鼠标滚轮往上能看到之前的命令、ls 输出
- **sticky 块本身不进 scrollback**——每次 render 在屏幕原位重写，scrollback 不堆积重复
- **超出 6 行事件窗口的事件历史会丢失**——`EVENT_MESSAGES` 数组只保留最近 6 条
- 完整事件历史的权威源是 `runs/<run_id>/rounds/round-NNN/provider.stdout.log`

### bash 实现限制

- 不处理 `SIGWINCH` resize；窗口拉伸期间渲染可能错位，需要重启 ralph 命令
- spinner 200ms 由 `sleep 0.2` 驱动；终端忙时帧率下降不影响功能
- `stty -echo -icanon` 是 sticky 模式的硬要求，trap 三路径都要还原
- tmux / screen 嵌套下未充分验证（QA 任务覆盖）

## 影响 REQ / 文档（实施时同步）

- **REQ-024**（`ralph watch`）：删除 `-v / --verbose` flag；watch TTY 默认 = 三段式 sticky；非 TTY = 一行 watch bar 后 exit。删除"双区域 -v"和"2 秒固定刷新 interval"表述。
- **REQ-025**（`ralph run` 进度可见性）：plain 输出契约从"启动 banner + iter 启停 + 60s heartbeat + 退出总结"调整为"...+ round 启停 + ..."（iter→round 改名）；`-v` flag 行为变化为启动 sticky；非 TTY 自动降级 plain。
- **REQ-026**（双层时间）：保留。
- **新增 REQ：per-task 防死循环 + HUMAN 自动插入**：单 task max_round / stall 触发 → 自动插 HUMAN → exit blocked_by_human。
- **`.ralph/README.md`** 重写：
  - 环境变量表（按 provider/loop/ui 分组 + 默认 + 说明 + 示例）
  - 《Ralph loop 与 round》：解释 round ≠ task，per-task round 计数
  - 《防死循环机制》：max_round + stall + HUMAN 自动插入
  - 《agent 调用 ralph》：默认 plain 就是 agent 友好
  - 《sticky 模式异常退出救援》：`stty sane`
- **`docs/architecture/overview.md`**：同步三种调用形态 + sticky renderer 共用 + per-task round + iter→round 改名。
- **`docs/architecture/integrations.md` / `docs/architecture/security.md`**：检查是否提及旧字段（`iteration` / `RALPH_MAX_ITER`），同步改名。
- **`docs/architecture/testing.md`**：补 sticky 渲染测试策略 + plain 模式回归 + per-task round 边界测试。

## 范围

- 新增 `.ralph/lib/sticky.sh`（命名待 PLAN 拍）：三段式 sticky renderer，被 `run -v` 和 `watch` 共用
- 重写 `.ralph/lib/watch.sh`：TTY 走 sticky；非 TTY 一行 watch bar 后 exit；删除 `-v` flag
- 调整 `.ralph/lib/run.sh`：保留 plain 默认契约（iter→round 改名）；`-v` 启动 sticky；TTY 检测做 fallback；删除 60s heartbeat 逻辑（plain 保留，sticky 不需要）
- 新增 per-task round 计数 + HUMAN 自动插入逻辑
- 全量 iter → round 改名（lib / status.json schema / 文件路径 / CLI flag / env / 文档）
- env 分组重命名（lib + 文档同步）
- 新建 `.ralph/.gitignore` 自包含；工程根 `.gitignore` 删除 ralph 相关行
- `.ralph/README.md` 按新模板重写
- 同步 REQ-024 / REQ-025 / overview / testing / 新增 REQ
- 集成测试：
  - TTY mock：sticky 三段式渲染、健康灯三态、退出后保留 sticky 块
  - plain 模式回归（启动 banner / round marker / heartbeat / 退出总结）
  - `ralph run -v` 非 TTY 自动降级 plain
  - `ralph watch` 非 TTY 一行 bar exit
  - per-task round 边界：max_round 触发自动插 HUMAN、stall 触发自动插 HUMAN、task 切换归零
  - iter→round 改名后所有路径 / 字段 / flag 一致

## 非范围

- 不实现自适应事件区高度（resize 兼容）
- 不实现"鼠标滚轮翻 scrollback 看完整事件历史"
- 不改 status.json schema 的语义（只字段名 iter→round 改名）
- 不改 provider adapter 行为
- 不引入新字段进 status.json（健康灯由 sticky renderer 自己根据 stdout mtime 推导）

## 关键风险

- `stty -echo -icanon` 改 tty 状态，trap 不全（kill -9 / shell 强退）会留 tty 在 noecho；需测试所有异常退出路径都覆盖 stty 还原；README 给 `stty sane` 救援指南
- iter→round 改名是 **breaking change**：现有 `.ralph/runs/` 下旧目录结构（`iterations/iter-NNN/`）和新 ralph 不兼容；需评估"旧 run 目录怎么办"（保留可读 / 自动迁移 / 文档说明）
- env 分组改名同样 breaking：用户已写的 `.env` / shell export 失效；dev 阶段不留 alias，需 README 醒目提示
- 删除 `RALPH_MAX_ITER`（全局 max）改为 `RALPH_LOOP_MAX_ROUND`（per-task）：语义变了，原本设 `RALPH_MAX_ITER=20` 的用户改成 `RALPH_LOOP_MAX_ROUND=20` 后行为完全不同（per-task 上限）；需 release notes 强调
- HUMAN 自动插入会修改用户的 `.ralph/TASKS.md`：是 invasive 行为；需要确保只在明确触发时才动，且操作可逆（人工勾掉就好）
- cursor_up + 重绘在 tmux / screen 嵌套下未验证；spinner 帧率高时可能闪烁
- TTY 检测在某些诡异 CI runner 下可能误判；逃生口是不开 `-v`

## 验收口径（待 PLAN 阶段细化）

- `bash scripts/check.sh` 通过
- `bash scripts/integration-test.sh` 通过，含 sticky 渲染 / plain 回归 / per-task round 边界 / iter→round 改名一致性测试
- `git diff --check` 通过
- TTY 下 `ralph run -v` 和 `ralph watch` 视觉一致；非 TTY 退回逐行
- `ralph run` plain 输出 ≈ `ralph-plain-poc.sh` 的形态
- requirements / overview / `.ralph/README.md` / testing docs 字段名一致（无残留 `iter` / `RALPH_MAX_ITER`）
- 真实 provider smoke：跑 1 次 `ralph run -v --provider claude` 长任务，sticky 紧凑、健康灯反映状态、退出后 sticky 块保留可见
- 真实 plain smoke：跑 1 次 `ralph run`，输出 ≤ ~30 行（4-5 round），main agent grep 友好

## 待解决 / 未决（PLAN 阶段细化）

- **顶栏 `model` 字段**：当前不放（ralph 不知道 CLI 默认值）；如果 PLAN 引入 adapter 主动报告 model 名机制可重新加入
- **last 事件具体格式**：tool vs chat 截断方式细节
- **plain 模式 6 种 exit_reason 输出格式**：iter ✗/⏸ marker 行 + summary 块字段微调（last_error / blocked_at / stall 详情）按 exit_reason 分支；沿用 REQ-019 字段集
- **watch 历史回放**：当前决定不回放，但 attach 时是否打印一行 "attached to run X / round N" 表明定位？
- **多 run 并发场景**：一个 workspace 同时跑两个 `ralph run`（`locked` 阻挡），watch 在两个 run 之间切换的体验
- **PoC 入仓**：`ralph-sticky-poc.sh` 和 `ralph-plain-poc.sh` 决定保留作设计活文档，commit 进根目录
- **PoC 与决策的用词差异（已知）**：当前 `ralph-sticky-poc.sh` 底栏用 `round`（codex 改版本遗留）、`ralph-plain-poc.sh` 用 `iter`（旧版未同步），均与 I5 决策 `round` 不一致。视觉已验证 OK，用词在 DEV-1 全量改名时一并对齐。`ralph-sticky-poc.sh` 健康灯黄/红阈值当前 60/180，I5 决策为 60/300，DEV-3 实施 sticky.sh 时按决策值对齐
- **tmux / screen 兼容性 smoke**：QA 任务必须覆盖
- **旧 run 目录兼容**：`runs/<old_run>/iterations/iter-NNN/` 是否影响新版 ralph 读？建议：新 ralph 只读 `runs/<run>/rounds/`，旧目录保留可见但 `ralph status` 不展示
