#!/usr/bin/env bash
set -euo pipefail

# watch.sh — watch command: TTY sticky / non-TTY one-line bar (I5-design §2)
#
# TTY:   source sticky.sh → poll status.json + tail provider.stdout.log → sticky render
# Non-TTY: one-line bar snapshot from status.json, then exit
#
# Ctrl+C exits watch only — does not affect the running ralph process.

# ── Truncate run_id: first 12 chars + "..." ─────────────────────────────────
_ralph_watch_truncate_id() {
  local id="$1"
  if [[ ${#id} -gt 12 ]]; then
    printf '%s...' "${id:0:12}"
  else
    printf '%s' "$id"
  fi
}

# ── Color detection ─────────────────────────────────────────────────────────
_ralph_watch_color_supported() {
  [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]
}

# ── Pick status color by state / exit_reason ─────────────────────────────────
_ralph_watch_status_color() {
  local state="$1" exit_reason="$2"
  if [[ "$state" == "running" || "$exit_reason" == "done" ]]; then
    printf '%s' "green"
  elif [[ "$exit_reason" == "provider_failed" || "$exit_reason" == "protocol_changed" || "$exit_reason" == "timeout" \
        || "$exit_reason" == "blocked_by_human" ]]; then
    printf '%s' "red"
  elif [[ "$exit_reason" == "locked" || "$exit_reason" == "interrupted" ]]; then
    printf '%s' "yellow"
  fi
}

# ── Bar content: one-line status string from status.json (non-TTY only) ─────
_ralph_watch_bar_text() {
  local f="$1"

  if [[ ! -f "$f" ]]; then
    printf '%s' "no active run"
    return 0
  fi

  local status_json
  status_json="$(_w_status_snapshot "$f")" \
    || { echo "ralph watch: cannot read status.json" >&2; return 1; }

  local run_id round checked total state exit_reason provider short_id bar
  run_id="$(_ralph_status_snapshot_val "$status_json" "run_id")"
  round="$(_ralph_status_snapshot_val "$status_json" "round")"
  checked="$(_ralph_status_snapshot_val "$status_json" "tasks_checked")"
  total="$(_ralph_status_snapshot_val "$status_json" "tasks_total")"
  state="$(_ralph_status_snapshot_val "$status_json" "state")"
  exit_reason="$(_ralph_status_snapshot_val "$status_json" "exit_reason")"
  provider="$(_ralph_status_snapshot_val "$status_json" "provider")"

  short_id="$(_ralph_watch_truncate_id "$run_id")"

  local dim="" reset="" green="" red="" yellow=""
  if _ralph_watch_color_supported; then
    dim=$'\033[2m'
    reset=$'\033[0m'
    green=$'\033[32m'
    red=$'\033[31m'
    yellow=$'\033[33m'
  fi

  local status_color="" color_name
  color_name="$(_ralph_watch_status_color "$state" "${exit_reason:-}")"
  case "$color_name" in
    green)  status_color="$green"  ;;
    red)    status_color="$red"    ;;
    yellow) status_color="$yellow" ;;
  esac

  bar="${dim}run:${reset} ${short_id}"
  bar+="  ${dim}round${reset} ${round}"
  bar+="  ${checked}/${total} ${dim}tasks${reset}"
  bar+="  ${dim}state:${reset} ${status_color}${state:-}${reset}"
  if [[ -n "$exit_reason" && "$exit_reason" != "null" ]]; then
    bar+="  ${dim}exit_reason:${reset} ${status_color}${exit_reason}${reset}"
  fi
  if [[ -n "$provider" && "$provider" != "null" ]]; then
    bar+="  ${dim}provider:${reset} ${provider}"
  fi

  printf '%s' "$bar"
}

