#!/usr/bin/env bash
# Ralph watch PoC v1（启动前视觉锚点）
# 跑法：bash ralph-sticky-poc.sh
# 退出：Ctrl+C
#
# **状态**：本 PoC 是 I5 启动前的视觉契约 v1，**不再跟踪实施期变更**。
# 当前生效合约见 `docs/requirements/ralph-loop/I5-design.md` §0 ChangeLog
# 和实际实现 `.ralph/lib/sticky.sh`。主要差异：
#   - live 模式高度 11 行（v1: 10 行）；新增 `( CTRL+C to exit )` 提示行
#   - 删除顶栏起始 `[HH:MM:SS]` 时间戳
#   - frozen 模式（watch attach 已 finished run）顶栏改 `finished Xago · duration`
#   - exit_reason=done 底栏简化为 `✓ all tasks done · ( CTRL+C to exit )`
#   - spinner / 渲染节奏 200ms → 100ms
#
# v1 PoC 默认 10 行：顶栏 + 分割线 + 6 行事件区 + 分割线 + 底栏。
# 可用 RALPH_STICKY_EVENT_LINES 覆盖事件区行数。运行时只重绘本次输出块，
# 不设置 scroll region，不清屏，不删除 Ctrl+C 时已经输出的内容。

set -u

# ── ANSI ────────────────────────────────────────────────────────────────────
CSI=$'\033['
HIDE_CURSOR="${CSI}?25l"
SHOW_CURSOR="${CSI}?25h"
SAVE_CURSOR="${CSI}s"
RESTORE_CURSOR="${CSI}u"
EL="${CSI}K"
DIM="${CSI}2m"
BOLD="${CSI}1m"
RESET="${CSI}0m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
RED="${CSI}31m"
CYAN="${CSI}36m"
GRAY="${CSI}90m"
AMBER="${CSI}38;5;178m"

cursor_up() { printf '%s%dA' "$CSI" "$1"; }

