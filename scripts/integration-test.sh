#!/usr/bin/env bash
# integration-test.sh — 集成测试入口

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# ── 测试基础设施 ──────────────────────────────────────────────────────────────

PASS=0
FAIL=0
ERRORS=()

_pass() { echo "  [PASS] $1"; PASS=$(( PASS + 1 )); }
_fail() { echo "  [FAIL] $1"; ERRORS+=("$1"); FAIL=$(( FAIL + 1 )); }

# 创建 mock workspace；返回临时目录路径到 stdout
# 用法：ws=$(setup_workspace [--no-prompt] [--no-tasks] [--no-env] [--no-git] [--provider <p>])
setup_workspace() {
  local no_prompt=0 no_tasks=0 no_env=0 no_git=0
  local provider="fake"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-prompt)   no_prompt=1; shift ;;
      --no-tasks)    no_tasks=1;  shift ;;
      --no-env)      no_env=1;    shift ;;
      --no-git)      no_git=1;    shift ;;
      --provider)    provider="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local ws
  ws="$(mktemp -d)"
  mkdir -p "$ws/.ralph/bin" "$ws/.ralph/lib"

  # 软链工具文件
  ln -sf "$REPO_ROOT/.ralph/bin/ralph" "$ws/.ralph/bin/ralph"
  for f in "$REPO_ROOT/.ralph/lib/"*.sh; do
    ln -sf "$f" "$ws/.ralph/lib/$(basename "$f")"
  done

  [[ "$no_prompt" -eq 0 ]] && printf '# Test prompt\nDo one task.\n' > "$ws/.ralph/PROMPT.md"
  if [[ "$no_tasks" -eq 0 ]]; then
    printf '%s\n' "- [ ] Task A" "- [ ] Task B" > "$ws/.ralph/TASKS.md"
  fi
  if [[ "$no_env" -eq 0 ]]; then
    printf 'RALPH_PROVIDER=%s\n' "$provider" > "$ws/.ralph/.env"
  fi
  if [[ "$no_git" -eq 0 ]]; then
    git -C "$ws" init -q
    git -C "$ws" config user.email "test@test.com"
    git -C "$ws" config user.name "Test"
    git -C "$ws" add .
    git -C "$ws" commit -q -m "init"
  fi

  echo "$ws"
}

# 从 result.json 读取 exit_reason
get_exit_reason() {
  local run_dir="$1"
  grep '"exit_reason"' "$run_dir/result.json" 2>/dev/null \
    | sed 's/.*"exit_reason":[[:space:]]*"\([^"]*\)".*/\1/' | head -1
}

# 从 result.json 读取 last_error.type（需要 jq）
get_last_error_type() {
  local run_dir="$1"
  jq -r '.last_error.type // empty' "$run_dir/result.json" 2>/dev/null
}

# 找最新 run 目录
latest_run_dir() {
  local ws="$1"
  local runs_dir="$ws/.ralph/runs"
  [[ -d "$runs_dir" ]] || { echo ""; return; }
  local first
  first=$(ls -dt "$runs_dir"/*/ 2>/dev/null | head -1) || true
  echo "${first%/}"
}

cleanup_ws() { rm -rf "$1"; }

count_runs() {
  local runs_dir="$1/.ralph/runs"
  [[ -d "$runs_dir" ]] || { echo 0; return; }
  ls -1 "$runs_dir" 2>/dev/null | wc -l | tr -d ' '
}

# ── 用例 ─────────────────────────────────────────────────────────────────────

echo "=== integration-test.sh ==="

# ────────────────────────────────
# 退出原因测试（7 种）
# ────────────────────────────────

echo ""
echo "-- Exit reason: done"
ws=$(setup_workspace)
# 单条任务，happy 场景一轮完成
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake \
  >"$stdout_file" 2>"$stderr_file" || rc=$?
run_dir="$(latest_run_dir "$ws")"
stdout_silent=0
[[ ! -s "$stdout_file" ]] && stdout_silent=1
progress_ok=0
if grep -Eq 'ralph [^ ]+ \| run ' "$stderr_file" \
  && grep -Eq 'round 1/.*→' "$stderr_file" \
  && grep -Eq 'round 1/.*✓ done' "$stderr_file"; then
  progress_ok=1
fi
rm -f "$stdout_file" "$stderr_file"
if [[ -n "$run_dir" && "$(get_exit_reason "$run_dir")" == "done" && "$rc" -eq 0 \
   && "$stdout_silent" -eq 1 && "$progress_ok" -eq 1 ]]; then
  _pass "done: exit_reason=done, rc=0, stdout silent, progress markers on stderr"
else
  _fail "done: expected done/rc=0 + stdout silent + progress markers, got rc=$rc run_dir=$run_dir stdout_silent=$stdout_silent progress_ok=$progress_ok"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: provider_failed (crash)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=crash bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "provider_failed" && "$rc" -eq 2 ]]; then
  _pass "provider_failed (crash): exit_reason=provider_failed, rc=2"
else
  _fail "provider_failed (crash): expected provider_failed/rc=2, got $reason/$rc"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: provider_failed (api-error)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(RALPH_FAKE_SCENARIO=api-error bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
error_type="$(grep '"type"' "$run_dir/result.json" 2>/dev/null | sed 's/.*"type":[[:space:]]*"\([^"]*\)".*/\1/' | head -1)" || error_type=""
if [[ "$reason" == "provider_failed" && "$rc" -eq 2 && "$error_type" == "api" ]]; then
  _pass "provider_failed (api-error): exit_reason=provider_failed, rc=2, error.type=api"
else
  _fail "provider_failed (api-error): got reason=$reason rc=$rc type=$error_type"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Provider retry: rate_limit"
ws=$(setup_workspace)
rc=0
stderr_file="$(mktemp)"
RALPH_FAKE_SCENARIO=rate_limit RALPH_LOOP_RETRY_SCHEDULE="1 1" bash "$ws/.ralph/bin/ralph" run --provider fake --max-retry 2 \
  2>"$stderr_file" || rc=$?

run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir")"
retry_count=$(grep -c "retry" "$stderr_file" || true)
if [[ "$reason" == "provider_failed" && "$rc" -eq 2 && "$retry_count" -eq 2 ]]; then
  _pass "retry (rate_limit): retried 2 times then failed as expected"
else
  _fail "retry (rate_limit): expected 2 retries, got $retry_count. reason=$reason, rc=$rc"
fi
cleanup_ws "$ws"
rm -f "$stderr_file"

# ────────────────────────────────
echo ""
echo "-- Provider retry: api-error (no retry)"
ws=$(setup_workspace)
rc=0
stderr_file="$(mktemp)"
RALPH_FAKE_SCENARIO=api-error bash "$ws/.ralph/bin/ralph" run --provider fake \
  2>"$stderr_file" || rc=$?
retry_count=$(grep -c "retry" "$stderr_file" || true)
if [[ "$retry_count" -eq 0 ]]; then
  _pass "retry (api-error): no retry as expected"
else
  _fail "retry (api-error): expected 0 retries, got $retry_count"
fi
cleanup_ws "$ws"
rm -f "$stderr_file"

# ────────────────────────────────
echo ""
echo "-- Provider retry: status.json"
ws=$(setup_workspace)
RALPH_FAKE_SCENARIO=rate_limit RALPH_LOOP_RETRY_SCHEDULE="5 5" bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null &
PID=$!
sleep 2 
status_file="$ws/.ralph/status.json"
retry_count_json=$(jq -r '.retry_count' "$status_file" 2>/dev/null || echo "null")
next_retry_at=$(jq -r '.next_retry_at' "$status_file" 2>/dev/null || echo "null")
kill $PID || true
wait $PID 2>/dev/null || true
if [[ "$retry_count_json" -eq 1 && "$next_retry_at" != "null" ]]; then
  _pass "retry (status.json): retry_count=1 and next_retry_at set during backoff"
else
  _fail "retry (status.json): retry_count=$retry_count_json, next_retry_at=$next_retry_at"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: timeout"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=slow RALPH_FAKE_SLEEP=30 bash "$ws/.ralph/bin/ralph" run --provider fake --round-timeout 2 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
round_dir="${run_dir}/rounds/round-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
meta_exit_ok=0
meta_dur_ok=0
round_exit="$(grep '"exit_code"' "$round_dir/meta.json" 2>/dev/null | sed 's/.*"exit_code":[[:space:]]*\([^,}]*\).*/\1/' | tr -d ' ')" || round_exit=""
round_dur="$(grep '"duration_ms"' "$round_dir/meta.json" 2>/dev/null | sed 's/.*"duration_ms":[[:space:]]*\([^,}]*\).*/\1/' | tr -d ' ')" || round_dur=""
[[ "$round_exit" != "0" && -n "$round_exit" ]] && meta_exit_ok=1
[[ "$round_dur" -gt 0 ]] 2>/dev/null && meta_dur_ok=1
if [[ "$reason" == "timeout" && "$rc" -eq 3 && "$meta_exit_ok" -eq 1 && "$meta_dur_ok" -eq 1 ]]; then
  _pass "timeout: exit_reason=timeout, rc=3, meta exit_code≠0, duration_ms>0"
else
  _fail "timeout: reason=$reason rc=$rc meta_exit_ok=$meta_exit_ok meta_dur_ok=$meta_dur_ok"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Timeout kills provider child process tree"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=slow_child RALPH_FAKE_SLEEP=30 \
  bash "$ws/.ralph/bin/ralph" run --provider fake --round-timeout 2 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
round_dir="${run_dir}/rounds/round-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
child_pid="$(cat "$round_dir/slow-child.pid" 2>/dev/null || true)"
child_dead=0
if [[ -n "$child_pid" ]] && ! kill -0 "$child_pid" 2>/dev/null; then
  child_dead=1
fi
if [[ "$child_dead" -ne 1 && -n "$child_pid" ]]; then
  kill "$child_pid" 2>/dev/null || true
fi
if [[ "$reason" == "timeout" && "$rc" -eq 3 && -n "$child_pid" && "$child_dead" -eq 1 ]]; then
  _pass "timeout process tree: provider child process is cleaned up"
else
  _fail "timeout process tree: reason=$reason rc=$rc child_pid=${child_pid:-missing} child_dead=$child_dead"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Per-task max_round: happy completes within limit (--max-round 1)"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake --max-round 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "done" && "$rc" -eq 0 ]]; then
  _pass "per-task max_round happy: exit_reason=done, rc=0 (no false trigger)"
else
  _fail "per-task max_round happy: expected done/rc=0, got $reason/$rc"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Per-task max_round: stagnation triggers blocked_by_human"
ws=$(setup_workspace)
printf '%s\n' "- [ ] DEV-1: Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=stagnation bash "$ws/.ralph/bin/ralph" run --provider fake --max-round 3 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "blocked_by_human" && "$rc" -eq 7 ]]; then
  _pass "per-task max_round: exit_reason=blocked_by_human, rc=7"
else
  _fail "per-task max_round: expected blocked_by_human/rc=7, got $reason/$rc"
fi
if grep -q '^\- \[ \] HUMAN-1:' "$ws/.ralph/TASKS.md"; then
  _pass "per-task max_round: HUMAN-1 inserted in TASKS.md"
else
  _fail "per-task max_round: HUMAN-1 not found in TASKS.md"
fi
if grep -q '^\- \[ \] DEV-1:' "$ws/.ralph/TASKS.md"; then
  _pass "per-task max_round: original task preserved after HUMAN-1"
else
  _fail "per-task max_round: original task missing from TASKS.md"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Per-task stall: stagnation triggers blocked_by_human"
ws=$(setup_workspace)
printf '%s\n' "- [ ] DEV-1: Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=stagnation bash "$ws/.ralph/bin/ralph" run --provider fake --stall-limit 3 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "blocked_by_human" && "$rc" -eq 7 ]]; then
  _pass "per-task stall: exit_reason=blocked_by_human, rc=7"
else
  _fail "per-task stall: expected blocked_by_human/rc=7, got $reason/$rc"
fi
# Verify HUMAN-1 template has 4 indented structured fields
_h_line="$(grep -n '^\- \[ \] HUMAN-1:' "$ws/.ralph/TASKS.md" | head -1)" || _h_line=""
if [[ -n "$_h_line" ]]; then
  _h_lineno="${_h_line%%:*}"
  _f1="$(sed -n "$(( _h_lineno + 1 ))p" "$ws/.ralph/TASKS.md")"
  _f2="$(sed -n "$(( _h_lineno + 2 ))p" "$ws/.ralph/TASKS.md")"
  _f3="$(sed -n "$(( _h_lineno + 3 ))p" "$ws/.ralph/TASKS.md")"
  _f4="$(sed -n "$(( _h_lineno + 4 ))p" "$ws/.ralph/TASKS.md")"
  if [[ "$_f1" =~ '触发：' && "$_f2" =~ '已耗时：' && "$_f3" =~ '建议：' && "$_f4" =~ '修复后：' ]]; then
    _pass "per-task stall: HUMAN-1 template has 4 structured fields"
  else
    _fail "per-task stall: HUMAN-1 template missing structured fields (got: $_f1 / $_f2 / $_f3 / $_f4)"
  fi
else
  _fail "per-task stall: HUMAN-1 not found in TASKS.md"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Per-task stall: task switch resets stall count (stall-limit=2)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=partial_progress bash "$ws/.ralph/bin/ralph" run \
  --provider fake --stall-limit 2 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "blocked_by_human" && "$rc" -eq 7 ]]; then
  _pass "partial_progress per-task stall: exit_reason=blocked_by_human, rc=7"
