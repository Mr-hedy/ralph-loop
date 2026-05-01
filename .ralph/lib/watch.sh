#!/usr/bin/env bash
set -euo pipefail

# watch.sh — sticky bar rendering (DEV-3)
# Requires: status.sh sourced before calling bar functions (for _ralph_status_json_val)

# ── Truncate run_id: first 12 chars + "..." ─────────────────────────────────
_ralph_watch_truncate_id() {
  local id="$1"
  if [[ ${#id} -gt 12 ]]; then
    printf '%s...' "${id:0:12}"
  else
    printf '%s' "$id"
  fi
}

# ── Bar content: one-line status string from status.json ────────────────────
_ralph_watch_bar_text() {
  local f="$1"

  if [[ ! -f "$f" ]]; then
    printf '%s' "no active run"
    return 0
  fi

  local run_id iter checked total state exit_reason provider short_id bar
  run_id="$(_ralph_status_json_val "$f" "run_id")"
  iter="$(_ralph_status_json_val "$f" "iteration")"
  checked="$(_ralph_status_json_val "$f" "tasks_checked")"
  total="$(_ralph_status_json_val "$f" "tasks_total")"
  state="$(_ralph_status_json_val "$f" "state")"
  exit_reason="$(_ralph_status_json_val "$f" "exit_reason")"
  provider="$(_ralph_status_json_val "$f" "provider")"

  short_id="$(_ralph_watch_truncate_id "$run_id")"

  bar="run: ${short_id}"
  bar+="  iter ${iter}"
  bar+="  ${checked}/${total} tasks"
  bar+="  state: ${state:-}"
  [[ -n "$exit_reason" && "$exit_reason" != "null" ]] && bar+="  exit_reason: ${exit_reason}"
  [[ -n "$provider" && "$provider" != "null" ]] && bar+="  provider: ${provider}"

  printf '%s' "$bar"
}

# ── ANSI terminal: set scroll region to exclude bottom 1 line ───────────────
_ralph_watch_scroll_set() {
  local lines
  lines="$(tput lines 2>/dev/null || echo 24)"
  printf '\033[1;%dr' "$((lines - 1))"
}

# ── ANSI terminal: reset scroll region ──────────────────────────────────────
_ralph_watch_scroll_reset() {
  printf '\033[r'
}

# ── Draw sticky bar at terminal bottom ──────────────────────────────────────
_ralph_watch_bar_draw() {
  local status_file="$1"
  local lines bar
  lines="$(tput lines 2>/dev/null || echo 24)"
  bar="$(_ralph_watch_bar_text "$status_file")"
  printf '\033[%d;1H\033[2K%s' "$lines" "$bar"
}

# ── Build iter log path from status.json run_id + iteration ──────────────────
_ralph_watch_iter_log_path() {
  local workspace="$1" status_file="$2"
  if [[ ! -f "$status_file" ]]; then
    return 1
  fi
  local run_id iter
  run_id="$(_ralph_status_json_val "$status_file" "run_id")"
  iter="$(_ralph_status_json_val "$status_file" "iteration")"
  if [[ -z "$run_id" || -z "$iter" || "$run_id" == "null" || "$iter" == "null" ]]; then
    return 1
  fi
  local zero_padded
  printf -v zero_padded '%03d' "$iter"
  printf '%s/.ralph/runs/%s/iterations/iter-%s/log' "$workspace" "$run_id" "$zero_padded"
}

# ── Tail area: print new lines from current iter log ─────────────────────────
# Tracks last-read byte offset in _RALPH_TAIL_OFFSET (per log path).
# When log path changes (iter switch), resets offset and clears _RALPH_TAIL_PREV_PATH.
_ralph_watch_tail_draw() {
  local workspace="$1" status_file="$2"
  local log_path
  log_path="$(_ralph_watch_iter_log_path "$workspace" "$status_file")" || return 0

  if [[ ! -f "$log_path" ]]; then
    return 0
  fi

  # Detect iter switch: path changed → reset offset
  if [[ "${_RALPH_TAIL_PREV_PATH:-}" != "$log_path" ]]; then
    _RALPH_TAIL_PREV_PATH="$log_path"
    _RALPH_TAIL_OFFSET=0
  fi

  local size
  size="$(stat -f%z "$log_path" 2>/dev/null || stat -c%s "$log_path" 2>/dev/null)" || return 0

  # Nothing new since last read
  if [[ "$size" -le "${_RALPH_TAIL_OFFSET:-0}" ]]; then
    return 0
  fi

  # Print new bytes
  dd if="$log_path" bs=1 skip="${_RALPH_TAIL_OFFSET:-0}" count=$((size - _RALPH_TAIL_OFFSET)) 2>/dev/null
  _RALPH_TAIL_OFFSET=$size
}

# ── Render one frame: tail area + sticky bar ─────────────────────────────────
ralph_watch_frame() {
  local workspace="$1" status_file="$2"
  _ralph_watch_tail_draw "$workspace" "$status_file"
  _ralph_watch_bar_draw "$status_file"
}

# ── Watch state ─────────────────────────────────────────────────────────────
_RALPH_WATCH_CLEANED=0
_RALPH_SLEEP_PID=""

_ralph_watch_cleanup() {
  [[ "$_RALPH_WATCH_CLEANED" -eq 1 ]] && return 0
  _RALPH_WATCH_CLEANED=1
  _ralph_watch_scroll_reset
  tput clear 2>/dev/null || true
  printf '\033[?25h'
}

_ralph_watch_on_sigint() {
  kill "${_RALPH_SLEEP_PID:-}" 2>/dev/null || true
  _ralph_watch_cleanup
  exit 130
}

# ── Main watch entry point ──────────────────────────────────────────────────
ralph_watch() {
  local workspace status_file
  workspace="$(ralph_workspace_root)"
  status_file="${workspace}/.ralph/status.json"

  # shellcheck source=status.sh
  source "$RALPH_ROOT/lib/status.sh"

  _RALPH_TAIL_OFFSET=0
  _RALPH_TAIL_PREV_PATH=""

  # Hide cursor
  printf '\033[?25l'

  trap '_ralph_watch_cleanup' EXIT
  trap '_ralph_watch_on_sigint' INT

  tput clear 2>/dev/null || true
  _ralph_watch_scroll_set
  printf '\033[1;1H'

  ralph_watch_frame "$workspace" "$status_file"

  # sleep & wait: bash interruptible wait lets SIGINT handler fire immediately
  while true; do
    sleep 2 & _RALPH_SLEEP_PID=$!
    wait "$_RALPH_SLEEP_PID" 2>/dev/null || true
    ralph_watch_frame "$workspace" "$status_file"
  done
}
