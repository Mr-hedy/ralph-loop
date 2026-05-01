# I1 设计方案 — Dogfood T5（Status + Watch 真实功能）

> 状态：已确认，待实施
> 创建：2026-04-30
> 角色：I1 启动前的设计方案锚点；本文不可变，实施过程不修改
> 与 `I1-FINAL-TASK.md` 关系：I1 完成时 cp `.ralph/TASKS.md` 归档为 `I1-FINAL-TASK.md`，不替换本文档；本文是"启动前"，归档是"完成后"，并存

## 背景与目标

- **v0.1 已发布**（2026-04-28，version `0.1.0`），T6 全部子任务闭环
- 候选下阶段任务：T3（Codex adapter）/ T4（Gemini adapter）/ T5（status + watch 真实功能）/ T7（skill 封装）
- **用户决策（2026-04-30）**：用 ralph-loop 工具自身执行后续开发（dogfood），实战验证 + 边用边修；首批 dogfood 任务选 T5（工程能力闭环优先于 provider 能力补充）
- I1 启动前需要把 `.ralph/PROMPT.md` / `.ralph/TASKS.md` / ralph 工具内核做几项扩展，让 ralph 适合 dogfood

## 命名约定

- **Phase / Iteration（同义）**：roadmap 的最小规划单位 = 一次迭代 = 一次归档单元，编号 `I1`/`I2`/`I3`...
- **Release / Version**：多个 iteration 组成的发布单元，例如 `v0.1`（= T0+T1+T2+T6 集合）/ `v0.2`（含 I1 dogfood T5）
- **历史 T0-T7**：v0.1 的历史命名，保留不动；新阶段统一用 `I` 前缀，dogfood T5 = **I1**
- 不引入双编号体系（之前讨论的 `T` + `I` 双轨被废弃，简化为单一 `I`）

## 核心决策

### 1. 任务类型扩展（7 类前缀）

`.ralph/PROMPT.md` 引入任务类型前缀，决定本轮 agent 的 mindset 和参考的 `.spec/` 规范段。**ralph 工具内核不解析前缀**，前缀只是 agent 自检入口（"看到 REQ-N → 读 `.spec/rules/requirements.md`"）。

| 前缀 | mindset | 必读 spec | 主要产出 |
|------|---------|-----------|---------|
| `REQ-N` | 需求澄清 | `.spec/rules/requirements.md` | `docs/requirements/<module>/requirements.md` |
| `SOL-N` | 方案决策（存在真实取舍时） | `.spec/rules/solution.md` | requirements/architecture/任务事实源对应章节 |
| `PLAN-N` | 迭代规划 | `.spec/rules/roadmap.md` | `docs/roadmap.md` |
| `TASK-N` | 任务拆解 | `.spec/README.md` 阶段 4 | `.ralph/TASKS.md` 后续追加 |
| (空) / `DEV-N` | 开发实施（默认） | `CLAUDE.md` + 代码事实 | 代码 / 文档 / 提示词 / 论文等任何"按已确认需求/方案产出具体交付物"的工作 |
| `QA-N` | 测试设计与实施 | `.spec/rules/testing.md` | `docs/architecture/testing.md` + 测试代码 |
| `REVIEW-N` | 审查 | `.spec/rules/review.md` 或 `.spec/rules/adversarial-review.md` | findings / 事实源修订 |

**约定细节**：

- 默认无前缀视为 `DEV-N`，向后兼容
- 任务类型按需选用，不强求每次都用；简单 dogfood 任务可能就一路 `DEV-N`
- DEV 涵盖文字类工作（文档、提示词、论文）；任务描述里写清楚要做什么即可
- REVIEW 不拆 review 和 adversarial-review；任务描述第一行明确审查模式：`REVIEW-N: <对象> | review` 或 `REVIEW-N: <对象> | adversarial-review`
- 简单需求允许 ralph 跑全流程（REQ → SOL → TASK → DEV → QA → REVIEW 串行任务）；复杂或决策密度高的需求建议在 Claude Code 对话里完成 REQ/SOL/PLAN/TASK，ralph 只跑 DEV/QA/REVIEW

### 2. HUMAN-N 阻塞机制

**触发场景**：agent 在任意任务类型执行中遇到**自己无法独立决策**的情况：
- 需求层歧义、自相矛盾、缺关键边界条件
- 方案层多个取舍但 spec/docs 里没有判据
- DEV/QA 阶段发现需求文档隐含矛盾

**Agent 行为**（写进 `.ralph/PROMPT.md`）：

1. 在当前 blocked 任务**上方**插入 `- [ ] HUMAN-N: <问题描述>`，含上下文/选项/影响
2. 在 blocked 任务后追加 `→ BLOCKED by HUMAN-N`，**保留 `- [ ]`**（不勾不删）
3. `git add -A && git commit && exit`（自然结束本轮）

