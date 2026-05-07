#!/usr/bin/env bash
# sticky.sh — 三段式 sticky renderer（I5-design §1/§4/§5/§13）
#
# 公共 API:
#   ralph_sticky_enter          — 进入 sticky 模式（保存 stty，hide cursor）
#   ralph_sticky_render_frame   — 渲染一帧（顶栏 + 横线 + 事件区 + 横线 + 底栏）
#   ralph_sticky_cleanup        — 退出 sticky 模式（还原 stty，show cursor）
#   ralph_sticky_append_event   — 追加事件到事件区
#   ralph_sticky_install_traps  — 安装 INT/TERM/EXIT trap（自动还原终端）
#
# 调用方需在 render_frame 前设置以下变量:
#   _RALPH_STICKY_RUN_START_TS   — run 启动 unix timestamp
#   _RALPH_STICKY_ROUND          — 本次 run 累计 oneshot 数（顶栏 oneshots N）
#   _RALPH_STICKY_TASK_START_TS  — 当前 task 首次出现 unix timestamp（底栏 spinner 用）
#   _RALPH_STICKY_TASKS_DONE     — 已勾选任务数
#   _RALPH_STICKY_TASKS_TOTAL    — 任务总数
#   _RALPH_STICKY_CURRENT_TASK   — 第一个未勾选任务文本
#   _RALPH_STICKY_TASK_TRY       — per-task round 尝试次数
#   _RALPH_STICKY_MAX_ROUND      — 单 task 上限（0=∞）
#   _RALPH_STICKY_STALL_COUNT    — 当前 task 连续无进展次数
#   _RALPH_STICKY_STALL_LIMIT    — stall 上限
#   _RALPH_STICKY_PROVIDER       — provider 名
#   _RALPH_STICKY_RETRY_COUNT    — 当前 retry 次数
#   _RALPH_STICKY_LOG_PATH       — provider.stdout.log 路径（健康灯用）
#   _RALPH_STICKY_EXIT_REASON    — 退出原因（最后一次渲染用；空=运行中）
#   _RALPH_STICKY_FROZEN_NOW     — 冻结时间戳（unix epoch）；非空时顶/底栏 elapsed
#                                  使用此值代替实时 `date +%s`，且 spinner 不再前进。
#                                  用途：watch attach 已 finished 的 run 时定格画面。
#
# 环境变量:
#   RALPH_UI_STICKY_EVENT_LINES  — 事件区行数（默认 6）
#   RALPH_UI_HEALTH_GREEN_SEC    — 健康灯绿色阈值秒（默认 60）
#   RALPH_UI_HEALTH_RED_SEC      — 健康灯红色阈值秒（默认 300）

set -u

# ── ANSI constants ────────────────────────────────────────────────────────────
_SCSI=$'\033['
_SHIDE="${_SCSI}?25l"
_SSHOW="${_SCSI}?25h"
_SSAVE="${_SCSI}s"
_SREST="${_SCSI}u"
_SEL="${_SCSI}K"
_SDIM="${_SCSI}2m"
_SBOLD="${_SCSI}1m"
_SRESET="${_SCSI}0m"
_SGREEN="${_SCSI}32m"
_SYELLOW="${_SCSI}33m"
_SRED="${_SCSI}31m"
_SCYAN="${_SCSI}36m"
_SGRAY="${_SCSI}90m"
_SAMBER="${_SCSI}38;5;178m"

# ── Layout config ─────────────────────────────────────────────────────────────
_SEVENT_WINDOW="${RALPH_UI_STICKY_EVENT_LINES:-6}"
if [[ ! "$_SEVENT_WINDOW" =~ ^[0-9]+$ || "$_SEVENT_WINDOW" -lt 1 ]]; then
  _SEVENT_WINDOW=6
fi
_STICKY_LINES=$(( _SEVENT_WINDOW + 4 ))
_SHEALTH_GREEN="${RALPH_UI_HEALTH_GREEN_SEC:-60}"
_SHEALTH_RED="${RALPH_UI_HEALTH_RED_SEC:-300}"

