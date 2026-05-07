#!/usr/bin/env bash
# run.sh — ralph run 主循环

_RALPH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$_RALPH_LIB_DIR/common.sh"
source "$_RALPH_LIB_DIR/tasks.sh"
source "$_RALPH_LIB_DIR/session.sh"

# ── 全局运行状态（trap 访问）─────────────────────────────────────────────────
_RALPH_LOCK_FILE=""
_RALPH_LOCK_ACQUIRED=0
_RALPH_RUN_DIR=""
_RALPH_WORKSPACE=""
_RALPH_START_TIME=0
_RALPH_CURRENT_ITERATION=""
_RALPH_TAIL_PID=""
_RALPH_TAIL_FILTER_PID=""
_RALPH_TAIL_FIFO=""
_RALPH_HEARTBEAT_PID=""
_RALPH_PROVIDER_PID=""
_RALPH_CURRENT_TASK_ID=""
_RALPH_CURRENT_TASK_TRY=0
_RALPH_STICKY_MODE=0
_RALPH_STICKY_TAIL_PID=""
_RALPH_STICKY_FILTER_PID=""
_RALPH_STICKY_EVENT_FILE=""
_RALPH_STICKY_LAST_POS=0

# ── 退出辅助函数 ─────────────────────────────────────────────────────────────
_ralph_stop_verbose_tail() {
  local pid
  for pid in "${_RALPH_TAIL_PID:-}" "${_RALPH_TAIL_FILTER_PID:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  for pid in "${_RALPH_TAIL_PID:-}" "${_RALPH_TAIL_FILTER_PID:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  [[ -n "${_RALPH_TAIL_FIFO:-}" ]] && rm -f "$_RALPH_TAIL_FIFO" 2>/dev/null || true
  _RALPH_TAIL_PID=""
  _RALPH_TAIL_FILTER_PID=""
  _RALPH_TAIL_FIFO=""
}

_ralph_stop_provider_heartbeat() {
  local pid="${_RALPH_HEARTBEAT_PID:-}"
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  _RALPH_HEARTBEAT_PID=""
}

_ralph_stop_sticky_tail() {
  local pid
  for pid in "${_RALPH_STICKY_TAIL_PID:-}" "${_RALPH_STICKY_FILTER_PID:-}"; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  for pid in "${_RALPH_STICKY_TAIL_PID:-}" "${_RALPH_STICKY_FILTER_PID:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true
  done
  [[ -n "${_RALPH_STICKY_EVENT_FILE:-}" ]] && rm -f "$_RALPH_STICKY_EVENT_FILE" 2>/dev/null || true
  _RALPH_STICKY_TAIL_PID=""
  _RALPH_STICKY_FILTER_PID=""
  _RALPH_STICKY_EVENT_FILE=""
  _RALPH_STICKY_LAST_POS=0
}

# 更新 sticky renderer 需要的变量（每次 render_frame 前调用）
_ralph_sticky_update_vars() {
  _RALPH_STICKY_RUN_START_TS="${_RALPH_START_TIME:-$(date +%s)}"
  _RALPH_STICKY_ROUND="${_RALPH_ROUND:-0}"
  _RALPH_STICKY_TASKS_DONE="${_RALPH_TASKS_CHECKED_END:-0}"
  _RALPH_STICKY_TASKS_TOTAL="${_RALPH_TASKS_TOTAL:-0}"
  _RALPH_STICKY_CURRENT_TASK=""
  if declare -f first_unchecked_task >/dev/null 2>&1; then
    _RALPH_STICKY_CURRENT_TASK="$(first_unchecked_task "${_RALPH_WORKSPACE:-.}/.ralph/TASKS.md" 2>/dev/null)" || _RALPH_STICKY_CURRENT_TASK=""
  fi
  _RALPH_STICKY_TASK_TRY="${_RALPH_CURRENT_TASK_TRY:-1}"
  _RALPH_STICKY_MAX_ROUND="${RALPH_LOOP_MAX_ROUND:-0}"
  _RALPH_STICKY_PROVIDER="${_RALPH_PROVIDER:-unknown}"
  _RALPH_STICKY_LOG_PATH="${_RALPH_CURRENT_LOG_PATH:-}"
  _RALPH_STICKY_EXIT_REASON="${_RALPH_EXIT_REASON:-}"
  _RALPH_STICKY_RETRY_COUNT="${retry_count:-0}"
}

_ralph_child_pids() {
  local parent="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -P "$parent" 2>/dev/null || true
  else
    ps -eo pid=,ppid= 2>/dev/null \
      | awk -v ppid="$parent" '$2 == ppid { print $1 }' || true
  fi
}

_ralph_process_tree_pids() {
  local root="$1"
  [[ "$root" =~ ^[0-9]+$ ]] || return 0
  printf '%s\n' "$root"

  local child
  while IFS= read -r child; do
    [[ "$child" =~ ^[0-9]+$ ]] || continue
    _ralph_process_tree_pids "$child"
  done < <(_ralph_child_pids "$root")
}

_ralph_terminate_process_tree() {
  local root="$1"
  [[ "$root" =~ ^[0-9]+$ ]] || return 0

  local pids pid
  pids="$(_ralph_process_tree_pids "$root" | awk '!seen[$0]++')" || pids="$root"
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in $pids; do
    kill -KILL "$pid" 2>/dev/null || true
  done
}

_ralph_stop_active_provider() {
  local pid="${_RALPH_PROVIDER_PID:-}"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    _ralph_terminate_process_tree "$pid"
    wait "$pid" 2>/dev/null || true
  fi
  _RALPH_PROVIDER_PID=""
}

_ralph_start_provider_heartbeat() {
  local log_path="$1"
  local round="$2"
  local max_round_disp="$3"

  local interval="${RALPH_PROGRESS_HEARTBEAT_SEC:-60}"
  if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -le 0 ]]; then
    return 0
  fi

  (
    local elapsed=0
    while :; do
      sleep "$interval" || exit 0
      elapsed=$(( elapsed + interval ))
      local bytes=0 lines=0 now_local
      if [[ -f "$log_path" ]]; then
        bytes="$(wc -c < "$log_path" 2>/dev/null)" || bytes=0
        lines="$(wc -l < "$log_path" 2>/dev/null)" || lines=0
      fi
      now_local="$(date +"%H:%M:%S")"
      printf '[%s] round %s/%s still running | elapsed %ss | provider log %s bytes/%s lines | tail -f %s\n' \
        "$now_local" "$round" "$max_round_disp" "$elapsed" "$bytes" "$lines" "$log_path" >&2
    done
  ) &
  _RALPH_HEARTBEAT_PID=$!
}