**Agent 约束**（PROMPT.md 内强约束）：

- ralph oneshot 内 **不得勾 `[x]` HUMAN-N 任务**（这是人类的动作）
- ralph oneshot 内 **不得执行 HUMAN-N 任务的内容**（HUMAN-N 是给人类的）
- 普通 Claude Code 对话里 PROMPT.md 不被加载，没有这条约束 — 人类主导对话时，agent 可勾掉 HUMAN-N（这是分层约束自然成立）

**ralph 工具层动作**：

- 每轮启动前扫描 `.ralph/TASKS.md` 第一个 `- [ ]` 任务前缀是否 `HUMAN-`，是 → **不启动 oneshot**，直接 exit code 4
- 新 exit reason `blocked_by_human`（exit code 4，优先级高于 done）

**人类侧解锁**：

- Claude Code 对话里和 agent 协作得出共识
- 把答案落到对应 docs（需求归 requirements，架构归 architecture）
- HUMAN-N 任务描述末尾追加 `答（<日期>）: <答案摘要>，落地: <docs 路径>`
- 把 HUMAN-N 改 `[x]`，commit
- 重跑 `ralph run`，agent 回到原 blocked 任务，按答案继续

**Escalation 路径 A（REVIEW 任务）**：

agent 任务遇到阻塞但**在 ralph loop 内可由其他 role 解决**（例如 DEV 发现需求文档表述不精确，可由 REQ 修订），不走 HUMAN-N，而是：

1. 保持当前任务 `- [ ]`（不勾）
2. 在当前任务**上方**插入 `- [ ] REVIEW-N [blocked-by <当前任务>]: <一句问题陈述>`
3. exit
4. 下轮 agent pick REVIEW，settles 后当前任务 retry

**A vs B 判据**：能不能在 ralph loop 内不引入外部信息就解决。能 → 路径 A；不能 → 路径 B（HUMAN-N）。拿不准时走 B（宁可停一次）。

### 3. TASKS.md 自描述策略（取消 SUMMARY）

**不引入** `.ralph/SUMMARY.md` 或 `.ralph/summaries/` 目录。理由：

- 任务进度、阻塞点、HUMAN 答案沉淀都已在 `.ralph/TASKS.md` 里
- exit_reason、commits 等元数据在 `.ralph/runs/<run_id>/status.json` 里
- 接力建议是基于 exit_reason 的模板化输出，ralph 退出时直接终端打印即可
- 增加 SUMMARY 等于维护重复信息，违反单一事实源原则

**TASKS.md 自描述要承担的内容**（四段结构）：

```markdown
# Tasks

> 当前迭代: I1
> 关联 roadmap: T5（dogfood Status + Watch 真实功能）
> 起始: 2026-04-30

## 当前有效结论
（沉淀本迭代关键决策，含 HUMAN 任务的最终答案摘要）
- ralph status 默认输出 JSON（HUMAN-1 已答 2026-04-30，详见 requirements REQ-XXX）

## 规则
- 顶层 - [ ] 是未完成任务，- [x] 是已完成
- HUMAN-N 任务在 ralph oneshot 内不可勾选
- ...

## 当前任务
- [x] DEV-1: ...
- [x] HUMAN-1: 确认 status 输出格式
  - 答（2026-04-30）：默认 JSON，--text 切换为 plain text
  - 落地：docs/requirements/ralph-loop/requirements.md REQ-XXX
- [ ] DEV-2: ...
- [ ] HUMAN-2: ...  → BLOCKED 等待中
  - 上下文：...
  - 选项：...
```

### 4. Iteration 归档约定

**触发时机**：iteration 完成（`ralph run` 退出 `exit_reason=done` + 所有任务 `[x]`）

**归档动作**（人类执行）：

```bash
cp .ralph/TASKS.md docs/requirements/<module>/I<N>-FINAL-TASK.md
# 清空 .ralph/TASKS.md 当前任务段，"当前迭代"改为下一个 iteration
git commit
```

**归档原则**：

- 归档物是 `.ralph/TASKS.md` 本身（含所有 `[x]` 状态、HUMAN 任务最终答案、决策记录），自包含
- 不维护 SUMMARY；TASKS.md 已经是完整事实
- I<N>-FINAL-TASK.md 不可变，归档后不再修改
- 同 iteration 不再分子文件（`T5.1-tasks.md` 这种是 task 维度，归到 phase 归档里）

**roadmap.md 同步**：iteration 完成行加引用：

```markdown
| I1 dogfood T5 | 已完成 (2026-XX-XX) | docs/requirements/ralph-loop/I1-FINAL-TASK.md |
```