# ── Internal state ────────────────────────────────────────────────────────────
_SRENDERED=0
_SREDRAWING=0
_SSTTY_SAVED=""
_SSTTY_ACTIVE=0
_SCLEANED=0
_SCOLS=80
_SROWS=24
_SEV_TIMES=()
_SEV_MSGS=()
_SSPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧")
_SSPIN_IDX=0
_SLOG_LAST_SIZE=0
_SLAST_ACTIVITY_TS=0
_STICKY_LINES_LAST=""   # last frame's rendered height (for live↔frozen size transitions)

# ── Terminal size ─────────────────────────────────────────────────────────────
_srefresh_size() {
  local size
  if size="$(stty size < /dev/tty 2>/dev/null)" && [[ "$size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
    _SROWS="${BASH_REMATCH[1]}"
    _SCOLS="${BASH_REMATCH[2]}"
  else
    _SCOLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    _SROWS="${LINES:-$(tput lines 2>/dev/null || echo 24)}"
  fi
  [[ "$_SCOLS" =~ ^[0-9]+$ ]] || _SCOLS=80
  [[ "$_SROWS" =~ ^[0-9]+$ ]] || _SROWS=24
  [[ $_SCOLS -lt 20 ]] && _SCOLS=20 || true
  [[ $_SROWS -lt 10 ]] && _SROWS=10 || true
}

# ── Utility ───────────────────────────────────────────────────────────────────
_sfmt_elapsed() {
  local s=${1:-0} h m
  h=$(( s / 3600 ))
  m=$(( (s % 3600) / 60 ))
  s=$(( s % 60 ))
  printf '%02d:%02d:%02d' "$h" "$m" "$s"
}

# Coarse humanized "ago" formatter: 0~59s → "Ns" / 1~59m → "Nm" /
# 1~23h → "Nh" / >=1d → "Nd"
_sfmt_ago() {
  local s=${1:-0}
  if (( s < 60 )); then printf '%ds' "$s"
  elif (( s < 3600 )); then printf '%dm' $(( s / 60 ))
  elif (( s < 86400 )); then printf '%dh' $(( s / 3600 ))
  else printf '%dd' $(( s / 86400 ))
  fi
}

_schar_width() {
  case "$1" in
    [一-龥]|[，。！？：；、（）【】《》""'']) printf '2' ;;
    *) printf '1' ;;
  esac
}