else
  _fail "partial_progress per-task stall: expected blocked_by_human/rc=7, got $reason/$rc"
fi
if command -v jq >/dev/null 2>&1; then
  sc1="$(jq '.stall_count // 0' "$run_dir/rounds/round-001/meta.json" 2>/dev/null)" || sc1=0
  sc2="$(jq '.stall_count // 0' "$run_dir/rounds/round-002/meta.json" 2>/dev/null)" || sc2=0
  sc3="$(jq '.stall_count // 0' "$run_dir/rounds/round-003/meta.json" 2>/dev/null)" || sc3=0
  if [[ "$sc1" -eq 0 && "$sc2" -eq 1 && "$sc3" -eq 2 ]]; then
    _pass "partial_progress per-task stall_count: round1=0 round2=1 round3=2"
  else
    _fail "partial_progress per-task stall_count: expected 0/1/2, got $sc1/$sc2/$sc3"
  fi
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Stagnation: full happy run has stall_count=0"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
if [[ "$(get_exit_reason "$run_dir")" == "done" ]]; then
  if command -v jq >/dev/null 2>&1; then
    sc1="$(jq '.stall_count // 0' "$run_dir/rounds/round-001/meta.json" 2>/dev/null)" || sc1=0
    if [[ "$sc1" -eq 0 ]]; then
      _pass "happy stall_count: exit_reason=done, stall_count=0"
    else
      _fail "happy stall_count: expected sc=0, got $sc1"
    fi
  else
    _pass "happy stall_count: exit_reason=done (no jq, skipping sc check)"
  fi
else
  _fail "happy stall_count: expected exit_reason=done"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Long provider oneshot emits heartbeat without -v"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
stderr_file="$(mktemp)"
RALPH_FAKE_SCENARIO=slow RALPH_FAKE_SLEEP=2 RALPH_PROGRESS_HEARTBEAT_SEC=1 \
  bash "$ws/.ralph/bin/ralph" run --provider fake --max-round 1 \
  >/dev/null 2>"$stderr_file" || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
heartbeat_ok=0
grep -Eq 'still running .*provider log .*tail -f .*/provider.stdout.log' "$stderr_file" 2>/dev/null && heartbeat_ok=1
if [[ "$rc" -eq 7 && "$reason" == "blocked_by_human" && "$heartbeat_ok" -eq 1 ]]; then
  _pass "provider heartbeat: default run prints still-running marker for long oneshot"
else
  _fail "provider heartbeat: expected rc=7 blocked_by_human + heartbeat, got rc=$rc reason=$reason heartbeat_ok=$heartbeat_ok"
fi
rm -f "$stderr_file"
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Dynamic TASKS.md growth updates run totals"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=append_task_once bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
result_total="$(jq '.tasks_total // 0' "$run_dir/result.json" 2>/dev/null)" || result_total=0
result_checked="$(jq '.tasks_checked_end // 0' "$run_dir/result.json" 2>/dev/null)" || result_checked=0
status_total="$(jq '.tasks_total // 0' "$ws/.ralph/status.json" 2>/dev/null)" || status_total=0
status_checked="$(jq '.tasks_checked // 0' "$ws/.ralph/status.json" 2>/dev/null)" || status_checked=0
round1_after_total="$(jq '.tasks_after.total // 0' "$run_dir/rounds/round-001/meta.json" 2>/dev/null)" || round1_after_total=0
round1_after_checked="$(jq '.tasks_after.checked // 0' "$run_dir/rounds/round-001/meta.json" 2>/dev/null)" || round1_after_checked=0
summary_ok=0
grep -q 'Tasks:         2 / 2' "$run_dir/exit-message.txt" 2>/dev/null && summary_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" \
  && "$result_total" -eq 2 && "$result_checked" -eq 2 \
  && "$status_total" -eq 2 && "$status_checked" -eq 2 \
  && "$round1_after_total" -eq 2 && "$round1_after_checked" -eq 1 \
  && "$summary_ok" -eq 1 ]]; then
  _pass "dynamic task totals: result/status/meta/summary show 2/2 after appended task"
else
  _fail "dynamic task totals: rc=$rc reason=$reason result=$result_checked/$result_total status=$status_checked/$status_total iter1_after=$round1_after_checked/$round1_after_total summary_ok=$summary_ok"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: locked"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
# 模拟持有 lock：写入当前进程 PID（让 ralph 认为持有者仍活着）
lockf="$ws/.ralph/lock"
echo "$$" > "$lockf"
rc=0
stderr_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
rm -f "$lockf"  # 释放
run_dir="$(latest_run_dir "$ws")"
if [[ "$rc" -eq 6 && -z "$run_dir" ]]; then
  _pass "locked: rc=6, no run dir"
else
  _fail "locked: expected rc=6 and no run dir, got rc=$rc run_dir=$run_dir"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: interrupted (post-lock)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
# 用 SIGTERM（macOS bash 上 INT 在等待子进程时被 deferred/ignored；TERM 立即触发 trap）。
# slow_child 验证 interrupted 和 timeout 一样会清理 provider 外部子进程。
RALPH_FAKE_SCENARIO=slow_child RALPH_FAKE_SLEEP=30 RALPH_PROGRESS_HEARTBEAT_SEC=0 \
  bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null &
bg_pid=$!
child_pid=""
for _ in 1 2 3 4 5; do
  child_pid="$(find "$ws/.ralph/runs" -name slow-child.pid -exec sh -c 'cat "$1"' _ {} \; 2>/dev/null | head -1 || true)"
  [[ -n "$child_pid" ]] && break
  sleep 1
done
kill -TERM "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true
run_dir="$(latest_run_dir "$ws" 2>/dev/null || true)"
reason="$(get_exit_reason "$run_dir" 2>/dev/null || true)"
child_dead=0
if [[ -n "$child_pid" ]] && ! kill -0 "$child_pid" 2>/dev/null; then
  child_dead=1
fi
if [[ "$child_dead" -ne 1 && -n "$child_pid" ]]; then
  kill "$child_pid" 2>/dev/null || true
fi
if [[ "$reason" == "interrupted" && -n "$child_pid" && "$child_dead" -eq 1 ]]; then
  _pass "interrupted (post-lock): exit_reason=interrupted and provider child process is cleaned up"
else
  _fail "interrupted (post-lock): reason=$reason run_dir=$run_dir child_pid=${child_pid:-missing} child_dead=$child_dead"
fi
cleanup_ws "$ws"

# ────────────────────────────────
# 启动校验失败（6 种）
# ────────────────────────────────

echo ""
echo "-- Startup check: missing PROMPT.md"
ws=$(setup_workspace --no-prompt)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "missing PROMPT.md: rc!=0, correct stderr prefix, no run dir"
else
  _fail "missing PROMPT.md: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: missing TASKS.md"
ws=$(setup_workspace --no-tasks)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "missing TASKS.md: rc!=0, correct stderr prefix, no run dir"
else
  _fail "missing TASKS.md: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: missing .env / RALPH_PROVIDER empty"
ws=$(setup_workspace --no-env)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(env -u RALPH_PROVIDER bash "$ws/.ralph/bin/ralph" run 2>&1 >/dev/null) || rc=$?

runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "missing .env: rc!=0, correct stderr prefix, no run dir"
else
  _fail "missing .env: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: not a git repository"
ws=$(setup_workspace --no-git)
rc=0
stderr_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "not a git repo: rc!=0, correct stderr prefix, no run dir"
else
  _fail "not a git repo: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: unknown provider (no adapter file)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(bash "$ws/.ralph/bin/ralph" run --provider bogus 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "unknown provider: rc!=0, correct stderr prefix, no run dir"
else
  _fail "unknown provider: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: provider CLI not found (RALPH_FAKE_CLI)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(RALPH_FAKE_CLI=__nonexistent_cli_xxx__ bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: missing dependency:"* && "$runs_count" -eq 0 ]]; then
  _pass "CLI not found: rc!=0, missing dependency prefix, no run dir"
else
  _fail "CLI not found: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: UUID force fail (RALPH_UUID_FORCE_FAIL=1, provider=claude)"
ws=$(setup_workspace --provider claude)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
# adapter-claude.sh 的 provider_check_deps 要求 claude 和 jq 在 PATH
# 把 mock-claude 注入 PATH 满足 claude dep check，再用 RALPH_UUID_FORCE_FAIL=1 触发 UUID startup 失败
uuid_claude_bin="$(mktemp -d)"
ln -sf "$REPO_ROOT/tests/fixtures/mock-claude" "$uuid_claude_bin/claude"
rc=0
stderr_out=$(env PATH="$uuid_claude_bin:$PATH" RALPH_UUID_FORCE_FAIL=1 bash "$ws/.ralph/bin/ralph" run --provider claude 2>&1 >/dev/null) || rc=$?
rm -rf "$uuid_claude_bin"
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "UUID force fail: rc!=0, correct stderr prefix, no run dir"
else
  _fail "UUID force fail: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
# 依赖校验框架（T2.0）
# ────────────────────────────────

# 构造排除指定命令的 tmpbin（PATH 隔离辅助）；调用方负责 rm -rf
_build_path_without() {
  local exclude_cmd="$1"
  local tmpbin d f bname
  local -a dirs
  tmpbin="$(mktemp -d)"
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
      [[ -x "$f" && ! -d "$f" ]] || continue
      bname="$(basename "$f")"
      [[ "$bname" == "$exclude_cmd" ]] && continue
      [[ -e "$tmpbin/$bname" ]] && continue
      ln -sf "$f" "$tmpbin/$bname"
    done
  done
  echo "$tmpbin"
}

