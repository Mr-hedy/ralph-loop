#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="build"
if [[ "${1:-}" == "--verify" ]]; then
  mode="verify"
  shift
fi
version="$(sed -n 's/^RALPH_VERSION="\([^"]*\)"$/\1/p' "$repo_root/.ralph/bin/ralph")"
requested_version="${1:-$version}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ || "$requested_version" != "$version" || $# -gt 1 || ( "$mode" == "verify" && $# -ne 0 ) ]]; then
  echo "usage: $0 [$version|--verify] (must match .ralph/bin/ralph)" >&2
  exit 2
fi

src_ralph="$repo_root/.ralph"
current_release="$repo_root/release/$version"
if [[ "$mode" == "build" && -e "$current_release" ]]; then
  echo "release already exists: $current_release" >&2
  exit 1
fi
if [[ "$mode" == "verify" && ! -d "$current_release" ]]; then
  echo "release missing: $current_release" >&2
  exit 1
fi
scratch="$(mktemp -d "$repo_root/release/.build-$version.XXXXXX")"
trap 'rm -r -- "$scratch"' EXIT
out="$scratch/package"
mkdir -p "$out/.ralph/bin" "$out/.ralph/lib" "$out/.spec" "$out/docs"
cp "$src_ralph/bin/ralph" "$out/.ralph/bin/ralph"
grep -Fxq "RALPH_VERSION=\"$version\"" "$out/.ralph/bin/ralph"
for file in "$src_ralph"/lib/*.sh; do
  base="$(basename "$file")"
  cp "$file" "$out/.ralph/lib/$base"
done
cp "$src_ralph/PROMPT.md" "$out/.ralph/PROMPT.md"
cp "$src_ralph/README.md" "$out/.ralph/README.md"
cp "$src_ralph/.gitignore" "$out/.ralph/.gitignore"
cp -R "$repo_root/.spec/." "$out/.spec/"

cat > "$out/.ralph/TASKS.md" <<'EOF'
# Tasks

> 主题: <首次项目会话补齐>
> 起始: <YYYY-MM-DD>
> 归档目标: `docs/features/<feature>/final-task.md`（无项目归档 workflow 时补齐）

## 当前有效结论

> 由 feature 需求、方案决策和 `.spec/` 规范确认后填写。

## 历史索引

> 首次项目会话根据已有文档填写；没有历史时留空。

## 规则

> 任务只能追加；每轮只执行一个顶层任务；完成任务必须记录完成、验证和未验证项。

## 当前任务

> 待首次项目会话根据用户目标、项目事实、`docs/README.md` 和 `.spec/` 规范补齐。
> 本文件没有顶层未完成任务时，`ralph run` 不会启动 provider；这是预期的初始化状态。
EOF

cat > "$out/.ralph/.env.example" <<'EOF'
# Ralph 配置示例。复制为 .ralph/.env 后按需取消注释；本文件不会执行 shell 代码。
# 配置优先级：命令行参数 > 当前进程环境变量 > 本文件 > 内置默认值。
#
# 必填：provider。当前正式支持 claude（Claude Code CLI）、codex（Codex CLI）和 antigravity（Antigravity CLI / agy）。任选其一。
# fake 仅用于测试 Ralph；其他 provider 名称会在启动阶段失败。
# RALPH_PROVIDER=claude
# RALPH_PROVIDER=antigravity

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
# Claude/Codex 留空时使用各自默认目录。
# Antigravity 当前不支持独立配置目录：选择 antigravity 时不要设置此变量，
# 使用 agy 的默认登录态。显式设置非空值会在启动前报错退出，不会回退到默认账号。
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
| 某个功能需求 | `features/<feature>/requirements.md`（按需创建） |
| 某个功能方案/验证 | `features/<feature>/solution.md`、`testing.md`（按需创建） |
| 项目级稳定契约 | `architecture.md`、`security.md`、`integrations.md`、`testing.md`（按需创建） |
| 业务系统排查 | `troubleshooting/<slug>.md`（按需创建） |
| 运行过程与复盘 | `checkpoints/`、`postmortems/`（按需创建） |

新增文档时必须同步更新本地图；本文件只做导航，不承载正文。
EOF

sed "s/__VERSION__/${version}/g" "$repo_root/templates/RELEASE-README.md" > "$out/README.md"

if [[ "$mode" == "verify" ]]; then
  if ! diff -rq "$out" "$current_release"; then
    echo "release differs from generated output: $current_release" >&2
    exit 1
  fi
  if [[ ! -x "$current_release/.ralph/bin/ralph" ]]; then
    echo "release CLI is not executable: $current_release/.ralph/bin/ralph" >&2
    exit 1
  fi
  printf 'release verified: %s\n' "$current_release"
else
  mv "$out" "$current_release"
  printf 'release built: %s\n' "$current_release"
fi