# Truncate string to fit max display columns (CJK-aware), append "..." if truncated
_struncate_cols() {
  local txt="$1" max="$2"
  local suffix="..." suffix_w=3 out="" used=0 i ch w limit total=0

  if [[ $max -lt 1 ]]; then return; fi

  for ((i=0; i<${#txt}; i++)); do
    ch="${txt:i:1}"
    w="$(_schar_width "$ch")"
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
    w="$(_schar_width "$ch")"
    if [[ $(( used + w )) -gt $limit ]]; then break; fi
    out+="$ch"
    used=$(( used + w ))
  done
  printf '%s%s' "$out" "$suffix"
}

# Byte-based truncation for event lines
_struncate_bytes() {
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

_scursor_up() { printf '%s%dA' "$_SCSI" "$1"; }

# ── Health light (§5) ────────────────────────────────────────────────────────
_shealth() {
  local now exit_reason
  now=$(date +%s)
  exit_reason="${_RALPH_STICKY_EXIT_REASON:-}"

  # Exit-state lights
  case "$exit_reason" in
    done)
      printf '%s✓%s' "$_SGREEN" "$_SRESET"
      return
      ;;
    provider_failed|timeout|blocked_by_human)
      printf '%s✗%s' "$_SRED" "$_SRESET"
      return
      ;;
    interrupted)
      printf '%s⏸%s' "$_SYELLOW" "$_SRESET"
      return
      ;;
  esac

  # Running: check provider.stdout.log byte growth
  local log_path="${_RALPH_STICKY_LOG_PATH:-}"
  if [[ -n "$log_path" && -f "$log_path" ]]; then
    local current_size
    current_size="$(stat -f%z "$log_path" 2>/dev/null || stat -c%s "$log_path" 2>/dev/null)" || current_size=0
    if (( current_size > _SLOG_LAST_SIZE )); then
      _SLAST_ACTIVITY_TS="$now"
      _SLOG_LAST_SIZE="$current_size"
    fi
  fi

  local since=$(( now - _SLAST_ACTIVITY_TS ))
  if (( since > _SHEALTH_RED )); then
    printf '%s●%s' "$_SRED" "$_SRESET"
  elif (( since > _SHEALTH_GREEN )); then
    printf '%s●%s' "$_SYELLOW" "$_SRESET"
  else
    printf '%s●%s' "$_SGREEN" "$_SRESET"
  fi
}

# ── Draw: horizontal rule ────────────────────────────────────────────────────
_sdraw_hr() {
  printf '%s%s%s%s%s\n' "$_SEL" "$_SDIM" "$_SGRAY" "$(printf '─%.0s' $(seq 1 "$_SCOLS"))" "$_SRESET"
}

# ── Draw: top bar (§4) ───────────────────────────────────────────────────────
_sdraw_top() {
  local now tasks_color
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    now="$_RALPH_STICKY_FROZEN_NOW"
  else
    now=$(date +%s)
  fi
  local start_ts="${_RALPH_STICKY_RUN_START_TS:-$now}"

  local done="${_RALPH_STICKY_TASKS_DONE:-0}"
  local total="${_RALPH_STICKY_TASKS_TOTAL:-0}"
  local oneshots="${_RALPH_STICKY_ROUND:-0}"
  local provider="${_RALPH_STICKY_PROVIDER:-unknown}"
  local ver="${RALPH_VERSION:-0.2}"

  if (( done >= total && total > 0 )); then
    tasks_color="$_SGREEN"
  else
    tasks_color="$_SRESET"
  fi

  local line
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    # Frozen mode: show "finished Xago · duration H:MM:SS" instead of "elapsed H:MM:SS".
    # "ago" updates on every frame using wall clock; "duration" stays fixed (historical).
    local wall_now ago_sec ran_sec
    wall_now=$(date +%s)
    ago_sec=$(( wall_now - now ))
    (( ago_sec < 0 )) && ago_sec=0
    ran_sec=$(( now - start_ts ))
    (( ran_sec < 0 )) && ran_sec=0
    local ran_disp ago_disp
    ran_disp=$(_sfmt_elapsed "$ran_sec")
    ago_disp=$(_sfmt_ago "$ago_sec")
    line=$(printf '%sralph %s%s %s· tasks%s %s%d/%d%s %s· oneshots%s %s%d%s %s· provider%s %s %s· finished%s %s%s ago%s %s· duration%s %s' \
      "$_SCYAN" "$ver" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$tasks_color" "$done" "$total" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$_SBOLD" "$oneshots" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$provider" \
      "$_SGRAY" "$_SRESET" "$_SDIM" "$ago_disp" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$ran_disp")
  else
    local elapsed
    elapsed=$(_sfmt_elapsed $(( now - start_ts )))
    line=$(printf '%sralph %s%s %s· tasks%s %s%d/%d%s %s· oneshots%s %s%d%s %s· provider%s %s %s· elapsed%s %s' \
      "$_SCYAN" "$ver" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$tasks_color" "$done" "$total" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$_SBOLD" "$oneshots" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$provider" \
      "$_SGRAY" "$_SRESET" "$elapsed")
  fi
  printf '%s%s\n' "$_SEL" "$line"
}

# ── Draw: event area (6-line window) ─────────────────────────────────────────
_sdraw_events() {
  local i count blank_count idx ts event max line
  count=${#_SEV_MSGS[@]}
  if [[ $count -gt $_SEVENT_WINDOW ]]; then count=$_SEVENT_WINDOW; fi
  blank_count=$(( _SEVENT_WINDOW - count ))
  max=$(( _SCOLS - 12 ))
  if [[ $max -lt 8 ]]; then max=8; fi

  for ((i=0; i<_SEVENT_WINDOW; i++)); do
    if (( i < blank_count )); then
      line=""
    else
      idx=$(( i - blank_count ))
      ts="${_SEV_TIMES[$idx]:-}"
      event="${_SEV_MSGS[$idx]:-}"
      line=$(printf '%s[%s]%s %s' "$_SGRAY" "$ts" "$_SRESET" "$(_struncate_bytes "$event" "$max")")
    fi
    printf '%s%s\n' "$_SEL" "$line"
  done
}

# ── Draw: bottom bar (§4) ────────────────────────────────────────────────────
# Frozen 模式末尾追加 " · (ctrl + c) exit" 暗色后缀（用于 ralph watch attach
# 已 finished run 的场景，提示用户怎么退出 watch）。Live 模式不加后缀——
# 提示文本在独立的 _sdraw_hint 行里展示。
_sdraw_bottom() {
  local now task_elapsed health spin task_short line
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    now="$_RALPH_STICKY_FROZEN_NOW"
  else
    now=$(date +%s)
  fi
  local task_start="${_RALPH_STICKY_TASK_START_TS:-$now}"
  task_elapsed=$(_sfmt_elapsed $(( now - task_start )))

  local frozen_suffix="" frozen_suffix_w=0
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    # 提示文本最弱化（_SDIM）；"all tasks done" 等状态信息用 _SGRAY（更显眼）
    frozen_suffix=$(printf ' %s· ( CTRL+C to exit )%s' "$_SDIM" "$_SRESET")
    frozen_suffix_w=24   # plain 列数 " · ( CTRL+C to exit )" = 23 + 1 缓冲
  fi

  # Special case: exit_reason=done → 全部任务勾完，底栏简化为 "<health> all tasks done"
  # round/stall/spinner/time/arrow 在此终态下都已无现实参考意义。
  if [[ "${_RALPH_STICKY_EXIT_REASON:-}" == "done" ]]; then
    health="$(_shealth)"
    line=$(printf '%s %sall tasks done%s' "$health" "$_SGRAY" "$_SRESET")
    line+="$frozen_suffix"
    printf '%s%s\n' "$_SEL" "$line"
    return
  fi

  if [[ "${_RALPH_STICKY_RETRY_COUNT:-0}" -gt 0 ]]; then
    spin="⏳"
  else
    spin="${_SSPIN_FRAMES[$_SSPIN_IDX]}"
  fi
  health="$(_shealth)"

  local task_try="${_RALPH_STICKY_TASK_TRY:-1}"
  local max_round="${_RALPH_STICKY_MAX_ROUND:-0}"
  local max_round_disp="∞"
  [[ "$max_round" -gt 0 ]] && max_round_disp="$max_round"

  local stall_count="${_RALPH_STICKY_STALL_COUNT:-0}"
  local stall_limit="${_RALPH_STICKY_STALL_LIMIT:-5}"

  # Task name truncation: compute visible prefix width
  local prefix_plain task_max
  prefix_plain="● round ${task_try}/${max_round_disp} · stall ${stall_count}/${stall_limit} · X HH:MM:SS · → "
  task_max=$(( _SCOLS - ${#prefix_plain} - 1 - frozen_suffix_w ))
  if [[ $task_max -lt 8 ]]; then task_max=8; fi
  task_short=$(_struncate_cols "${_RALPH_STICKY_CURRENT_TASK:-}" "$task_max")

  # Stall color (AMBER approaching, RED at limit)
  local stall_color stall_warn
  stall_warn=$(( stall_limit - 2 ))
  if [[ $stall_warn -lt 1 ]]; then stall_warn=1; fi
  if (( stall_count >= stall_limit )); then
    stall_color="$_SRED"
  elif (( stall_count >= stall_warn )); then
    stall_color="$_SAMBER"
  else
    stall_color="$_SRESET"
  fi

  line=$(printf '%s %sround%s %s%d/%s%s %s·%s %sstall%s %s%d/%d%s %s·%s %s%s%s %s %s· →%s %s%s' \
    "$health" \
    "$_SGRAY" "$_SRESET" "$_SBOLD" "$task_try" "$max_round_disp" "$_SRESET" \
    "$_SGRAY" "$_SRESET" \
    "$_SGRAY" "$_SRESET" "$stall_color" "$stall_count" "$stall_limit" "$_SRESET" \
    "$_SGRAY" "$_SRESET" \
    "$_SCYAN" "$spin" "$_SRESET" "$task_elapsed" \
    "$_SGRAY" "$_SRESET" \
    "$task_short" "$_SRESET")
  line+="$frozen_suffix"

  printf '%s%s\n' "$_SEL" "$line"
}

# ── Draw: hint line (live mode only) ─────────────────────────────────────────
# 仅 live 模式（FROZEN_NOW 空）渲染。Frozen 态的提示走 _sdraw_bottom 末尾后缀。
# 文本与 frozen 后缀完全一致，保证视觉一致性。
_sdraw_hint() {
  printf '%s%s( CTRL+C to exit )%s\n' "$_SEL" "$_SDIM" "$_SRESET"
}

# ── Public API ────────────────────────────────────────────────────────────────

ralph_sticky_enter() {
  _srefresh_size

  # Save + set terminal state
  if [[ -r /dev/tty ]]; then
    _SSTTY_SAVED="$(stty -g < /dev/tty 2>/dev/null || true)"
    if [[ -n "$_SSTTY_SAVED" ]]; then
      stty -echo -icanon min 0 time 0 < /dev/tty 2>/dev/null || true
      _SSTTY_ACTIVE=1
    fi
  fi

  # Initialize health tracking
  _SLAST_ACTIVITY_TS="$(date +%s)"
  _SLOG_LAST_SIZE=0

  # Reset render state
  _SRENDERED=0
  _SREDRAWING=0
  _SCLEANED=0
  _STICKY_LINES_LAST=""

  # Clear event buffer
  _SEV_TIMES=()
  _SEV_MSGS=()
  _SSPIN_IDX=0

  printf '%s' "$_SHIDE"
}

ralph_sticky_cleanup() {
  ((_SCLEANED)) && return 0
  _SCLEANED=1

  # Restore cursor position if mid-redraw
  if ((_SREDRAWING)); then
    printf '%s' "$_SREST"
    _SREDRAWING=0
  fi

  # Drain stale tty input then restore original settings
  if ((_SSTTY_ACTIVE)); then
    local _
    while IFS= read -r -s -n 1 -t 0.001 _ < /dev/tty 2>/dev/null; do
      :
    done
    stty "$_SSTTY_SAVED" < /dev/tty 2>/dev/null || true
    _SSTTY_ACTIVE=0
  fi

  printf '%s%s' "$_SSHOW" "$_SRESET"
}

ralph_sticky_append_event() {
  local event="$1"
  local ts
  ts=$(date +%H:%M:%S)

  _SEV_TIMES+=("$ts")
  _SEV_MSGS+=("$event")

  # Evict oldest events beyond window
  while ((${#_SEV_MSGS[@]} > _SEVENT_WINDOW)); do
    _SEV_TIMES=("${_SEV_TIMES[@]:1}")
    _SEV_MSGS=("${_SEV_MSGS[@]:1}")
  done
}

ralph_sticky_render_frame() {
  _srefresh_size

  # Advance spinner (frozen in finished/replay mode)
  if [[ -z "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    _SSPIN_IDX=$(( ( _SSPIN_IDX + 1 ) % 8 ))
  fi

  # 当前帧目标高度：live = N+5（含 hint 行），frozen = N+4
  local target_size
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    target_size=$(( _SEVENT_WINDOW + 4 ))
  else
    target_size=$(( _SEVENT_WINDOW + 5 ))
  fi
  local last_size="${_STICKY_LINES_LAST:-$target_size}"

  if ((_SRENDERED)); then
    # Move cursor up by PREVIOUS frame's size（处理 live↔frozen 变高场景）
    _scursor_up "$last_size"
  fi

  _sdraw_top
  _sdraw_hr
  _sdraw_events
  _sdraw_hr
  _sdraw_bottom
  if [[ -z "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    _sdraw_hint
  fi

  # 收缩场景（live 11 → frozen 10）：清掉残留的下一行，再把 cursor 拉回到
  # 当前帧底部，保证下一帧 cursor_up "$target_size" 能精确回到顶部。
  if (( target_size < last_size )); then
    local extra=$(( last_size - target_size ))
    local i
    for ((i=0; i<extra; i++)); do
      printf '%s\n' "$_SEL"
    done
    _scursor_up "$extra"
  fi

  _SRENDERED=1
  _STICKY_LINES_LAST="$target_size"
}

# ── Trap helpers ──────────────────────────────────────────────────────────────
# Caller invokes ralph_sticky_install_traps after ralph_sticky_enter
# to ensure INT/TERM/EXIT restore terminal state.
_ralph_sticky_on_int()  { ralph_sticky_cleanup; exit 130; }
_ralph_sticky_on_term() { ralph_sticky_cleanup; exit 143; }
_ralph_sticky_on_exit() { ralph_sticky_cleanup; }

ralph_sticky_install_traps() {
  trap '_ralph_sticky_on_int'  INT
  trap '_ralph_sticky_on_term' TERM
  trap '_ralph_sticky_on_exit' EXIT
}