### 5. T → I 命名迁移（保留历史方案）

- v0.1 历史 `T0-T7` 命名 **保留不动**（task.md / roadmap.md / checkpoints / commit messages）
- root `task.md` 顶部加封版 banner（"v0.1.0 已封版，本仓库切换到 .ralph/TASKS.md，本文件保留作为 v0.1 历史归档"）
- v0.1 整体作为一次 release，**不重新归档** — `task.md` 封版即作为 release-level 归档
- 新阶段从 **I1** 开始（dogfood T5），新约定从 I1 起严格生效

### 6. `.ralph/` 目录最终形态

```
.ralph/
├── bin/
│   └── ralph                # CLI 入口
├── lib/
│   ├── common.sh            # 通用函数
│   ├── run.sh               # ralph run 主循环
│   ├── tasks.sh             # TASKS 解析 + HUMAN-N 扫描（扩展）
│   ├── session.sh           # provider session 采集
│   ├── adapter-fake.sh      # fake provider
│   ├── adapter-claude.sh    # Claude adapter
│   ├── adapter-codex.sh     # 未来 T3
│   └── adapter-gemini.sh    # 未来 T4
├── PROMPT.md                # 循环协议（每轮 system prompt）✓ 入仓
├── TASKS.md                 # 当前任务事实源 ✓ 入仓
├── TASKS.bak                # hello world demo 样例参考 ✓ 入仓
├── runs/                    # 每 run 临时证据 ✗ gitignore
│   └── <run_id>/
│       ├── context.json
│       ├── status.json
│       ├── stdout.log / stderr.log / chat.log / tools.log
│       └── iterations/iter-NNN/{meta.json, prompt.txt}
├── lock                     # 运行时锁 ✗ gitignore
├── status.json              # 当前状态（含 current_iteration 指针）✗ gitignore
└── .env                     # 私有配置 ✗ gitignore
```

**入仓边界判据**：跨 run 持久 + 项目核心契约 → 入仓；运行时临时产物 + 私有配置 → gitignore。

### 7. `docs/` 目录形态（与归档约定相关部分）

```
docs/
├── README.md
├── requirements.md
├── requirements/
│   └── ralph-loop/
│       ├── requirements.md           # 长期演进的需求事实源
│       ├── I1-design.md              # 本文档（I1 启动前方案锚点）
│       ├── I1-FINAL-TASK.md          # I1 完成后归档（cp from TASKS.md）
│       └── I2-FINAL-TASK.md          # 未来
├── architecture/
│   ├── overview.md                   # 加 Iteration 协议段
│   ├── integrations.md
│   ├── security.md
│   └── testing.md
├── checkpoints/
├── postmortems/
├── collaboration/
└── roadmap.md
```

### 8. PROMPT.md 重构（去样板自我矮化）

**问题**：当前 `.ralph/PROMPT.md` 头尾注释把自己定位成"参考样板，随 cp -r 部署"，是自我矮化 — 它就是 ralph 内核循环协议本身，本仓库自己用、使用者 cp 部署后也直接用，不存在"样板/实例"二分。

**动作**：去掉头尾"参考样板"注释，PROMPT.md 直接作为通用循环协议存在。同样处理 `.ralph/TASKS.md` 头部注释。

### 9. ralph 工具内核扩展（v0.1.1 增量）

**新增功能**：

1. HUMAN-N 扫描 + exit code 4（`blocked_by_human`）
2. 退出时终端格式化打印（exit_reason / iteration / 完成任务 / 阻塞点 / 接力提示）
3. status.json 字段扩展：`current_iteration` / `blocked_by` / `completed_this_run`
4. 集成测试 2-3 用例（HUMAN 任务存在 → exit 4；HUMAN [x] 后正常进入下一轮；终端打印格式快照）

**不做**：

- 不引入 SUMMARY 生成逻辑（决策 3）
- 不引入 questions/open|answered 目录（HUMAN-N 用 TASKS.md 内表达）
- 不引入多 role 系统的解析逻辑（任务前缀只是 prompt 层约定，工具不解析）

**版本号**：v0.1.0 → v0.1.1（非破坏性增量功能，未改动现有 exit reason 含义）

## 实施路径（7 步）

按依赖顺序：

