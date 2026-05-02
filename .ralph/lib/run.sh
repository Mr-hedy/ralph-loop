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

_ralph_write_result() {
  local exit_reason="$1"
  local iterations="$2"
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
  "iterations": ${iterations},
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
  local iterations="$2"
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
  lines+=("Iterations:    $iterations")
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
    stagnated)
      lines+=("")
      lines+=("连续多轮无文件变更，疑似 agent 卡住或任务描述不清。")
      lines+=("Next step:")
      lines+=("  排查最后任务描述是否模糊、provider 是否异常、PROMPT 是否需调整。")
      ;;
    timeout)
      lines+=("")
      lines+=("单轮 oneshot 超时。")
      lines+=("Next step:")
      lines+=("  考虑拆分任务或排查 provider 性能；调整 --timeout。")
      ;;
    max_iterations)
      lines+=("")
      lines+=("已达 --max-iter 上限。")
      lines+=("Next step:")
      lines+=("  评估剩余任务复杂度，必要时拆分；或提高 --max-iter 重跑。")
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
  local iterations="${3:-0}"
  local tasks_total="${4:-0}"
  local tasks_checked_start="${5:-0}"
  local tasks_checked_end="${6:-0}"
  local started_at="${7:-}"
  local last_error="${8:-null}"

  _ralph_stop_verbose_tail

  if [[ "$_RALPH_LOCK_ACQUIRED" -eq 1 && -n "$_RALPH_RUN_DIR" ]]; then
    _ralph_write_result "$exit_reason" "$iterations" "$tasks_total" \
      "$tasks_checked_start" "$tasks_checked_end" "$started_at" "$last_error"
    # TASKS.md 快照
    local tasks_md="$_RALPH_WORKSPACE/.ralph/TASKS.md"
    [[ -f "$tasks_md" ]] && cp "$tasks_md" "$_RALPH_RUN_DIR/TASKS.md"
    # status.json 更新为 finished
    _ralph_update_status "finished" "$exit_reason" "$iterations" "$tasks_total" "$tasks_checked_end"
    # 终端格式化总结（接力提示）
    _ralph_print_summary "$exit_reason" "$iterations" "$tasks_total" "$tasks_checked_end"
    ralph_lock_release "$_RALPH_LOCK_FILE"
  fi
  exit "$exit_code"
}

# ── trap ─────────────────────────────────────────────────────────────────────
_ralph_trap_interrupted() {
  if [[ "$_RALPH_LOCK_ACQUIRED" -eq 0 ]]; then
    # lock 获取前：不产生 run 目录
    echo "ralph: interrupted before lock acquired" >&2
    exit 130
  else
    _ralph_finish "interrupted" 130 \
      "${_RALPH_ITER:-0}" "${_RALPH_TASKS_TOTAL:-0}" \
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
  local iteration="$7"
  local tasks_total="$8"
  local tasks_checked="$9"
  local exit_reason="${10:-}"

  cat > "$_RALPH_WORKSPACE/.ralph/status.json" <<EOF
{
  "run_id": "$(ralph_json_escape "$run_id")",
  "run_dir": "$(ralph_json_escape ".ralph/runs/$run_id")",
  "workspace": "$(ralph_json_escape "$_RALPH_WORKSPACE")",
  "provider": "$(ralph_json_escape "$provider")",
  "model": $(ralph_json_str "$model"),
  "effort": $(ralph_json_str "$effort"),
  "started_at": "$(ralph_json_escape "$started_at")",
  "updated_at": "$(ralph_json_escape "$(ralph_timestamp)")",
  "iteration": ${iteration},
  "iteration_name": $(ralph_json_str "$_RALPH_CURRENT_ITERATION"),
  "state": "$(ralph_json_escape "$state")",
  "tasks_total": ${tasks_total},
  "tasks_checked": ${tasks_checked},
  "exit_reason": $(ralph_json_str "$exit_reason"),
  "last_error": null
}
EOF
}