echo ""
echo "-- Dep check: happy path (git + fake CLI present)"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
stderr_out=$(RALPH_FAKE_SCENARIO=happy RALPH_PROVIDER=fake bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
if [[ "$rc" -eq 0 && "$stderr_out" != *"missing dependency"* ]]; then
  _pass "dep happy: exit 0, no missing dependency in stderr"
else
  _fail "dep happy: rc=$rc stderr=$stderr_out"
fi
cleanup_ws "$ws"

echo ""
echo "-- Dep check: git missing from PATH (PATH isolation)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
tmpbin=$(_build_path_without git)
rc=0
stderr_out=$(env PATH="$tmpbin" bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
rm -rf "$tmpbin"
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: missing dependency: git"* && "$runs_count" -eq 0 ]]; then
  _pass "dep git missing: rc!=0, stderr has 'missing dependency: git', no run dir"
else
  _fail "dep git missing: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

echo ""
echo "-- Dep check: multiple deps missing (git + fake CLI) — non-fail-fast"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
tmpbin=$(_build_path_without git)
rc=0
stderr_out=$(env PATH="$tmpbin" RALPH_FAKE_CLI=__nonexistent_yyy__ bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
rm -rf "$tmpbin"
if [[ "$rc" -ne 0 \
  && "$stderr_out" == *"ralph: missing dependency: git"* \
  && "$stderr_out" == *"ralph: missing dependency: __nonexistent_yyy__"* ]]; then
  _pass "dep multi-missing: both git and fake CLI reported in one pass"
else
  _fail "dep multi-missing: rc=$rc stderr=$stderr_out"
fi
cleanup_ws "$ws"

# setup_claude_workspace — 单一来源（T2.2 建立，T2.5 扩展场景）
# 设置全局 SETUP_CLAUDE_WS / SETUP_CLAUDE_BIN / SETUP_CLAUDE_HOME（不用 $() 子 shell）
# 调用方：env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run
SETUP_CLAUDE_WS=""
SETUP_CLAUDE_BIN=""
SETUP_CLAUDE_HOME=""
setup_claude_workspace() {
  SETUP_CLAUDE_WS="$(setup_workspace --provider claude)"

  # HOME 隔离（强制要求，见 docs/architecture/testing.md §测试隔离规则）
  local home_parent
  home_parent="$(mktemp -d)"
  SETUP_CLAUDE_HOME="$home_parent/home"
  mkdir -p "$SETUP_CLAUDE_HOME/.claude/projects"

  # mock-claude 软链到 workspace 内 tests-bin/（仅注入 ralph run 子进程 PATH）
  SETUP_CLAUDE_BIN="$SETUP_CLAUDE_WS/tests-bin"
  mkdir -p "$SETUP_CLAUDE_BIN"
  ln -sf "$REPO_ROOT/tests/fixtures/mock-claude" "$SETUP_CLAUDE_BIN/claude"
}

cleanup_claude_ws() {
  [[ -n "${SETUP_CLAUDE_HOME:-}" ]] && rm -rf "$(dirname "$SETUP_CLAUDE_HOME")"
  [[ -n "${SETUP_CLAUDE_WS:-}" ]] && cleanup_ws "$SETUP_CLAUDE_WS"
  SETUP_CLAUDE_WS=""
  SETUP_CLAUDE_BIN=""
  SETUP_CLAUDE_HOME=""
}

# ────────────────────────────────
# Claude adapter 骨架（T2.1）
# ────────────────────────────────

echo ""
echo "-- Claude adapter: happy path (mock-claude, HOME isolated)"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
round_dir="${run_dir}/rounds/round-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
stdout_ok=0
# stream-json 模式：provider.stdout.log 含 result 事件，is_error=false
[[ -f "$round_dir/provider.stdout.log" ]] && \
  grep -E '^\{' "$round_dir/provider.stdout.log" 2>/dev/null \
  | jq -r 'select(.type == "result") | .is_error' 2>/dev/null \
  | grep -q '^false$' && stdout_ok=1
session_ok=0
grep -qE '"session_id":[[:space:]]*"[0-9a-f-]{36}"' "$round_dir/meta.json" 2>/dev/null && session_ok=1
history_ok=0
# session.history.log 取代 chat.log + tools.log，含 user / assistant / thinking / tool-use / tool-result
[[ -f "$round_dir/session.history.log" ]] && \
  grep -q '\[user\]' "$round_dir/session.history.log" && \
  grep -q '\[assistant\]' "$round_dir/session.history.log" && \
  grep -q '\[thinking\]' "$round_dir/session.history.log" && \
  grep -q '\[tool-use name=' "$round_dir/session.history.log" && \
  grep -q 'tool input truncated; see session.claude.jsonl' "$round_dir/session.history.log" && \
  grep -q '"content":"xxxxxxxx' "$round_dir/session.claude.jsonl" && \
  grep -q '\[tool-result name=' "$round_dir/session.history.log" && history_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$stdout_ok" -eq 1 && "$session_ok" -eq 1 \
   && "$history_ok" -eq 1 ]]; then
  _pass "claude happy: exit 0, done, stream-json result event, session_id UUID, session.history.log derived"
else
  _fail "claude happy: rc=$rc reason=$reason stdout_ok=$stdout_ok session_ok=$session_ok history_ok=$history_ok"
fi
cleanup_claude_ws

# ────────────────────────────────
# ralph run -v live tail regression（M1）
# ────────────────────────────────

echo ""
echo "-- ralph run -v live tail: happy stream emits filter markers"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
stderr_file="$(mktemp)"
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_MOCK_CLAUDE_POST_STREAM_SLEEP=2 \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude -v \
  >/dev/null 2>"$stderr_file" || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
marker_ok=0
grep -Eq '⚙ session|💬|✓ result' "$stderr_file" 2>/dev/null && marker_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$marker_ok" -eq 1 ]]; then
  _pass "run -v happy: output contains stream-json filter marker"
else
  _fail "run -v happy: expected rc=0 done + marker, got rc=$rc reason=$reason marker_ok=$marker_ok"
fi
rm -f "$stderr_file"
cleanup_claude_ws

echo ""
echo "-- ralph run -v live tail: is_error_auth emits error marker"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
stderr_file="$(mktemp)"
RALPH_MOCK_CLAUDE_SCENARIO=is_error_auth RALPH_MOCK_CLAUDE_POST_STREAM_SLEEP=2 \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude -v \
  >/dev/null 2>"$stderr_file" || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
error_marker_ok=0
grep -Eq '❌ error|error:' "$stderr_file" 2>/dev/null && error_marker_ok=1
if [[ "$rc" -eq 2 && "$reason" == "provider_failed" && "$error_marker_ok" -eq 1 ]]; then
  _pass "run -v auth error: output contains error filter marker"
else
  _fail "run -v auth error: expected rc=2 provider_failed + error marker, got rc=$rc reason=$reason marker_ok=$error_marker_ok"
fi
rm -f "$stderr_file"
cleanup_claude_ws

# ────────────────────────────────
# Session 采集（T2.2）
# ────────────────────────────────

echo ""
echo "-- Claude session: collect happy (exact match by session_id)"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
round_dir="${run_dir}/rounds/round-001"
jsonl_ok=0; capture_ok=0; history_ok=0
[[ -f "$round_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
# session.history.log 含 thinking + tool_use 摘要 + tool_result；完整 input 保留在 session.claude.jsonl
[[ -f "$round_dir/session.history.log" ]] && \
  grep -q '\[user\]' "$round_dir/session.history.log" \
  && grep -q '\[thinking\]' "$round_dir/session.history.log" \
  && grep -q '\[tool-use name=Bash\]' "$round_dir/session.history.log" \
  && grep -q 'tool input truncated; see session.claude.jsonl' "$round_dir/session.history.log" \
  && grep -q '"content":"xxxxxxxx' "$round_dir/session.claude.jsonl" \
  && grep -q '\[tool-result name=Bash\]' "$round_dir/session.history.log" && history_ok=1
if [[ "$jsonl_ok" -eq 1 && "$capture_ok" -eq 1 && "$history_ok" -eq 1 ]]; then
  _pass "session collect happy: jsonl ok, capture_status=ok, session.history.log derived"
else
  _fail "session collect happy: jsonl_ok=$jsonl_ok capture_ok=$capture_ok history_ok=$history_ok"
fi
cleanup_claude_ws

echo ""
echo "-- Claude session: CLAUDE_CONFIG_DIR aware capture (REQ-022 / SC-022-3)"
# 验证 adapter 在 CLAUDE_CONFIG_DIR 非空时从该路径采集 session，不读 \$HOME/.claude
setup_claude_workspace
custom_cfg="$(dirname "$SETUP_CLAUDE_HOME")/custom-claude-cfg"
mkdir -p "$custom_cfg/projects"
# 在 workspace .env 加 RALPH_PROVIDER_CONFIG_DIR（adapter 翻译为 CLAUDE_CONFIG_DIR）
printf 'RALPH_PROVIDER_CONFIG_DIR=%s\n' "$custom_cfg" >> "$SETUP_CLAUDE_WS/.ralph/.env"
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
round_dir="${run_dir}/rounds/round-001"
jsonl_ok=0; capture_ok=0; src_ok=0; home_clean=1
[[ -f "$round_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
# session_source_path 应在 custom_cfg/projects/ 下
src_path="$(jq -r '.session_source_path // ""' "$round_dir/meta.json" 2>/dev/null)"
[[ "$src_path" == "$custom_cfg/projects/"* ]] && src_ok=1
# 反向断言：$HOME/.claude/projects/ 下不应有任何 jsonl（mock-claude 必须写到 CLAUDE_CONFIG_DIR）
if find "$SETUP_CLAUDE_HOME/.claude/projects" -name "*.jsonl" -type f 2>/dev/null | grep -q .; then
  home_clean=0
fi
if [[ "$jsonl_ok" -eq 1 && "$capture_ok" -eq 1 && "$src_ok" -eq 1 && "$home_clean" -eq 1 ]]; then
  _pass "session CLAUDE_CONFIG_DIR aware: jsonl ok, capture_status=ok, source from custom cfg, HOME/.claude clean"
else
  _fail "session CLAUDE_CONFIG_DIR aware: jsonl_ok=$jsonl_ok capture_ok=$capture_ok src_ok=$src_ok home_clean=$home_clean src=$src_path"
fi
cleanup_claude_ws

echo ""
echo "-- Claude session: mtime fallback (UUID mismatch → fallback by mtime)"
setup_claude_workspace
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=mtime_fallback \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude --max-round 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
round_dir="${run_dir}/rounds/round-001"
jsonl_ok=0; warn_ok=0
[[ -f "$round_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"fallback by mtime"' "$round_dir/meta.json" 2>/dev/null && warn_ok=1
if [[ "$jsonl_ok" -eq 1 && "$warn_ok" -eq 1 ]]; then
  _pass "session mtime fallback: session.claude.jsonl exists, capture_warning=fallback by mtime"
else
  _fail "session mtime fallback: jsonl_ok=$jsonl_ok warn_ok=$warn_ok"
fi
cleanup_claude_ws

echo ""
echo "-- Claude session: missing session file → capture_status=warning"
setup_claude_workspace
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=missing_session \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude --max-round 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
round_dir="${run_dir}/rounds/round-001"
no_jsonl=0; warn_ok=0; empty_history_ok=0
[[ ! -f "$round_dir/session.claude.jsonl" ]] && no_jsonl=1
grep -q '"capture_status": "warning"' "$round_dir/meta.json" 2>/dev/null && warn_ok=1
# 派生视图文件存在但内容为空（warning 时不派生）
[[ -f "$round_dir/session.history.log" && ! -s "$round_dir/session.history.log" ]] && empty_history_ok=1
if [[ "$no_jsonl" -eq 1 && "$warn_ok" -eq 1 && "$empty_history_ok" -eq 1 ]]; then
  _pass "session missing: no session.claude.jsonl, capture_status=warning, empty session.history.log"
else
  _fail "session missing: no_jsonl=$no_jsonl warn_ok=$warn_ok empty_history_ok=$empty_history_ok"
fi
cleanup_claude_ws

# ────────────────────────────────
# 错误诊断矩阵（T2.3）
# 每个用例：mock-claude 输出 is_error:true + 关键词 → provider_diagnose 分类 → result.json.last_error.type
# ────────────────────────────────

_run_diagnose_case() {
  local scenario="$1" expected_type="$2" label="$3"
  setup_claude_workspace
  printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
  git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "tasks" 2>/dev/null || true
  local rc=0
  RALPH_MOCK_CLAUDE_SCENARIO="$scenario" \
    env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
    bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
  local run_dir error_type
  run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
  error_type="$(get_last_error_type "$run_dir")"
  if [[ "$rc" -eq 2 && "$error_type" == "$expected_type" ]]; then
    _pass "$label: rc=2, last_error.type=$expected_type"
  else
    _fail "$label: rc=$rc error_type=$error_type (expected rc=2 type=$expected_type)"
  fi
  cleanup_claude_ws
}

echo ""
echo "-- Claude diagnose: auth (unauthor keyword)"
_run_diagnose_case is_error_auth auth "diagnose auth"

echo ""
echo "-- Claude diagnose: rate_limit (429 keyword)"
_run_diagnose_case is_error_rate rate_limit "diagnose rate_limit"

echo ""
echo "-- Claude diagnose: quota (credits exhausted keyword)"
_run_diagnose_case is_error_quota quota "diagnose quota"

echo ""
echo "-- Claude diagnose: api (500 keyword)"
_run_diagnose_case is_error_api api "diagnose api"

echo ""
echo "-- Claude diagnose: concurrency (tool_use_concurrency keyword)"
_run_diagnose_case is_error_concurrency concurrency "diagnose concurrency"

echo ""
echo "-- Claude diagnose: unknown (CLI crash, no stdout)"
_run_diagnose_case crash unknown "diagnose unknown (crash)"

# ────────────────────────────────
# SC-014-1: --effort flag 接入（T6.2）
# ────────────────────────────────

get_received_effort() {
  local round_dir="$1"
  # stream-json 模式：从 provider.stdout.log 末尾的 result 事件取 _received_effort
  grep -E '^\{' "$round_dir/provider.stdout.log" 2>/dev/null \
    | jq -r 'select(.type == "result") | ._received_effort // ""' 2>/dev/null \
    | tail -1
}

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=low → --effort low"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_PROVIDER_EFFORT=low \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; round_dir="${run_dir}/rounds/round-001"
rcv="$(get_received_effort "$round_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "low" ]]; then
  _pass "SC-014-1 effort=low: --effort low received by mock-claude"
else
  _fail "SC-014-1 effort=low: expected low, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=medium → --effort medium"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_PROVIDER_EFFORT=medium \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; round_dir="${run_dir}/rounds/round-001"
rcv="$(get_received_effort "$round_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "medium" ]]; then
  _pass "SC-014-1 effort=medium: --effort medium received by mock-claude"
else
  _fail "SC-014-1 effort=medium: expected medium, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=high → --effort high"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_PROVIDER_EFFORT=high \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; round_dir="${run_dir}/rounds/round-001"
rcv="$(get_received_effort "$round_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "high" ]]; then
  _pass "SC-014-1 effort=high: --effort high received by mock-claude"
else
  _fail "SC-014-1 effort=high: expected high, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=none → --effort not passed"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_PROVIDER_EFFORT=none \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; round_dir="${run_dir}/rounds/round-001"
rcv="$(get_received_effort "$round_dir")"
if [[ "$rc" -eq 0 && -z "$rcv" ]]; then
  _pass "SC-014-1 effort=none: --effort not passed to mock-claude"
else
  _fail "SC-014-1 effort=none: expected empty, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

# ────────────────────────────────
# 依赖校验补缺（T2.5）
# ────────────────────────────────

echo ""
echo "-- Dep check: jq missing from PATH (claude adapter, PATH isolation)"
setup_claude_workspace
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "init" 2>/dev/null || true
tmpbin_nojq=$(_build_path_without jq)
ln -sf "$REPO_ROOT/tests/fixtures/mock-claude" "$tmpbin_nojq/claude"
rc=0
stderr_out=$(env PATH="$tmpbin_nojq" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>&1 >/dev/null) || rc=$?
rm -rf "$tmpbin_nojq"
runs_count=$(count_runs "$SETUP_CLAUDE_WS")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: missing dependency: jq"* && "$runs_count" -eq 0 ]]; then
  _pass "dep jq missing (claude): rc!=0, stderr has 'missing dependency: jq', no run dir"
else
  _fail "dep jq missing (claude): rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_claude_ws

echo ""
echo "-- Dep check: claude + jq both missing (claude adapter, non-fail-fast)"
setup_claude_workspace
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "init" 2>/dev/null || true
tmpbin_none=$(_build_path_without jq)
rm -f "$tmpbin_none/claude"   # ensure claude also absent from PATH
rc=0
stderr_out=$(env PATH="$tmpbin_none" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>&1 >/dev/null) || rc=$?
rm -rf "$tmpbin_none"
runs_count=$(count_runs "$SETUP_CLAUDE_WS")
if [[ "$rc" -ne 0 \
  && "$stderr_out" == *"ralph: missing dependency: claude"* \
  && "$stderr_out" == *"ralph: missing dependency: jq"* \
  && "$runs_count" -eq 0 ]]; then
  _pass "claude+jq both missing: both deps reported in one pass, no run dir"
else
  _fail "claude+jq both missing: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_claude_ws

# ────────────────────────────────
# --version / --help / status（T2.6）
# ────────────────────────────────

echo ""
echo "-- ralph --version"
rc=0
version_out=$(bash "$REPO_ROOT/.ralph/bin/ralph" --version 2>/dev/null) || rc=$?
if [[ "$rc" -eq 0 && "$version_out" == *"0.1.1"* ]]; then
  _pass "ralph --version: exit 0, contains 0.1.1"
else
  _fail "ralph --version: rc=$rc out=$version_out"
fi

echo ""
echo "-- ralph --help"
rc=0
bash "$REPO_ROOT/.ralph/bin/ralph" --help >/dev/null 2>/dev/null || rc=$?
if [[ "$rc" -eq 0 ]]; then
  _pass "ralph --help: exit 0"
else
  _fail "ralph --help: rc=$rc"
fi

echo ""
echo "-- ralph run --help"
rc=0
run_help_out=$(bash "$REPO_ROOT/.ralph/bin/ralph" run --help 2>/dev/null) || rc=$?
if [[ "$rc" -eq 0 && "$run_help_out" == *"--provider"* && "$run_help_out" == *"--max-round"* ]]; then
  _pass "ralph run --help: exit 0, contains flag names"
else
  _fail "ralph run --help: rc=$rc out=$run_help_out"
fi

echo ""
echo "-- ralph watch --help"
rc=0
watch_help_out=$(bash "$REPO_ROOT/.ralph/bin/ralph" watch --help 2>/dev/null) || rc=$?
if [[ "$rc" -eq 0 && "$watch_help_out" == *"sticky"* && "$watch_help_out" != *"-v"* \
  && "$watch_help_out" != *"--verbose"* ]]; then
  _pass "ralph watch --help: exit 0, documents sticky mode, no -v flag"
else
  _fail "ralph watch --help: rc=$rc out=$watch_help_out"
fi

# ────────────────────────────────
# SC-023: status 集成测试（QA-1）
# ────────────────────────────────

echo ""
echo "-- SC-023-1: ralph status plain text — all 15 field labels + checked progress"
ws=$(setup_workspace)
cat > "$ws/.ralph/status.json" <<'SJEOF'
{
  "run_id": "20260501-120000-abc1234",
  "run_dir": ".ralph/runs/20260501-120000-abc1234",
  "workspace": "/tmp/test-ws",
  "provider": "fake",
  "model": "test-model",
  "effort": "high",
  "started_at": "2026-05-01T12:00:00Z",
  "updated_at": "2026-05-01T12:01:00Z",
  "round": 3,
  "iteration_name": "I1",
  "state": "running",
  "tasks_total": 5,
  "tasks_checked": 2,
  "exit_reason": null,
  "last_error": null
}
SJEOF
rc=0
status_out=$(bash "$ws/.ralph/bin/ralph" status 2>/dev/null) || rc=$?
fields_ok=1
for f in run_id: run_dir: workspace: provider: model: effort: started_at: updated_at: round: iteration_name: state: tasks: exit_reason: last_error:; do
  if [[ "$status_out" != *"$f"* ]]; then
    fields_ok=0
    break
  fi
done
checked_ok=0
[[ "$status_out" == *"2 / 5 checked"* ]] && checked_ok=1
local_time_ok=0
echo "$status_out" | grep -Eq 'started_at:[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}' \
  && echo "$status_out" | grep -Eq 'updated_at:[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}' \
  && local_time_ok=1
if [[ "$rc" -eq 0 && "$fields_ok" -eq 1 && "$checked_ok" -eq 1 && "$local_time_ok" -eq 1 ]]; then
  _pass "SC-023-1/SC-026-1: labels + checked progress + local time format present, exit 0"
else
  _fail "SC-023-1/SC-026-1: rc=$rc fields_ok=$fields_ok checked_ok=$checked_ok local_time_ok=$local_time_ok"
fi
cleanup_ws "$ws"

echo ""
echo "-- SC-023-2: ralph status --json — byte-for-byte match with status.json"
ws=$(setup_workspace)
cat > "$ws/.ralph/status.json" <<'SJEOF'
{
  "run_id": "20260501-120000-abc1234",
  "run_dir": ".ralph/runs/20260501-120000-abc1234",
  "workspace": "/tmp/test-ws",
  "provider": "fake",
  "model": "test-model",
  "effort": "high",
  "started_at": "2026-05-01T12:00:00Z",
  "updated_at": "2026-05-01T12:01:00Z",
  "round": 3,
  "iteration_name": "I1",
  "state": "running",
  "tasks_total": 5,
  "tasks_checked": 2,
  "exit_reason": null,
  "last_error": null
}
SJEOF
rc=0
tmpout="$(mktemp)"
bash "$ws/.ralph/bin/ralph" status --json > "$tmpout" 2>/dev/null || rc=$?
diff_ok=0
diff "$ws/.ralph/status.json" "$tmpout" >/dev/null 2>&1 && diff_ok=1
rm -f "$tmpout"
if [[ "$rc" -eq 0 && "$diff_ok" -eq 1 ]]; then
  _pass "SC-023-2: --json output matches status.json byte-for-byte"
else
  _fail "SC-023-2: rc=$rc diff_ok=$diff_ok"
fi
cleanup_ws "$ws"

echo ""
echo "-- SC-023-3: ralph status — status.json missing: exit 0 + hint + no side effects"
ws=$(setup_workspace)
rm -f "$ws/.ralph/status.json"
ralph_files_before="$(find "$ws/.ralph" -type f | sort)"
rc=0
status_out=$(bash "$ws/.ralph/bin/ralph" status 2>/dev/null) || rc=$?
ralph_files_after="$(find "$ws/.ralph" -type f | sort)"
no_side_effects=0
[[ "$ralph_files_before" == "$ralph_files_after" ]] && no_side_effects=1
hint_ok=0
echo "$status_out" | grep -q "无运行中/已结束的 run" && hint_ok=1
if [[ "$rc" -eq 0 && "$hint_ok" -eq 1 && "$no_side_effects" -eq 1 ]]; then
  _pass "SC-023-3: no status.json → exit 0, hint message, no side effects"
else
  _fail "SC-023-3: rc=$rc hint_ok=$hint_ok no_side=$no_side_effects"
fi
cleanup_ws "$ws"

# ────────────────────────────────
# SC-024: watch 集成测试（QA-2）
# ────────────────────────────────

echo ""
echo "-- SC-024-2: ralph watch -v → rejected with exit 2"
rc=0
bash "$REPO_ROOT/.ralph/bin/ralph" watch -v 2>/dev/null || rc=$?
if [[ "$rc" -eq 2 ]]; then
  _pass "SC-024-2: ralph watch -v → exit 2 (flag removed)"
else
  _fail "SC-024-2: expected exit 2, got rc=$rc"
fi

echo ""
echo "-- SC-024-4: watch non-TTY fallback → one-line bar + exit 0"
ws=$(setup_workspace)
cat > "$ws/.ralph/status.json" <<'SJEOF'
{
  "run_id": "20260501-120000-abc1234",
  "run_dir": ".ralph/runs/20260501-120000-abc1234",
  "workspace": "/tmp/test-ws",
  "provider": "fake",
  "model": "test-model",
  "effort": "high",
  "started_at": "2026-05-01T12:00:00Z",
  "updated_at": "2026-05-01T12:01:00Z",
  "round": 3,
  "iteration_name": "I1",
  "state": "running",
  "tasks_total": 5,
  "tasks_checked": 2,
  "exit_reason": null,
  "last_error": null
}
SJEOF
rc=0
watch_out=$(bash "$ws/.ralph/bin/ralph" watch 2>/dev/null | cat) || rc=$?
one_line=0
line_count="$(printf '%s\n' "$watch_out" | wc -l | tr -d ' ')"
[[ "$line_count" -eq 1 ]] && one_line=1
has_bar=0
if printf '%s\n' "$watch_out" | grep -q "run: 20260501-120..." \
  && printf '%s\n' "$watch_out" | grep -q "iter_name: I1" \
  && printf '%s\n' "$watch_out" | grep -q "round 3" \
  && printf '%s\n' "$watch_out" | grep -q "2/5 tasks" \
  && printf '%s\n' "$watch_out" | grep -q "state: running" \
  && printf '%s\n' "$watch_out" | grep -q "provider: fake"; then
  has_bar=1
fi
detail_absent=0
if ! printf '%s\n' "$watch_out" | grep -q "workspace:" \
  && ! printf '%s\n' "$watch_out" | grep -q "run_dir:" \
  && ! printf '%s\n' "$watch_out" | grep -q "started_at:" \
  && ! printf '%s\n' "$watch_out" | grep -q "last_error:"; then
  detail_absent=1
fi
if [[ "$rc" -eq 0 && "$one_line" -eq 1 && "$has_bar" -eq 1 && "$detail_absent" -eq 1 ]]; then
  _pass "SC-024-4: watch non-TTY → one-line bar without status detail fields, exit 0"
else
  _fail "SC-024-4: rc=$rc one_line=$one_line has_bar=$has_bar detail_absent=$detail_absent output=$watch_out"
fi
cleanup_ws "$ws"

# ── HUMAN-N 阻塞机制（v0.1.1）──────────────────────────────────────────────────

echo ""
echo "-- blocked_by_human: HUMAN-N is first unchecked → exit 7, no provider call"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
- [ ] HUMAN-1: 确认默认值
- [ ] DEV-1: 实现功能
TASKS_EOF
rc=0
bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null 1>/dev/null || rc=$?
run_dir=$(latest_run_dir "$ws")
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "blocked_by_human" && "$rc" -eq 7 ]]; then
  _pass "blocked_by_human: exit_reason=blocked_by_human, rc=7"
else
  _fail "blocked_by_human: expected blocked_by_human/rc=7, got $reason/$rc"
fi
# 验证未调用 provider（无 round-001 目录或 round 目录中无 log）
if [[ ! -d "$run_dir/rounds/round-001" ]]; then
  _pass "blocked_by_human: no round directory created (provider not called)"
else
  _fail "blocked_by_human: round directory created (should not call provider)"
fi

echo ""
echo "-- blocked_by_human cleared: HUMAN-N marked [x], normal flow resumes"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
- [x] HUMAN-1: 已答完
- [ ] Task A
TASKS_EOF
rc=0
bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null 1>/dev/null || rc=$?
run_dir=$(latest_run_dir "$ws")
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "done" && "$rc" -eq 0 ]]; then
  _pass "blocked_by_human cleared: HUMAN-1 [x] → exit_reason=done, rc=0"
