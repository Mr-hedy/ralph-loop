#!/usr/bin/env bash
# sticky.sh — 三段式 sticky renderer（I5-design §1/§4/§5/§13）
#
# 公共 API:
#   ralph_sticky_enter          — 进入 sticky 模式（保存 stty，hide cursor）
#   ralph_sticky_render_frame [final] — 渲染一帧（顶栏 + 横线 + 事件区 + 横线 + 底栏）
#   ralph_sticky_cleanup        — 退出 sticky 模式（还原 stty，show cursor）
#   ralph_sticky_append_event   — 追加事件到事件区
#   ralph_sticky_install_traps  — 安装 INT/TERM/EXIT trap（自动还原终端）
#
# 调用方需在 render_frame 前设置以下变量:
#   _RALPH_STICKY_RUN_START_TS   — run 启动 unix timestamp
#   _RALPH_STICKY_ROUND          — 本次 run 累计 oneshot 数（顶栏 oneshots N）
#   _RALPH_STICKY_TASK_START_TS  — 当前 task 首次出现 unix timestamp（底栏 spinner 用）
#   _RALPH_STICKY_TASK_INDEX     — 派发时的任务序号（未知时为空）
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
#   RALPH_UI_STICKY_REPLY_LINES  — 最新回复行数（默认 2）
#   RALPH_UI_STICKY_EVENT_LINES  — 滚动事件行数（默认 4）
#   RALPH_UI_HEALTH_GREEN_SEC    — 健康灯绿色阈值秒（默认 60）
#   RALPH_UI_HEALTH_RED_SEC      — 健康灯红色阈值秒（默认 300）

set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/events.sh"

# ── ANSI constants ────────────────────────────────────────────────────────────
_SCSI=$'\033['
_SHIDE="${_SCSI}?25l"
_SSHOW="${_SCSI}?25h"
_SWRAP_OFF="${_SCSI}?7l"
_SWRAP_ON="${_SCSI}?7h"
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
if [[ -n "${NO_COLOR:-}" ]]; then
  _SDIM="" _SBOLD="" _SRESET="" _SGREEN="" _SYELLOW="" _SRED=""
  _SCYAN="" _SGRAY="" _SAMBER=""
fi

