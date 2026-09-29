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
# 第一次使用通常只需指定 RALPH_PROVIDER，其余保持注释即可使用默认值。
# 单次调整：有对应 CLI 参数时用 ralph run 参数，其余选项用进程环境变量。
# 长期固定在当前 workspace 才写入 .env。
# 配置优先级：命令行参数 > 当前进程环境变量 > 本文件 > 内置默认值。
#
# 必须选一个 provider；可写在 .env，也可在运行时传 --provider 或设置进程环境变量。
# 正式支持 claude（Claude Code CLI）、codex（Codex CLI）、antigravity（Antigravity CLI / agy）。
# fake 仅用于测试 Ralph；其他 provider 名称会在启动阶段失败。
# RALPH_PROVIDER=claude
# RALPH_PROVIDER=codex
# RALPH_PROVIDER=antigravity

# 默认：不指定模型，由所选 provider 决定。通常保持注释。
# 只有项目要求固定某个模型，或确需控制模型的能力、费用时才填写 provider 支持的名称。
# RALPH_PROVIDER_MODEL=

# 默认：不传推理强度，由 provider 决定。通常保持注释。
# 需要明确偏向速度/成本或复杂任务的推理深度时才设置 low / medium / high；
# none 明确表示不向 provider 传 effort 参数。具体效果由所选 provider 决定。
# RALPH_PROVIDER_EFFORT=low

# 默认 0：不按轮数限制单个任务；一般保持默认，仍受无进展限制保护。
# 需要控制单任务的调用次数/预算时设置正整数；达到上限会插入 HUMAN 阻塞任务。
# RALPH_LOOP_MAX_ROUND=0

# 默认 0：单轮不设超时，允许长任务自然结束。
# 担心 provider 长时间卡住，或运行环境有时间限制时设置秒数；超时会结束该 run。
# RALPH_LOOP_ROUND_TIMEOUT=0

# 默认 5：同一任务连续 5 轮无进展后交给人处理；一般保持默认。
# 希望更早介入时调低；已确认任务确实需要更多探索轮次时可调高。
# RALPH_LOOP_STALL_LIMIT=5

# 默认 3：对 rate limit、network 等暂态错误重试，业务失败不按此重试。
# 希望暂态错误立即暴露时设为 0；网络长期不稳时可按预算调高。
# RALPH_LOOP_MAX_RETRY=3

# 只在 provider 报 rate_limit / network 等可重试错误时生效；正常运行不等待。
# 默认：第一次失败后等 60 秒再试；再次失败等 120 秒；第三次等 300 秒。
# 重试次数由 RALPH_LOOP_MAX_RETRY 控制；等待时间写成空格分隔的秒数。
# 通常保持默认；只有需匹配 provider 限流窗口或调整恢复速度时才修改。
# RALPH_LOOP_RETRY_SCHEDULE=60 120 300

# 默认 60 秒：普通文本模式下，同一轮还在执行时，每 60 秒打印一次
# “仍在运行”、已耗时和日志路径；只是提示，不会重启或停止 provider。
# 需要更频繁提示时调低；不需要提示时设为 0。run -v 的 sticky 界面不用此心跳。
# RALPH_PROGRESS_HEARTBEAT_SEC=60

# 默认 6 行：sticky/watch 事件区长度；通常保持默认。
# 终端空间较小或想同时看到更多事件时才调整。
# RALPH_UI_STICKY_EVENT_LINES=6

# 默认静默 60 秒变黄、300 秒变红；只是界面提示，不会停止 provider。
# 只有 provider 正常输出间隔明显更长/更短、导致提示频繁误判时才调整。
# 若调整，保持 GREEN_SEC 小于 RED_SEC。
# RALPH_UI_HEALTH_GREEN_SEC=60
# RALPH_UI_HEALTH_RED_SEC=300

# 默认：使用 provider 自己的配置和已登录账号；通常保持注释。
# 只有 Claude/Codex 需要隔离账号或凭据时才填写已准备好的独立配置目录：
# Claude → CLAUDE_CONFIG_DIR，Codex → CODEX_HOME；此项不改变权限或沙箱模式。
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