refresh_terminal_size() {
  local size
  if size="$(stty size < /dev/tty 2>/dev/null)" && [[ "$size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
    ROWS="${BASH_REMATCH[1]}"
    COLS="${BASH_REMATCH[2]}"
  else
    COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    ROWS="${LINES:-$(tput lines 2>/dev/null || echo 24)}"
  fi
  [[ "$COLS" =~ ^[0-9]+$ ]] || COLS=80
  [[ "$ROWS" =~ ^[0-9]+$ ]] || ROWS=24
  [[ $COLS -lt 20 ]] && COLS=20 || true
  [[ $ROWS -lt 10 ]] && ROWS=10 || true
}

# ── 终端尺寸 / 布局 ─────────────────────────────────────────────────────────
COLS=80
ROWS=24
refresh_terminal_size
EVENT_WINDOW="${RALPH_STICKY_EVENT_LINES:-6}"
if [[ ! "$EVENT_WINDOW" =~ ^[0-9]+$ || "$EVENT_WINDOW" -lt 1 ]]; then
  printf 'ralph-sticky-poc: RALPH_STICKY_EVENT_LINES must be a positive integer\n' >&2
  exit 1
fi
STICKY_LINES=$(( EVENT_WINDOW + 4 ))
EVENT_TIMES=()
EVENT_MESSAGES=()
RENDERED=0
REDRAWING=0
STTY_SAVED=""
STTY_ACTIVE=0

# ── 状态 ────────────────────────────────────────────────────────────────────
START_TS=$(date +%s)
ITER=1
ITER_START_TS=$START_TS
EVENT_COUNT=0
LAST_EVENT="(no events yet)"
LAST_EVENT_TS=$START_TS
SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧")
SPIN_IDX=0
TASKS_TOTAL=12
TASKS_DONE=0
STALL_COUNT=1
STALL_LIMIT=5
CURRENT_TASK="REQ-2: 新增 REQ：per-task 防死循环 + HUMAN 自动插入"

# ── 横线 / 进入 / 退出 ──────────────────────────────────────────────────────
draw_hr() {
  printf '%s%s%s%s%s\n' "$EL" "$DIM" "$GRAY" "$(printf '─%.0s' $(seq 1 "$COLS"))" "$RESET"
}

enter_layout() {
  refresh_terminal_size
  if [[ -r /dev/tty ]]; then
    STTY_SAVED="$(stty -g < /dev/tty 2>/dev/null || true)"
    if [[ -n "$STTY_SAVED" ]]; then
      # noecho 防止 Enter/普通按键移动光标；cbreak 让退出时可以丢弃误按输入。
      stty -echo -icanon min 0 time 0 < /dev/tty 2>/dev/null || true
      STTY_ACTIVE=1
    fi
  fi
  printf '%s' "$HIDE_CURSOR"
}

cleanup() {
  local status="${1:-0}"
  trap - INT TERM EXIT
  if (( REDRAWING == 1 )); then
    printf '%s' "$RESTORE_CURSOR"
  fi
  if (( STTY_ACTIVE == 1 )); then
    local _
    while IFS= read -r -s -n 1 -t 0.001 _ < /dev/tty 2>/dev/null; do
      :
    done
    stty "$STTY_SAVED" < /dev/tty 2>/dev/null || true
    STTY_ACTIVE=0
  fi
  printf '%s%s' "$SHOW_CURSOR" "$RESET"
  exit "$status"
}
trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup $?' EXIT

# 简单起见，不处理 resize（用户说没有屏幕自适应需求）
# 如果 resize，行为可能错乱，需要重启 PoC

# ── 工具 ────────────────────────────────────────────────────────────────────
fmt_elapsed() {
  local s=$1 h m
  h=$(( s / 3600 ))
  m=$(( (s % 3600) / 60 ))
  s=$(( s % 60 ))
  printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

truncate_str() {
  local txt="$1" max="$2"
  if [[ $max -lt 1 ]]; then return; fi
  if (( ${#txt} > max )); then
    if (( max <= 3 )); then
      printf '%s' "${txt:0:max}"
    else
      printf '%s...' "${txt:0:max-3}"
    fi
  else
    printf '%s' "$txt"
  fi
}

char_width() {
  local ch="$1"
  case "$ch" in
    [一-龥]|[，。！？：；、（）【】《》“”‘’]) printf '2' ;;
    *) printf '1' ;;
  esac
}

truncate_cols() {
  local txt="$1" max="$2"
  local suffix="..." suffix_w=3 out="" used=0 i ch w limit
  if [[ $max -lt 1 ]]; then return; fi

  local total=0
  for ((i=0; i<${#txt}; i++)); do
    ch="${txt:i:1}"
    w="$(char_width "$ch")"
    total=$(( total + w ))
  done
  if (( total <= max )); then
    printf '%s' "$txt"
    return
  fi

  if (( max <= suffix_w )); then
    printf '%s' "${txt:0:max}"
    return
  fi

  limit=$(( max - suffix_w ))
  for ((i=0; i<${#txt}; i++)); do
    ch="${txt:i:1}"
    w="$(char_width "$ch")"
    if [[ $(( used + w )) -gt $limit ]]; then break; fi
    out+="$ch"
    used=$(( used + w ))
  done
  printf '%s%s' "$out" "$suffix"
}

# ── 顶栏 ────────────────────────────────────────────────────────────────────
draw_top() {
  local now elapsed line started tasks_color
  now=$(date +%s)
  elapsed=$(fmt_elapsed $(( now - START_TS )))
  started=$(date -r "$START_TS" +%H:%M:%S 2>/dev/null || date -d "@$START_TS" +%H:%M:%S)
  if (( TASKS_DONE >= TASKS_TOTAL )); then
    tasks_color="$GREEN"
  else
    tasks_color="$RESET"
  fi
  line=$(printf '%s[%s]%s %sralph 0.2%s %s· tasks%s %s%d/%d%s %s· provider%s claude %s· elapsed%s %s' \
    "$GRAY" "$started" "$RESET" \
    "$CYAN" "$RESET" \
    "$GRAY" "$RESET" "$tasks_color" "$TASKS_DONE" "$TASKS_TOTAL" "$RESET" \
    "$GRAY" "$RESET" "$GRAY" "$RESET" "$elapsed")
  printf '%s%s\n' "$EL" "$line"
}

# ── 底栏 ────────────────────────────────────────────────────────────────────
draw_bottom() {
  local now iter_elapsed health spin task_short line since_ev
  now=$(date +%s)
  iter_elapsed=$(fmt_elapsed $(( now - ITER_START_TS )))
  spin="${SPIN_FRAMES[$SPIN_IDX]}"

  since_ev=$(( now - LAST_EVENT_TS ))
  if (( since_ev > 180 )); then
    health="${RED}●${RESET}"
  elif (( since_ev > 60 )); then
    health="${YELLOW}●${RESET}"
  else
    health="${GREEN}●${RESET}"
  fi

  local prefix_plain task_max
  prefix_plain="● round ${ITER}/∞ · stall ${STALL_COUNT}/${STALL_LIMIT} · ${spin} ${iter_elapsed} · → "
  task_max=$(( COLS - ${#prefix_plain} - 1 ))
  if [[ $task_max -lt 8 ]]; then task_max=8; fi
  task_short=$(truncate_cols "$CURRENT_TASK" "$task_max")

  local stall_color stall_warn
  stall_warn=$(( STALL_LIMIT - 2 ))
  if [[ $stall_warn -lt 1 ]]; then stall_warn=1; fi
  if (( STALL_COUNT >= STALL_LIMIT )); then
    stall_color="$RED"
  elif (( STALL_COUNT >= stall_warn )); then
    stall_color="$AMBER"
  else
    stall_color="$RESET"
  fi

  line=$(printf '%s %sround%s %s%d/∞%s %s·%s %sstall%s %s%d/%d%s %s·%s %s%s%s %s %s· →%s %s%s' \
    "$health" \
    "$GRAY" "$RESET" "$BOLD" "$ITER" "$RESET" \
    "$GRAY" "$RESET" \
    "$GRAY" "$RESET" "$stall_color" "$STALL_COUNT" "$STALL_LIMIT" "$RESET" \
    "$GRAY" "$RESET" \
    "$CYAN" "$spin" "$RESET" "$iter_elapsed" \
    "$GRAY" "$RESET" \
    "$task_short" "$RESET")

  printf '%s%s\n' "$EL" "$line"
}

# ── 事件 append ─────────────────────────────────────────────────────────────
append_event() {
  local ts event
  ts=$(date +%H:%M:%S)
  event="$1"
  EVENT_COUNT=$(( EVENT_COUNT + 1 ))
  LAST_EVENT="$event"
  LAST_EVENT_TS=$(date +%s)

  EVENT_TIMES+=("$ts")
  EVENT_MESSAGES+=("$event")
  while (( ${#EVENT_MESSAGES[@]} > EVENT_WINDOW )); do
    EVENT_TIMES=("${EVENT_TIMES[@]:1}")
    EVENT_MESSAGES=("${EVENT_MESSAGES[@]:1}")
  done
}

draw_events() {
  local i line count blank_count idx ts event max
  count=${#EVENT_MESSAGES[@]}
  if [[ $count -gt $EVENT_WINDOW ]]; then count=$EVENT_WINDOW; fi
  blank_count=$(( EVENT_WINDOW - count ))
  max=$(( COLS - 12 ))
  if [[ $max -lt 8 ]]; then max=8; fi

  for ((i=0; i<EVENT_WINDOW; i++)); do
    if (( i < blank_count )); then
      line=""
    else
      idx=$(( i - blank_count ))
      ts="${EVENT_TIMES[$idx]:-}"
      event="${EVENT_MESSAGES[$idx]:-}"
      line=$(printf '%s[%s]%s %s' "$GRAY" "$ts" "$RESET" "$(truncate_str "$event" "$max")")
    fi
    printf '%s%s\n' "$EL" "$line"
  done
}

render_frame() {
  refresh_terminal_size
  if (( RENDERED == 1 )); then
    printf '%s' "$SAVE_CURSOR"
    REDRAWING=1
    cursor_up "$STICKY_LINES"
  fi

  draw_top
  draw_hr
  draw_events
  draw_hr
  draw_bottom
  if (( REDRAWING == 1 )); then
    printf '%s' "$RESTORE_CURSOR"
    REDRAWING=0
  fi
  RENDERED=1
}

# ── mock 事件 ───────────────────────────────────────────────────────────────
EVENTS=(
  "💬 \"Reading requirements doc to understand sticky bar layout...\""
  "🔧 Read docs/requirements/ralph-loop/requirements.md"
  "💭 thinking (892 tok)"
  "🔧 Bash bash -n .ralph/lib/watch.sh"
  "💬 \"Found the issue at line 142\""
  "🔧 Edit .ralph/lib/watch.sh:142  (+3 -1)"
  "💬 \"Re-running tests to confirm fix...\""
  "🔧 Bash bash scripts/integration-test.sh"
  "✓ tests pass (83/83)"
  "💬 \"Moving on to REQ-2: implement sticky bar\""
  "🔧 Read .ralph/lib/status.sh"
  "💭 thinking (1.4K tok)"
  "🔧 Edit .ralph/lib/watch.sh:88"
  "💬 \"Validating sticky bar render against terminal resize...\""
  "🔧 Bash bash scripts/integration-test.sh"
  "❌ error: rate_limited, retry in 30s"
  "💬 \"Retrying after backoff...\""
  "🔧 Bash bash scripts/integration-test.sh"
  "✓ all tests pass"
  "💬 \"REQ-2 complete, marking [x]\""
)

# ── 主循环 ──────────────────────────────────────────────────────────────────
enter_layout
render_frame

EV_IDX=0
TICK=0
while true; do
  SPIN_IDX=$(( (SPIN_IDX + 1) % 8 ))

  if (( TICK % 5 == 0 )); then
    append_event "${EVENTS[$EV_IDX]}"
    EV_IDX=$(( (EV_IDX + 1) % ${#EVENTS[@]} ))

    if (( EVENT_COUNT % 10 == 0 )); then
      ITER=$(( ITER + 1 ))
      ITER_START_TS=$(date +%s)
      TASKS_DONE=$(( TASKS_DONE + 1 ))
      case "$TASKS_DONE" in
        1) CURRENT_TASK="REQ-2: 新增 REQ：per-task 防死循环 + HUMAN 自动插入" ;;
        2) CURRENT_TASK="DEV-3: 接入 ANSI scroll region" ;;
        3) CURRENT_TASK="QA-4: 终端兼容性测试" ;;
        *) CURRENT_TASK="REQ-N: 后续任务" ;;
      esac
    fi
  fi

  render_frame
  TICK=$(( TICK + 1 ))
  sleep 0.2
done