1. **重写 `.ralph/PROMPT.md`**：去样板注释 + 7 类任务前缀 + HUMAN-N 触发 + agent 行为约束 + Escalation 路径 A
2. **重写 `.ralph/TASKS.md`**：去样板注释 + 四段结构 + 顶部"当前迭代: I1"声明 + 当前任务暂留空骨架
3. **hello world demo 挪 `.ralph/TASKS.bak`**
4. **ralph 内核改动**（v0.1.1）：HUMAN-N 扫描 + exit code 4 + 退出终端打印 + status.json 字段扩展 + 集成测试
5. **更新 `CLAUDE.md`**：去样板段 + 任务类型路由 + iteration 归档约定
6. **`task.md` 封版** + roadmap.md T→I 迁移说明
7. **更新 `.spec/rules/roadmap.md` + README + requirements.md + architecture/overview.md**：归档约定规则、exit reason 8 种、新 REQ 条目、Iteration 协议段

第 1-3 步一批 commit；第 4 步单独 commit（动内核 + 集成测试）；第 5-7 收尾批次。

## 验证标准（I1 启动就绪）

- 1-7 步全部完成
- `bash scripts/check.sh` 通过
- `bash scripts/integration-test.sh` 通过（含新增 HUMAN-N 用例）
- ralph 工具版本号 0.1.1
- `.ralph/PROMPT.md` 不再含"参考样板"自我矮化注释
- `.ralph/TASKS.md` 顶部声明 `当前迭代: I1`
- root `task.md` 顶部有封版 banner

## 对 agent-collab-kit 的同步建议

ralph-loop 和 agent-collab-kit 是两个独立工程。ralph-loop 这边的工作不擅自动 kit 工程的代码。下面列出本轮决策中需要 kit 同步的部分，**由用户拿去 kit 工程那边推进**。

| 决策 | kit 同步动作 |
|------|-------------|
| 7 类任务前缀 + `.spec/` 路由 | `template/.ralph/PROMPT.md` 加任务类型段；`template/AGENTS.md` 加路由 |
| HUMAN-N 触发条件 + agent 行为约束 | `template/.ralph/PROMPT.md` 加 HUMAN-N 段（agent 行为 + 不勾不执行约束） |
| Escalation 路径 A（REVIEW 任务） | `template/.ralph/PROMPT.md` 加 Escalation 段 |
| TASKS.md 四段结构 + 顶部声明"当前迭代" | `template/.ralph/TASKS.md` 改结构 |
| Iteration 归档约定（cp TASKS → `I<N>-FINAL-TASK.md`） | `template/.spec/rules/roadmap.md` + `template/AGENTS.md` 加归档动作 |
| Generated check 脚本同步 | `scripts/check-kit.mjs` / `scripts/check-project.mjs` 加对应文本契约检查 |

**kit 不动**（这些是 ralph 工具能力，kit 只透传部署单元）：

- HUMAN-N 工具层（exit code 4 + 退出打印 + status.json 字段）
- T→I 迁移（kit 用 P0/P1 体系，不强制 T→I）
- 取消 SUMMARY 设计（kit 本来就没引入过 SUMMARY）

## 已知风险与未验证点

- **HUMAN-N 命名**：选择 `HUMAN-N`，含义清楚（"等人类"）；如 dogfood 中发现命名不顺，可在 v0.1.x 内迁移
- **Iteration 范围识别走 TASKS.md 顶部声明**：依赖人类切换 iteration 时改 TASKS.md + commit；如 dogfood 中发现误判频繁，再考虑加 `--iteration` 显式参数
- **Escalation 路径 A（REVIEW 任务）是 prompt 层约定**：ralph 工具不解析 REVIEW-N，靠 agent 自觉走流程；如 agent 误用导致死循环，需要在集成测试或 stagnation 边界覆盖
- **kit 同步的时机**：本方案不强制 kit 同步顺序；用户在 dogfood I1 验证完毕后再推进 kit 同步更稳妥（避免 kit 提前同步未验证设计）

## 与既有事实源的分布

本文档是**集中方案**（A 路径）。决策内容分散落到事实源（B 路径）按以下分配：

| 内容 | 落地位置 | 何时落地 |
|------|---------|---------|
| ralph 能力扩展（HUMAN-N、退出打印、status.json 字段、任务类型路由） | `docs/requirements/ralph-loop/requirements.md` 追加 REQ 条目 | 实施 task 5（ralph 内核）时 |
| Iteration 协议（命名、归档动作、退出原因 8 种、HUMAN-N 触发条件） | `docs/architecture/overview.md` 新增"Iteration 协议"段 | 实施 task 7（架构同步）时 |
| 任务源切换（root task.md 封版 + .ralph/TASKS.md 启用） | `CLAUDE.md` + `task.md` 顶部 banner | 实施 task 6 时 |
| T→I 命名迁移说明 | `docs/roadmap.md` 顶部映射注释 | 实施 task 7 时 |
| 归档动作规范 | `.spec/rules/roadmap.md` 加段 | 实施 task 8 时 |
| 退出原因 8 种 + 归档约定简介 | `README.md` | 实施 task 8 时 |