else
  _fail "blocked_by_human cleared: expected done/rc=0, got $reason/$rc"
fi

echo ""
echo "-- iteration_name parsed from TASKS.md top-level declaration"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
> 当前迭代: I1
> 主题: 测试 iteration name 解析

- [ ] Task A
- [ ] Task B
TASKS_EOF
rc=0
bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null 1>/dev/null || rc=$?
run_dir=$(latest_run_dir "$ws")
iter_name=""
if command -v jq >/dev/null 2>&1 && [[ -f "$run_dir/result.json" ]]; then
  iter_name="$(jq -r '.iteration_name // ""' "$run_dir/result.json")"
else
  iter_name="$(grep '"iteration_name"' "$run_dir/result.json" 2>/dev/null \
    | sed 's/.*"iteration_name":[[:space:]]*"\([^"]*\)".*/\1/' | head -1)"
fi
if [[ "$iter_name" == "I1" ]]; then
  _pass "iteration_name parsed: I1"
else
  _fail "iteration_name expected I1, got '$iter_name'"
fi

echo ""
echo "-- task prefix uppercase enforcement: lowercase prefix → startup_failed exit 1"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
- [ ] dev-1: 小写前缀应该被拒绝
TASKS_EOF
rc=0
err_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 1>/dev/null) || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$err_out" | grep -q "UPPERCASE"; then
  _pass "lowercase prefix: exit 1 + stderr contains UPPERCASE"
else
  _fail "lowercase prefix: expected exit 1 + UPPERCASE error, got rc=$rc / stderr=$err_out"
fi

echo ""
echo "-- task prefix uppercase enforcement: mixed case prefix → startup_failed exit 1"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
- [ ] Dev-1: 大小写混合也应该被拒绝
TASKS_EOF
rc=0
err_out=$(bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 1>/dev/null) || rc=$?
if [[ "$rc" -eq 1 ]] && echo "$err_out" | grep -q "UPPERCASE"; then
  _pass "mixed case prefix: exit 1 + stderr contains UPPERCASE"
else
  _fail "mixed case prefix: expected exit 1 + UPPERCASE error, got rc=$rc / stderr=$err_out"
fi

echo ""
echo "-- task prefix uppercase enforcement: no prefix (legacy) → still works"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
- [ ] Task A
- [ ] Task B
TASKS_EOF
rc=0
bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null 1>/dev/null || rc=$?
run_dir=$(latest_run_dir "$ws")
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "done" && "$rc" -eq 0 ]]; then
  _pass "no-prefix legacy tasks: exit_reason=done (validation skipped)"
