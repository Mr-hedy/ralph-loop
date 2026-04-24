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

# ── 退出辅助函数 ─────────────────────────────────────────────────────────────
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

_ralph_finish() {
  local exit_reason="$1"
  local exit_code="$2"
  local iterations="${3:-0}"
  local tasks_total="${4:-0}"
  local tasks_checked_start="${5:-0}"
  local tasks_checked_end="${6:-0}"
  local started_at="${7:-}"
  local last_error="${8:-null}"

  if [[ "$_RALPH_LOCK_ACQUIRED" -eq 1 && -n "$_RALPH_RUN_DIR" ]]; then
    _ralph_write_result "$exit_reason" "$iterations" "$tasks_total" \
      "$tasks_checked_start" "$tasks_checked_end" "$started_at" "$last_error"
    # TASKS.md 快照
    local tasks_md="$_RALPH_WORKSPACE/.ralph/TASKS.md"
    [[ -f "$tasks_md" ]] && cp "$tasks_md" "$_RALPH_RUN_DIR/TASKS.md"
    # status.json 更新为 finished
    _ralph_update_status "finished" "$exit_reason" "$iterations" "$tasks_total" "$tasks_checked_end"
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

  # .env + RALPH_PROVIDER 非空
  [[ -n "$provider" ]] || {
    echo "$_STARTUP_FAIL_PREFIX RALPH_PROVIDER is not set" >&2; return 1; }

  # .git/
  [[ -d "$workspace/.git" ]] || {
    echo "$_STARTUP_FAIL_PREFIX $workspace is not a git repository" >&2; return 1; }

  # command -v $RALPH_PROVIDER_CLI
  [[ -n "${RALPH_PROVIDER_CLI:-}" ]] || {
    echo "$_STARTUP_FAIL_PREFIX RALPH_PROVIDER_CLI not set by adapter" >&2; return 1; }
  command -v "$RALPH_PROVIDER_CLI" >/dev/null 2>&1 || {
    echo "$_STARTUP_FAIL_PREFIX provider CLI not found: $RALPH_PROVIDER_CLI" >&2; return 1; }

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
  local stagnation_limit=5

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
  fi

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

  # status.json 初始写入
  _ralph_write_status "running" "$run_id" "$provider" "$model" "$effort" \
    "$started_at" 0 "$tasks_total" "$tasks_checked_start"

  # TASKS.md 空或全部已勾选 → 直接 done，不产生 iteration
  if [[ "$tasks_total" -eq 0 || "$tasks_checked_start" -ge "$tasks_total" ]]; then
    _ralph_finish "done" 0 0 "$tasks_total" "$tasks_checked_start" "$tasks_checked_start" "$started_at" "null"
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
    local log_path="$iter_dir/log"
    local iter_start_ts
    iter_start_ts=$(( $(date -u +%s) * 1000 ))

    # 准备 prompt（PROMPT.md 全文 + runtime 块）
    local prompt_file="$iter_dir/prompt.md"
    {
      cat "$workspace/.ralph/PROMPT.md"
      printf '\n\n<ralph-runtime>\nrun_id: %s\niteration: %d\nstart_sha: %s\nworkspace: %s\n</ralph-runtime>\n' \
        "$run_id" "$iteration" "$start_sha" "$workspace"
    } > "$prompt_file"

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
          wait "$pid" 2>/dev/null || true
          _RALPH_TASKS_CHECKED_END="$checked_before"
          _ralph_finish "timeout" 3 "$iteration" "$tasks_total" \
            "$tasks_checked_start" "$checked_before" "$started_at" "null"
        fi
      done
      wait "$pid" 2>/dev/null || rc=$?
    else
      RALPH_WORKSPACE="$workspace" provider_oneshot "$prompt_file" "$log_path" "$iter_dir" || rc=$?
    fi

    local iter_end_ts duration_ms
    iter_end_ts=$(( $(date -u +%s) * 1000 ))
    duration_ms=$(( iter_end_ts - iter_start_ts ))

    # meta.json 初始写入
    init_meta "$iter_dir" "$iteration" "$provider" "$rc" "$duration_ms"

    # provider 失败判定
    if [[ "$rc" -ne 0 ]]; then
      provider_collect_session "$iter_dir" || true
      provider_diagnose "$iter_dir" || true
      # 读取 error type
      local error_type=""
      error_type="$(grep '"type"' "$iter_dir/meta.json" 2>/dev/null | sed 's/.*"type":[[:space:]]*"\([^"]*\)".*/\1/' | head -1)" || error_type="unknown"
      last_error_json="{\"type\":\"$(ralph_json_escape "${error_type:-unknown}")\",\"message\":\"provider exited with code $rc\",\"raw\":\"\"}"
      _RALPH_TASKS_CHECKED_END="$checked_before"
      _ralph_finish "provider_failed" 2 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_before" "$started_at" "$last_error_json"
    fi

    # session 采集 + 诊断
    provider_collect_session "$iter_dir" || true
    provider_diagnose "$iter_dir" || true

    # changed_files + stagnation 判定
    local checked_after
    checked_after="$(count_checked "$tasks_md")"
    _RALPH_TASKS_CHECKED_END="$checked_after"

    local changed_files_list
    changed_files_list="$(ralph_changed_files "$start_sha")"

    if [[ "$checked_after" -eq "$checked_before" && -z "$changed_files_list" ]]; then
      stagnation_count=$(( stagnation_count + 1 ))
    else
      stagnation_count=0
    fi

    # 更新 meta.json
    local tasks_before_json="{\"total\":${tasks_total},\"checked\":${checked_before}}"
    local tasks_after_json="{\"total\":${tasks_total},\"checked\":${checked_after}}"
    # 简单追加字段（sed 更新）
    sed -i.bak \
      -e "s|\"tasks_before\": null|\"tasks_before\": ${tasks_before_json}|" \
      -e "s|\"tasks_after\": null|\"tasks_after\": ${tasks_after_json}|" \
      -e "s|\"stagnation_count\": 0|\"stagnation_count\": ${stagnation_count}|" \
      "$iter_dir/meta.json" 2>/dev/null || true
    rm -f "$iter_dir/meta.json.bak"

    # status.json 刷新
    _ralph_update_status "running" "" "$iteration" "$tasks_total" "$checked_after"

    # stagnation 退出
    if [[ "$stagnation_count" -ge "$stagnation_limit" ]]; then
      _ralph_finish "stagnated" 5 "$iteration" "$tasks_total" \
        "$tasks_checked_start" "$checked_after" "$started_at" "null"
    fi
  done
}
