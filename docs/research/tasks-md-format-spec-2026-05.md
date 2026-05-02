---
status: active
date: 2026-05-02
topic: TASKS.md 格式规范回溯——从无结构 sub-bullet 切到 7 字段结构化模板
audience: 本仓库 + agent-collab-kit 工程同步参考
---

# TASKS.md 格式规范回溯（2026-05）

## 背景

本仓库 `.ralph/TASKS.md` 在 v0.1 + I1 prep 阶段使用的是无结构 sub-bullet 模板：

```markdown
- [ ] DEV-1: 实现 ralph status plain text 输出（REQ-023 / SC-023-1, SC-023-3）
  - 新建 `.ralph/lib/status.sh`
  - 读 `.ralph/status.json`，渲染 15 字段 plain text
  - status.json 不存在时 stdout 输出"无运行" + exit 0
  - 在 `.ralph/bin/ralph` 加 status 子命令 dispatcher
```

每个任务下面是若干"实施 hints"。

I1 dogfood 第一次 `ralph run`（2026-05-01）暴露这种模板的多个缺陷，最终决定切换到结构化 7 字段模板，对齐 `agent-collab-kit/.ralph/TASKS.md` git 历史中已稳定使用的形态。

## 触发动机

### 1. 任务实施过程黑盒，agent 19 min 不可见

I1 dogfood iter-001 的 DEV-1（"实现 ralph status plain text 输出"）真实跑了 1134 秒（约 19 分钟）。期间用户从外部观察看不到任何进展信号——iter log 是 0 字节直到 oneshot 结束（Claude `--output-format json` 是单 JSON 一次性 dump）。

这反映了两层问题：
- **观察性层**（commit 3 修复）：run 主循环没有进度 marker；后续切到 stream-json + 加 `-v` flag
- **任务结构层**（本文件主题）：旧模板不强制 agent 在过程中追加"完成: ..."条目；过程不可观察是因为没有过程产物结构

agent-collab-kit 的模板要求 agent 每个阶段追加 `- 完成: <阶段产出>`，TASKS.md 自带阶段性 audit trail。dogfood 期间能从 TASKS.md 看到 agent 当前在哪个阶段。

### 2. 缺乏明确"这件事算什么时候做完"

旧模板的 sub-bullet 是混合的：有些是实施步骤，有些是范围，有些是验收点。agent 完成一些 sub-bullet 就勾掉，但不一定完整满足"成功标准"。

本仓库**核心原则之一是"Evidence over confidence"**——但模板本身没有 enforce 验证证据。

新模板用 7 字段强制：
- **预期 / 输入 / 范围 / 验证计划** 在任务开始前就写好（契约）
- **完成 / 验证 / 未验证** 在任务过程中追加（产物）
- "未验证" 必填，显式标注 residual risk

### 3. 已 done 任务字段无法分清"实施想法 vs 实际产物"

旧模板的 sub-bullet 同时承载实施 hints（"新建 .ralph/lib/status.sh"）和实际产物。任务勾掉之后，sub-bullet 还是当初的那些字。reviewer 不知道 agent 是否真的做了 sub-bullet 描述的所有事，还是部分做了部分跳过。

新模板把意图与产物**物理分离**：
- 预期/输入/范围/验证计划：任务开始前的契约，agent 不能后期改写
- 完成 / 验证 / 未验证：agent 实际产生的轨迹

## 决策

| 项 | 决策 | 备注 |
|---|---|---|
| 模板字段 | 7 字段（预期 / 输入 / 范围 / 验证计划 / 完成 / 验证 / 未验证） | 与 agent-collab-kit `.ralph/TASKS.md` git 历史中 c43b9e8 之后稳定形态对齐 |
| 字段必填性 | 全部必填；"未验证" 无残留时写 `None` | "未验证" 必填，对齐 "Evidence over confidence" 原则 |
| 已 done 任务 | 不回填新格式（保留历史） | I1 已完成的 DEV-1 ~ DEV-10 + QA-1/2 保留旧格式作为历史；新任务（HUMAN-1 + 后续）切新格式 |
| HUMAN-N 模板 | 上下文 / 选项 / 影响 / 答（待） / 答（YYYY-MM-DD）+ 落地 | 已有 PROMPT.md 内描述，本规范集中沉淀 |
| REVIEW-N 模板 | 两种用法（常规 vs escalation）互斥不可混用 | `| review` / `| adversarial-review` 后缀 vs `[blocked-by]` 前缀 |
| spec 落点 | `.spec/rules/tasks.md` | 与 requirements / solution / roadmap / review / testing 等并列；`.ralph/PROMPT.md` 路由到此 |
| 自修改规则归口 | 本规范集中描述，PROMPT.md 路由 | 避免双源不一致 |

