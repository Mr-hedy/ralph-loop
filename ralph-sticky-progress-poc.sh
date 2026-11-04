#!/usr/bin/env bash
# Ralph watch 布局 PoC。直接运行会自动播放三个模拟任务，Ctrl+C 可提前退出。
# bash ralph-sticky-progress-poc.sh --snapshot  可查看第二项任务的一帧。
# 使用 0.1.10 的发布版渲染器和两项行数配置。工具、回复和结果使用本地演示数据。
set -eu
shopt -s extglob

case "${1:-}" in
  '')         mode=live ;;
  --snapshot) mode=snapshot ;;
  -h|--help)  echo '用法：bash ralph-sticky-progress-poc.sh [--snapshot]'; exit 0 ;;
  *)          echo "未知参数：$1" >&2; exit 2 ;;
esac
if (( $# > 1 )); then echo '只接受 --snapshot 或 --help' >&2; exit 2; fi
[[ -t 1 ]] || mode=snapshot
if [[ "$mode" == snapshot ]]; then NO_COLOR=1; fi

poc_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$poc_dir/release/0.1.10/.ralph/lib/sticky.sh"
RALPH_VERSION=0.1.10
_RALPH_STICKY_PROVIDER=demo
_RALPH_STICKY_RUN_START_TS=$(date +%s)
_RALPH_STICKY_ROUND=0
_RALPH_STICKY_TASK_TRY=0
_RALPH_STICKY_MAX_ROUND=0 _RALPH_STICKY_STALL_COUNT=0 _RALPH_STICKY_STALL_LIMIT=5
_RALPH_STICKY_RETRY_COUNT=0 _RALPH_STICKY_LOG_PATH='' _RALPH_STICKY_EXIT_REASON=''
_RALPH_STICKY_FROZEN_NOW=''
tasks=('DEV-1: 修复断线后的状态恢复' 'DEV-2: 补齐请求预算检查' 'QA-3: 验证异常边界')
_RALPH_STICKY_TASKS_TOTAL=${#tasks[@]}
_RALPH_STICKY_TASK_INDEX=0

show_for() {
  [[ "$mode" == live ]] || return 0
  ralph_sticky_render_frame
  sleep "$1"
}

begin_round() {
  local next_task="$1"
  _RALPH_STICKY_ROUND=$(( _RALPH_STICKY_ROUND + 1 ))
  if (( _RALPH_STICKY_TASK_INDEX == next_task )); then
    _RALPH_STICKY_TASK_TRY=$(( _RALPH_STICKY_TASK_TRY + 1 ))
  else
    _RALPH_STICKY_TASK_INDEX=$next_task
    _RALPH_STICKY_CURRENT_TASK="${tasks[next_task - 1]}"
    _RALPH_STICKY_TASK_START_TS=$(date +%s)
    _RALPH_STICKY_TASK_TRY=1
  fi
  _sticky_clear_events
  show_for 0.8
}

model() {
  local text="${3//+([[:space:]])/ }"
  _sticky_reply "$1" "$2" "$text" "$(date +%H:%M:%S)"
  show_for 0.45
}

tool() {
  ralph_sticky_append_event "$1"
  show_for 0.65
}

if [[ "$mode" == live ]]; then
  ralph_sticky_install_traps
  ralph_sticky_enter
else
  _SEL='' _SWRAP_OFF='' _SWRAP_ON=''
  _srefresh_size() { _SCOLS=100; _SROWS=24; }
  _SLAST_ACTIVITY_TS=$_RALPH_STICKY_RUN_START_TS
fi

begin_round 1
model append demo/1 '正在核对断线'
model append demo/1 '后的状态恢复路径。'
tool '🔧 开始 read_file · 读取恢复逻辑'
model append demo/1 $'\n已找到状态回写的位置，'
model append demo/1 '接下来运行复现用例。'
model append demo/1 $'\n我会核对失败的断言，再修改对应分支。'
tool '✓ 完成 read_file · 找到状态回写分支'
tool '🔧 开始 run_command · 运行复现用例'
tool '✓ 完成 run_command · 已复现状态不一致'
tool '🔧 开始 read_file · 读取失败断言'
tool '✓ 完成 read_file · 已定位断言'
tool '🔧 开始 edit_file · 修改状态回写'
tool '✓ 完成 edit_file · 已更新恢复分支'
model set verify '修复已写入。下一轮用相同输入验证恢复结果。'
show_for 1.1

begin_round 1
model set retest '正在用上一轮的失败样例验证修复。'
tool '🔧 开始 run_command · 重跑复现用例'
tool '✓ 完成 run_command · 恢复结果符合预期'
show_for 1.1

begin_round 2
model append demo/1 '已找到请求预算的入口。'
model append demo/1 $'\n接下来检查'
model append demo/1 '超时和取消两条路径。'
model append demo/1 $'\n验证会覆盖正常返回和预算耗尽。'
tool '🔧 开始 read_file · 定位预算检查'
tool '✓ 完成 read_file · 已定位入口'
tool '🔧 开始 edit_file · 补齐超时检查'
tool '✓ 完成 edit_file · 已更新超时分支'
tool '🔧 开始 run_command · 运行预算用例'
tool '✓ 完成 run_command · 两条路径均通过'
if [[ "$mode" == snapshot ]]; then ralph_sticky_render_frame | tr -d '\r'; exit 0; fi
show_for 1.2

begin_round 3
model set regression '现在执行最后一项任务，验证断线、超时和取消场景。'
tool '🔧 开始 run_command · 运行回归用例'
tool '✓ 完成 run_command · 三种场景均通过'
model set final '三项任务均已完成，回归验证通过。'
_RALPH_STICKY_EXIT_REASON=done
_RALPH_STICKY_FROZEN_NOW=$(date +%s)
ralph_sticky_render_frame final
