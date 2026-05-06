#!/usr/bin/env bash
set -euo pipefail

# Extract a value from a flat JSON file by key.
# Handles quoted strings, null, and bare numbers.
_ralph_status_json_val() {
  local file="$1" key="$2"
  local line val
  line="$(grep "\"${key}\"" "$file" 2>/dev/null | head -1)" || { printf ''; return 0; }
  val="${line#*: }"
  val="${val%,}"
  if [[ "$val" == \"*\" ]]; then
    val="${val#\"}"
    val="${val%\"}"
  fi
  printf '%s' "$val"
}

# Display a value; null or empty → "-"
_ralph_status_fmt() {
  if [[ "$1" == "null" || -z "$1" ]]; then
    printf '%s' "-"
  else
    printf '%s' "$1"
  fi
}

ralph_status() {
  local status_file
  status_file="$(ralph_workspace_root)/.ralph/status.json"

  if [[ ! -f "$status_file" ]]; then
    echo "无运行中/已结束的 run"
    return 0
  fi

  local f="$status_file"
  printf '%-15s %s\n' "run_id:"         "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "run_id")")"
  printf '%-15s %s\n' "run_dir:"        "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "run_dir")")"
  printf '%-15s %s\n' "workspace:"      "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "workspace")")"
  printf '%-15s %s\n' "provider:"       "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "provider")")"
  printf '%-15s %s\n' "model:"          "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "model")")"
  printf '%-15s %s\n' "effort:"         "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "effort")")"
  printf '%-15s %s\n' "started_at:"     "$(ralph_iso_to_local_display "$(_ralph_status_json_val "$f" "started_at")")"
  printf '%-15s %s\n' "updated_at:"     "$(ralph_iso_to_local_display "$(_ralph_status_json_val "$f" "updated_at")")"
  printf '%-15s %s\n' "round:"          "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "round")")"
  printf '%-15s %s\n' "iteration_name:" "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "iteration_name")")"
  printf '%-15s %s\n' "state:"          "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "state")")"
  printf '%-15s %s / %s checked\n' "tasks:" \
    "$(_ralph_status_json_val "$f" "tasks_checked")" \
    "$(_ralph_status_json_val "$f" "tasks_total")"
  printf '%-15s %s\n' "exit_reason:"    "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "exit_reason")")"
  printf '%-15s %s\n' "last_error:"     "$(_ralph_status_fmt "$(_ralph_status_json_val "$f" "last_error")")"
}