_ralph_write_result() {
  local exit_reason="$1"
  local rounds="$2"
  local tasks_total="$3"
  local tasks_checked_start="$4"
  local tasks_checked_end="$5"
  local started_at="$6"
  local last_error="${7:-null}"

  [[ -z "$_RALPH_RUN_DIR" ]] && return 0
  local finished_at duration_sec
  finished_at="$(ralph_timestamp)"
  duration_sec=$(( $(date -u +%s) - _RALPH_START_TIME ))

  cat > "$_RALPH_RUN_DIR/result.json" <<EOF
{
  "run_id": "$(ralph_json_escape "${_RALPH_RUN_DIR##*/}")",
  "exit_reason": "$(ralph_json_escape "$exit_reason")",
  "iteration_name": $(ralph_json_str "$_RALPH_CURRENT_ITERATION"),
  "rounds": ${rounds},
  "tasks_total": ${tasks_total},
  "tasks_checked_start": ${tasks_checked_start},
  "tasks_checked_end": ${tasks_checked_end},
  "started_at": "$(ralph_json_escape "$started_at")",
  "finished_at": "$(ralph_json_escape "$finished_at")",
  "duration_sec": ${duration_sec},
  "last_error": ${last_error}
}
EOF
}

# 退出时人类可读总结打印（终端 + .ralph/runs/<run_id>/exit-message.txt）
_ralph_print_summary() {
  local exit_reason="$1"
  local rounds="$2"
  local tasks_total="$3"
  local tasks_checked_end="$4"

  local run_id="${_RALPH_RUN_DIR##*/}"
  local iter_label="${_RALPH_CURRENT_ITERATION:-(unspecified)}"
  local first_unchecked=""
  local tasks_md="$_RALPH_WORKSPACE/.ralph/TASKS.md"
  if [[ -f "$tasks_md" ]] && declare -f first_unchecked_task >/dev/null 2>&1; then
    first_unchecked="$(first_unchecked_task "$tasks_md")"
  fi

  local sep="────────────────────────────────────────────────"
  local total_dur=""
  if [[ -n "${_RALPH_START_TIME:-}" ]]; then
    total_dur="$(ralph_format_duration $(( $(date -u +%s) - _RALPH_START_TIME )))"
  fi
  local started_local=""
  if [[ -n "${_RALPH_STARTED_AT:-}" ]]; then
    started_local="$(ralph_iso_to_local_display "$_RALPH_STARTED_AT")"
  fi
  local lines=()
  lines+=("$sep")
  lines+=("Ralph Run Complete")
  lines+=("$sep")
  lines+=("Run ID:        $run_id")
  lines+=("Iteration:     $iter_label")
  lines+=("Exit Reason:   $exit_reason")
  lines+=("Rounds:        $rounds")
  lines+=("Tasks:         $tasks_checked_end / $tasks_total")
  [[ -n "$started_local" ]] && lines+=("Started:       $started_local")
  [[ -n "$total_dur" ]]     && lines+=("Duration:      $total_dur")

  case "$exit_reason" in
    done)
      lines+=("")
      lines+=("All tasks completed.")
      lines+=("")
      lines+=("Next step:")
      lines+=("  归档动作：cp .ralph/TASKS.md docs/requirements/<module>/${iter_label}-FINAL-TASK.md")
      lines+=("  清空 .ralph/TASKS.md 当前任务段，'当前迭代' 改为下一个；commit。")
      ;;
    blocked_by_human)
      lines+=("")
      lines+=("Blocked by human task:")
      lines+=("  $first_unchecked")
      lines+=("")
      lines+=("Next step:")
      lines+=("  在 Claude Code 对话中和 agent 协作回答此 HUMAN 任务，")
      lines+=("  把答案落到对应 docs（requirements / architecture），")
      lines+=("  在 TASKS.md 里勾掉 HUMAN 任务，重启 ralph run。")
      ;;
    timeout)
      lines+=("")
      lines+=("单轮 oneshot 超时。")
      lines+=("Next step:")
      lines+=("  考虑拆分任务或排查 provider 性能；调整 --round-timeout。")
      ;;
    provider_failed)
      lines+=("")
      lines+=("Provider CLI 退出非 0。")
      lines+=("Next step:")
      lines+=("  查看 .ralph/runs/$run_id/result.json 的 last_error 字段诊断。")
      ;;
    interrupted)
      lines+=("")
      lines+=("SIGINT 中断（lock 已释放）。直接重跑 ralph run 即可继续。")
      ;;
    locked)
      lines+=("")
      lines+=("Lock 冲突：另有 ralph run 在跑。")
      ;;
  esac
  lines+=("$sep")

  printf '%s\n' "${lines[@]}" >&2

  # 同时写到 run dir 方便人类 cat 给 main agent
  if [[ -n "$_RALPH_RUN_DIR" && -d "$_RALPH_RUN_DIR" ]]; then
    printf '%s\n' "${lines[@]}" > "$_RALPH_RUN_DIR/exit-message.txt"
  fi
}

