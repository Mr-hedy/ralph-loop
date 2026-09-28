---
id: PM-0008
title: "抽样校验使发布包与现行协作入口同时保留旧事实"
status: active
domain: "release / documentation / verification"
severity: "high"
affected_modules:
  - "docs/"
  - ".spec/"
  - ".ralph/README.md"
  - "scripts/build-release.sh"
  - "scripts/check.sh"
linked_commits:
  - "a5ad531100550894b382e56d03fedea08a8476e4"
trigger_conditions:
  - "按新 .spec 布局迁移现行文档并生成 release，但只检查部分源文件和发布内容"
failure_pattern:
  - "检查命令通过，现行文档仍有旧事实，发布包仍要求读取未随包交付的文件"
prevention_checks:
  - "bash scripts/build-release.sh --verify 完整比对当前生成包"
  - "按 docs/testing.md 的 Release 部署验证检查新 workspace 入口、可执行权限与必读文件"
  - "按 docs/testing.md 的文档语义检查核对研究文档索引、状态、可见链接文字和正文职责"
---

# 抽样校验使发布包与现行协作入口同时保留旧事实

## 现象

v0.1.3 整理后，`bash scripts/check.sh` 与 mock 集成测试通过，但现行 `docs/requirements.md` 仍称本仓库不使用 Ralph dogfood，`docs/architecture.md` 仍要求使用者自行创建已由 release 提供的模板。发布版 `.spec/README.md` 无条件要求读取包内不存在的 `docs/postmortems/README.md`，发布版 `.ralph/README.md` 将未入包的 `docs/security.md` 称作部署后的权威阅读入口。用户发现旧 `docs/requirements/` 目录后，进一步审查才暴露这些同类遗漏。

## 根因

- 迁移时以文件移动和局部引用替换作为完成判据，没有复查现行需求、架构和新手入口的行为陈述。
- `scripts/check.sh` 只比较 `.spec/`、部分 `.ralph/` 源文件和少数发布包特征，未从构建脚本重建完整包逐项对比，也未在全新 workspace 检查必读文件是否存在。
- 历史兼容导航页保留在部分旧目录，却移除了另一些旧目录，缺少统一的迁移终态检查。

## 修复

- 修正现行项目事实、用户控制任务生成与验收的入口说明；发布版对未入包项目文档改为条件化或明确说明仅存在于开发仓库。
- 移除旧 `docs/requirements/`、`docs/architecture/` 和 `docs/collaboration/` 导航目录；历史快照原文保留在 feature history、checkpoint 和研究文档中。
- `scripts/build-release.sh --verify` 在临时目录重建当前版本，并对包的完整文件树做比对；构建时先写临时目录，成功后才移入正式版本路径。
- `scripts/check.sh` 调用完整包比对，并拒绝旧目录重新出现。
- 后续整体审查发现发布版 TASKS 规则仍含本开发仓库专用的历史任务与检查命令，且 README 使用未安装的全局 `ralph` 命令；已将分发规则改为项目声明的入口和命令，并修正 quickstart。发布校验增加 CLI 可执行权限检查。
- v0.1.3 提交后的定向复核发现，研究回溯文档未进入文档地图且仍标为 active，方案正文保留独立审查报告段，测试文档的状态字段混入单次验证结果，部分现行链接仍显示旧文件名。字节一致性检查无法发现文档语义和职责漂移；已按现行 DOCS/ARCHITECTURE 规则修正，并在测试规范中补充人工核对点。

## 预防检查

- 类型：script + manual-check。
- 位置：`scripts/build-release.sh --verify`、`scripts/check.sh`、`docs/testing.md` §Release 部署验证和文档规则验证。
- 通过标准：生成包与从源文件重建的包完全一致且 CLI 可执行；复制到临时 Git workspace 后 CLI/fake smoke 通过；发布入口要求立即读取的路径存在或明确为按需创建/开发仓库专有；随包分发的规则不要求使用者运行开发仓库专用脚本；现行文档地图、状态、链接显示文字和正文职责经人工核对一致。
- 适用范围：`.spec/`、`.ralph/`、模板、构建脚本、release 或文档事实源路由变化。

## 知识沉淀

- 保留在本记录：遗漏链条、根因和适用范围。
- 需要提炼到 skill：无；本轮不实施 Hook 或动作 Skills。
- 需要提炼到 `.spec/`：已把验收返工的用户决策边界贯穿 Review 与 adversarial review 输出规则。
- 需要提炼到 `docs/`：现行需求、架构、测试规范和文档地图已同步。
- 需要提炼到脚本或测试：发布包完整比对已进入 `scripts/check.sh`。

## 后续

- 真实 Claude/Codex provider smoke 和完整 Main Agent 协作演练仍需单独验证；fake 部署 smoke 不证明这些链路。
- 用户要求 `.ralph/TASKS.md` 完全不变，其中的旧文档路径仍是未来执行前需由人核对的已知限制。