else
  _fail "no-prefix legacy tasks: expected done/0, got $reason/$rc"
fi

echo ""
echo "-- load_env: ~/foo tilde expansion → \$HOME/foo"
ws=$(setup_workspace)
cat > "$ws/.ralph/.env" <<TASKS_EOF
RALPH_PROVIDER=fake
RALPH_PROVIDER_CONFIG_DIR=~/test-cfg
TASKS_EOF
out=$(bash -c "source '$REPO_ROOT/.ralph/lib/common.sh'; load_env '$ws/.ralph/.env'; echo \"PCD=\$RALPH_PROVIDER_CONFIG_DIR\"")
expected="PCD=$HOME/test-cfg"
if [[ "$out" == *"$expected"* ]]; then
  _pass "load_env tilde expansion: ~/test-cfg → \$HOME/test-cfg"
else
  _fail "load_env tilde expansion: expected '$expected', got '$out'"
fi

echo ""
echo "-- adapter-claude.sh translates RALPH_PROVIDER_CONFIG_DIR → CLAUDE_CONFIG_DIR"
out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
  export RALPH_PROVIDER_CONFIG_DIR=/tmp/ralph-test-claude-cfg
  source '$REPO_ROOT/.ralph/lib/common.sh'
  source '$REPO_ROOT/.ralph/lib/adapter-claude.sh'
  echo \"CCD=\${CLAUDE_CONFIG_DIR:-UNSET}\"
")
if [[ "$out" == *"CCD=/tmp/ralph-test-claude-cfg"* ]]; then
  _pass "adapter-claude: CLAUDE_CONFIG_DIR translated from RALPH_PROVIDER_CONFIG_DIR"
else
  _fail "adapter-claude translation: expected CCD=/tmp/ralph-test-claude-cfg, got '$out'"
fi

echo ""
echo "-- adapter-claude.sh robustness: empty RALPH_PROVIDER_CONFIG_DIR → CLAUDE_CONFIG_DIR NOT exported"
out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
  source '$REPO_ROOT/.ralph/lib/common.sh'
  source '$REPO_ROOT/.ralph/lib/adapter-claude.sh'
  if [[ -z \${CLAUDE_CONFIG_DIR+x} ]]; then
    echo 'UNSET'
  else
    echo \"SET=\$CLAUDE_CONFIG_DIR\"
  fi
")
if [[ "$out" == *"UNSET"* ]]; then
  _pass "adapter-claude empty case: CLAUDE_CONFIG_DIR not exported (robust)"
else
  _fail "adapter-claude empty case: expected UNSET, got '$out'"
fi

echo ""
echo "-- exit-message.txt generated with iteration + exit_reason context"
ws=$(setup_workspace)
cat > "$ws/.ralph/TASKS.md" <<TASKS_EOF
> 当前迭代: I1

- [ ] HUMAN-1: 测试
- [ ] DEV-1: foo
TASKS_EOF
rc=0
bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null 1>/dev/null || rc=$?
run_dir=$(latest_run_dir "$ws")
if [[ -f "$run_dir/exit-message.txt" ]] \
   && grep -q "blocked_by_human" "$run_dir/exit-message.txt" \
   && grep -q "I1" "$run_dir/exit-message.txt"; then
  _pass "exit-message.txt: contains blocked_by_human + I1"
else
  _fail "exit-message.txt: missing or wrong content (expected blocked_by_human + I1)"
fi

# ────────────────────────────────
# Codex adapter（I2 QA-1）
# ────────────────────────────────

# setup_codex_workspace — Codex adapter 测试 workspace + HOME 隔离 + mock-codex 注入
SETUP_CODEX_WS=""
SETUP_CODEX_BIN=""
SETUP_CODEX_HOME=""
setup_codex_workspace() {
  SETUP_CODEX_WS="$(setup_workspace --provider codex)"

  # HOME 隔离（避免写真实 ~/.codex）
  local home_parent
  home_parent="$(mktemp -d)"
  SETUP_CODEX_HOME="$home_parent/home"
  mkdir -p "$SETUP_CODEX_HOME"

  # mock-codex 软链到 workspace 内 tests-bin/
  SETUP_CODEX_BIN="$SETUP_CODEX_WS/tests-bin"
  mkdir -p "$SETUP_CODEX_BIN"
  ln -sf "$REPO_ROOT/tests/fixtures/mock-codex" "$SETUP_CODEX_BIN/codex"
}

cleanup_codex_ws() {
  [[ -n "${SETUP_CODEX_HOME:-}" ]] && rm -rf "$(dirname "$SETUP_CODEX_HOME")"
  [[ -n "${SETUP_CODEX_WS:-}" ]] && cleanup_ws "$SETUP_CODEX_WS"
  SETUP_CODEX_WS=""
  SETUP_CODEX_BIN=""
  SETUP_CODEX_HOME=""
}

echo ""
echo "-- Codex adapter: happy path (mock-codex, HOME isolated)"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CODEX_SCENARIO=happy \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
stdout_ok=0
# provider.stdout.log 含 thread.started 事件
[[ -f "$round_dir/provider.stdout.log" ]] && \
  grep -q '"thread.started"' "$round_dir/provider.stdout.log" 2>/dev/null && stdout_ok=1
session_id_ok=0
grep -qE '"session_id":[[:space:]]*"[^"]+"' "$round_dir/meta.json" 2>/dev/null && session_id_ok=1
session_ok=0
[[ -f "$round_dir/session.codex.jsonl" ]] && session_ok=1
capture_ok=0
grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
history_ok=0
# session.history.log 含 assistant / tool-use / tool-result（真实 CLI 不含 user 事件）
[[ -f "$round_dir/session.history.log" ]] && \
  grep -q '\[assistant\]' "$round_dir/session.history.log" && \
  grep -q '\[tool-use name=Bash\]' "$round_dir/session.history.log" && \
  grep -q '\[tool-result name=Bash\]' "$round_dir/session.history.log" && history_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$stdout_ok" -eq 1 && "$session_id_ok" -eq 1 \
   && "$session_ok" -eq 1 && "$capture_ok" -eq 1 && "$history_ok" -eq 1 ]]; then
  _pass "codex happy: exit 0, done, thread.started, session_id, session.codex.jsonl, capture_status=ok, history.log derived"
else
  _fail "codex happy: rc=$rc reason=$reason stdout_ok=$stdout_ok session_id_ok=$session_id_ok session_ok=$session_ok capture_ok=$capture_ok history_ok=$history_ok"
fi
cleanup_codex_ws

echo ""
echo "-- Codex adapter: run -v live tail emits Codex event markers"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
stderr_file="$(mktemp)"
RALPH_MOCK_CODEX_SCENARIO=happy RALPH_MOCK_CODEX_POST_STREAM_SLEEP=2 \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex -v \
  >/dev/null 2>"$stderr_file" || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
marker_ok=0
grep -Eq '⚙ session|💬|🔧|⏎ result|✓ result' "$stderr_file" 2>/dev/null && marker_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$marker_ok" -eq 1 ]]; then
  _pass "codex run -v: stderr contains Codex JSONL filter marker"
else
  _fail "codex run -v: expected rc=0 done + marker, got rc=$rc reason=$reason marker_ok=$marker_ok"
fi
rm -f "$stderr_file"
cleanup_codex_ws

echo ""
echo "-- SC-022-4: adapter-codex.sh translates RALPH_PROVIDER_CONFIG_DIR → CODEX_HOME"
out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
  export RALPH_PROVIDER_CONFIG_DIR=/tmp/ralph-test-codex-cfg
  source '$REPO_ROOT/.ralph/lib/common.sh'
  source '$REPO_ROOT/.ralph/lib/adapter-codex.sh'
  echo \"CH=\${CODEX_HOME:-UNSET}\"
")
if [[ "$out" == *"CH=/tmp/ralph-test-codex-cfg"* ]]; then
  _pass "adapter-codex: CODEX_HOME translated from RALPH_PROVIDER_CONFIG_DIR"
else
  _fail "adapter-codex translation: expected CH=/tmp/ralph-test-codex-cfg, got '$out'"
fi

echo ""
echo "-- SC-022-4: adapter-codex.sh robustness: empty RALPH_PROVIDER_CONFIG_DIR → CODEX_HOME NOT exported"
out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
  source '$REPO_ROOT/.ralph/lib/common.sh'
  source '$REPO_ROOT/.ralph/lib/adapter-codex.sh'
  if [[ -z \${CODEX_HOME+x} ]]; then
    echo 'UNSET'
  else
    echo \"SET=\$CODEX_HOME\"
  fi
")
if [[ "$out" == *"UNSET"* ]]; then
  _pass "adapter-codex empty case: CODEX_HOME not exported (robust)"
else
  _fail "adapter-codex empty case: expected UNSET, got '$out'"
fi