_ralph_finish() {
  local exit_reason="$1"
  local exit_code="$2"
  local rounds="${3:-0}"
  local tasks_total="${4:-0}"
  local tasks_checked_start="${5:-0}"
  local tasks_checked_end="${6:-0}"
  local started_at="${7:-}"
  local last_error="${8:-null}"

  _ralph_stop_verbose_tail
  _ralph_stop_sticky_tail
  _ralph_stop_provider_heartbeat

  # sticky 最终帧（显示退出状态 ✓/✗/⏸）后清理终端
  if [[ "${_RALPH_STICKY_MODE:-0}" -eq 1 ]]; then
    _RALPH_EXIT_REASON="$exit_reason"
    _RALPH_STICKY_EXIT_REASON="$exit_reason"
    _RALPH_STICKY_TASKS_DONE="$tasks_checked_end"
    _RALPH_STICKY_TASKS_TOTAL="$tasks_total"
    _RALPH_STICKY_ROUND="${_RALPH_ROUND:-$rounds}"
    # 最终帧走 frozen 视觉（顶栏 "finished 0s ago · duration"，底栏 "all tasks done"
    # 或 frozen 后缀），与 ralph watch attach 已 finished run 的画面一致。
    _RALPH_STICKY_FROZEN_NOW="$(date +%s)"
    ralph_sticky_render_frame
    ralph_sticky_cleanup
  fi

  if [[ "$_RALPH_LOCK_ACQUIRED" -eq 1 && -n "$_RALPH_RUN_DIR" ]]; then
    _ralph_write_result "$exit_reason" "$rounds" "$tasks_total" \
      "$tasks_checked_start" "$tasks_checked_end" "$started_at" "$last_error"
    # TASKS.md 快照
    local tasks_md="$_RALPH_WORKSPACE/.ralph/TASKS.md"
    [[ -f "$tasks_md" ]] && cp "$tasks_md" "$_RALPH_RUN_DIR/TASKS.md"
    # status.json 更新为 finished
    _ralph_update_status "finished" "$exit_reason" "$rounds" "$tasks_total" "$tasks_checked_end" "$last_error"
    # 终端格式化总结（接力提示）
    _ralph_print_summary "$exit_reason" "$rounds" "$tasks_total" "$tasks_checked_end"
    ralph_lock_release "$_RALPH_LOCK_FILE"
  fi
  exit "$exit_code"
}

# ── trap ─────────────────────────────────────────────────────────────────────
_ralph_trap_interrupted() {
  if [[ "${_RALPH_STICKY_MODE:-0}" -eq 1 ]]; then
    ralph_sticky_cleanup
  fi
  if [[ "$_RALPH_LOCK_ACQUIRED" -eq 0 ]]; then
    # lock 获取前：不产生 run 目录
    echo "ralph: interrupted before lock acquired" >&2
    exit 130
  else
    _ralph_stop_active_provider
    _ralph_finish "interrupted" 130 \
      "${_RALPH_ROUND:-0}" "${_RALPH_TASKS_TOTAL:-0}" \
      "${_RALPH_TASKS_CHECKED_START:-0}" "${_RALPH_TASKS_CHECKED_END:-0}" \
      "${_RALPH_STARTED_AT:-}" "null"
  fi
}
trap '_ralph_trap_interrupted' INT TERM

# ── status.json 辅助 ─────────────────────────────────────────────────────────
_ralph_write_status() {
  local state="$1"
  local run_id="$2"
  local provider="$3"
  local model="$4"
  local effort="$5"
  local started_at="$6"
  local round="$7"
  local tasks_total="$8"
  local tasks_checked="$9"
  local exit_reason="${10:-}"
  local last_error_json="${11:-null}"
  local retry_count="${12:-0}"
  local next_retry_at="${13:-null}"
  local task_try="${14:-1}"

  cat > "$_RALPH_WORKSPACE/.ralph/status.json" <<EOF
{
  "run_id": "$(ralph_json_escape "$run_id")",
  "run_dir": "$(ralph_json_escape ".ralph/runs/$run_id")",
  "workspace": "$(ralph_json_escape "$_RALPH_WORKSPACE")",
  "provider": "$(ralph_json_escape "$provider")",
  "model": $(ralph_json_str "$model"),
  "effort": $(ralph_json_str "$effort"),
  "started_at": "$(ralph_json_escape "$started_at")",
  "task_started_at": $(ralph_json_str "${_RALPH_TASK_STARTED_AT:-$started_at}"),
  "updated_at": "$(ralph_json_escape "$(ralph_timestamp)")",
  "round": ${round},
  "task_try": ${task_try},
  "iteration_name": $(ralph_json_str "$_RALPH_CURRENT_ITERATION"),
  "state": "$(ralph_json_escape "$state")",
  "tasks_total": ${tasks_total},
  "tasks_checked": ${tasks_checked},
  "exit_reason": $(ralph_json_str "$exit_reason"),
  "retry_count": ${retry_count},
  "next_retry_at": $(ralph_json_num "$next_retry_at"),
  "last_error": ${last_error_json}
}
EOF
}

_ralph_update_status() {
  local state="$1"
  local exit_reason="${2:-}"
  local round="${3:-0}"
  local tasks_total="${4:-0}"
  local tasks_checked="${5:-0}"
  local last_error_json="${6:-null}"
  local retry_count="${7:-0}"
  local next_retry_at="${8:-null}"
  local task_try="${9:-${_RALPH_CURRENT_TASK_TRY:-1}}"

  _ralph_write_status "$state" "$_RALPH_RUN_ID" "$_RALPH_PROVIDER" \
    "$_RALPH_MODEL" "$_RALPH_EFFORT" "$_RALPH_STARTED_AT" \
    "$round" "$tasks_total" "$tasks_checked" "$exit_reason" \
    "$last_error_json" "$retry_count" "$next_retry_at" "$task_try"
}

# ── 启动校验 ─────────────────────────────────────────────────────────────────
_STARTUP_FAIL_PREFIX="ralph: startup check failed:"