_ralph_update_status() {
  local state="$1"
  local exit_reason="${2:-}"
  local iteration="${3:-0}"
  local tasks_total="${4:-0}"
  local tasks_checked="${5:-0}"
  _ralph_write_status "$state" "$_RALPH_RUN_ID" "$_RALPH_PROVIDER" \
    "$_RALPH_MODEL" "$_RALPH_EFFORT" "$_RALPH_STARTED_AT" \
    "$iteration" "$tasks_total" "$tasks_checked" "$exit_reason"
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
  local model="${RALPH_MODEL:-}"
  local effort="${RALPH_EFFORT:-}"
  local max_iter="${RALPH_MAX_ITER:-0}"
  local timeout_sec="${RALPH_TIMEOUT:-0}"
  local stagnation_limit="${RALPH_STAGNATION_LIMIT:-5}"

  # workspace 定位
  local workspace
  workspace="$(ralph_workspace_root)"
  _RALPH_WORKSPACE="$workspace"
  cd "$workspace"

  # .env 加载（在 CLI flag 合并之前，保证优先级 CLI > env > .env）
  load_env "$workspace/.ralph/.env"

  # 重新读取（.env 可能补充了值）
  provider="${RALPH_PROVIDER:-$provider}"
  model="${RALPH_MODEL:-$model}"
  effort="${RALPH_EFFORT:-$effort}"
  max_iter="${RALPH_MAX_ITER:-$max_iter}"
  timeout_sec="${RALPH_TIMEOUT:-$timeout_sec}"

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
  mkdir -p "$run_dir/iterations"

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
  "max_iter": ${max_iter},
  "timeout": ${timeout_sec},
  "stagnation_limit": ${stagnation_limit},
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

  # status.json 初始写入
  _ralph_write_status "running" "$run_id" "$provider" "$model" "$effort" \
    "$started_at" 0 "$tasks_total" "$tasks_checked_start"

  # TASKS.md 空或全部已勾选 → 直接 done，不产生 iteration
  if [[ "$tasks_total" -eq 0 || "$tasks_checked_start" -ge "$tasks_total" ]]; then
    _ralph_finish "done" 0 0 "$tasks_total" "$tasks_checked_start" "$tasks_checked_start" "$started_at" "null"
  fi

  # blocked_by_human 预检：第一个未勾选任务前缀是 HUMAN- → 不启动 oneshot，直接 exit 7
  if is_blocked_by_human "$tasks_md"; then
    _ralph_finish "blocked_by_human" 7 0 "$tasks_total" \
      "$tasks_checked_start" "$tasks_checked_start" "$started_at" "null"
  fi

  local stagnation_count=0
  local iteration=0
  local last_error_json="null"

  # ── 主循环 ──────────────────────────────────────────────────────────────
  while true; do
    iteration=$(( iteration + 1 ))
    _RALPH_ITER="$iteration"

    # 全部完成判定（在 max_iter 检查前）
    local checked_before
    checked_before="$(count_checked "$tasks_md")"
    local total_now
    total_now="$(count_total "$tasks_md")"

    if [[ "$checked_before" -ge "$total_now" && "$total_now" -gt 0 ]]; then
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "done" 0 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "null"
    fi

    # blocked_by_human 检查（done 之后，max_iter 之前）：第一个未勾选任务前缀是 HUMAN- → 不调 provider，exit 7
    if is_blocked_by_human "$tasks_md"; then
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "blocked_by_human" 7 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "null"
    fi

    # max_iter 检查
    if [[ "$max_iter" -gt 0 && "$iteration" -gt "$max_iter" ]]; then
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "max_iterations" 4 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "null"
    fi

    # 准备 iter 目录
    local iter_label
    iter_label="$(printf 'iter-%03d' "$iteration")"
    local iter_dir="$run_dir/iterations/$iter_label"
    mkdir -p "$iter_dir"
    local log_path="$iter_dir/provider.stdout.log"
    local iter_start_ts
    iter_start_ts=$(( $(date -u +%s) * 1000 ))

    # 捕获本轮开始时的 worktree 状态（方案 B：in-memory hash，不写 .git/refs）
    local fingerprint_before before_iter_head
    fingerprint_before="$(ralph_worktree_fingerprint)"
    before_iter_head="$(git rev-parse HEAD 2>/dev/null)" || before_iter_head=""

    # 准备 prompt（PROMPT.md 全文 + runtime 块）—— 写到 iter 外的临时文件，
    # 不留 prompt.md 副本（动态部分见 meta.json.runtime_block，静态部分通过
    # start_sha 还原 git show $start_sha:.ralph/PROMPT.md）
    local prompt_file
    prompt_file="$(mktemp -t "ralph-prompt-${iter_label}.XXXXXX")"
    local runtime_block
    printf -v runtime_block 'run_id: %s\niteration: %d\nstart_sha: %s\nworkspace: %s' \
      "$run_id" "$iteration" "$start_sha" "$workspace"
    {
      cat "$workspace/.ralph/PROMPT.md"
      printf '\n\n<ralph-runtime>\n%s\n</ralph-runtime>\n' "$runtime_block"
    } > "$prompt_file"

    # meta.json 骨架（在 provider_oneshot 之前，让 adapter 可写入 session_id 等字段）
    init_meta "$iter_dir" "$iteration" "$provider" 0 0
    update_meta_jq "$iter_dir" '.runtime_block = $rb' --arg rb "$runtime_block"

    # 进度 marker：iter 启动（D-2 默认）
    # max_iter=0 显示为 ∞；first task 描述截前 60 字符做提示
    local _max_iter_disp="∞"
    [[ "$max_iter" -gt 0 ]] && _max_iter_disp="$max_iter"
    local _first_task=""
    if declare -f first_unchecked_task >/dev/null 2>&1; then
      _first_task="$(first_unchecked_task "$tasks_md" 2>/dev/null)" || _first_task=""
    fi
    local _now_local
    _now_local="$(date +"%H:%M:%S")"
    local _start_marker="[$_now_local] iter $iteration/$_max_iter_disp"
    if [[ -n "$_first_task" ]]; then
      _start_marker+=" → ${_first_task:0:80}"
    fi
    printf '%s\n' "$_start_marker" >&2

    # 启动 -v live tail（如启用 RALPH_VERBOSE=1）：在 provider_oneshot 期间
    # tail provider.stdout.log，过滤 stream-json events 实时打印 agent 行为
    # 重要：redirection 顺序 `>&2 2>/dev/null` —— stdout 先转 fd2（终端 stderr）
    # 再 stderr 转 /dev/null。反序会让 stdout 也跟去 /dev/null（fd2 已被覆盖）
    if [[ "${RALPH_VERBOSE:-0}" == "1" ]]; then
      _ralph_stop_verbose_tail
      touch "$log_path"
      _RALPH_TAIL_FIFO="$(mktemp -t ralph-tail.XXXXXX)"
      rm -f "$_RALPH_TAIL_FIFO"
      mkfifo "$_RALPH_TAIL_FIFO"
      tail -f "$log_path" > "$_RALPH_TAIL_FIFO" 2>/dev/null &
      _RALPH_TAIL_PID=$!
      _ralph_filter_verbose < "$_RALPH_TAIL_FIFO" >&2 2>/dev/null &
      _RALPH_TAIL_FILTER_PID=$!
    fi

    # provider_oneshot（带 timeout 支持）
    local rc=0
    if [[ "$timeout_sec" -gt 0 ]]; then
      # 用后台 + kill 实现单轮超时
      RALPH_WORKSPACE="$workspace" provider_oneshot "$prompt_file" "$log_path" "$iter_dir" &
      local pid=$!
      local elapsed=0
      while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        elapsed=$(( elapsed + 1 ))
        if [[ "$elapsed" -ge "$timeout_sec" ]]; then
          kill "$pid" 2>/dev/null || true
          local timeout_pid_rc=0
          wait "$pid" 2>/dev/null || timeout_pid_rc=$?
          local timeout_end_ts timeout_dur_ms
          timeout_end_ts=$(( $(date -u +%s) * 1000 ))
          timeout_dur_ms=$(( timeout_end_ts - iter_start_ts ))
          update_meta_field "$iter_dir" exit_code "$timeout_pid_rc"
          update_meta_field "$iter_dir" duration_ms "$timeout_dur_ms"
          provider_collect_session "$iter_dir" || true
          provider_diagnose "$iter_dir" || true
          _RALPH_TASKS_CHECKED_END="$checked_before"
          _ralph_finish "timeout" 3 "$iteration" "$tasks_total" \
            "$tasks_checked_start" "$checked_before" "$started_at" "null"
        fi
      done
      wait "$pid" 2>/dev/null || rc=$?
    else
      RALPH_WORKSPACE="$workspace" provider_oneshot "$prompt_file" "$log_path" "$iter_dir" || rc=$?
    fi

    # 停 -v live tail
    _ralph_stop_verbose_tail

    # 清理 prompt 临时文件（provider 已经读完）
    rm -f "$prompt_file"

    local iter_end_ts duration_ms
    iter_end_ts=$(( $(date -u +%s) * 1000 ))
    duration_ms=$(( iter_end_ts - iter_start_ts ))

    # exit_code / duration_ms 事后回填（保留 adapter 已写入的其他字段，如 session_id）
    update_meta_field "$iter_dir" exit_code "$rc"
    update_meta_field "$iter_dir" duration_ms "$duration_ms"

    # provider 失败判定
    if [[ "$rc" -ne 0 ]]; then
      provider_collect_session "$iter_dir" || true
      provider_diagnose "$iter_dir" || true
      # 优先从 meta.json 读取 provider_diagnose 写入的 error 对象（jq 可用时）
      local error_obj=""
      if command -v jq >/dev/null 2>&1 && [[ -f "$iter_dir/meta.json" ]]; then
        error_obj="$(jq -c '.error // empty' "$iter_dir/meta.json" 2>/dev/null)" || error_obj=""
      fi
      if [[ -n "$error_obj" && "$error_obj" != "null" ]]; then
        last_error_json="$error_obj"
      else
        last_error_json="{\"type\":\"unknown\",\"message\":\"provider exited with code $rc\",\"raw\":\"\"}"
      fi
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "provider_failed" 2 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "$last_error_json"
    fi

    # session 采集 + 诊断
    provider_collect_session "$iter_dir" || true
    provider_diagnose "$iter_dir" || true

    # changed_files + stagnation 判定（方案 B：本轮 vs 上轮 fingerprint 对比）
    local checked_after
    checked_after="$(count_checked "$tasks_md")"
    _RALPH_TASKS_CHECKED_END="$checked_after"

    local fingerprint_after
    fingerprint_after="$(ralph_worktree_fingerprint)"

    if [[ "$checked_after" -eq "$checked_before" && "$fingerprint_after" == "$fingerprint_before" ]]; then
      stagnation_count=$(( stagnation_count + 1 ))
    else
      stagnation_count=0
    fi

    # changed_files_total（cumulative since start_sha，诊断用）
    local changed_files_total_list
    changed_files_total_list="$(ralph_changed_files "$start_sha")"

    # changed_files_iter（本轮 vs 上轮；fingerprint 相同则为空）
    local changed_files_iter_list=""
    if [[ "$fingerprint_after" != "$fingerprint_before" ]]; then
      changed_files_iter_list="$(ralph_changed_files "$before_iter_head")"
    fi

    # 更新 meta.json
    local tasks_before_json="{\"total\":${tasks_total},\"checked\":${checked_before}}"
    local tasks_after_json="{\"total\":${tasks_total},\"checked\":${checked_after}}"
    sed -i.bak \
      -e "s|\"tasks_before\": null|\"tasks_before\": ${tasks_before_json}|" \
      -e "s|\"tasks_after\": null|\"tasks_after\": ${tasks_after_json}|" \
      -e "s|\"stagnation_count\": 0|\"stagnation_count\": ${stagnation_count}|" \
      "$iter_dir/meta.json" 2>/dev/null || true
    rm -f "$iter_dir/meta.json.bak"

    # changed_files_total + changed_files_iter 写入 meta.json（需要 jq）
    if command -v jq >/dev/null 2>&1; then
      local cf_total_json cf_iter_json
      if [[ -n "$changed_files_total_list" ]]; then
        cf_total_json="$(printf '%s\n' "$changed_files_total_list" | jq -R . | jq -s . 2>/dev/null)" || cf_total_json="[]"
      else
        cf_total_json="[]"
      fi
      if [[ -n "$changed_files_iter_list" ]]; then
        cf_iter_json="$(printf '%s\n' "$changed_files_iter_list" | jq -R . | jq -s . 2>/dev/null)" || cf_iter_json="[]"
      else
        cf_iter_json="[]"
      fi
      update_meta_jq "$iter_dir" \
        '.changed_files_total = $cf_total | .changed_files_iter = $cf_iter' \
        --argjson cf_total "$cf_total_json" --argjson cf_iter "$cf_iter_json" || true
    fi

    # status.json 刷新
    _ralph_update_status "running" "" "$iteration" "$tasks_total" "$checked_after"

    # 进度 marker：iter 完成（D-2 默认）
    local _iter_dur_sec=$(( duration_ms / 1000 ))
    local _run_dur_sec=$(( $(date -u +%s) - _RALPH_START_TIME ))
    local _delta_tasks=$(( checked_after - checked_before ))
    local _now_local
    _now_local="$(date +"%H:%M:%S")"
    local _end_status="✓ done"
    [[ "$_delta_tasks" -eq 0 ]] && _end_status="◷ no progress"
    printf '[%s] iter %d/%s %s | tasks %d/%d | iter %s | run %s\n' \
      "$_now_local" "$iteration" "$_max_iter_disp" "$_end_status" \
      "$checked_after" "$tasks_total" \
      "$(ralph_format_duration "$_iter_dur_sec")" \
      "$(ralph_format_duration "$_run_dur_sec")" >&2

    # stagnation 退出
    if [[ "$stagnation_count" -ge "$stagnation_limit" ]]; then
      _ralph_finish "stagnated" 5 "$iteration" "$tasks_total" \
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
    [[ "$line" =~ ^[[:space:]]*\{ ]] || continue
    # 对每个事件按 type 简化输出（jq 失败则跳过）
    printf '%s\n' "$line" | jq -r '
      if .type == "system" and .subtype == "init" then
        "  ⚙ session " + ((.session_id // "") | .[0:8])
      elif .type == "assistant" then
        ((.message.content // []) | if type == "array" then . else [] end | .[]
          | if .type == "thinking" then "  💭 " + ((.thinking // "") | .[0:120])
            elif .type == "text"   then "  💬 " + ((.text // "") | .[0:120])
            elif .type == "tool_use" then "  🔧 " + (.name // "?") + " " + ((.input // {}) | tostring | .[0:80])
            else empty end)
      elif .type == "user" then
        ((.message.content // []) | if type == "array" then . else [] end | .[]
          | select(.type == "tool_result")
          | "  ⏎ result " + ((.content // "") | tostring | .[0:80]))
      elif .type == "result" then
        if .is_error then "  ❌ error: " + ((.result // "") | .[0:120])
        else "  ✓ result " + ((.result // "") | .[0:120]) end
      else empty end
    ' 2>/dev/null
  done
}