## 与 agent-collab-kit 的 diff

本规范与 `agent-collab-kit/.ralph/TASKS.md` git 历史（截至 2026-05-02 commit `3db0d01`）的差异：

| 维度 | 本规范 | agent-collab-kit |
|---|---|---|
| 字段命名 | 预期 / 输入 / 范围 / 验证计划 / 完成 / 验证 / 未验证 | 同（一致） |
| 任务前缀 | 8 类（REQ/SOL/ROADMAP/PLAN/DEV/QA/REVIEW/HUMAN） | kit 当前未严格分类（多用 I<N> 编号 + 描述）|
| HUMAN-N 阻塞机制 | 工具层 hardcode + exit 7 + PROMPT.md 强约束 | kit 没有 ralph 工具层，无对应阻塞机制 |
| 启动校验前缀全大写 | exit 1 强约束 | 同上 |
| spec 落点 | `.spec/rules/tasks.md` | kit 通常通过 `template/.spec/rules/` 同步给 generated project |

## 同步建议（kit 工程拿去推进）

> 本仓库不动 kit 代码；以下建议供 user 拿到 agent-collab-kit 工程那边手动推进。

1. **新增 `template/.spec/rules/tasks.md`**：参考本仓库 `.spec/rules/tasks.md`，删去 ralph oneshot 相关段落（kit 没有 ralph 工具层），保留：
   - 文件结构（4 段）
   - 任务前缀（8 类，如果 kit 决定采纳）—— **可选项**，kit 可保留 I<N> 编号体系
   - 未完成 / 已完成模板（7 字段，与 kit 现状一致）
   - REVIEW-N 两种用法
   - 自修改规则
   - 归档约定（cp 至 `I<N>-FINAL-TASK.md`）

2. **更新 `template/AGENTS.md` 路由**：加 `tasks.md` 行到 `.spec/rules/` 路由表

3. **更新 `scripts/check-kit.mjs` / `scripts/check-project.mjs`**：加 `template/.spec/rules/tasks.md` 存在性检查 + 关键字段名（`预期`/`输入`/`范围`/`验证计划`/`完成`/`验证`/`未验证`）grep 检查

4. **决定是否引入 8 类前缀 + 启动校验**：kit 当前用 I<N> 编号，引入前缀需要权衡。建议：**不强引入**，因为 kit 是模板源，不强加于使用者；如使用者部署 ralph harness 后想要前缀强约束，可在 `.ralph/PROMPT.md` 单独定义（沿用 ralph-loop 模式）

## 实施记录

- `commit 5581001`（feat observability）：commit 3 of 5 batch；包含 progress markers 直接受益于本规范的"过程可见性"目标
- `commit ?`（feat tasks-spec）：本文件 + `.spec/rules/tasks.md` + HUMAN-1 reformat + PROMPT.md/CLAUDE.md/AGENTS.md 路由更新

## 风险与未验证

- **真实 dogfood 验证**：本规范在 ralph oneshot 内 agent 是否能稳定按 7 字段产出 / 追加"完成"条目，未实测；I1 完成后第二次 dogfood（I2）会是首次真实验证
- **过期模板共存**：I1 已完成任务用旧模板，新任务用新模板，TASKS.md 在归档前会有混合形态；归档为 `I1-FINAL-TASK.md` 后混合状态被冻结，不再问题
- **HUMAN-1 重写后效果**：HUMAN-1 当前用旧子 bullet 写法，本批次会重写为新 7 字段；agent 在解锁后能否按答案继续推进，待真实场景验证