# ── Layout config ─────────────────────────────────────────────────────────────
# 限定十进制数值，防止前导零被按八进制解释或非法值进入 shell 算术。
_sconfig_number() {
  if [[ "$1" =~ ^[0-9]{1,9}$ ]] && (( 10#$1 >= ${3:-0} && 10#$1 <= ${4:-999999999} )); then
    printf '%s' "$(( 10#$1 ))"
  else
    printf '%s' "$2"
  fi
}
_SREPLY_ROWS="$(_sconfig_number "${RALPH_UI_STICKY_REPLY_LINES:-}" 2 1)"
_SEVENT_WINDOW="$(_sconfig_number "${RALPH_UI_STICKY_EVENT_LINES:-}" 4 1)"
# 缓存上限与请求的行数分开。多保留一个码点用于区分刚好填满与确实截断。
_SREPLY_LIMIT=131072
if (( _SEVENT_WINDOW > 65535 )); then _SEVENT_WINDOW=65535; fi  # winsize 的行数上限
_SHEALTH_GREEN="$(_sconfig_number "${RALPH_UI_HEALTH_GREEN_SEC:-60}" 60)"
_SHEALTH_RED="$(_sconfig_number "${RALPH_UI_HEALTH_RED_SEC:-300}" 300)"
if (( _SHEALTH_RED <= _SHEALTH_GREEN )); then
  _SHEALTH_GREEN=60
  _SHEALTH_RED=300
fi

# ── Internal state ────────────────────────────────────────────────────────────
_SRENDERED=0
_SREDRAWING=0
_SSTTY_SAVED=""
_SSTTY_ACTIVE=0
_SINPUT_POLL=0
_SCLEANED=0
_SCOLS=80
_SROWS=24
_SEV_TIMES=()
_SEV_MSGS=()
_SEV_NEXT=0
_SSPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧")
_SSPIN_IDX=0
_SLOG_LAST_SIZE=0
_SLOG_LAST_ID=""
_SLAST_ACTIVITY_TS=0
_STICKY_LINES_LAST=""   # last frame's rendered height (for live↔frozen size transitions)
_SFRAME_COLS=0 _SFRAME_ROWS=0
_SRESIZE_PENDING=''

# ── Terminal size ─────────────────────────────────────────────────────────────
_srefresh_size() {
  local size
  # 保存实际的输出 fd，避免命令替换中的 stdout 管道遮住目标 PTY。
  if { size="$(stty size <&9 2>/dev/null)"; } 9>&1 && [[ "$size" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
    _SROWS="${BASH_REMATCH[1]}"
    _SCOLS="${BASH_REMATCH[2]}"
    [[ "$_SCOLS" != 0 ]] || _SCOLS=80
    [[ "$_SROWS" != 0 ]] || _SROWS=24
  else
    _SCOLS="$(_sconfig_number "${COLUMNS:-$(tput cols 2>/dev/null || true)}" 80 1 65535)"
    _SROWS="$(_sconfig_number "${LINES:-$(tput lines 2>/dev/null || true)}" 24 1 65535)"
  fi
}

# ── Utility ───────────────────────────────────────────────────────────────────
# Bash 按 locale 切字符串。只在文字处理函数内使用 UTF-8，不改 provider 的环境。
_sticky_text_locale() {
  local probe='中' candidate LC_ALL="${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}"
  for candidate in "$LC_ALL" C.UTF-8 en_US.UTF-8 UTF-8; do
    LC_ALL="$candidate"
    if (( ${#probe} == 1 )); then printf '%s' "$LC_ALL"; return; fi
  done
  printf 'C'
}
_STEXT_LOCALE="$(_sticky_text_locale 2>/dev/null)"

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
  # Bash 3.2 的 printf 返回非 ASCII 字符的首字节（可能为负），新 Bash
  # 可返回码点。统一保守预留两列，避免中文、假名、全角字符和 emoji 溢出。
  local code
  printf -v code '%d' "'$1"
  if (( code < 0 || code > 127 )); then _SCHAR_WIDTH=2; else _SCHAR_WIDTH=1; fi
}

# Truncate string to fit max display columns (CJK-aware), append "..." if truncated
_struncate_cols() {
  local LC_ALL="$_STEXT_LOCALE"
  local txt="$1" max="$2"
  local suffix="..." suffix_w=3 out="" used=0 i ch w limit total=0

  if [[ $max -lt 1 ]]; then return; fi

  for ((i=0; i<${#txt}; i++)); do
    ch="${txt:i:1}"
    _schar_width "$ch"
    w="$_SCHAR_WIDTH"
    total=$(( total + w ))
    if (( total > max )); then break; fi
  done
  if (( total <= max )); then
    printf '%s' "$txt"
    return
  fi

  if (( max <= suffix_w )); then
    printf '%s' "${suffix:0:max}"
    return
  fi

  limit=$(( max - suffix_w ))
  for ((i=0; i<${#txt}; i++)); do
    ch="${txt:i:1}"
    _schar_width "$ch"
    w="$_SCHAR_WIDTH"
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
  local now exit_reason color="$_SGREEN" symbol="●"
  now=$(date +%s)
  exit_reason="${_RALPH_STICKY_EXIT_REASON:-}"

  # Exit-state lights
  case "$exit_reason" in
    done)
      printf -v _SHEALTH '%s✓%s' "$_SGREEN" "$_SRESET"
      printf '%s' "$_SHEALTH"
      return
      ;;
    provider_failed|timeout|blocked_by_human|protocol_changed)
      printf -v _SHEALTH '%s✗%s' "$_SRED" "$_SRESET"
      printf '%s' "$_SHEALTH"
      return
      ;;
    interrupted)
      printf -v _SHEALTH '%s⏸%s' "$_SYELLOW" "$_SRESET"
      printf '%s' "$_SHEALTH"
      return
      ;;
  esac

  # Running: check provider.stdout.log byte growth
  local log_path="${_RALPH_STICKY_LOG_PATH:-}"
  if [[ -n "$log_path" && -f "$log_path" ]]; then
    local current_size current_id attributes
    attributes="$(stat -f '%i %z' "$log_path" 2>/dev/null)" || attributes=""
    if [[ ! "$attributes" =~ ^[0-9]+[[:space:]][0-9]+$ ]]; then
      attributes="$(stat -c '%i %s' "$log_path" 2>/dev/null)" || attributes=""
    fi
    [[ "$attributes" =~ ^[0-9]+[[:space:]][0-9]+$ ]] || attributes="0 0"
    read -r current_id current_size <<< "$attributes"
    if [[ "$current_id" != "$_SLOG_LAST_ID" ]] || (( current_size != _SLOG_LAST_SIZE )); then
      _SLAST_ACTIVITY_TS="$now"
      _SLOG_LAST_SIZE="$current_size"
      _SLOG_LAST_ID="$current_id"
    fi
  fi

  local since=$(( now - _SLAST_ACTIVITY_TS ))
  if (( since > _SHEALTH_RED )); then
    color="$_SRED"
  elif (( since > _SHEALTH_GREEN )); then
    color="$_SYELLOW"
  fi
  printf -v _SHEALTH '%s%s%s' "$color" "$symbol" "$_SRESET"
  printf '%s' "$_SHEALTH"
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

  local task_index="${_RALPH_STICKY_TASK_INDEX:--}"
  local total="${_RALPH_STICKY_TASKS_TOTAL:-0}"
  local oneshots="${_RALPH_STICKY_ROUND:-0}"
  local provider="${_RALPH_STICKY_PROVIDER:-unknown}"
  local ver="${RALPH_VERSION:-0.2}"

  if [[ "${_RALPH_STICKY_EXIT_REASON:-}" == done ]]; then
    task_index="$total"
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
    line=$(printf '%sralph %s%s %s· tasks%s %s%s/%d%s %s· oneshots%s %s%d%s %s· provider%s %s %s· finished%s %s%s ago%s %s· duration%s %s' \
      "$_SCYAN" "$ver" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$tasks_color" "$task_index" "$total" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$_SBOLD" "$oneshots" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$provider" \
      "$_SGRAY" "$_SRESET" "$_SDIM" "$ago_disp" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$ran_disp")
  else
    local elapsed
    elapsed=$(_sfmt_elapsed $(( now - start_ts )))
    line=$(printf '%sralph %s%s %s· tasks%s %s%s/%d%s %s· oneshots%s %s%d%s %s· provider%s %s %s· elapsed%s %s' \
      "$_SCYAN" "$ver" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$tasks_color" "$task_index" "$total" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$_SBOLD" "$oneshots" "$_SRESET" \
      "$_SGRAY" "$_SRESET" "$provider" \
      "$_SGRAY" "$_SRESET" "$elapsed")
  fi
  printf '%s%s\n' "$_SEL" "$line"
}

# 当前观察进程独占的游标和显示状态。持有 fd 8，避免两次刷新之间旧 inode 被复用。
_SREAD_PATH='' _SREAD_ID='' _SREAD_POS=0 _SREAD_SIZE=0 _SREAD_WAIT_SIZE=-1
_SREPLY_ID='' _SREPLY_TEXT='' _SREPLY_TIME=''

_SREPLY_SESSIONS=() _SREPLY_STEPS=()

_sticky_clear_events() {
  _SREPLY_ID='' _SREPLY_TEXT='' _SREPLY_TIME=''
  _SEV_TIMES=() _SEV_MSGS=() _SEV_NEXT=0
  _SREPLY_SESSIONS=() _SREPLY_STEPS=()
  _SREAD_POS=0 _SREAD_SIZE=0 _SREAD_WAIT_SIZE=-1
}

_sticky_reset_log() {
  exec 8<&-
  _SREAD_PATH='' _SREAD_ID=''
  _sticky_clear_events
}

# 每个会话只保存已出现的最新步骤编号；退回旧步骤的迟到片段不能覆盖新回复。
_sticky_new_step() {
  local session="${1%/*}" step="${1##*/}" i
  for ((i=0; i<${#_SREPLY_SESSIONS[@]}; i++)); do
    if [[ "${_SREPLY_SESSIONS[i]}" == "$session" ]]; then
      (( step > _SREPLY_STEPS[i] )) || return 1
      _SREPLY_STEPS[i]="$step"
      return 0
    fi
  done
  _SREPLY_SESSIONS+=("$session")
  _SREPLY_STEPS+=("$step")
}

_sticky_reply() {
  local LC_ALL="$_STEXT_LOCALE"
  local op="$1" id="$2" text="$3" stamp="$4"
  if [[ "$op" == append && "$id" == "$_SREPLY_ID" ]]; then
    # 每个片段已经折叠空白；拼接时只消除边界上重复的空格。
    local remaining=$(( _SREPLY_LIMIT + 1 - ${#_SREPLY_TEXT} ))
    (( remaining > 0 )) || return 0
    if [[ "${_SREPLY_TEXT: -1}" == ' ' && "${text:0:1}" == ' ' ]]; then text="${text:1}"; fi
    _SREPLY_TEXT+="${text:0:remaining}"
    return 0
  fi
  if [[ "${text:0:1}" == ' ' ]]; then text="${text:1}"; fi
  text="${text:0:_SREPLY_LIMIT+1}"
  [[ -n "$text" ]] || return 0
  if [[ "$op" == append ]]; then _sticky_new_step "$id" || return 0; fi
  if [[ "$op" == final ]] && [[ "$text" == "$_SREPLY_TEXT" || "$text " == "$_SREPLY_TEXT" || "$text" == "$_SREPLY_TEXT " ]]; then
    return 0
  fi
  if [[ "$id" == null || "$id" != "$_SREPLY_ID" ]]; then _SREPLY_TIME="$stamp"; fi
  _SREPLY_ID="$id"
  _SREPLY_TEXT="$text"
}

ralph_sticky_read_log() {
  local path="$1" flush="${2:-0}" attrs id size stamp op key text
  if [[ "$path" != "$_SREAD_PATH" ]]; then _sticky_reset_log; fi
  [[ -f "$path" ]] || return 0
  if ! { exec 8< "$path"; } 2>/dev/null; then return 0; fi
  attrs="$(stat -Lf '%d:%i %z' /dev/fd/8 2>/dev/null)" ||
    attrs="$(stat -Lc '%d:%i %s' /dev/fd/8 2>/dev/null)" || return 0
  read -r id size <<< "$attrs"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  if [[ "$id" != "$_SREAD_ID" ]] || (( size < _SREAD_SIZE )); then
    _sticky_clear_events
  fi
  _SREAD_PATH="$path" _SREAD_ID="$id" _SREAD_SIZE="$size"
  (( size > _SREAD_POS && (flush || size != _SREAD_WAIT_SIZE) )) || return 0
  local before="$_SREAD_POS"
  stamp="$(date +%H:%M:%S)"
  # 只读同一 fd 在取样时已经写完的记录。awk 在 C locale 数原始字节，
  # 只转交以 { 开头的 provider 行；最后一行数字是本批真正消费到的位置。
  # 未收齐的行留到下帧，结束时允许最后一行没有换行符。
  # tr 等长替换 NUL 以保留 BSD awk 的字节计数；分批结束时它的 EPIPE 不进入画面。
  while IFS=$'\t' read -r op key text; do
    case "$op" in
      event) ralph_sticky_append_event "$key" "$stamp" ;;
      cursor) _SREAD_POS="$key" ;;
      set|append|final) _sticky_reply "$op" "$key" "$text" "$stamp" ;;
    esac
  done < <(tail -c "+$(( _SREAD_POS + 1 ))" /dev/fd/8 2>/dev/null |
    LC_ALL=C tr '\000' '\001' 2>/dev/null |
    LC_ALL=C awk -v pos="$_SREAD_POS" -v endpos="$size" -v flush="$flush" '
      BEGIN {start=pos}
      {
        nextpos=pos+length($0)+1
        if (nextpos>endpos && !(flush && nextpos==endpos+1)) exit
        if (substr($0,1,1)=="{") print
        pos=(nextpos>endpos ? endpos : nextpos)
        if (pos==endpos || NR>=128 || pos-start>=262144) exit
      }
      END {printf "%.0f\n",pos}
    ' | ralph_filter_events sticky "$(( _SREPLY_LIMIT + 2 ))")
  if (( _SREAD_POS == before )); then _SREAD_WAIT_SIZE="$size"; fi
}

# 正常结束时收齐最后一批记录；每批之间轮询键盘，取消路径直接保留已有画面。
ralph_sticky_drain_log() {
  local path="$1" before previous_id
  while true; do
    _sticky_poll_input
    before="$_SREAD_POS" previous_id="$_SREAD_ID"
    ralph_sticky_read_log "$path" 1
    (( _SREAD_POS < _SREAD_SIZE )) || break
    [[ "$_SREAD_ID" != "$previous_id" || "$_SREAD_POS" != "$before" ]] || break
  done
}

_sdraw_reply() {
  local rows="$1" stamp='' pad indent width
  (( rows > 0 )) || return 0
  if [[ -n "$_SREPLY_TIME" ]]; then stamp="[$_SREPLY_TIME] "; fi
  indent=$(( ${#stamp} + 3 ))  # 时间、两列气泡和一个空格
  width=$(( _SCOLS > indent ? _SCOLS - indent : 0 ))
  printf -v pad '%*s' "$indent" ''

  # 一次按 UTF-8 码点排出可见行；非 ASCII 保守占两列。逐字从长字符串
  # 取子串会反复扫描前缀，在较高的回复区阻塞重绘及键盘轮询。
  printf '%s' "$_SREPLY_TEXT" | jq -Rrs --argjson rows "$rows" --argjson width "$width" \
    --argjson cap "$_SREPLY_LIMIT" --arg first "$_SEL$_SGRAY$stamp${_SRESET}💬 " --arg rest "$_SEL$pad" '
    def cells: if . < 128 then 1 else 2 end;
    def wrap:
      foreach (.[], null) as $c ({row:[], used:0};
        del(.out) |
        if $c == null then .out = .row
        elif $c == 32 and .used == 0 then .
        else (if ($c|cells) > $width then 46 else $c end) as $ch | ($ch|cells) as $w |
          if .used+$w <= $width then .row += [$ch] | .used += $w
          else .out = .row |
            if $ch == 32 then .row=[] | .used=0 else .row=[$ch] | .used=$w end
          end
        end; .out // empty);
    def ellipsis:
      if $width <= 3 then "." * $width else
        ([foreach .[] as $c (0; .+($c|cells); if . <= $width-3 then $c else empty end)] | implode) + "..."
      end;
    (if $width == 0 then [] else
       (if length > $cap then .[:$cap]+"..." else rtrimstr(" ") end) |
       (if length == 0 then "本轮暂未收到模型文字。" else . end) |
       .[:($rows*($width+1)+1)] | explode | [limit($rows+1; wrap)]
     end) as $lines |
    range($rows) as $i |
    (if $i == 0 then $first else $rest end) +
    (($lines[$i] // []) | if $i == $rows-1 and ($lines|length) > $rows then ellipsis else implode end)
  '
}

# ── Draw: scrolling event area ───────────────────────────────────────────────
_sdraw_events() {
  local window="${1:-$_SEVENT_WINDOW}"
  local i count blank_count idx ts event max line
  count=${#_SEV_MSGS[@]}
  if [[ $count -gt $window ]]; then count=$window; fi
  blank_count=$(( window - count ))
  max=$(( _SCOLS - 12 ))
  if [[ $max -lt 8 ]]; then max=8; fi

  for ((i=0; i<window; i++)); do
    if (( i < blank_count )); then
      line=""
    else
      idx=$(( (_SEV_NEXT - count + i - blank_count + _SEVENT_WINDOW) % _SEVENT_WINDOW ))
      ts="${_SEV_TIMES[$idx]:-}"
      event="${_SEV_MSGS[$idx]:-}"
      event="${event//$'\n'/ }"
      event="${event//$'\r'/ }"
      event="${event//$'\t'/ }"
      line=$(printf '%s[%s]%s %s' "$_SGRAY" "$ts" "$_SRESET" "$(_struncate_cols "$event" "$max")")
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
    frozen_suffix=$(printf ' %s· (Ctrl+C to exit)%s' "$_SDIM" "$_SRESET")
    frozen_suffix_w=24   # plain 列数 " · (Ctrl+C to exit)" = 23 + 1 缓冲
  fi

  # Special case: exit_reason=done → 全部任务勾完，底栏简化为 "<health> all tasks done"
  # round/stall/spinner/time/arrow 在此终态下都已无现实参考意义。
  if [[ "${_RALPH_STICKY_EXIT_REASON:-}" == "done" ]]; then
    _shealth >/dev/null
    health="$_SHEALTH"
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
  # 日志活动状态必须在渲染进程保留；命令替换会在子 shell 丢失更新。
  _shealth >/dev/null
  health="$_SHEALTH"

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
  local title="${_RALPH_STICKY_CURRENT_TASK:-}"
  task_short=$(_struncate_cols "${title//[[:cntrl:]]/ }" "$task_max")

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
  printf '%s%s(Ctrl+C to exit)%s\n' "$_SEL" "$_SDIM" "$_SRESET"
}

# ── Public API ────────────────────────────────────────────────────────────────

ralph_sticky_enter() {
  _srefresh_size
  _SINPUT_POLL=0

  # Save + set terminal state
  if [[ -r /dev/tty ]]; then
    _SSTTY_SAVED="$(stty -g 2>/dev/null < /dev/tty || true)"
    if [[ -n "$_SSTTY_SAVED" ]]; then
      if stty -echo -icanon min 0 time 0 < /dev/tty 2>/dev/null; then
        _SSTTY_ACTIVE=1
        # 持续渲染的调用方可启用键盘轮询；其他调用保持原生 SIGINT。
        # 避免刷新时键盘信号同时打到前台 helper。
        if [[ "${1:-0}" == 1 ]] && stty intr undef < /dev/tty 2>/dev/null; then
          _SINPUT_POLL=1
        fi
      fi
    fi
  fi

  # Initialize health tracking
  _SLAST_ACTIVITY_TS="$(date +%s)"
  _SLOG_LAST_SIZE=0
  _SLOG_LAST_ID=""

  # Reset render state
  _SRENDERED=0
  _SREDRAWING=0
  _SCLEANED=0
  _STICKY_LINES_LAST=""
  _SRESIZE_PENDING=''

  _sticky_reset_log
  _SSPIN_IDX=0

  printf '%s' "$_SHIDE"
}

ralph_sticky_cleanup() {
  ((_SCLEANED)) && return 0
  _SCLEANED=1
  exec 8<&-
  _SINPUT_POLL=0

  # Restore cursor position if mid-redraw
  if ((_SREDRAWING)); then
    printf '%s' "$_SREST"
    _SREDRAWING=0
  fi

  # Drain stale tty input then restore original settings
  if ((_SSTTY_ACTIVE)); then
    local _
    while IFS= read -r _ < /dev/tty 2>/dev/null; do
      :
    done
    stty "$_SSTTY_SAVED" < /dev/tty 2>/dev/null || true
    _SSTTY_ACTIVE=0
  fi

  printf '%s%s%s' "$_SWRAP_ON" "$_SSHOW" "$_SRESET"
  if [[ "${_STICKY_LINES_LAST:-1}" -eq 0 ]]; then printf '\n'; fi
}

ralph_sticky_append_event() {
  local event="$1"
  local ts="${2:-$(date +%H:%M:%S)}"

  _SEV_TIMES[_SEV_NEXT]="$ts"
  _SEV_MSGS[_SEV_NEXT]="$event"
  _SEV_NEXT=$(( (_SEV_NEXT + 1) % _SEVENT_WINDOW ))
}

_sticky_poll_input() {
  if (( _SINPUT_POLL )); then
    # 已设置 min=0/time=0；普通 read 不阻塞，可能以 EOF 返回部分输入。
    # Bash 3.2 不支持 read -t 的小数，也不再让 -n/-s 临时改终端模式。
    local key=""
    IFS= read -r key < /dev/tty 2>/dev/null || true
    if [[ "$key" == *$'\003'* ]]; then
      kill -INT "$$"
      return 0
    fi
  fi
}

ralph_sticky_render_frame() {
  _sticky_poll_input
  _srefresh_size
  local resized=0 geometry="${_SCOLS}x${_SROWS}"
  if (( _SRENDERED && (_SFRAME_COLS != _SCOLS || _SFRAME_ROWS != _SROWS) )); then
    # 连续拖动窗口合并到尺寸稳定后的重绘；退出前的最后一帧立即绘制。
    if [[ "${1:-}" != final && "$_SRESIZE_PENDING" != "$geometry" ]]; then
      _SRESIZE_PENDING="$geometry"
      return 0
    fi
    resized=1
  fi
  _SRESIZE_PENDING=''

  # Advance spinner (frozen in finished/replay mode)
  if [[ -z "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    _SSPIN_IDX=$(( ( _SSPIN_IDX + 1 ) % 8 ))
  fi

  # 保留一行给绘制后的光标，避免最后一个换行把头部滚入历史。
  local overhead=5 reply_lines=0 event_lines=0 available target_size
  if [[ -n "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
    overhead=4
  fi
  if (( _SROWS <= 5 )); then
    target_size=1
    (( _SROWS > 1 )) || target_size=0
  else
    available=$(( _SROWS - overhead - 1 ))
    reply_lines=$(( available < _SREPLY_ROWS ? available : _SREPLY_ROWS ))
    # 至少容得下两行时，较大的回复区配置也要给最新工具事件留一行。
    if (( available > 1 && reply_lines == available )); then reply_lines=$(( available - 1 )); fi
    event_lines=$(( available - reply_lines ))
    if (( event_lines > _SEVENT_WINDOW )); then event_lines=$_SEVENT_WINDOW; fi
    target_size=$(( reply_lines + event_lines + overhead ))
  fi
  local last_size="${_STICKY_LINES_LAST:-$target_size}"

  # 固定行数回移依赖每个逻辑行只占一个终端行。宽字符、窄窗口和
  # 顶/底栏不能靠字符数量保证宽度；绘制时禁止自动折行，结束立即还原。
  printf '%s' "$_SWRAP_OFF"

  printf '\r'
  if (( resized )); then
    # 尺寸变化可能把旧帧从历史带回视口。保留光标之前的内容，用普通
    # 换行把它送入滚动历史，从空页重新定位；无需猜测旧顶栏坐标。
    printf '%sJ' "$_SCSI"
    printf '%*s' "$_SROWS" '' | tr ' ' '\n'
    if (( _SROWS > 1 )); then _scursor_up "$(( _SROWS - 1 ))"; fi
    printf '\r'
  elif (( _SRENDERED && last_size > 0 )); then
    # Move cursor up by PREVIOUS frame's size（处理 live↔frozen 变高场景）
    _scursor_up "$last_size"
  fi

  if (( _SROWS <= 5 )); then
    # 极矮窗口保留顶栏；一行窗口不输出换行，以免每次刷新滚屏。
    if (( _SROWS == 1 )); then _sdraw_top | tr -d '\r\n'; else _sdraw_top; fi
  else
    _sdraw_top
    _sdraw_hr
    _sdraw_reply "$reply_lines"
    _sdraw_events "$event_lines"
    _sdraw_hr
    _sdraw_bottom
    if [[ -z "${_RALPH_STICKY_FROZEN_NOW:-}" ]]; then
      _sdraw_hint
    fi
  fi

  # 收缩场景（如结束后少一行提示）：清掉残留的下一行，再把 cursor 拉回到
  # 当前帧底部，保证下一帧 cursor_up "$target_size" 能精确回到顶部。
  if (( target_size < last_size )); then
    # 清除光标以下的旧内容，不额外换行；窗口收缩时额外换行会再次滚屏。
    printf '%sJ' "$_SCSI"
  fi

  _SRENDERED=1
  _STICKY_LINES_LAST="$target_size"
  _SFRAME_COLS="$_SCOLS" _SFRAME_ROWS="$_SROWS"
  printf '%s' "$_SWRAP_ON"
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
