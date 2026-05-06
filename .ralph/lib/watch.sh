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
  elif [[ "$exit_reason" == "provider_failed" || "$exit_reason" == "timeout" \
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

  local run_id round iter_name checked total state exit_reason provider short_id bar
  run_id="$(_ralph_status_json_val "$f" "run_id")"
  round="$(_ralph_status_json_val "$f" "round")"
  iter_name="$(_ralph_status_json_val "$f" "iteration_name")"
  checked="$(_ralph_status_json_val "$f" "tasks_checked")"
  total="$(_ralph_status_json_val "$f" "tasks_total")"
  state="$(_ralph_status_json_val "$f" "state")"
  exit_reason="$(_ralph_status_json_val "$f" "exit_reason")"
  provider="$(_ralph_status_json_val "$f" "provider")"

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
  if [[ -n "$iter_name" && "$iter_name" != "null" ]]; then
    bar+="  ${dim}iter_name:${reset} ${iter_name}"
  fi
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

# ── Event filter (same logic as run.sh _ralph_filter_verbose) ──────────────
_ralph_watch_filter_events() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^\{ ]] || continue
    printf '%s\n' "$line" | jq -r '
      def flat: tostring | gsub("\\s+"; " ");
      def trunc($n): flat | if length > $n then .[0:$n] else . end;
      if .type == "system" and .subtype == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:8])
      elif .type == "assistant" then
        ((.message.content // []) | if type == "array" then . else [] end | .[]
          | if .type == "thinking" then "  💭 " + ((.thinking // "") | trunc(120))
            elif .type == "text"   then "  💬 " + ((.text // "") | trunc(120))
            elif .type == "tool_use" then "  🔧 " + (.name // "?") + " " + ((.input // {}) | trunc(80))
            else empty end)
      elif .type == "user" then
        ((.message.content // []) | if type == "array" then . else [] end | .[]
          | select(.type == "tool_result")
          | "  ⏎ result " + ((.content // "") | trunc(80)))
      elif .type == "result" then
        if has("text") then "  ✓ result " + ((.text // "") | trunc(120))
        elif .is_error then "  ❌ error: " + ((.result // "") | trunc(120))
        elif .result != null then "  ✓ result " + ((.result // "") | trunc(120))
        elif .stats != null then
          "  ✓ result tokens=" + ((.stats.total_tokens // 0) | tostring)
          + " tools=" + ((.stats.tool_calls // 0) | tostring)
          + " dur=" + (((.stats.duration_ms // 0) / 1000 | floor) | tostring) + "s"
        else "  ✓ result" end
      elif .type == "thread.started" then
        "  ⚙ session " + ((.thread_id // "") | .[0:12])
      elif .type == "item.completed" and (.item.type // "") == "agent_message" then
        "  💬 " + ((.item.text // "") | trunc(120))
      elif .type == "item.started" and (.item.type // "") == "command_execution" then
        "  🔧 " + ((.item.command // "?") | trunc(80))
      elif .type == "item.completed" and (.item.type // "") == "command_execution" then
        "  ⏎ result " + ((.item.output // "") | trunc(80))
      elif .type == "turn.completed" then
        "  ✓ result"
      elif .type == "turn.failed" then
        "  ❌ error: " + ((.error.message // .message // "") | trunc(120))
      elif .type == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:12])
      elif .type == "message" and (.role // "") == "assistant" then
        if (.delta // false) then empty
        else "  💬 " + ((.content // .text // "") | trunc(120)) end
      elif .type == "tool_use" then
        "  🔧 " + ((.tool_name // .name // "?") | trunc(40)) + " " + (((.parameters // .input // {}) | tostring) | trunc(60))
      elif .type == "tool_result" then
        "  ⏎ result " + ((.output // .content // "") | tostring | trunc(80))
      elif .type == "text" then
        "  💬 " + ((.text // "") | trunc(120))
      elif .type == "complete" then
        "  ✓ result " + ((.text // "") | trunc(120))
      elif .type == "error" then
        "  ❌ error: " + ((.error.message // .message // "") | trunc(120))
      else empty end
    ' 2>/dev/null
  done
}

# ── Read a value from JSON file ─────────────────────────────────────────────
_w_json_val() {
  local file="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".$key // \"\"" "$file" 2>/dev/null || echo ""
  else
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 \
      | sed 's/.*: *"//' | sed 's/"$//' || echo ""
  fi
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

# Tail state
_W_TAIL_PID=""
_W_FILTER_PID=""
_W_FIFO=""
_W_EVENT_FILE=""
_W_LAST_EV_POS=0
_W_PREV_LOG_PATH=""
_W_CLEANED=0

_w_stop_tail() {
  local p
  for p in "${_W_TAIL_PID:-}" "${_W_FILTER_PID:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
  for p in "${_W_TAIL_PID:-}" "${_W_FILTER_PID:-}"; do
    [[ -n "$p" ]] && wait "$p" 2>/dev/null || true
  done
  [[ -n "${_W_FIFO:-}" ]] && rm -f "$_W_FIFO" 2>/dev/null || true
  [[ -n "${_W_EVENT_FILE:-}" ]] && rm -f "$_W_EVENT_FILE" 2>/dev/null || true
  _W_TAIL_PID=""
  _W_FILTER_PID=""
  _W_FIFO=""
  _W_EVENT_FILE=""
  _W_LAST_EV_POS=0
}

_w_start_tail() {
  local log_path="$1"
  _w_stop_tail
  [[ ! -f "$log_path" ]] && return

  _W_EVENT_FILE="$(mktemp -t ralph-watch-ev.XXXXXX)"
  _W_LAST_EV_POS=0

  _W_FIFO="$(mktemp -t ralph-watch-fifo.XXXXXX)"
  rm -f "$_W_FIFO"
  mkfifo "$_W_FIFO"

  tail -n 0 -f "$log_path" > "$_W_FIFO" 2>/dev/null &
  _W_TAIL_PID=$!
  _ralph_watch_filter_events < "$_W_FIFO" >> "$_W_EVENT_FILE" 2>/dev/null &
  _W_FILTER_PID=$!
}

# ── Trap handlers ──────────────────────────────────────────────────────────
_w_cleanup() {
  ((_W_CLEANED)) && return 0
  _W_CLEANED=1
  _w_stop_tail
  ralph_sticky_cleanup
}

_w_on_int() {
  _w_cleanup
  exit 130
}

_w_on_exit() {
  _w_cleanup
}

# ── TTY sticky watch main ─────────────────────────────────────────────────
ralph_watch() {
  local workspace status_file
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

  # Read initial state
  local run_id run_dir_str provider started_at round state
  run_id="$(_ralph_status_json_val "$status_file" "run_id")"
  run_dir_str="$(_ralph_status_json_val "$status_file" "run_dir")"
  provider="$(_ralph_status_json_val "$status_file" "provider")"
  started_at="$(_ralph_status_json_val "$status_file" "started_at")"
  round="$(_ralph_status_json_val "$status_file" "round")"
  state="$(_ralph_status_json_val "$status_file" "state")"

  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    printf 'ralph watch: no active run\n'
    return 0
  fi

  # Sticky renderer base variables
  _RALPH_STICKY_PROVIDER="${provider:-unknown}"
  if [[ -n "$started_at" && "$started_at" != "null" ]]; then
    _RALPH_STICKY_RUN_START_TS="$(ralph_iso_to_epoch "$started_at")"
  fi
  if [[ -z "${_RALPH_STICKY_RUN_START_TS:-}" ]]; then
    _RALPH_STICKY_RUN_START_TS="$(date +%s)"
  fi

  # Read context.json for max_round and stall_limit
  local full_run_dir="$workspace/${run_dir_str#./}"
  _RALPH_STICKY_MAX_ROUND=0
  _RALPH_STICKY_STALL_LIMIT=5
  if [[ -f "$full_run_dir/context.json" ]]; then
    local ctx_val
    ctx_val="$(_w_json_val "$full_run_dir/context.json" "max_round")"
    [[ -n "$ctx_val" && "$ctx_val" != "null" ]] && _RALPH_STICKY_MAX_ROUND="$ctx_val"
    ctx_val="$(_w_json_val "$full_run_dir/context.json" "stall_limit")"
    [[ -n "$ctx_val" && "$ctx_val" != "null" ]] && _RALPH_STICKY_STALL_LIMIT="$ctx_val"
  fi

  # Enter sticky mode
  ralph_sticky_enter

  # Install traps (custom: also stop tail on cleanup)
  trap '_w_on_int'  INT
  trap '_w_on_exit' EXIT

  # Tracking state
  local _w_prev_round="${round:-0}"
  local _w_prev_run_id="${run_id:-}"
  local _w_prev_task_started_at=""
  local _w_task_start_ts
  _w_task_start_ts="$(date +%s)"
  local _w_finished=0
  _W_PREV_LOG_PATH=""

  # Main polling loop
  while true; do
    # Re-read status.json
    if [[ ! -f "$status_file" ]]; then
      sleep 0.5
      continue
    fi

    run_id="$(_ralph_status_json_val "$status_file" "run_id")"
    run_dir_str="$(_ralph_status_json_val "$status_file" "run_dir")"
    provider="$(_ralph_status_json_val "$status_file" "provider")"
    round="$(_ralph_status_json_val "$status_file" "round")"
    state="$(_ralph_status_json_val "$status_file" "state")"
    local tasks_checked tasks_total exit_reason task_started_at
    tasks_checked="$(_ralph_status_json_val "$status_file" "tasks_checked")"
    tasks_total="$(_ralph_status_json_val "$status_file" "tasks_total")"
    exit_reason="$(_ralph_status_json_val "$status_file" "exit_reason")"
    task_started_at="$(_ralph_status_json_val "$status_file" "task_started_at")"

    # Detect run_id change → full reset
    if [[ -n "$run_id" && "$run_id" != "null" && "$run_id" != "$_w_prev_run_id" ]]; then
      _w_prev_run_id="$run_id"
      _w_prev_round="$round"
      _w_prev_task_started_at=""
      _w_finished=0
      _SEV_TIMES=()
      _SEV_MSGS=()
      # Refresh run start ts from new started_at (elapsed restarts on each run)
      started_at="$(_ralph_status_json_val "$status_file" "started_at")"
      if [[ -n "$started_at" && "$started_at" != "null" ]]; then
        _RALPH_STICKY_RUN_START_TS="$(ralph_iso_to_epoch "$started_at")"
      fi
      [[ -z "${_RALPH_STICKY_RUN_START_TS:-}" ]] && _RALPH_STICKY_RUN_START_TS="$(date +%s)"
      # Re-read context.json for new run
      full_run_dir="$workspace/${run_dir_str#./}"
      _RALPH_STICKY_MAX_ROUND=0
      _RALPH_STICKY_STALL_LIMIT=5
      if [[ -f "$full_run_dir/context.json" ]]; then
        local ctx_val
        ctx_val="$(_w_json_val "$full_run_dir/context.json" "max_round")"
        [[ -n "$ctx_val" && "$ctx_val" != "null" ]] && _RALPH_STICKY_MAX_ROUND="$ctx_val"
        ctx_val="$(_w_json_val "$full_run_dir/context.json" "stall_limit")"
        [[ -n "$ctx_val" && "$ctx_val" != "null" ]] && _RALPH_STICKY_STALL_LIMIT="$ctx_val"
      fi
    fi

    # Track round change (used for log path bookkeeping)
    if [[ -n "$round" && "$round" != "null" && "$round" != "$_w_prev_round" ]]; then
      _w_prev_round="$round"
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
      _w_ts_epoch="$(ralph_iso_to_epoch "$_w_ts_src")"
      [[ -n "$_w_ts_epoch" ]] && _w_task_start_ts="$_w_ts_epoch"
    fi

    # Compute current log path
    local log_path=""
    if [[ -n "$run_id" && "$run_id" != "null" && -n "$round" && "$round" != "null" ]]; then
      local zero_padded
      printf -v zero_padded '%03d' "$round"
      log_path="$workspace/.ralph/runs/$run_id/rounds/round-$zero_padded/provider.stdout.log"
    fi

    # Start/restart tail if log path changed and run is still active
    if [[ "${state:-}" != "finished" && -n "$log_path" && -f "$log_path" ]]; then
      if [[ "$log_path" != "$_W_PREV_LOG_PATH" ]]; then
        _w_start_tail "$log_path"
        _W_PREV_LOG_PATH="$log_path"
      fi
    fi

    # Read new events from event file
    if [[ -f "${_W_EVENT_FILE:-}" ]]; then
      local ev_size
      ev_size="$(wc -c < "$_W_EVENT_FILE" 2>/dev/null | tr -d '[:space:]')" || ev_size=0
      if [[ "$ev_size" -gt "${_W_LAST_EV_POS:-0}" ]]; then
        local new_events
        new_events="$(tail -c "+$(( _W_LAST_EV_POS + 1 ))" "$_W_EVENT_FILE" 2>/dev/null)" || new_events=""
        _W_LAST_EV_POS="$ev_size"
        local ev_line
        while IFS= read -r ev_line; do
          [[ -n "$ev_line" ]] && ralph_sticky_append_event "$ev_line"
        done <<< "$new_events"
      fi
    fi

    # Get current task from TASKS.md
    local current_task=""
    local tasks_md="$workspace/.ralph/TASKS.md"
    if [[ -f "$tasks_md" ]]; then
      current_task="$(grep -m1 '^- \[ \]' "$tasks_md" 2>/dev/null | sed 's/^- \[ \] //' | cut -c1-80)" || current_task=""
    fi

    # Try to read stall_count from latest meta.json
    local stall_count=0
    if [[ -n "$log_path" ]]; then
      local round_dir="${log_path%/*}"
      if [[ -f "$round_dir/meta.json" ]]; then
        local sc
        sc="$(_w_json_val "$round_dir/meta.json" "stall_count")"
        [[ -n "$sc" && "$sc" != "null" ]] && stall_count="$sc"
      fi
    fi

    # Update sticky vars
    _RALPH_STICKY_ROUND="${round:-0}"
    _RALPH_STICKY_TASKS_DONE="${tasks_checked:-0}"
    _RALPH_STICKY_TASKS_TOTAL="${tasks_total:-0}"
    _RALPH_STICKY_CURRENT_TASK="$current_task"
    _RALPH_STICKY_PROVIDER="${provider:-unknown}"
    _RALPH_STICKY_TASK_START_TS="$_w_task_start_ts"
    _RALPH_STICKY_LOG_PATH="${log_path:-}"
    _RALPH_STICKY_STALL_COUNT="$stall_count"

    if [[ "${state:-}" == "finished" ]]; then
      _RALPH_STICKY_EXIT_REASON="${exit_reason:-}"
      if [[ "$_w_finished" -eq 0 ]]; then
        _w_finished=1
        _w_stop_tail
      fi
    else
      _RALPH_STICKY_EXIT_REASON=""
    fi

    # Render frame
    ralph_sticky_render_frame

    sleep 0.2
  done
}