_ralph_startup_checks() {
  local workspace="$1"
  local provider="$2"

  # PROMPT.md
  [[ -f "$workspace/.ralph/PROMPT.md" ]] || {
    echo "$_STARTUP_FAIL_PREFIX .ralph/PROMPT.md not found" >&2; return 1; }

  # TASKS.md
  [[ -f "$workspace/.ralph/TASKS.md" ]] || {
    echo "$_STARTUP_FAIL_PREFIX .ralph/TASKS.md not found" >&2; return 1; }

  # 任务前缀全大写校验（快速失败，在 lock 之前）
  if ! validate_task_prefixes "$workspace/.ralph/TASKS.md"; then
    echo "$_STARTUP_FAIL_PREFIX TASKS.md task prefixes must be UPPERCASE (see PROMPT.md task type table)" >&2
    return 1
  fi

  # .env + RALPH_PROVIDER 非空
  [[ -n "$provider" ]] || {
    echo "$_STARTUP_FAIL_PREFIX RALPH_PROVIDER is not set" >&2; return 1; }

  # .git/
  [[ -d "$workspace/.git" ]] || {
    echo "$_STARTUP_FAIL_PREFIX $workspace is not a git repository" >&2; return 1; }

  # UUID 校验（仅 claude provider）
  if [[ "$provider" == "claude" ]]; then
    ralph_uuid >/dev/null || return 1
  fi

  return 0
}

