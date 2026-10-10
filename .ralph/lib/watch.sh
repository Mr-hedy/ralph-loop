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
  status_json="$(jq -ec 'select(type == "object")' "$f" 2>/dev/null)" \
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

# ── Event filter (same logic as run.sh _ralph_filter_verbose) ──────────────
_ralph_watch_filter_events() {
  local mode="${1:-compact}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^\{ ]]; then
      if [[ "$mode" == "details" ]]; then
        printf '%s\n' "$line" | jq -Rr '
          "[provider] " + gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; "")'
      fi
      continue
    fi
    printf '%s\n' "$line" | jq -r --arg mode "$mode" '
      def safe: tostring | gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; "");
      def flat: safe | gsub("\\s+"; " ");
      def trunc($n): if $mode == "details" then safe
        else flat | if length > $n then .[0:$n] else . end end;
      def agy_error: (.result.error // .error // null);
      def agy_has_error:
        agy_error as $e |
        if $e == null then false
        elif ($e | type) == "string" or ($e | type) == "object" then ($e | length) > 0
        else false end;
      def agy_error_text:
        agy_error as $e |
        if ($e | type) == "object" then
          if (($e.message // "") | length) > 0 then ($e.message | tostring)
          elif (($e.type // "") | length) > 0 then "error type: " + ($e.type | tostring)
          else ($e | tostring) end
        elif ($e | type) == "string" then $e
        else "provider result status ERROR" end;
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
          | (if .is_error then "  ❌ error: " else "  ⏎ result " end) + ((.content // "") | trunc(80)))
      elif .type == "result" then
        if .is_error then "  ❌ error: " + ((.result // .text // "") | trunc(120))
        elif has("text") then "  ✓ result " + ((.text // "") | trunc(120))
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
      elif .type == "item.completed" and (.item.type // "") == "reasoning" then
        "  💭 " + ((.item.text // "") | trunc(120))
      elif .type == "item.started" and (.item.type // "") == "command_execution" then
        "  🔧 " + ((.item.command // "?") | trunc(80))
      elif .type == "item.completed" and (.item.type // "") == "command_execution" then
        (if .item.status == "failed" or .item.status == "declined" or ((.item.exit_code // 0) != 0)
          then "  ❌ command" else "  ⏎ command" end)
        + " exit=" + ((.item.exit_code // "unknown") | tostring)
        + " " + ((.item.aggregated_output // .item.output // .item.stdout // "") | trunc(80))
      elif .type == "item.completed" and (.item.type // "") == "file_change" then
        (if .item.status == "failed" then "  ❌ files " else "  ✓ files " end)
        + ((.item.changes // []) | trunc(120))
      elif (.type == "item.started" or .type == "item.completed") and (.item.type // "") == "mcp_tool_call" then
        (if .item.status == "failed" or .item.error != null then "  ❌ MCP "
          elif .type == "item.started" then "  🔧 MCP " else "  ⏎ MCP " end)
        + (.item.server // "?") + "/" + (.item.tool // "?") + " "
        + ((if .type == "item.started" then .item.arguments else .item.error // .item.result end) | trunc(120))
      elif .type == "item.completed" and (.item.type // "") == "web_search" then
        "  🔎 " + ((.item.query // "") | trunc(120))
      elif .type == "item.completed" and (.item.type // "") == "error" then
        "  ❌ error: " + ((.item.message // "") | trunc(120))
      elif .type == "turn.completed" then
        "  ✓ result"
      elif .type == "turn.failed" then
        "  ❌ error: " + ((.error.message // .message // "") | trunc(120))
      elif .type == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:12])
      elif .type == "message" and (.role // "") == "assistant" then
        "  💬 " + ((.content // .text // "") | trunc(120))
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
      elif .event == "init" then
        "  ⚙ session " + ((.conversation_id // .init.conversation_id // "") | .[0:12])
      elif .event == "step_update" then
        (.step_update // .) as $s |
        ($s.agent_response // .agent_response // {}) as $a |
        ($a.thinking_delta // $s.thinking_delta // $a.thinking // $s.thinking // "") as $thinking |
        ($a.text_delta // $s.text_delta // "") as $text |
        ($s.tool_name // "") as $tool |
        ($s.tool_info // {}) as $info |
        (($s.state // "") | tostring | ascii_upcase) as $state |
        (if ($thinking | length) > 0 then "  💭 " + ($thinking | trunc(120)) else empty end),
        (if ($text | length) > 0 then "  💬 " + ($text | trunc(120)) else empty end),
        (if ($tool | length) > 0 then
          if $state == "ERROR" or $state == "FAILED" or ($info | agy_has_error) then
            "  ❌ 失败 " + $tool + " → " + (($info.error // $info.output // "未提供错误详情") | trunc(120)) +
            (if $info.error != null and $info.output != null then " → 输出：" + ($info.output | trunc(120)) else "" end)
          elif $state == "DONE" then
            "  ✓ 完成 " + $tool +
            (if $info.output != null then " → " + ($info.output | trunc(120)) else "" end)
          else
            "  🔧 " + (if $state == "ACTIVE" or $state == "RUNNING" then "开始 "
              elif $state != "" then "[" + $state + "] " else "" end) + $tool + " " +
            (($info.command // $info.parameters // $info) | trunc(80))
          end
        elif $s.subagent_info != null then "  ⚙ subagent " + ($s.subagent_info | trunc(80))
        elif $mode == "details" and $s.step_type == "agent_response" and ($text | length) == 0 and ($thinking | length) == 0 then
          "  ⚙ agent_response " + $state
        else empty end)
      elif .event == "result" then
        ((.result.response // .response // "") as $response |
          if ($response | length) > 0 then "  💬 最终回复：" + ($response | trunc(120)) else empty end),
        (if ((((.result.denied_actions // .denied_actions // []) | length)) > 0) then "  ❌ denied tools: " + (((.result.denied_actions // .denied_actions) | tostring) | trunc(100))
        elif agy_has_error then "  ❌ error: " + (agy_error_text | trunc(120))
        elif ((.result.status // .status // "") == "SUCCESS") then "  ✓ result"
        elif ((.result.status // .status // "") == "ERROR") then "  ❌ error: provider result status ERROR"
        else "  ⚠ unknown result status: " + ((.result.status // .status // "missing") | tostring | trunc(80)) end)
      elif $mode == "details" then "[provider event] " + (. | safe)
      else empty end | safe
    ' 2>/dev/null || {
      if [[ "$mode" == "details" ]]; then
        printf '%s\n' "$line" | jq -Rr '
          "[provider unparsed] " + gsub("[\u0000-\u0008\u000b-\u001f\u007f]"; "")'
      fi
    }
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

# 同一帧的字段必须来自同一个 status 版本，而非每个字段重新打开文件。
_w_snapshot_val() {
  jq -r --arg key "$2" '.[$key] // ""' <<< "$1"
}

# 详情视图只消费完整行；半行留到下次刷新，已结束 round 可输出末尾无换行行。
_W_DETAILS_POS=0
_W_DETAILS_ID=""
_W_DETAILS_LOG=""
_w_details_read_log() {
  local log_path="$1" flush="${2:-0}" line size identity
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
  while IFS= read -r line || [[ "$flush" -eq 1 && -n "$line" ]]; do
    _W_DETAILS_POS=$(( _W_DETAILS_POS + ${#line} + 1 ))
    printf '%s\n' "$line" | _ralph_watch_filter_events details || true
  done < <(tail -c "+$(( _W_DETAILS_POS + 1 ))" /dev/fd/3 2>/dev/null)
  return 0
}

# 默认 watch 保持原有紧凑契约；详情模式提供可回看的执行过程。
ralph_watch_details() {
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
    if ! fields="$(jq -er 'select(type == "object") | [.run_id // "-", .provider // "-", .round // 0,
        .state // "-", .exit_reason // "-", .tasks_checked // 0, .tasks_total // 0] | @tsv' "$status_file" 2>/dev/null)"; then
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
    read -r run_id provider round state exit_reason checked total <<< "$fields"
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
      if [[ "$run_id" == "$prev_run" ]]; then
        for (( skipped=prev_round+1; skipped<round; skipped++ )); do
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

  tail -n 0 -F "$log_path" > "$_W_FIFO" 2>/dev/null &
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

  if ! status_json="$(jq -ec 'select(type == "object")' "$status_file" 2>/dev/null)"; then
    printf 'ralph watch: cannot read status.json\n' >&2
    return 1
  fi

  # Read initial state
  local run_id run_dir_str provider started_at round state
  run_id="$(_w_snapshot_val "$status_json" "run_id")"
  run_dir_str="$(_w_snapshot_val "$status_json" "run_dir")"
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
  ralph_sticky_enter 1

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

    if ! status_json="$(jq -ec 'select(type == "object")' "$status_file" 2>/dev/null)"; then
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
    run_dir_str="$(_w_snapshot_val "$status_json" "run_dir")"
    provider="$(_w_snapshot_val "$status_json" "provider")"
    round="$(_w_snapshot_val "$status_json" "round")"
    state="$(_w_snapshot_val "$status_json" "state")"
    local tasks_checked tasks_total exit_reason task_started_at task_try
    tasks_checked="$(_w_snapshot_val "$status_json" "tasks_checked")"
    tasks_total="$(_w_snapshot_val "$status_json" "tasks_total")"
    exit_reason="$(_w_snapshot_val "$status_json" "exit_reason")"
    task_started_at="$(_w_snapshot_val "$status_json" "task_started_at")"
    task_try="$(_w_snapshot_val "$status_json" "task_try")"

    # Detect run_id change → full reset
    if [[ -n "$run_id" && "$run_id" != "null" && "$run_id" != "$_w_prev_run_id" ]]; then
      _w_prev_run_id="$run_id"
      _w_prev_round="$round"
      _w_prev_task_started_at=""
      _w_finished=0
      _RALPH_STICKY_FROZEN_NOW=""
      _SEV_TIMES=()
      _SEV_MSGS=()
      # Refresh run start ts from new started_at (elapsed restarts on each run)
      started_at="$(_w_snapshot_val "$status_json" "started_at")"
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
    _RALPH_STICKY_TASK_TRY="${task_try:-1}"

    if [[ "${state:-}" == "finished" ]]; then
      _RALPH_STICKY_EXIT_REASON="${exit_reason:-}"
      if [[ "$_w_finished" -eq 0 ]]; then
        _w_finished=1
        _w_stop_tail
        # Freeze displayed clock at run's last update timestamp.
        # Prefer status.json updated_at (when ralph wrote finished); fallback to now.
        local _w_updated_at _w_frozen_epoch=""
        _w_updated_at="$(_w_snapshot_val "$status_json" "updated_at")"
        if [[ -n "$_w_updated_at" && "$_w_updated_at" != "null" ]]; then
          _w_frozen_epoch="$(ralph_iso_to_epoch "$_w_updated_at")"
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