echo ""
echo "-- SC-022-5: Codex session CODEX_HOME aware capture (REQ-022)"
setup_codex_workspace
custom_cfg="$(dirname "$SETUP_CODEX_HOME")/custom-codex-cfg"
mkdir -p "$custom_cfg/sessions"
# 在 workspace .env 加 RALPH_PROVIDER_CONFIG_DIR（adapter 翻译为 CODEX_HOME）
printf 'RALPH_PROVIDER_CONFIG_DIR=%s\n' "$custom_cfg" >> "$SETUP_CODEX_WS/.ralph/.env"
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
# Clear RALPH_PROVIDER_CONFIG_DIR so load_env can set it from .env (parent env may have it set)
RALPH_MOCK_CODEX_SCENARIO=happy \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
jsonl_ok=0; capture_ok=0; src_ok=0; home_clean=1
[[ -f "$round_dir/session.codex.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
# session_source_path 应在 custom_cfg/sessions/ 下
src_path="$(jq -r '.session_source_path // ""' "$round_dir/meta.json" 2>/dev/null)"
[[ "$src_path" == "$custom_cfg/sessions/"* ]] && src_ok=1
# 反向断言：$HOME/.codex/sessions/ 下不应有任何 jsonl（mock-codex 写到 CODEX_HOME）
if find "$SETUP_CODEX_HOME/.codex/sessions" -name "*.jsonl" -type f 2>/dev/null | grep -q .; then
  home_clean=0
fi
if [[ "$jsonl_ok" -eq 1 && "$capture_ok" -eq 1 && "$src_ok" -eq 1 && "$home_clean" -eq 1 ]]; then
  _pass "session CODEX_HOME aware: jsonl ok, capture_status=ok, source from custom cfg, HOME/.codex clean"
else
  _fail "session CODEX_HOME aware: jsonl_ok=$jsonl_ok capture_ok=$capture_ok src_ok=$src_ok home_clean=$home_clean src=$src_path"
fi
cleanup_codex_ws

echo ""
echo "-- Codex session: missing thread_id → capture_status=warning + history from stdout"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CODEX_SCENARIO=missing_thread_id \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex --max-round 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
warn_ok=0; history_ok=0
grep -q '"capture_status": "warning"' "$round_dir/meta.json" 2>/dev/null && warn_ok=1
# history 派生从 provider.stdout.log 读取，不依赖 session 文件
[[ -f "$round_dir/session.history.log" && -s "$round_dir/session.history.log" ]] && \
  grep -q '\[assistant\]' "$round_dir/session.history.log" && history_ok=1
if [[ "$warn_ok" -eq 1 && "$history_ok" -eq 1 ]]; then
  _pass "codex missing thread_id: capture_status=warning, session.history.log derived from stdout"
else
  _fail "codex missing thread_id: warn_ok=$warn_ok history_ok=$history_ok"
fi
cleanup_codex_ws

# Codex 错误诊断矩阵（DEV-4）
_run_codex_diagnose_case() {
  local scenario="$1" expected_type="$2" label="$3"
  setup_codex_workspace
  printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
  git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "tasks" 2>/dev/null || true
  local rc=0
  RALPH_MOCK_CODEX_SCENARIO="$scenario" \
    env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
    bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
  local run_dir error_type
  run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
  error_type="$(get_last_error_type "$run_dir")"
  if [[ "$rc" -eq 2 && "$error_type" == "$expected_type" ]]; then
    _pass "$label: rc=2, last_error.type=$expected_type"
  else
    _fail "$label: rc=$rc error_type=$error_type (expected rc=2 type=$expected_type)"
  fi
  cleanup_codex_ws
}

echo ""
echo "-- Codex diagnose: auth (401 unauthorized)"
_run_codex_diagnose_case turn_failed_auth auth "codex diagnose auth"

echo ""
echo "-- Codex diagnose: rate_limit (429)"
_run_codex_diagnose_case turn_failed_rate_limit rate_limit "codex diagnose rate_limit"

echo ""
echo "-- Codex diagnose: quota (credits exhausted)"
_run_codex_diagnose_case turn_failed_quota quota "codex diagnose quota"

echo ""
echo "-- Codex diagnose: network (ECONNRESET)"
_run_codex_diagnose_case turn_failed_network network "codex diagnose network"

echo ""
echo "-- Codex diagnose: api (500)"
_run_codex_diagnose_case turn_failed_api api "codex diagnose api"

echo ""
echo "-- Codex diagnose: unknown (unrecognized error)"
_run_codex_diagnose_case turn_failed_unknown unknown "codex diagnose unknown"

echo ""
echo "-- Codex diagnose: error event fallback (auth via error event, no turn.failed)"
_run_codex_diagnose_case error_event_auth auth "codex diagnose error event fallback"

echo ""
echo "-- Codex diagnose: stderr fallback (non-JSON stderr, network)"
_run_codex_diagnose_case stderr_error network "codex diagnose stderr fallback"

echo ""
echo "-- Codex diagnose: crash (no stdout)"
_run_codex_diagnose_case crash unknown "codex diagnose crash"

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=low → codex receives -c model_reasoning_effort=low"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CODEX_SCENARIO=happy RALPH_PROVIDER_EFFORT=low \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
received_effort="$(grep -E '^[[:space:]]*\{' "$round_dir/provider.stdout.log" 2>/dev/null \
  | jq -r 'select(.type == "thread.started") | ._received_effort // empty' 2>/dev/null \
  | head -1)" || received_effort=""
if [[ "$rc" -eq 0 && "$received_effort" == "model_reasoning_effort=low" ]]; then
  _pass "SC-014-1 codex effort=low: mock-codex received model_reasoning_effort=low"
else
  _fail "SC-014-1 codex effort=low: rc=$rc received_effort='$received_effort'"
fi
cleanup_codex_ws

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_EFFORT=none → codex effort flag not passed"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CODEX_SCENARIO=happy RALPH_PROVIDER_EFFORT=none \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
received_effort="$(grep -E '^[[:space:]]*\{' "$round_dir/provider.stdout.log" 2>/dev/null \
  | jq -r 'select(.type == "thread.started") | ._received_effort // empty' 2>/dev/null \
  | head -1)" || received_effort=""
if [[ "$rc" -eq 0 && -z "$received_effort" ]]; then
  _pass "SC-014-1 codex effort=none: mock-codex received no effort override"
else
  _fail "SC-014-1 codex effort=none: rc=$rc received_effort='$received_effort'"
fi
cleanup_codex_ws

echo ""
echo "-- SC-014-1: RALPH_PROVIDER_MODEL empty → codex model flag not passed"
setup_codex_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CODEX_WS/.ralph/TASKS.md"
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CODEX_SCENARIO=happy RALPH_PROVIDER_MODEL="" \
  env PATH="$SETUP_CODEX_BIN:$PATH" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CODEX_WS")"
round_dir="${run_dir}/rounds/round-001"
received_model="$(grep -E '^[[:space:]]*\{' "$round_dir/provider.stdout.log" 2>/dev/null \
  | jq -r 'select(.type == "thread.started") | ._received_model // empty' 2>/dev/null \
  | head -1)" || received_model=""
if [[ "$rc" -eq 0 && -z "$received_model" ]]; then
  _pass "SC-014-1 codex empty model: mock-codex received no model flag"
else
  _fail "SC-014-1 codex empty model: rc=$rc received_model='$received_model'"
fi
cleanup_codex_ws

echo ""
echo "-- Dep check: codex + jq both missing (codex adapter, non-fail-fast)"
setup_codex_workspace
git -C "$SETUP_CODEX_WS" add . && git -C "$SETUP_CODEX_WS" commit -q -m "init" 2>/dev/null || true
tmpbin_codex_none=$(_build_path_without jq)
rm -f "$tmpbin_codex_none/codex"   # ensure codex also absent from PATH
rc=0
stderr_out=$(env PATH="$tmpbin_codex_none" HOME="$SETUP_CODEX_HOME" \
  bash "$SETUP_CODEX_WS/.ralph/bin/ralph" run --provider codex 2>&1 >/dev/null) || rc=$?
rm -rf "$tmpbin_codex_none"
runs_count=$(count_runs "$SETUP_CODEX_WS")
if [[ "$rc" -ne 0 \
  && "$stderr_out" == *"ralph: missing dependency: codex"* \
  && "$stderr_out" == *"ralph: missing dependency: jq"* \
  && "$runs_count" -eq 0 ]]; then
  _pass "codex+jq both missing: both deps reported in one pass, no run dir"
else
  _fail "codex+jq both missing: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_codex_ws

	# ────────────────────────────────
	# Gemini adapter（I4 QA-1）
	# ────────────────────────────────

	SETUP_GEMINI_WS=""
	SETUP_GEMINI_BIN=""
	SETUP_GEMINI_HOME=""
	setup_gemini_workspace() {
	  SETUP_GEMINI_WS="$(setup_workspace --provider gemini)"

	  # HOME 隔离（避免写真实 ~/.gemini）
	  local home_parent
	  home_parent="$(mktemp -d)"
	  SETUP_GEMINI_HOME="$home_parent/home"
	  mkdir -p "$SETUP_GEMINI_HOME"

	  # mock-gemini 软链到 workspace 内 tests-bin/
	  SETUP_GEMINI_BIN="$SETUP_GEMINI_WS/tests-bin"
	  mkdir -p "$SETUP_GEMINI_BIN"
	  ln -sf "$REPO_ROOT/tests/fixtures/mock-gemini" "$SETUP_GEMINI_BIN/gemini"
	}

	cleanup_gemini_ws() {
	  [[ -n "${SETUP_GEMINI_HOME:-}" ]] && rm -rf "$(dirname "$SETUP_GEMINI_HOME")"
	  [[ -n "${SETUP_GEMINI_WS:-}" ]] && cleanup_ws "$SETUP_GEMINI_WS"
	  SETUP_GEMINI_WS=""
	  SETUP_GEMINI_BIN=""
	  SETUP_GEMINI_HOME=""
	}

	echo ""
	echo "-- Gemini adapter: happy path (mock-gemini, HOME isolated)"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=happy \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
	stdout_ok=0
	# stream-json 模式：provider.stdout.log 含 init + message + result 事件（QA-2 真实 schema）
	[[ -f "$round_dir/provider.stdout.log" ]] && \
	  grep -q '"type":"init"' "$round_dir/provider.stdout.log" 2>/dev/null && \
	  grep -q '"type":"result"' "$round_dir/provider.stdout.log" 2>/dev/null && stdout_ok=1
	session_id_ok=0
	grep -qE '"session_id":[[:space:]]*"[^"]+"' "$round_dir/meta.json" 2>/dev/null && session_id_ok=1
	session_ok=0
	[[ -f "$round_dir/session.gemini.json" ]] && session_ok=1
	capture_ok=0
	grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
	history_ok=0
	# session.history.log 含 [assistant] / [tool-use] / [tool-result] / [result]（从 provider.stdout.log 事件流派生）
	[[ -f "$round_dir/session.history.log" ]] && \
	  grep -q '\[assistant\]' "$round_dir/session.history.log" && \
	  grep -q '\[tool-use Bash\]' "$round_dir/session.history.log" && \
	  grep -q '\[tool-result\]' "$round_dir/session.history.log" && \
	  grep -q '\[result\]' "$round_dir/session.history.log" && history_ok=1
	if [[ "$rc" -eq 0 && "$reason" == "done" && "$stdout_ok" -eq 1 && "$session_id_ok" -eq 1 \
	   && "$session_ok" -eq 1 && "$capture_ok" -eq 1 && "$history_ok" -eq 1 ]]; then
	  _pass "gemini happy: exit 0, done, stream-json events, session_id, session.gemini.json, capture_status=ok, history.log derived"
	else
	  _fail "gemini happy: rc=$rc reason=$reason stdout_ok=$stdout_ok session_id_ok=$session_id_ok session_ok=$session_ok capture_ok=$capture_ok history_ok=$history_ok"
	fi
	cleanup_gemini_ws

	echo ""
	echo "-- Gemini adapter: run -v live tail emits Gemini event markers"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	stderr_file="$(mktemp)"
	RALPH_MOCK_GEMINI_SCENARIO=happy RALPH_MOCK_GEMINI_POST_STREAM_SLEEP=2 \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini -v \
	  >/dev/null 2>"$stderr_file" || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
	marker_ok=0
	grep -Eq '⚙ session|💬|✓ result' "$stderr_file" 2>/dev/null && marker_ok=1
	if [[ "$rc" -eq 0 && "$reason" == "done" && "$marker_ok" -eq 1 ]]; then
	  _pass "gemini run -v: stderr contains Gemini event filter marker"
	else
	  _fail "gemini run -v: expected rc=0 done + marker, got rc=$rc reason=$reason marker_ok=$marker_ok"
	fi
	rm -f "$stderr_file"
	cleanup_gemini_ws

	echo ""
	echo "-- adapter-gemini.sh translates RALPH_PROVIDER_CONFIG_DIR → GEMINI_CLI_HOME"
	out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
	  export RALPH_PROVIDER_CONFIG_DIR=/tmp/ralph-test-gemini-cfg
	  source '$REPO_ROOT/.ralph/lib/common.sh'
	  source '$REPO_ROOT/.ralph/lib/adapter-gemini.sh'
	  echo \"GCH=\${GEMINI_CLI_HOME:-UNSET}\"
	")
	if [[ "$out" == *"GCH=/tmp/ralph-test-gemini-cfg"* ]]; then
	  _pass "adapter-gemini: GEMINI_CLI_HOME translated from RALPH_PROVIDER_CONFIG_DIR"
	else
	  _fail "adapter-gemini translation: expected GCH=/tmp/ralph-test-gemini-cfg, got '$out'"
	fi

	echo ""
	echo "-- adapter-gemini.sh robustness: empty RALPH_PROVIDER_CONFIG_DIR → GEMINI_CLI_HOME NOT exported"
	out=$(env -i HOME="$HOME" PATH="$PATH" bash -c "
	  source '$REPO_ROOT/.ralph/lib/common.sh'
	  source '$REPO_ROOT/.ralph/lib/adapter-gemini.sh'
	  if [[ -z \${GEMINI_CLI_HOME+x} ]]; then
	    echo 'UNSET'
	  else
	    echo \"SET=\$GEMINI_CLI_HOME\"
	  fi
	")
	if [[ "$out" == *"UNSET"* ]]; then
	  _pass "adapter-gemini empty case: GEMINI_CLI_HOME not exported (robust)"
	else
	  _fail "adapter-gemini empty case: expected UNSET, got '$out'"
	fi

	echo ""
	echo "-- Gemini session: GEMINI_CLI_HOME aware capture (REQ-022)"
	setup_gemini_workspace
	custom_cfg="$(dirname "$SETUP_GEMINI_HOME")/custom-gemini-cfg"
	mkdir -p "$custom_cfg"
	# 在 workspace .env 加 RALPH_PROVIDER_CONFIG_DIR（adapter 翻译为 GEMINI_CLI_HOME）
	printf 'RALPH_PROVIDER_CONFIG_DIR=%s\n' "$custom_cfg" >> "$SETUP_GEMINI_WS/.ralph/.env"
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=happy \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	json_ok=0; capture_ok=0; src_ok=0; home_clean=1
	[[ -f "$round_dir/session.gemini.json" ]] && json_ok=1
	grep -q '"capture_status": "ok"' "$round_dir/meta.json" 2>/dev/null && capture_ok=1
	# session_source_path 应在 custom_cfg/.gemini/tmp/ 下
	src_path="$(jq -r '.session_source_path // ""' "$round_dir/meta.json" 2>/dev/null)"
	[[ "$src_path" == "$custom_cfg/.gemini/tmp/"* ]] && src_ok=1
	# 反向断言：$HOME/.gemini/ 下不应有任何 session 文件（mock-gemini 写到 GEMINI_CLI_HOME）
	if find "$SETUP_GEMINI_HOME/.gemini" -name "*.json" -type f 2>/dev/null | grep -q .; then
	  home_clean=0
	fi
	if [[ "$json_ok" -eq 1 && "$capture_ok" -eq 1 && "$src_ok" -eq 1 && "$home_clean" -eq 1 ]]; then
	  _pass "session GEMINI_CLI_HOME aware: json ok, capture_status=ok, source from custom cfg, HOME/.gemini clean"
	else
	  _fail "session GEMINI_CLI_HOME aware: json_ok=$json_ok capture_ok=$capture_ok src_ok=$src_ok home_clean=$home_clean src=$src_path"
	fi
	cleanup_gemini_ws

	echo ""
	echo "-- Gemini session: session_id mismatch → mtime fallback"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=session_mismatch \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini --max-round 1 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	json_ok=0; warn_ok=0
	[[ -f "$round_dir/session.gemini.json" ]] && json_ok=1
	grep -q '"fallback by mtime"' "$round_dir/meta.json" 2>/dev/null && warn_ok=1
	if [[ "$json_ok" -eq 1 && "$warn_ok" -eq 1 ]]; then
	  _pass "gemini session mtime fallback: session.gemini.json exists, capture_warning=fallback by mtime"
	else
	  _fail "gemini session mtime fallback: json_ok=$json_ok warn_ok=$warn_ok"
	fi
	cleanup_gemini_ws

	echo ""
	echo "-- Gemini session: missing session file → capture_status=warning + history from stdout"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=no_session_file \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini --max-round 1 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	no_session=0; warn_ok=0; history_ok=0
	[[ ! -f "$round_dir/session.gemini.json" ]] && no_session=1
	grep -q '"capture_status": "warning"' "$round_dir/meta.json" 2>/dev/null && warn_ok=1
	# 派生视图仍从 stdout 产出（不依赖 session 文件）
	[[ -f "$round_dir/session.history.log" ]] && \
	  grep -q '\[assistant\]' "$round_dir/session.history.log" && history_ok=1
	if [[ "$no_session" -eq 1 && "$warn_ok" -eq 1 && "$history_ok" -eq 1 ]]; then
	  _pass "gemini missing session: no session.gemini.json, capture_status=warning, history from stdout"
	else
	  _fail "gemini missing session: no_session=$no_session warn_ok=$warn_ok history_ok=$history_ok"
	fi
	cleanup_gemini_ws

	# Gemini 错误诊断矩阵
	_run_gemini_diagnose_case() {
	  local scenario="$1" expected_type="$2" label="$3"
	  setup_gemini_workspace
	  printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	  git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "tasks" 2>/dev/null || true
	  local rc=0
	  RALPH_MOCK_GEMINI_SCENARIO="$scenario" \
	    env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	    bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>/dev/null || rc=$?
	  local run_dir error_type
	  run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	  error_type="$(get_last_error_type "$run_dir")"
	  if [[ "$rc" -eq 2 && "$error_type" == "$expected_type" ]]; then
	    _pass "$label: rc=2, last_error.type=$expected_type"
	  else
	    _fail "$label: rc=$rc error_type=$error_type (expected rc=2 type=$expected_type)"
	  fi
	  cleanup_gemini_ws
	}

	echo ""
	echo "-- Gemini diagnose: auth (401 unauthorized)"
	_run_gemini_diagnose_case auth_error auth "gemini diagnose auth"

	echo ""
	echo "-- Gemini diagnose: rate_limit (429)"
	_run_gemini_diagnose_case rate_limit_error rate_limit "gemini diagnose rate_limit"

	echo ""
	echo "-- Gemini diagnose: quota (billing quota exhausted)"
	_run_gemini_diagnose_case quota_error quota "gemini diagnose quota"

	echo ""
	echo "-- Gemini diagnose: network (ECONNRESET)"
	_run_gemini_diagnose_case network_error network "gemini diagnose network"

	echo ""
	echo "-- Gemini diagnose: api (500)"
	_run_gemini_diagnose_case api_error api "gemini diagnose api"

	echo ""
	echo "-- Gemini diagnose: unknown (unrecognized error)"
	_run_gemini_diagnose_case unknown_error unknown "gemini diagnose unknown"

	echo ""
	echo "-- Gemini diagnose: crash (no stdout)"
	_run_gemini_diagnose_case crash unknown "gemini diagnose crash"

	echo ""
	echo "-- SC-014-1: RALPH_PROVIDER_MODEL empty → gemini model flag not passed"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=happy RALPH_PROVIDER_MODEL="" \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	received_model="$(grep -E '^\{' "$round_dir/provider.stdout.log" 2>/dev/null \
	  | jq -r 'select(.type == "init") | ._received_model // empty' 2>/dev/null \
	  | head -1)" || received_model=""
	if [[ "$rc" -eq 0 && -z "$received_model" ]]; then
	  _pass "SC-014-1 gemini empty model: mock-gemini received no model flag"
	else
	  _fail "SC-014-1 gemini empty model: rc=$rc received_model='$received_model'"
	fi
	cleanup_gemini_ws

	echo ""
	echo "-- SC-014-1: RALPH_PROVIDER_MODEL set → gemini receives --model"
	setup_gemini_workspace
	printf '%s\n' "- [ ] Task A" > "$SETUP_GEMINI_WS/.ralph/TASKS.md"
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "single task" 2>/dev/null || true
	rc=0
	RALPH_MOCK_GEMINI_SCENARIO=happy RALPH_PROVIDER_MODEL="gemini-2.5-pro" \
	  env PATH="$SETUP_GEMINI_BIN:$PATH" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>/dev/null || rc=$?
	run_dir="$(latest_run_dir "$SETUP_GEMINI_WS")"
	round_dir="${run_dir}/rounds/round-001"
	received_model="$(grep -E '^\{' "$round_dir/provider.stdout.log" 2>/dev/null \
	  | jq -r 'select(.type == "init") | ._received_model // empty' 2>/dev/null \
	  | head -1)" || received_model=""
	if [[ "$rc" -eq 0 && "$received_model" == "gemini-2.5-pro" ]]; then
	  _pass "SC-014-1 gemini model set: mock-gemini received model=gemini-2.5-pro"
	else
	  _fail "SC-014-1 gemini model set: rc=$rc received_model='$received_model'"
	fi
	cleanup_gemini_ws

	echo ""
	echo "-- Dep check: gemini + jq both missing (gemini adapter, non-fail-fast)"
	setup_gemini_workspace
	git -C "$SETUP_GEMINI_WS" add . && git -C "$SETUP_GEMINI_WS" commit -q -m "init" 2>/dev/null || true
	tmpbin_gemini_none=$(_build_path_without jq)
	rm -f "$tmpbin_gemini_none/gemini"   # ensure gemini also absent from PATH
	rc=0
	stderr_out=$(env PATH="$tmpbin_gemini_none" HOME="$SETUP_GEMINI_HOME" RALPH_PROVIDER_CONFIG_DIR="" \
	  bash "$SETUP_GEMINI_WS/.ralph/bin/ralph" run --provider gemini 2>&1 >/dev/null) || rc=$?
	rm -rf "$tmpbin_gemini_none"
	runs_count=$(count_runs "$SETUP_GEMINI_WS")
	if [[ "$rc" -ne 0 \
	  && "$stderr_out" == *"ralph: missing dependency: gemini"* \
	  && "$stderr_out" == *"ralph: missing dependency: jq"* \
	  && "$runs_count" -eq 0 ]]; then
	  _pass "gemini+jq both missing: both deps reported in one pass, no run dir"
	else
	  _fail "gemini+jq both missing: rc=$rc runs=$runs_count stderr=$stderr_out"
	fi
	cleanup_gemini_ws

	# ── Sticky UI (I5 QA-1) ───────────────────────────────────────────────────

	_strip_ansi() { sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g'; }

	# Source sticky.sh in a subshell with mocked terminal for unit-level tests
	_sticky_unit() {
	  local code="$1"
	  (
	    source "$REPO_ROOT/.ralph/lib/sticky.sh"
	    _srefresh_size() { _SCOLS=100; _SROWS=30; }
	    ralph_sticky_enter() {
	      _SLAST_ACTIVITY_TS="$(date +%s)"
	      _SLOG_LAST_SIZE=0; _SRENDERED=0; _SREDRAWING=0; _SCLEANED=0
	      _SEV_TIMES=(); _SEV_MSGS=(); _SSPIN_IDX=0
	    }
	    ralph_sticky_cleanup() { :; }
	    _RALPH_STICKY_RUN_START_TS="$(date +%s)"
	    _RALPH_STICKY_ROUND=3
	    _RALPH_STICKY_ROUND_START_TS="$(date +%s)"
	    _RALPH_STICKY_TASKS_DONE=2
	    _RALPH_STICKY_TASKS_TOTAL=5
	    _RALPH_STICKY_CURRENT_TASK="Test task"
	    _RALPH_STICKY_TASK_TRY=1
	    _RALPH_STICKY_MAX_ROUND=10
	    _RALPH_STICKY_STALL_COUNT=0
	    _RALPH_STICKY_STALL_LIMIT=5
	    _RALPH_STICKY_PROVIDER="fake"
	    _RALPH_STICKY_RETRY_COUNT=0
	    _RALPH_STICKY_LOG_PATH="/dev/null"
	    _RALPH_STICKY_EXIT_REASON=""
	    eval "$code"
	  ) 2>/dev/null
	}

	# ── 1. First frame: 10 lines (top + hr + 6 events + hr + bottom) ────────
	echo ""
	echo "-- Sticky: first frame line count"
	out="$(_sticky_unit 'ralph_sticky_enter; ralph_sticky_render_frame')"
	# $(...) strips trailing \n, so add it back for accurate wc -l
	line_count=$(printf '%s\n' "$out" | _strip_ansi | wc -l | tr -d ' ')
	if [[ "$line_count" -eq 10 ]]; then
	  _pass "sticky frame: 10 lines (top+hr+6ev+hr+bottom)"
	else
	  _fail "sticky frame: expected 10 lines, got $line_count"
	fi

	# ── 1b. Top bar fields ──────────────────────────────────────────────────
	top_line=$(printf '%s' "$out" | _strip_ansi | head -1)
	top_ok=1
	echo "$top_line" | grep -q "ralph" || top_ok=0
	echo "$top_line" | grep -q "tasks 2/5" || top_ok=0
	echo "$top_line" | grep -q "round 3" || top_ok=0
	echo "$top_line" | grep -q "provider fake" || top_ok=0
	if [[ "$top_ok" -eq 1 ]]; then
	  _pass "sticky top: ralph/tasks/round/provider fields present"
	else
	  _fail "sticky top: missing fields in: $(echo "$top_line" | head -c 120)"
	fi

	# ── 1c. Bottom bar fields ───────────────────────────────────────────────
	bottom_line=$(printf '%s' "$out" | _strip_ansi | tail -1)
	bot_ok=1
	echo "$bottom_line" | grep -q "round 1/10" || bot_ok=0
	echo "$bottom_line" | grep -q "stall 0/5" || bot_ok=0
	echo "$bottom_line" | grep -q "→" || bot_ok=0
	echo "$bottom_line" | grep -q "Test task" || bot_ok=0
	if [[ "$bot_ok" -eq 1 ]]; then
	  _pass "sticky bottom: round/stall/arrow/task fields present"
	else
	  _fail "sticky bottom: missing fields in: $(echo "$bottom_line" | head -c 120)"
	fi

	# ── 2. cursor_up on second frame ────────────────────────────────────────
	echo ""
	echo "-- Sticky: cursor_up on redraw"
	out2="$(_sticky_unit 'ralph_sticky_enter; ralph_sticky_render_frame; ralph_sticky_render_frame')"
	if printf '%s' "$out2" | grep -q $'\033\[10A'; then
	  _pass "sticky redraw: cursor_up 10 lines on second frame"
	else
	  _fail "sticky redraw: cursor_up sequence not found in output"
	fi

	# ── 3. Health light: green (≤60s idle) ──────────────────────────────────
	echo ""
	echo "-- Sticky: health light green (fresh activity)"
	out_g="$(_sticky_unit 'ralph_sticky_enter; ralph_sticky_render_frame')"
	if printf '%s' "$out_g" | grep -q $'\033\[32m'; then
	  _pass "sticky health: green ANSI (32m) for fresh activity"
	else
	  _fail "sticky health: green ANSI not found"
	fi

	# Health light: yellow (60-300s idle)
	echo ""
	echo "-- Sticky: health light yellow (70s idle)"
	out_y="$(_sticky_unit '
	  ralph_sticky_enter
	  _SLAST_ACTIVITY_TS=$(( $(date +%s) - 70 ))
	  ralph_sticky_render_frame
	')"
	if printf '%s' "$out_y" | grep -q $'\033\[33m'; then
	  _pass "sticky health: yellow ANSI (33m) for 70s idle"
	else
	  _fail "sticky health: yellow ANSI not found for 70s idle"
	fi

	# Health light: red (>300s idle)
	echo ""
	echo "-- Sticky: health light red (400s idle)"
	out_r="$(_sticky_unit '
	  ralph_sticky_enter
	  _SLAST_ACTIVITY_TS=$(( $(date +%s) - 400 ))
	  ralph_sticky_render_frame
	')"
	if printf '%s' "$out_r" | grep -q $'\033\[31m'; then
	  _pass "sticky health: red ANSI (31m) for 400s idle"
	else
	  _fail "sticky health: red ANSI not found for 400s idle"
	fi

	# ── 4. Event area 6-line FIFO ───────────────────────────────────────────
	echo ""
	echo "-- Sticky: event area 6-line FIFO eviction"
	out_ev="$(_sticky_unit '
	  ralph_sticky_enter
	  for n in AA BB CC DD EE FF GG HH II JJ; do
	    ralph_sticky_append_event "$n"
	  done
	  ralph_sticky_render_frame
	')"
	clean_ev=$(printf '%s' "$out_ev" | _strip_ansi)
	ev_ok=1
	echo "$clean_ev" | grep -q "JJ" || ev_ok=0
	echo "$clean_ev" | grep -q "EE" || ev_ok=0
	echo "$clean_ev" | grep -q "AA" && ev_ok=0
	echo "$clean_ev" | grep -q "DD" && ev_ok=0
	if [[ "$ev_ok" -eq 1 ]]; then
	  _pass "sticky events: 6-line FIFO, EE..JJ visible, AA..DD evicted"
	else
	  _fail "sticky events: FIFO eviction not working"
	fi

	# ── 5. Exit-state symbols (✓/✗/⏸) ──────────────────────────────────────
	echo ""
	echo "-- Sticky: exit-state symbols"
	out_done="$(_sticky_unit '
	  ralph_sticky_enter
	  _RALPH_STICKY_EXIT_REASON="done"
	  ralph_sticky_render_frame
	')"
	if printf '%s' "$out_done" | grep -q '✓'; then
	  _pass "sticky exit: ✓ for done"
	else
	  _fail "sticky exit: ✓ not found for done"
	fi

	out_fail="$(_sticky_unit '
	  ralph_sticky_enter
	  _RALPH_STICKY_EXIT_REASON="provider_failed"
	  ralph_sticky_render_frame
	')"
	if printf '%s' "$out_fail" | grep -q '✗'; then
	  _pass "sticky exit: ✗ for provider_failed"
	else
	  _fail "sticky exit: ✗ not found for provider_failed"
	fi

	out_int="$(_sticky_unit '
	  ralph_sticky_enter
	  _RALPH_STICKY_EXIT_REASON="interrupted"
	  ralph_sticky_render_frame
	')"
	if printf '%s' "$out_int" | grep -q '⏸'; then
	  _pass "sticky exit: ⏸ for interrupted"
	else
	  _fail "sticky exit: ⏸ not found for interrupted"
	fi

	# ── 6. TTY tests (expect required) ──────────────────────────────────────
	if command -v expect >/dev/null 2>&1; then
	  # 6a. stty restore after explicit cleanup
	  echo ""
	  echo "-- Sticky: stty restore after cleanup (expect TTY)"
	  result_file="$(mktemp)"
	  tmpdir="$(mktemp -d)"
	  cat > "$tmpdir/stty-test.sh" <<STTYEOF
#!/usr/bin/env bash
set -u
source "$REPO_ROOT/.ralph/lib/sticky.sh"
result_file="$result_file"
_RALPH_STICKY_RUN_START_TS=\$(date +%s)
_RALPH_STICKY_ROUND=1
_RALPH_STICKY_ROUND_START_TS=\$(date +%s)
_RALPH_STICKY_TASKS_DONE=0
_RALPH_STICKY_TASKS_TOTAL=1
_RALPH_STICKY_CURRENT_TASK="Test"
_RALPH_STICKY_TASK_TRY=1
_RALPH_STICKY_MAX_ROUND=0
_RALPH_STICKY_STALL_COUNT=0
_RALPH_STICKY_STALL_LIMIT=5
_RALPH_STICKY_PROVIDER="fake"
_RALPH_STICKY_RETRY_COUNT=0
_RALPH_STICKY_LOG_PATH="/dev/null"
ralph_sticky_enter
ralph_sticky_render_frame
ralph_sticky_cleanup
# Check critical flags: echo, icanon restored; min=1, time=0
stty_out=\$(stty -a < /dev/tty 2>/dev/null)
ok=1
echo "\$stty_out" | grep -qE '[ :]icanon ' || ok=0
echo "\$stty_out" | grep -qE '[ :]echo '   || ok=0
echo "\$stty_out" | grep -qE 'min = 1'     || ok=0
echo "\$stty_out" | grep -qE 'time = 0'    || ok=0
if [[ "\$ok" -eq 1 ]]; then echo "OK" > "\$result_file"; else echo "FAIL" > "\$result_file"; fi
STTYEOF
	  chmod +x "$tmpdir/stty-test.sh"
	  cat > "$tmpdir/stty-test.exp" <<EXPEOF
set timeout 10
spawn bash "$tmpdir/stty-test.sh"
expect eof
EXPEOF
	  expect -f "$tmpdir/stty-test.exp" >/dev/null 2>&1 || true
	  result=$(cat "$result_file" 2>/dev/null || echo "MISSING")
	  if [[ "$result" == "OK" ]]; then
	    _pass "sticky stty: echo/icanon/min/time restored after cleanup"
	  else
	    _fail "sticky stty: not restored (result=$result)"
	  fi
	  rm -f "$result_file"
	  rm -rf "$tmpdir"

	  # 6b. stty restore after Ctrl+C via trap
	  echo ""
	  echo "-- Sticky: stty restore after Ctrl+C (expect TTY)"
	  result_file="$(mktemp)"
	  tmpdir="$(mktemp -d)"
	  cat > "$tmpdir/ctrlc-test.sh" <<CTRLEOF
#!/usr/bin/env bash
set -u
source "$REPO_ROOT/.ralph/lib/sticky.sh"
result_file="$result_file"
_RALPH_STICKY_RUN_START_TS=\$(date +%s)
_RALPH_STICKY_ROUND=1
_RALPH_STICKY_ROUND_START_TS=\$(date +%s)
_RALPH_STICKY_TASKS_DONE=0
_RALPH_STICKY_TASKS_TOTAL=1
_RALPH_STICKY_CURRENT_TASK="Test"
_RALPH_STICKY_TASK_TRY=1
_RALPH_STICKY_MAX_ROUND=0
_RALPH_STICKY_STALL_COUNT=0
_RALPH_STICKY_STALL_LIMIT=5
_RALPH_STICKY_PROVIDER="fake"
_RALPH_STICKY_RETRY_COUNT=0
_RALPH_STICKY_LOG_PATH="/dev/null"
ralph_sticky_enter
ralph_sticky_install_traps
ralph_sticky_render_frame
trap 'ralph_sticky_cleanup; stty_out=\$(stty -a < /dev/tty 2>/dev/null); ok=1; echo "\$stty_out" | grep -qE "[ :]icanon " || ok=0; echo "\$stty_out" | grep -qE "[ :]echo " || ok=0; echo "\$stty_out" | grep -qE "min = 1" || ok=0; echo "\$stty_out" | grep -qE "time = 0" || ok=0; if [[ "\$ok" -eq 1 ]]; then echo "OK" > "$result_file"; else echo "FAIL" > "$result_file"; fi' EXIT
sleep 10
CTRLEOF
	  chmod +x "$tmpdir/ctrlc-test.sh"
	  cat > "$tmpdir/ctrlc-test.exp" <<EXPEOF
set timeout 10
spawn bash "$tmpdir/ctrlc-test.sh"
sleep 1
send "\003"
expect eof
EXPEOF
	  expect -f "$tmpdir/ctrlc-test.exp" >/dev/null 2>&1 || true
	  result=$(cat "$result_file" 2>/dev/null || echo "MISSING")
	  if [[ "$result" == "OK" ]]; then
	    _pass "sticky Ctrl+C: echo/icanon/min/time restored after SIGINT"
	  else
	    _fail "sticky Ctrl+C: stty not restored (result=$result)"
	  fi
	  rm -f "$result_file"
	  rm -rf "$tmpdir"

	  # 6c. End-to-end: ralph run -v with fake provider
	  echo ""
	  echo "-- Sticky: ralph run -v end-to-end (expect TTY)"
	  ws=$(setup_workspace)
	  printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
	  git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true

	  stderr_file="$(mktemp)"
	  cat > "$ws/run-sticky.exp" <<EXPEOF
set timeout 30
spawn bash "$ws/.ralph/bin/ralph" run --provider fake -v
expect {
    timeout { puts "EXPECT_TIMEOUT"; exit 1 }
    eof { puts "EXPECT_EOF" }
}
EXPEOF
	  RALPH_FAKE_SCENARIO=slow RALPH_FAKE_SLEEP=1 expect -f "$ws/run-sticky.exp" > "$stderr_file" 2>/dev/null || true

	  sticky_ok=0
	  if grep -q "────────────────────────────────" "$stderr_file" \
	     && grep -q "tasks 0/1" "$stderr_file" \
	     && grep -q "round 1" "$stderr_file"; then
	    sticky_ok=1
	  fi
	  if [[ "$sticky_ok" -eq 1 ]]; then
	    _pass "sticky run -v: TTY shows horizontal rules and header"
	  else
	    _fail "sticky run -v: missing rules/header. Output: $(cat -v "$stderr_file" | head -n 5)"
	  fi

	  # 6d. ralph watch sticky
	  echo ""
	  echo "-- Sticky: ralph watch (expect TTY)"
	  cat > "$ws/watch-sticky.exp" <<EXPEOF
set timeout 10
spawn bash "$ws/.ralph/bin/ralph" watch
expect "ralph"
expect "round"
send \003
expect eof
lassign [wait] pid spawnid os_error_flag value
exit \$value
EXPEOF
	  expect -f "$ws/watch-sticky.exp" > "$stderr_file" 2>/dev/null || true
	  if grep -q "────────────────────────────────" "$stderr_file"; then
	    _pass "sticky watch: shows horizontal rules"
	  else
	    _fail "sticky watch: rules NOT found"
	  fi

	  cleanup_ws "$ws"
	  rm -f "$stderr_file"
	else
	  echo "expect not found, skipping sticky TTY tests"
	fi

	# ── 汇总 ─────────────────────────────────────────────────────────────────────

echo ""
echo "=== Results: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -gt 0 ]]; then
  echo "Failed cases:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi
echo "All integration tests passed."