# ── 主函数 ───────────────────────────────────────────────────────────────────
ralph_run() {
  local provider="${RALPH_PROVIDER:-}"
  local model="${RALPH_PROVIDER_MODEL:-}"
  local effort="${RALPH_PROVIDER_EFFORT:-}"
  local max_round="${RALPH_LOOP_MAX_ROUND:-0}"
  local timeout_sec="${RALPH_LOOP_ROUND_TIMEOUT:-0}"
  local stall_limit="${RALPH_LOOP_STALL_LIMIT:-5}"
  local max_retry="${RALPH_LOOP_MAX_RETRY:-3}"
  local retry_schedule="${RALPH_LOOP_RETRY_SCHEDULE:-60 120 300}"

  # workspace 定位
  local workspace
  workspace="$(ralph_workspace_root)"
  _RALPH_WORKSPACE="$workspace"
  cd "$workspace"

  # .env 加载（在 CLI flag 合并之前，保证优先级 CLI > env > .env）
  load_env "$workspace/.ralph/.env"

  # 重新读取（.env 可能补充了值）
  provider="${RALPH_PROVIDER:-$provider}"
  model="${RALPH_PROVIDER_MODEL:-$model}"
  effort="${RALPH_PROVIDER_EFFORT:-$effort}"
  max_round="${RALPH_LOOP_MAX_ROUND:-$max_round}"
  timeout_sec="${RALPH_LOOP_ROUND_TIMEOUT:-$timeout_sec}"
  stall_limit="${RALPH_LOOP_STALL_LIMIT:-$stall_limit}"
  max_retry="${RALPH_LOOP_MAX_RETRY:-$max_retry}"
  retry_schedule="${RALPH_LOOP_RETRY_SCHEDULE:-$retry_schedule}"

  # 载入 adapter（设置 RALPH_PROVIDER_CLI）
  local adapter_file="$workspace/.ralph/lib/adapter-${provider:-fake}.sh"
  if [[ -f "$adapter_file" ]]; then
    # shellcheck disable=SC1090
    source "$adapter_file"
  else
    echo "${_STARTUP_FAIL_PREFIX} unknown provider: ${provider:-fake} (adapter-${provider:-fake}.sh not found)" >&2
    exit 1
  fi

  # 依赖校验：先注册公共依赖，再调用 provider_check_deps，最后聚合输出
  ralph_require_cmd git "git version control" \
    $'macOS: brew install git\nLinux: apt install git-all'
  if declare -f provider_check_deps >/dev/null 2>&1; then
    provider_check_deps
  fi
  ralph_report_missing_deps || exit 1

  # 启动校验
  _ralph_startup_checks "$workspace" "$provider" || exit 1

  # 获取 lock
  local lock_file="$workspace/.ralph/lock"
  _RALPH_LOCK_FILE="$lock_file"
  mkdir -p "$workspace/.ralph"
  if ! ralph_lock_acquire "$lock_file"; then
    echo "ralph: another ralph run is already active (locked)" >&2
    exit 6
  fi
  _RALPH_LOCK_ACQUIRED=1

  # run_id + 目录
  local run_id started_at start_sha
  run_id="$(ralph_run_id)"
  _RALPH_RUN_ID="$run_id"
  started_at="$(ralph_timestamp)"
  _RALPH_STARTED_AT="$started_at"
  _RALPH_START_TIME="$(date -u +%s)"
  start_sha="$(git rev-parse HEAD 2>/dev/null)" || start_sha=""

  local run_dir="$workspace/.ralph/runs/$run_id"
  _RALPH_RUN_DIR="$run_dir"
  mkdir -p "$run_dir/rounds"

  # context.json
  local provider_version
  provider_version="$(command "$RALPH_PROVIDER_CLI" --version 2>/dev/null | head -1)" || provider_version=""
  cat > "$run_dir/context.json" <<EOF
{
  "run_id": "$(ralph_json_escape "$run_id")",
  "workspace": "$(ralph_json_escape "$workspace")",
  "provider": "$(ralph_json_escape "$provider")",
  "provider_version": $(ralph_json_str "$provider_version"),
  "model": $(ralph_json_str "$model"),
  "effort": $(ralph_json_str "$effort"),
  "max_round": ${max_round},
  "timeout": ${timeout_sec},
  "stall_limit": ${stall_limit},
  "start_sha": $(ralph_json_str "$start_sha"),
  "started_at": "$(ralph_json_escape "$started_at")",
  "env_source": ".ralph/.env + process env + CLI flags"
}
EOF

  # 初始任务计数
  local tasks_md="$workspace/.ralph/TASKS.md"
  local tasks_total tasks_checked_start
  tasks_total="$(count_total "$tasks_md")"
  tasks_checked_start="$(count_checked "$tasks_md")"
  _RALPH_TASKS_TOTAL="$tasks_total"
  _RALPH_TASKS_CHECKED_START="$tasks_checked_start"
  _RALPH_TASKS_CHECKED_END="$tasks_checked_start"
  _RALPH_PROVIDER="$provider"
  _RALPH_MODEL="$model"
  _RALPH_EFFORT="$effort"

  # 解析 TASKS.md 顶部 "当前迭代" 声明（如有），用于 status.json / result.json / 退出打印
  _RALPH_CURRENT_ITERATION="$(parse_current_iteration "$tasks_md")"

  # 启动 banner（D-2 进度 marker，stderr）
  local _banner_iter="${_RALPH_CURRENT_ITERATION:-}"
  [[ -z "$_banner_iter" || "$_banner_iter" == "null" ]] && _banner_iter="(no-iter)"
  printf '[%s] ralph %s | run %s | %s | tasks %d/%d done | provider %s\n' \
    "$(date +"%H:%M:%S")" \
    "$RALPH_VERSION" \
    "$run_id" \
    "$_banner_iter" \
    "$tasks_checked_start" \
    "$tasks_total" \
    "$provider" >&2

  # sticky 模式判定：RALPH_VERBOSE=1 且 stdout 是 TTY
  if [[ "${RALPH_VERBOSE:-0}" == "1" ]] && [[ -t 1 ]]; then
    _RALPH_STICKY_MODE=1
    source "$_RALPH_LIB_DIR/sticky.sh"
    _RALPH_STICKY_RUN_START_TS="$_RALPH_START_TIME"
    _RALPH_STICKY_PROVIDER="$provider"
    _RALPH_STICKY_STALL_LIMIT="$stall_limit"
    _RALPH_STICKY_MAX_ROUND="$max_round"
    _RALPH_STICKY_RETRY_COUNT=0
    ralph_sticky_enter
  fi

  # status.json 初始写入
  _ralph_write_status "running" "$run_id" "$provider" "$model" "$effort" \
    "$started_at" 0 "$tasks_total" "$tasks_checked_start" "null" "null" 0 "null" 1

  # TASKS.md 空或全部已勾选 → 直接 done，不产生 round
  if [[ "$tasks_total" -eq 0 || "$tasks_checked_start" -ge "$tasks_total" ]]; then
    _ralph_finish "done" 0 0 "$tasks_total" "$tasks_checked_start" "$tasks_checked_start" "$started_at" "null"
  fi

  # blocked_by_human 预检：第一个未勾选任务前缀是 HUMAN- → 不启动 oneshot，直接 exit 7
  if is_blocked_by_human "$tasks_md"; then
    _ralph_finish "blocked_by_human" 7 0 "$tasks_total" \
      "$tasks_checked_start" "$tasks_checked_start" "$started_at" "null"
  fi

  local stall_count=0
  local round=0
  local last_error_json="null"
  local retry_count=0

  # ── 主循环 ──────────────────────────────────────────────────────────────
  while true; do
    if [[ "$retry_count" -eq 0 ]]; then
      round=$(( round + 1 ))
    fi
    _RALPH_ROUND="$round"

    # per-task round tracking：仅在非 retry 时更新（retry 是同一 round 内重试，
    # 不构成新一次 task try；同时 round 也只在 retry_count==0 时递增，二者同源）
    if [[ "$retry_count" -eq 0 ]]; then
      local _first_task_text=""
      _first_task_text="$(first_unchecked_task "$tasks_md" 2>/dev/null)" || _first_task_text=""
      if [[ "$_first_task_text" != "${_RALPH_CURRENT_TASK_ID:-}" ]]; then
        _RALPH_CURRENT_TASK_ID="$_first_task_text"
        _RALPH_CURRENT_TASK_TRY=1
        _RALPH_TASK_START_TS="$(date -u +%s)"
        _RALPH_TASK_STARTED_AT="$(ralph_timestamp)"
        stall_count=0
      else
        _RALPH_CURRENT_TASK_TRY=$(( _RALPH_CURRENT_TASK_TRY + 1 ))
      fi
    fi

    # 全部完成判定（在 max_round 检查前）
    local checked_before
    checked_before="$(count_checked "$tasks_md")"
    local total_now
    total_now="$(count_total "$tasks_md")"
    tasks_total="$total_now"
    _RALPH_TASKS_TOTAL="$tasks_total"

    if [[ "$checked_before" -ge "$total_now" && "$total_now" -gt 0 ]]; then
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "done" 0 "$(( round - 1 ))" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "null"
    fi

    # blocked_by_human 检查（done 之后，max_round 之前）：第一个未勾选任务前缀是 HUMAN- → 不调 provider，exit 7
    if is_blocked_by_human "$tasks_md"; then
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "blocked_by_human" 7 "$(( round - 1 ))" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "null"
    fi

    # 准备 round 目录
    local round_label
    round_label="$(printf 'round-%03d' "$round")"
    local round_dir="$run_dir/rounds/$round_label"
    mkdir -p "$round_dir"
    local log_path="$round_dir/provider.stdout.log"
    touch "$log_path"
    local round_start_ts
    round_start_ts=$(( $(date -u +%s) * 1000 ))
    _RALPH_TASKS_CHECKED_END="$checked_before"

    # 捕获本轮开始时的 worktree 状态（方案 B：in-memory hash，不写 .git/refs）
    local fingerprint_before before_round_head
    fingerprint_before="$(ralph_worktree_fingerprint)"
    before_round_head="$(git rev-parse HEAD 2>/dev/null)" || before_round_head=""

    # 准备 prompt（PROMPT.md 全文 + runtime 块）—— 写到 round 外的临时文件，
    # 不留 prompt.md 副本（动态部分见 meta.json.runtime_block，静态部分通过
    # start_sha 还原 git show $start_sha:.ralph/PROMPT.md）
    local prompt_file
    prompt_file="$(mktemp -t "ralph-prompt-${round_label}.XXXXXX")"
    local runtime_block
    printf -v runtime_block 'run_id: %s\nround: %d\nstart_sha: %s\nworkspace: %s' \
      "$run_id" "$round" "$start_sha" "$workspace"
    {
      cat "$workspace/.ralph/PROMPT.md"
      printf '\n\n<ralph-runtime>\n%s\n</ralph-runtime>\n' "$runtime_block"
    } > "$prompt_file"

    # meta.json 骨架（在 provider_oneshot 之前，让 adapter 可写入 session_id 等字段）
    init_meta "$round_dir" "$round" "$provider" 0 0
    update_meta_jq "$round_dir" '.runtime_block = $rb' --arg rb "$runtime_block"

    # status 必须在 provider_oneshot 前指向当前 round；watch -v 依赖它定位
    # 当前正在写入的 provider.stdout.log。
    _ralph_update_status "running" "" "$round" "$tasks_total" "$checked_before" "null" "$retry_count"


    # 进度 marker：round 启动
    local _max_round_disp="∞"
    [[ "$max_round" -gt 0 ]] && _max_round_disp="$max_round"
    local _first_task=""
    if declare -f first_unchecked_task >/dev/null 2>&1; then
      _first_task="$(first_unchecked_task "$tasks_md" 2>/dev/null)" || _first_task=""
    fi
    _RALPH_CURRENT_LOG_PATH="$log_path"
    if [[ "$_RALPH_STICKY_MODE" -ne 1 ]]; then
      local _now_local
      _now_local="$(date +"%H:%M:%S")"
      local _start_marker="[$_now_local] round $round/$_max_round_disp"
      if [[ -n "$_first_task" ]]; then
        _start_marker+=" → ${_first_task:0:80}"
      fi
      printf '%s\n' "$_start_marker" >&2
    fi

    # 进度输出：sticky → event filter + render loop / plain → heartbeat
    if [[ "$_RALPH_STICKY_MODE" -eq 1 ]]; then
      # sticky 模式：后台 tail → filter → event 文件；主进程 render 循环
      _ralph_stop_sticky_tail
      touch "$log_path"
      _RALPH_STICKY_EVENT_FILE="$(mktemp -t ralph-sticky-events.XXXXXX)"
      _RALPH_STICKY_LAST_POS=0
      local _sticky_fifo
      _sticky_fifo="$(mktemp -t ralph-sticky-tail.XXXXXX)"
      rm -f "$_sticky_fifo"
      mkfifo "$_sticky_fifo"
      tail -f "$log_path" > "$_sticky_fifo" 2>/dev/null &
      _RALPH_STICKY_TAIL_PID=$!
      _ralph_filter_verbose < "$_sticky_fifo" >> "$_RALPH_STICKY_EVENT_FILE" 2>/dev/null &
      _RALPH_STICKY_FILTER_PID=$!
    else
      # plain 模式：60s heartbeat
      _ralph_start_provider_heartbeat "$log_path" "$round" "$_max_round_disp"
    fi

    # provider_oneshot（带 timeout / interrupt 清理支持）
    local rc=0
    RALPH_WORKSPACE="$workspace" provider_oneshot "$prompt_file" "$log_path" "$round_dir" &
    local pid=$!
    _RALPH_PROVIDER_PID="$pid"

    if [[ "$_RALPH_STICKY_MODE" -eq 1 ]]; then
      # sticky 模式：polling loop → 读事件 + render frame + 超时检测
      _RALPH_STICKY_TASK_START_TS="${_RALPH_TASK_START_TS:-$(( round_start_ts / 1000 ))}"
      while kill -0 "$pid" 2>/dev/null; do
        sleep 0.1
        # 读取新事件
        if [[ -f "$_RALPH_STICKY_EVENT_FILE" ]]; then
          local _ev_size=0
          _ev_size="$(wc -c < "$_RALPH_STICKY_EVENT_FILE" 2>/dev/null | tr -d '[:space:]')" || _ev_size=0
          if [[ "$_ev_size" -gt "$_RALPH_STICKY_LAST_POS" ]]; then
            local _new_events
            _new_events="$(tail -c "+$(( _RALPH_STICKY_LAST_POS + 1 ))" "$_RALPH_STICKY_EVENT_FILE" 2>/dev/null)" || _new_events=""
            _RALPH_STICKY_LAST_POS="$_ev_size"
            local _ev_line
            while IFS= read -r _ev_line; do
              [[ -n "$_ev_line" ]] && ralph_sticky_append_event "$_ev_line"
            done <<< "$_new_events"
          fi
        fi
        _ralph_sticky_update_vars
        ralph_sticky_render_frame
        # 超时检测
        if [[ "$timeout_sec" -gt 0 ]]; then
          local _elapsed_ms=$(( $(date -u +%s) * 1000 - round_start_ts ))
          if [[ "$(( _elapsed_ms / 1000 ))" -ge "$timeout_sec" ]]; then
            _ralph_terminate_process_tree "$pid"
            local timeout_pid_rc=0
            wait "$pid" 2>/dev/null || timeout_pid_rc=$?
            local timeout_end_ts timeout_dur_ms
            timeout_end_ts=$(( $(date -u +%s) * 1000 ))
            timeout_dur_ms=$(( timeout_end_ts - round_start_ts ))
            update_meta_field "$round_dir" exit_code "$timeout_pid_rc"
            update_meta_field "$round_dir" duration_ms "$timeout_dur_ms"
            provider_collect_session "$round_dir" || true
            provider_diagnose "$round_dir" || true
            local total_after_timeout checked_after_timeout
            total_after_timeout="$(count_total "$tasks_md")"
            checked_after_timeout="$(count_checked "$tasks_md")"
            tasks_total="$total_after_timeout"
            _RALPH_TASKS_TOTAL="$tasks_total"
            _RALPH_TASKS_CHECKED_END="$checked_after_timeout"
            _ralph_stop_sticky_tail
            _ralph_finish "timeout" 3 "$round" "$tasks_total" \
              "$tasks_checked_start" "$checked_after_timeout" "$started_at" "null"
          fi
        fi
      done
      wait "$pid" 2>/dev/null || rc=$?
    elif [[ "$timeout_sec" -gt 0 ]]; then
      # plain + timeout：用后台 + kill 实现单轮超时
      local elapsed=0
      while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        elapsed=$(( elapsed + 1 ))
        if [[ "$elapsed" -ge "$timeout_sec" ]]; then
          _ralph_terminate_process_tree "$pid"
          local timeout_pid_rc=0
          wait "$pid" 2>/dev/null || timeout_pid_rc=$?
          local timeout_end_ts timeout_dur_ms
          timeout_end_ts=$(( $(date -u +%s) * 1000 ))
          timeout_dur_ms=$(( timeout_end_ts - round_start_ts ))
          update_meta_field "$round_dir" exit_code "$timeout_pid_rc"
          update_meta_field "$round_dir" duration_ms "$timeout_dur_ms"
          provider_collect_session "$round_dir" || true
          provider_diagnose "$round_dir" || true
          local total_after_timeout checked_after_timeout
          total_after_timeout="$(count_total "$tasks_md")"
          checked_after_timeout="$(count_checked "$tasks_md")"
          tasks_total="$total_after_timeout"
          _RALPH_TASKS_TOTAL="$tasks_total"
          _RALPH_TASKS_CHECKED_END="$checked_after_timeout"
          _ralph_finish "timeout" 3 "$round" "$tasks_total" \
            "$tasks_checked_start" "$checked_after_timeout" "$started_at" "null"
        fi
      done
      wait "$pid" 2>/dev/null || rc=$?
    else
      wait "$pid" 2>/dev/null || rc=$?
    fi
    _RALPH_PROVIDER_PID=""

    # 停 tail / heartbeat / sticky
    _ralph_stop_verbose_tail
    _ralph_stop_sticky_tail
    _ralph_stop_provider_heartbeat

    # 清理 prompt 临时文件（provider 已经读完）
    rm -f "$prompt_file"

    local round_end_ts duration_ms
    round_end_ts=$(( $(date -u +%s) * 1000 ))
    duration_ms=$(( round_end_ts - round_start_ts ))

    # exit_code / duration_ms 事后回填（保留 adapter 已写入的其他字段，如 session_id）
    update_meta_field "$round_dir" exit_code "$rc"
    update_meta_field "$round_dir" duration_ms "$duration_ms"

    # provider 失败判定
    if [[ "$rc" -ne 0 ]]; then
      provider_collect_session "$round_dir" || true
      provider_diagnose "$round_dir" || true
      # 优先从 meta.json 读取 provider_diagnose 写入的 error 对象（jq 可用时）
      local error_obj=""
      if command -v jq >/dev/null 2>&1 && [[ -f "$round_dir/meta.json" ]]; then
        error_obj="$(jq -c '.error // empty' "$round_dir/meta.json" 2>/dev/null)" || error_obj=""
      fi
      if [[ -n "$error_obj" && "$error_obj" != "null" ]]; then
        last_error_json="$error_obj"
      else
        last_error_json="{\"type\":\"unknown\",\"message\":\"provider exited with code $rc\",\"raw\":\"\"}"
      fi

      local error_type="unknown"
      if [[ -n "$error_obj" && "$error_obj" != "null" ]]; then
        if command -v jq >/dev/null 2>&1; then
          error_type="$(printf '%s' "$error_obj" | jq -r '.type // "unknown"' 2>/dev/null)" || error_type="unknown"
        fi
      fi

      # 重试判定：transient 错误 && 未超限
      if [[ "$retry_count" -lt "$max_retry" ]] && [[ "$error_type" == "rate_limit" || "$error_type" == "network" ]]; then
        retry_count=$(( retry_count + 1 ))
        _RALPH_STICKY_RETRY_COUNT="$retry_count"
        
        # 计算 backoff
        local wait_sec
        wait_sec="$(echo "$retry_schedule" | awk -v i="$retry_count" '{print $i}')"
        [[ -z "$wait_sec" ]] && wait_sec="$(echo "$retry_schedule" | awk '{print $NF}')"
        [[ ! "$wait_sec" =~ ^[0-9]+$ ]] && wait_sec=60
        
        local next_retry_at
        next_retry_at=$(( $(date -u +%s) + wait_sec ))

        # status.json 更新 retry 状态
        local checked_now
        checked_now="$(count_checked "$tasks_md")"
        _ralph_update_status "running" "" "$round" "$tasks_total" "$checked_now" "$last_error_json" "$retry_count" "$next_retry_at"

        # 输出 retry marker
        if [[ "$_RALPH_STICKY_MODE" -ne 1 ]]; then
          printf 'ralph: round %d retry %d/%d after %ds backoff (last_error: %s)\n' \
            "$round" "$retry_count" "$max_retry" "$wait_sec" "$error_type" >&2
        fi

        sleep "$wait_sec"
        continue
      fi

      retry_count=0
      _RALPH_STICKY_RETRY_COUNT=0
      local total_after_failure checked_after_failure
      total_after_failure="$(count_total "$tasks_md")"
      checked_after_failure="$(count_checked "$tasks_md")"
      tasks_total="$total_after_failure"
      _RALPH_TASKS_TOTAL="$tasks_total"
      _RALPH_TASKS_CHECKED_END="$checked_after_failure"
      _ralph_finish "provider_failed" 2 "$round" "$tasks_total" \
        "$tasks_checked_start" "$checked_after_failure" "$started_at" "$last_error_json"
    fi

    # session 采集 + 诊断
    provider_collect_session "$round_dir" || true
    provider_diagnose "$round_dir" || true
    retry_count=0
    _RALPH_STICKY_RETRY_COUNT=0

    # changed_files + stall 判定（方案 B：本轮 vs 上轮 fingerprint 对比）
    local checked_after
    checked_after="$(count_checked "$tasks_md")"
    _RALPH_TASKS_CHECKED_END="$checked_after"
    local total_after
    total_after="$(count_total "$tasks_md")"
    tasks_total="$total_after"
    _RALPH_TASKS_TOTAL="$tasks_total"

    local fingerprint_after
    fingerprint_after="$(ralph_worktree_fingerprint)"

    if [[ "$checked_after" -eq "$checked_before" && "$fingerprint_after" == "$fingerprint_before" ]]; then
      stall_count=$(( stall_count + 1 ))
    else
      stall_count=0
    fi
    _RALPH_STICKY_STALL_COUNT="$stall_count"

    # changed_files_total（cumulative since start_sha，诊断用）
    local changed_files_total_list
    changed_files_total_list="$(ralph_changed_files "$start_sha")"

    # changed_files_round（本轮 vs 上轮；fingerprint 相同则为空）
    local changed_files_round_list=""
    if [[ "$fingerprint_after" != "$fingerprint_before" ]]; then
      changed_files_round_list="$(ralph_changed_files "$before_round_head")"
    fi

    # 更新 meta.json
    local tasks_before_json="{\"total\":${total_now},\"checked\":${checked_before}}"
    local tasks_after_json="{\"total\":${total_after},\"checked\":${checked_after}}"
    sed -i.bak \
      -e "s|\"tasks_before\": null|\"tasks_before\": ${tasks_before_json}|" \
      -e "s|\"tasks_after\": null|\"tasks_after\": ${tasks_after_json}|" \
      -e "s|\"stall_count\": 0|\"stall_count\": ${stall_count}|" \
      "$round_dir/meta.json" 2>/dev/null || true
    rm -f "$round_dir/meta.json.bak"

    # changed_files_total + changed_files_round 写入 meta.json（需要 jq）
    if command -v jq >/dev/null 2>&1; then
      local cf_total_json cf_round_json
      if [[ -n "$changed_files_total_list" ]]; then
        cf_total_json="$(printf '%s\n' "$changed_files_total_list" | jq -R . | jq -s . 2>/dev/null)" || cf_total_json="[]"
      else
        cf_total_json="[]"
      fi
      if [[ -n "$changed_files_round_list" ]]; then
        cf_round_json="$(printf '%s\n' "$changed_files_round_list" | jq -R . | jq -s . 2>/dev/null)" || cf_round_json="[]"
      else
        cf_round_json="[]"
      fi
      update_meta_jq "$round_dir" \
        '.changed_files_total = $cf_total | .changed_files_round = $cf_round' \
        --argjson cf_total "$cf_total_json" --argjson cf_round "$cf_round_json" || true
    fi

    # status.json 刷新
    _ralph_update_status "running" "" "$round" "$tasks_total" "$checked_after"

    # 进度 marker：round 完成
    local _round_dur_sec=$(( duration_ms / 1000 ))
    local _run_dur_sec=$(( $(date -u +%s) - _RALPH_START_TIME ))
    local _delta_tasks=$(( checked_after - checked_before ))
    if [[ "$_RALPH_STICKY_MODE" -ne 1 ]]; then
      local _now_local
      _now_local="$(date +"%H:%M:%S")"
      local _end_status="✓ done"
      [[ "$_delta_tasks" -eq 0 ]] && _end_status="◷ no progress"
      printf '[%s] round %d/%s %s | tasks %d/%d | round %s | run %s\n' \
        "$_now_local" "$round" "$_max_round_disp" "$_end_status" \
        "$checked_after" "$tasks_total" \
        "$(ralph_format_duration "$_round_dur_sec")" \
        "$(ralph_format_duration "$_run_dur_sec")" >&2
    fi

    # ── per-task 防死循环检查 ────────────────────────────────────────────────
    local _task_prefix=""
    if [[ -n "${_RALPH_CURRENT_TASK_ID:-}" && "${_RALPH_CURRENT_TASK_ID}" =~ ^([A-Z]+-[0-9]+) ]]; then
      _task_prefix="${BASH_REMATCH[1]}"
    elif [[ -n "${_RALPH_CURRENT_TASK_ID:-}" ]]; then
      _task_prefix="${_RALPH_CURRENT_TASK_ID:0:40}"
    fi
    local _run_elapsed=""
    if [[ -n "${_RALPH_START_TIME:-}" ]]; then
      _run_elapsed="$(ralph_format_duration $(( $(date -u +%s) - _RALPH_START_TIME )))"
    fi
    # 仅在当前 task 仍为 first_unchecked 时触发（已完成的不触发）
    local _still_first=""
    _still_first="$(first_unchecked_task "$tasks_md" 2>/dev/null)" || _still_first=""

    # per-task max_round 触发
    if [[ "$max_round" -gt 0 && "${_RALPH_CURRENT_TASK_TRY:-0}" -ge "$max_round" \
          && "$_still_first" == "${_RALPH_CURRENT_TASK_ID:-}" ]]; then
      local _human_n _task_lineno
      _human_n="$(next_human_number "$tasks_md")"
      _task_lineno="$(find_first_unchecked_lineno "$tasks_md")"
      insert_human_before_task "$tasks_md" "$_task_lineno" "$_human_n" \
        "$_task_prefix 已试 ${_RALPH_CURRENT_TASK_TRY} 次 round 超过上限（max_round ${max_round}）" \
        "$_task_prefix" "$_run_elapsed"
      _ralph_finish "blocked_by_human" 7 "$round" "$tasks_total" \
        "$tasks_checked_start" "$checked_after" "$started_at" "null"
    fi

    # per-task stall 触发
    if [[ "$stall_count" -ge "$stall_limit" \
          && "$_still_first" == "${_RALPH_CURRENT_TASK_ID:-}" ]]; then
      local _human_n _task_lineno
      _human_n="$(next_human_number "$tasks_md")"
      _task_lineno="$(find_first_unchecked_lineno "$tasks_md")"
      insert_human_before_task "$tasks_md" "$_task_lineno" "$_human_n" \
        "$_task_prefix 连续 ${stall_count} 次 round 无进展（stall ${stall_count}/${stall_limit}）" \
        "$_task_prefix" "$_run_elapsed"
      _ralph_finish "blocked_by_human" 7 "$round" "$tasks_total" \
        "$tasks_checked_start" "$checked_after" "$started_at" "null"
    fi
  done
}

# ── _ralph_filter_verbose ────────────────────────────────────────────────────
# stream-json events 流过滤器：在 -v 模式下把 events 转成简短人话行（stderr）
# 输入：每行一个 JSON event（来自 provider.stdout.log）
# 输出：精简事件标记（[user] / [assistant] / [tool-use] 等）
_ralph_filter_verbose() {
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 仅处理 JSON 行
    [[ "$line" =~ ^\{ ]] || continue
    # 对每个事件按 type 简化输出（jq 失败则跳过）
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
