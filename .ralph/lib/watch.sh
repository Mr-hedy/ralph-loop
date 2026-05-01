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

# ── Stub: tail area draw (DEV-4 implements) ─────────────────────────────────
_ralph_watch_tail_draw() {
  : # empty — DEV-4 fills this in
}

# ── Render one frame: tail area + sticky bar ─────────────────────────────────
ralph_watch_frame() {
  local status_file="$1"
  _ralph_watch_tail_draw
  _ralph_watch_bar_draw "$status_file"
}
