#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
if [[ -z "$version" || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi

src_ralph="$repo_root/.ralph"
out="$repo_root/release/$version"
rm -rf "$out"
mkdir -p "$out/.ralph/bin" "$out/.ralph/lib" "$out/.spec" "$out/docs"
cp "$src_ralph/bin/ralph" "$out/.ralph/bin/ralph"
for file in "$src_ralph"/lib/*.sh; do
  base="$(basename "$file")"
  [[ "$base" == adapter-gemini.sh ]] && continue
  cp "$file" "$out/.ralph/lib/$base"
done
cp "$src_ralph/PROMPT.md" "$out/.ralph/PROMPT.md"
cp "$src_ralph/README.md" "$out/.ralph/README.md"
cp "$src_ralph/.gitignore" "$out/.ralph/.gitignore"
cp -R "$repo_root/.spec/." "$out/.spec/"

cat > "$out/.ralph/TASKS.md" <<'EOF'
# Tasks

## 当前有效结论

> 由项目需求、架构决策和 `.spec/` 规范确认后填写。

## 任务维护规则

> 任务只能追加；每轮只执行一个顶层任务；完成任务必须记录完成、验证和未验证项。

## 当前任务

> 待首次项目会话根据用户目标、项目事实、`docs/README.md` 和 `.spec/` 规范补齐。
> 本文件没有顶层未完成任务时，`ralph run` 不会启动 provider；这是预期的初始化状态。
EOF

cat > "$out/.ralph/.env" <<'EOF'
# Ralph 配置文件（复制到项目后按需取消注释）。本文件不会执行 shell 代码。
# 配置优先级：命令行参数 > 当前进程环境变量 > 本文件 > 内置默认值。
#
# 必填：provider。当前正式支持 claude（Claude Code CLI）和 codex（Codex CLI）。
# fake 仅用于测试 Ralph；gemini 当前暂停接入，填写后会在启动阶段失败。
# RALPH_PROVIDER=claude

# Provider 模型名称。可选；留空时使用 provider 自身默认模型。
# RALPH_PROVIDER_MODEL=

# 推理强度。可选值：low / medium / high / none。
# 留空或 none 表示不向 provider 传递 effort 参数。
# RALPH_PROVIDER_EFFORT=low

# 每个任务最多执行多少轮。0 表示无限；达到上限会插入 HUMAN 阻塞任务。
# RALPH_LOOP_MAX_ROUND=0

# 单轮 oneshot 超时时间，单位为秒。0 表示无限。
# RALPH_LOOP_ROUND_TIMEOUT=0

# 连续多少轮没有任务进展后触发 HUMAN 阻塞。
# RALPH_LOOP_STALL_LIMIT=5

# provider 暂态错误的最大重试次数；业务失败不会无限重试。
# RALPH_LOOP_MAX_RETRY=3

# 重试等待时间，单位为秒，按顺序使用。
# RALPH_LOOP_RETRY_SCHEDULE=60 120 300

# 非 sticky 模式下的进度 heartbeat 间隔，单位为秒；0 表示关闭。
# RALPH_PROGRESS_HEARTBEAT_SEC=60

# sticky/watch 事件区最多显示的行数。
# RALPH_UI_STICKY_EVENT_LINES=6

# provider.stdout.log 静默多久后显示健康黄灯/红灯，单位为秒。
# RALPH_UI_HEALTH_GREEN_SEC=60
# RALPH_UI_HEALTH_RED_SEC=300

# 独立 provider 配置目录：Claude → CLAUDE_CONFIG_DIR，Codex → CODEX_HOME。
# 用于隔离账号、凭据和 native session；留空使用 provider 默认目录。
# RALPH_PROVIDER_CONFIG_DIR=
EOF

# The project-level AGENTS template is a release concern, not a spec rule.
cp "$repo_root/templates/AGENTS.md" "$out/AGENTS.md"
ln -s AGENTS.md "$out/CLAUDE.md"

cat > "$out/docs/README.md" <<'EOF'
# 项目文档地图

本文件是项目过程文档的唯一入口。新增、移动或归档文档时同步维护这里。

| 想了解什么 | 先读 |
|---|---|
| Ralph 运行方式 | `../.ralph/README.md` |
| 当前任务 | `../.ralph/TASKS.md` |
| 需求、方案、测试、审查规范 | `../.spec/README.md` |
| 项目需求 | `requirements.md`（创建后补充） |
| 项目架构 | `architecture/`（创建后补充） |
| 运行过程与复盘 | `checkpoints/`、`postmortems/`（创建后补充） |

新增文档时必须同步更新本地图；本文件只做导航，不承载正文。
EOF

cat > "$out/README.md" <<'EOF'
# Ralph Loop __VERSION__

这是 Ralph Loop 的可部署 release 包，包含 `.ralph/` 运行单元、`.spec/` 协作规范和 agent 启动入口。

## 部署

目标 workspace 已存在 `AGENTS.md`、`CLAUDE.md`、`.ralph/`、`.spec/` 或 `docs/` 时，不要直接覆盖；先将本目录复制到临时位置，再逐项人工合并。全新 workspace 才可以直接复制本目录内容。首次项目会话先阅读 `AGENTS.md`、`docs/README.md` 和 `.spec/README.md`，再根据用户目标补齐 `.ralph/TASKS.md`；清单准备好后才运行 Ralph。

正式支持 provider：Claude Code、Codex CLI；`fake` 仅用于测试。Gemini 暂停接入。
EOF
sed -i.bak "s/__VERSION__/${version}/" "$out/README.md"
rm -f "$out/README.md.bak"

printf 'release built: %s\n' "$out"
