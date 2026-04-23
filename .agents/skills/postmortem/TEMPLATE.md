---
id: PM-0001
title: "<简短标题>"
status: active
domain: "<domain>"
severity: "<low|medium|high|critical>"
affected_modules:
  - "<module>"
linked_commits:
  - "<commit-sha-or-pr-or-pending-reason>"
trigger_conditions:
  - "<触发该失败的条件>"
failure_pattern:
  - "<可复用的失败模式>"
prevention_checks:
  - "<命令、测试、脚本或人工检查>"
---

# <标题>

## 现象

- <用户可见或系统可见的现象>

## 根因

- <根因，而不是只描述直接触发点>

## 修复

- <改了什么>
- <为什么这个修复合适>

## 预防检查

- 类型：<automated-test | script | static-check | manual-check>
- 位置：<测试、命令、脚本路径或人工验证入口>
- 通过标准：<什么算通过，什么算失败>
- 适用范围：<必须运行该检查的模块或变更类型>

## 知识沉淀

- 保留在本记录：<只影响失败模式解释的内容>
- 需要提炼到 skill：<agent 执行动作规则，若无则写“无”>
- 需要提炼到 `.spec/`：<文档结构、事实源边界或协作模型，若无则写“无”>
- 需要提炼到 `docs/`：<项目事实、架构或 runbook 更新，若无则写“无”>
- 需要提炼到脚本或测试：<预防机制，若无则写“无”>

## 后续

- <仍需要补的测试、重构、监控或流程改进>