# 只把单份快照中经过类型校验的计数和可显示的文本交给终端。
_w_status_snapshot() {
  jq -sce '
    def uint: type == "number" and . >= 0 and . <= 2147483647 and . == floor;
    def count($default): if uint then . else $default end;
    def display_text: if type == "string" then gsub("[\u0000-\u001f\u007f-\u009f]"; " ") else null end;
    select(length == 1) | .[0] | select(type == "object") |
    select(.run_id == null or (.run_id | type == "string" and test("^[A-Za-z0-9_-]*\\z"))) |
    select(.round == null or (.round | uint)) |
    {run_id, round:(.round // 0), provider:(.provider|display_text), state:(.state|display_text),
     exit_reason:(.exit_reason|display_text), started_at:(.started_at|display_text),
     task_started_at:(.task_started_at|display_text), updated_at:(.updated_at|display_text),
     tasks_total:(.tasks_total|count(0)), tasks_checked:(.tasks_checked|count(0)),
     task_try:(.task_try|count(1)), retry_count:(.retry_count|count(0)),
     round_task:(.round_task | if type == "object" and (.index|uint) and (.total|uint)
        and .index > 0 and .index <= .total and (.title|type) == "string"
        then {index,total,title:(.title|display_text)} else null end)}
  ' "$1" 2>/dev/null
}

_w_json_count() {
  jq -ser --arg key "$2" 'select(length == 1) | .[0][$key] | select(type == "number" and . >= 0 and . <= 2147483647 and . == floor)' \
    "$1" 2>/dev/null || printf '%s' "$3"
}

_w_read_context() {
  _RALPH_STICKY_MAX_ROUND="$(_w_json_count "$1/context.json" max_round 0)"
  _RALPH_STICKY_STALL_LIMIT="$(_w_json_count "$1/context.json" stall_limit 5)"
}

# 同一帧的字段必须来自同一个 status 版本，而非每个字段重新打开文件。
_w_snapshot_val() {
  jq -r --arg key "$2" '.[$key] // ""' <<< "$1"
}

# 详情视图只消费完整行；半行留到下次刷新，已结束 round 可输出末尾无换行行。
_W_DETAILS_POS=0
_W_DETAILS_ID=""
_W_DETAILS_LOG=""
_w_details_read_log() {
  local log_path="$1" flush="${2:-0}" line size identity consumed
  local LC_ALL=C
  [[ -f "$log_path" ]] || return 0
  # 每次重新打开文件，从偏移 0 读取同一 inode 的属性和内容；持有描述符，
  # 避免读到一半换文件或观察暂停期间旧 inode 被重用。
  if ! { exec 3< "$log_path"; } 2>/dev/null; then return 0; fi
  identity="$(ls -diL /dev/fd/3 2>/dev/null | awk '{print $1}')" || return 0
  [[ -n "$identity" ]] || return 0
  if [[ "$log_path" != "$_W_DETAILS_LOG" ]]; then
    _W_DETAILS_POS=0
    _W_DETAILS_ID=""
    _W_DETAILS_LOG="$log_path"
  elif [[ -n "$_W_DETAILS_ID" && "$identity" != "$_W_DETAILS_ID" ]]; then
    printf '[provider] 新执行日志，重新读取当前内容。\n'
    _W_DETAILS_POS=0
  fi
  _W_DETAILS_ID="$identity"
  size="$(ls -lnL /dev/fd/3 2>/dev/null | awk '{print $5}')" || return 0
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  if [[ "$size" -lt "$_W_DETAILS_POS" ]]; then
    printf '[provider] 执行日志已重新开始，重新读取当前内容。\n'
    _W_DETAILS_POS=0
  fi
  while true; do
    if IFS= read -r line; then consumed=$(( ${#line} + 1 ))
    elif [[ "$flush" -eq 1 && -n "$line" ]]; then consumed=${#line}
    else break; fi
    _W_DETAILS_POS=$(( _W_DETAILS_POS + consumed ))
    printf '%s\n' "$line" | ralph_filter_events details || true
  done < <(tail -c "+$(( _W_DETAILS_POS + 1 ))" /dev/fd/3 2>/dev/null | LC_ALL=C tr '\000' '\001')
  return 0
}

# 只枚举实际存在的轮次；损坏的轮数也不会让详情视图扫描海量空路径。
_w_rounds_between() {
  local path n
  for path in "$1"/round-*/provider.stdout.log; do
    [[ -f "$path" ]] || continue
    n="${path%/*}"; n="${n##*/round-}"
    [[ "$n" =~ ^[0-9]{3,10}$ ]] || continue
    n=$(( 10#$n ))
    if (( $2 < n && n < $3 )); then printf '%d\n' "$n"; fi
  done | sort -nu
}

# 默认 watch 保持原有紧凑契约；详情模式提供可回看的执行过程。
ralph_watch_details() {
  source "$RALPH_ROOT/lib/events.sh"
  local workspace status_file follow=0
  workspace="$(ralph_workspace_root)"
  status_file="$workspace/.ralph/status.json"
  [[ -t 1 ]] && follow=1
  local run_id provider round state exit_reason checked total
  local prev_run="" prev_log="" prev_state="" prev_round=0 log_path="" padded fields flush skipped skipped_log read_failures=0
  _W_DETAILS_POS=0
  _W_DETAILS_ID=""
  _W_DETAILS_LOG=""
  while true; do
    if [[ ! -f "$status_file" ]]; then
      printf 'ralph watch: no active run (status.json not found)\n'
      exec 3<&-
      return 0
    fi
    if ! fields="$(_w_status_snapshot "$status_file" | jq -er '[.run_id // "-", .provider // "-", .round // 0,
        .state // "-", .exit_reason // "-", .tasks_checked // 0, .tasks_total // 0] | @tsv')"; then
      read_failures=$(( read_failures + 1 ))
      if [[ "$read_failures" -lt 4 ]]; then
        sleep 0.5
        continue
      fi
      printf 'ralph watch: cannot read status.json\n' >&2
      exec 3<&-
      return 1
    fi
    read_failures=0
    IFS=$'\t' read -r run_id provider round state exit_reason checked total <<< "$fields"
    if [[ "$run_id" == "-" ]]; then
      printf 'ralph watch: no active run\n'
      exec 3<&-
      return 0
    fi
    if [[ ! "$run_id" =~ ^[A-Za-z0-9_-]+$ || ! "$round" =~ ^[0-9]+$ ]]; then
      printf 'ralph watch: invalid run or round in status.json\n' >&2
      exec 3<&-
      return 1
    fi
    printf -v padded '%03d' "$round"
    log_path="$workspace/.ralph/runs/$run_id/rounds/round-$padded/provider.stdout.log"
    if [[ "$log_path" != "$prev_log" ]]; then
      # 先读完上一轮，再从头显示当前轮，避免切换时遗漏末尾结果。
      [[ -z "$prev_log" ]] || _w_details_read_log "$prev_log" 1
      # 若回放期间已有多轮完成，补读中间轮，避免只跟上最新状态而丢过程。
      if [[ "$run_id" == "$prev_run" ]] && (( round > prev_round + 1 )); then
        for skipped in $(_w_rounds_between "$workspace/.ralph/runs/$run_id/rounds" "$prev_round" "$round"); do
          printf -v padded '%03d' "$skipped"
          skipped_log="$workspace/.ralph/runs/$run_id/rounds/round-$padded/provider.stdout.log"
          if [[ -f "$skipped_log" ]]; then
            printf '\n── 补读 round %s ──\n' "$skipped"
            _W_DETAILS_POS=0
            _w_details_read_log "$skipped_log" 1
          fi
        done
      fi
      _W_DETAILS_POS=0
      prev_log="$log_path"
      prev_round="$round"
      printf '\n── run %s · provider %s · round %s · tasks %s/%s ──\n' \
        "$run_id" "$provider" "$round" "$checked" "$total"
      if [[ "$run_id" != "$prev_run" ]]; then
        printf '显示 AI 已输出的说明、工具操作和结果；当前轮已有内容会先回放。\n'
        if [[ "$provider" == "antigravity" ]]; then
          printf 'Antigravity 实时事件未必包含思考；原生会话副本可在本轮结束后查阅。\n'
        fi
        prev_run="$run_id"
      fi
      prev_state=""
    fi
    flush=0
    [[ "$state" != "finished" ]] || flush=1
    _w_details_read_log "$log_path" "$flush"
    if [[ "$state" != "$prev_state" ]]; then
      printf '[run] state=%s · tasks %s/%s · exit_reason=%s\n' \
        "$state" "$checked" "$total" "$exit_reason"
      prev_state="$state"
    fi
    if [[ "$state" == "finished" || "$follow" -eq 0 ]]; then
      [[ ! -f "$log_path" ]] || printf '原始记录：%s\n' "$log_path"
      exec 3<&-
      return 0
    fi
    sleep 0.5
  done
}

# ── Non-TTY snapshot entry point ────────────────────────────────────────────
ralph_watch_once() {
  local workspace status_file
  workspace="$(ralph_workspace_root)"
  status_file="${workspace}/.ralph/status.json"

  # shellcheck source=status.sh
  source "$RALPH_ROOT/lib/status.sh"

  _ralph_watch_bar_text "$status_file"
  printf '\n'
}

# ══════════════════════════════════════════════════════════════════════════════
# TTY sticky watch (I5-design §2)
# ══════════════════════════════════════════════════════════════════════════════

# ── TTY sticky watch main ─────────────────────────────────────────────────
ralph_watch() {
  local workspace status_file status_json read_failures=0
  workspace="$(ralph_workspace_root)"
  status_file="${workspace}/.ralph/status.json"

  # shellcheck source=status.sh
  source "$RALPH_ROOT/lib/status.sh"
  # shellcheck source=sticky.sh
  source "$RALPH_ROOT/lib/sticky.sh"

  if [[ ! -f "$status_file" ]]; then
    printf 'ralph watch: no active run (status.json not found)\n'
    return 0
  fi

  if ! status_json="$(_w_status_snapshot "$status_file")"; then
    printf 'ralph watch: cannot read status.json\n' >&2
    return 1
  fi

  # Read initial state
  local run_id provider started_at round state
  run_id="$(_w_snapshot_val "$status_json" "run_id")"
  provider="$(_w_snapshot_val "$status_json" "provider")"
  started_at="$(_w_snapshot_val "$status_json" "started_at")"
  round="$(_w_snapshot_val "$status_json" "round")"
  state="$(_w_snapshot_val "$status_json" "state")"

  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    printf 'ralph watch: no active run\n'
    return 0
  fi

  # Sticky renderer base variables
  _RALPH_STICKY_PROVIDER="${provider:-unknown}"
  if [[ -n "$started_at" && "$started_at" != "null" ]]; then
    _RALPH_STICKY_RUN_START_TS="$(ralph_iso_to_epoch "$started_at")" || _RALPH_STICKY_RUN_START_TS=""
  fi
  if [[ -z "${_RALPH_STICKY_RUN_START_TS:-}" ]]; then
    _RALPH_STICKY_RUN_START_TS="$(date +%s)"
  fi

  # Read context.json for max_round and stall_limit
  if [[ ! "$run_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
    printf 'ralph watch: invalid run in status.json\n' >&2
    return 1
  fi
  local full_run_dir="$workspace/.ralph/runs/$run_id"
  _w_read_context "$full_run_dir"

  # Enter sticky mode
  ralph_sticky_enter 1

  ralph_sticky_install_traps

  # Tracking state
  local _w_prev_run_id="${run_id:-}"
  local _w_prev_task_started_at=""
  local _w_task_start_ts
  _w_task_start_ts="$(date +%s)"
  local _w_finished=0 log_mode=attach

  # Main polling loop
  while true; do
    _sticky_poll_input
    # Re-read status.json
    if [[ ! -f "$status_file" ]]; then
      sleep 0.5
      continue
    fi

    if ! status_json="$(_w_status_snapshot "$status_file")"; then
      read_failures=$(( read_failures + 1 ))
      if (( read_failures >= 4 )); then
        printf 'ralph watch: cannot read status.json\n' >&2
        return 1
      fi
      sleep 0.5
      continue
    fi
    read_failures=0

    run_id="$(_w_snapshot_val "$status_json" "run_id")"
    provider="$(_w_snapshot_val "$status_json" "provider")"
    round="$(_w_snapshot_val "$status_json" "round")"
    state="$(_w_snapshot_val "$status_json" "state")"
    local tasks_total exit_reason task_started_at task_try
    tasks_total="$(_w_snapshot_val "$status_json" "tasks_total")"
    exit_reason="$(_w_snapshot_val "$status_json" "exit_reason")"
    task_started_at="$(_w_snapshot_val "$status_json" "task_started_at")"
    task_try="$(_w_snapshot_val "$status_json" "task_try")"

    if [[ ! "$run_id" =~ ^[A-Za-z0-9_-]+$ || ! "$round" =~ ^[0-9]+$ ]]; then
      printf 'ralph watch: invalid run or round in status.json\n' >&2
      return 1
    fi

    # Detect run_id change → full reset
    if [[ -n "$run_id" && "$run_id" != "null" && "$run_id" != "$_w_prev_run_id" ]]; then
      _w_prev_run_id="$run_id"
      _w_prev_task_started_at=""
      _w_finished=0
      _RALPH_STICKY_FROZEN_NOW=""
      _sticky_reset_log
      # 第一次看到另一个运行就已结束，只能回放；运行中切换则继续跟看。
      if [[ "$state" == finished ]]; then log_mode=history; else log_mode=live; fi
      # Refresh run start ts from new started_at (elapsed restarts on each run)
      started_at="$(_w_snapshot_val "$status_json" "started_at")"
      _RALPH_STICKY_RUN_START_TS=""
      if [[ -n "$started_at" && "$started_at" != "null" ]]; then
        _RALPH_STICKY_RUN_START_TS="$(ralph_iso_to_epoch "$started_at")" || _RALPH_STICKY_RUN_START_TS=""
      fi
      [[ -z "${_RALPH_STICKY_RUN_START_TS:-}" ]] && _RALPH_STICKY_RUN_START_TS="$(date +%s)"
      # Re-read context.json for new run
      full_run_dir="$workspace/.ralph/runs/$run_id"
      _w_read_context "$full_run_dir"
    fi

    # Refresh task_start_ts when status.json.task_started_at changes;
    # fallback to started_at for legacy status.json without the field.
    local _w_ts_src=""
    if [[ -n "$task_started_at" && "$task_started_at" != "null" ]]; then
      _w_ts_src="$task_started_at"
    elif [[ -n "${started_at:-}" && "$started_at" != "null" ]]; then
      _w_ts_src="$started_at"
    fi
    if [[ -n "$_w_ts_src" && "$_w_ts_src" != "$_w_prev_task_started_at" ]]; then
      _w_prev_task_started_at="$_w_ts_src"
      local _w_ts_epoch
      _w_ts_epoch="$(ralph_iso_to_epoch "$_w_ts_src")" || _w_ts_epoch=""
      [[ -n "$_w_ts_epoch" ]] && _w_task_start_ts="$_w_ts_epoch"
    fi

    # Compute current log path
    local log_path=""
    if [[ -n "$run_id" && "$run_id" != "null" && -n "$round" && "$round" != "null" ]]; then
      local zero_padded
      printf -v zero_padded '%03d' "$round"
      log_path="$workspace/.ralph/runs/$run_id/rounds/round-$zero_padded/provider.stdout.log"
    fi

    local flush=0 mode="$log_mode"
    if [[ "$state" == finished ]]; then
      flush=1
      [[ "$mode" != attach ]] || mode=history
    fi
    ralph_sticky_read_log "$log_path" "$flush" "$mode"
    if (( flush )); then
      # 同一运行可能在两帧之间换轮或重试并结束。读到最终日志后才结束跟看。
      if [[ "$log_mode" != history && -n "$_SREAD_ID" && -f "$log_path" ]]; then log_mode=history; fi
    elif [[ -n "$_SREAD_ID" || ! -e "$log_path" ]]; then
      log_mode=live
    fi

    # Try to read stall_count from latest meta.json
    local stall_count=0
    if [[ -f "${log_path%/*}/meta.json" ]]; then
      stall_count="$(_w_json_count "${log_path%/*}/meta.json" stall_count 0)"
    fi

    # Update sticky vars
    _RALPH_STICKY_ROUND="${round:-0}"
    _RALPH_STICKY_TASK_INDEX="$(jq -r '.round_task.index // "-"' <<< "$status_json")"
    _RALPH_STICKY_CURRENT_TASK="$(jq -r '.round_task.title // ""' <<< "$status_json")"
    if [[ "$exit_reason" == done ]]; then
      _RALPH_STICKY_TASKS_TOTAL="${tasks_total:-0}"
    else
      _RALPH_STICKY_TASKS_TOTAL="$(jq -r '.round_task.total // .tasks_total // 0' <<< "$status_json")"
    fi
    _RALPH_STICKY_PROVIDER="${provider:-unknown}"
    _RALPH_STICKY_TASK_START_TS="$_w_task_start_ts"
    _RALPH_STICKY_LOG_PATH="${log_path:-}"
    _RALPH_STICKY_STALL_COUNT="$stall_count"
    _RALPH_STICKY_TASK_TRY="${task_try:-1}"
    _RALPH_STICKY_RETRY_COUNT="$(_w_snapshot_val "$status_json" retry_count)"

    if [[ "${state:-}" == "finished" ]]; then
      _RALPH_STICKY_EXIT_REASON="${exit_reason:-}"
      if [[ "$_w_finished" -eq 0 ]]; then
        _w_finished=1
        # Freeze displayed clock at run's last update timestamp.
        # Prefer status.json updated_at (when ralph wrote finished); fallback to now.
        local _w_updated_at _w_frozen_epoch=""
        _w_updated_at="$(_w_snapshot_val "$status_json" "updated_at")"
        if [[ -n "$_w_updated_at" && "$_w_updated_at" != "null" ]]; then
          _w_frozen_epoch="$(ralph_iso_to_epoch "$_w_updated_at")" || _w_frozen_epoch=""
        fi
        [[ -z "$_w_frozen_epoch" ]] && _w_frozen_epoch="$(date +%s)"
        _RALPH_STICKY_FROZEN_NOW="$_w_frozen_epoch"
      fi
    else
      _RALPH_STICKY_EXIT_REASON=""
      _RALPH_STICKY_FROZEN_NOW=""
    fi

    # Render frame
    ralph_sticky_render_frame

    sleep 0.1
  done
}
