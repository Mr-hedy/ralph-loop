#!/usr/bin/env bash
# Ralph run plain 模式 demo —— agent / CI 友好的追加式纯文本输出
# 跑法：bash ralph-plain-poc.sh
#
# 这是 `ralph run`（无 -v）默认的输出形态。设计原则：
#   - 事件驱动 + 60s heartbeat 兜底，没有定时刷新逻辑
#   - 只打 ralph 自己的 marker（启动 banner / round 启停 / heartbeat / 退出总结）
#   - **不打 agent 内部事件**（tool call / chat / thinking）— 那些一直写在
#     runs/<run_id>/rounds/round-NNN/provider.stdout.log，需要时按需 grep
#   - 无 ANSI 控制码，每行独立可 grep，main agent 消耗最少 context
#
# 一个 5 round / 10 分钟的 run 总输出 ≈ 30 行，main agent 完全消化得起。
#
# 与 ralph-sticky-poc.sh 的对比：
#   sticky-poc.sh = ralph run -v / ralph watch（人类用，三段式视觉化）
#   plain-poc.sh  = ralph run（agent / CI 用，追加式纯文本）

set -u

# 时间戳用模拟时间（不是 wallclock），让 demo 节奏可控
print_at() {
  local sim_time="$1"
  shift
  printf '[%s] %s\n' "$sim_time" "$*"
  sleep 0.5
}

# ── 启动 banner ────────────────────────────────────────────────────────────
print_at "14:05:08" "ralph 0.2 | run a3f9c2e | I5-design | tasks 0/12 done | provider claude"

# ── round 1（包含两次 60s heartbeat）────────────────────────────────────────
print_at "14:05:09" "round 1/∞ → REQ-1: 设计 sticky bar 样式"
print_at "14:06:09" "still running | elapsed 60s | provider log 18.2KB / 412 lines"
print_at "14:07:09" "still running | elapsed 120s | provider log 35.1KB / 798 lines"
print_at "14:08:44" "round 1/∞ ✓ done | tasks 1/12 | round 03:35 | run 03:35"

# ── round 2 ────────────────────────────────────────────────────────────────
print_at "14:08:45" "round 2/∞ → REQ-2: 实现 watch sticky bar"
print_at "14:09:45" "still running | elapsed 60s | provider log 22.3KB / 521 lines"
print_at "14:11:18" "round 2/∞ ✓ done | tasks 2/12 | round 02:33 | run 06:10"

# ── round 3 ────────────────────────────────────────────────────────────────
print_at "14:11:19" "round 3/∞ → DEV-3: 接入 ANSI cursor_up 重绘"
print_at "14:12:19" "still running | elapsed 60s | provider log 12.7KB / 287 lines"
print_at "14:12:55" "round 3/∞ ✓ done | tasks 3/12 | round 01:36 | run 07:46"

# ── round 4（演示错误退出场景）─────────────────────────────────────────────
print_at "14:12:56" "round 4/∞ → QA-4: 终端兼容性测试"
print_at "14:13:56" "still running | elapsed 60s | provider log 8.4KB / 192 lines"
print_at "14:14:30" "round 4/∞ ✗ failed | tasks 3/12 | round 01:34 | run 09:22"
print_at "14:14:30" "last_error: rate_limited (HTTP 429); retry exhausted"

# ── 退出总结块 ─────────────────────────────────────────────────────────────
echo ""
echo "─── ralph run summary ───────────────────────────────"
echo "Run ID:        a3f9c2e"
echo "Iteration:     I5-design"
echo "Rounds:        4"
echo "Tasks:         3/12 checked"
echo "Provider:      claude"
echo "Exit reason:   provider_failed"
echo "Last error:    rate_limited (HTTP 429); retry exhausted"
echo "Duration:      00:09:22"
echo "Run dir:       .ralph/runs/20260505T140508Z-a3f9c2e"
echo ""
echo "接力提示: 检查 provider quota；等 rate limit 重置后重跑；如反复触发，"
echo "         考虑降低 effort 或拆分剩余 9 个 task"
