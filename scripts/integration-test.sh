#!/usr/bin/env bash
# integration-test.sh — T1 集成测试，13 用例

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
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
if [[ -n "$run_dir" && "$(get_exit_reason "$run_dir")" == "done" && "$rc" -eq 0 ]]; then
  _pass "done: exit_reason=done, exit_code=0, run_dir exists"
else
  _fail "done: expected exit_reason=done rc=0, got rc=$rc run_dir=$run_dir"
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
echo "-- Exit reason: timeout"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=slow RALPH_FAKE_SLEEP=30 bash "$ws/.ralph/bin/ralph" run --provider fake --timeout 2 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "timeout" && "$rc" -eq 3 ]]; then
  _pass "timeout: exit_reason=timeout, rc=3"
else
  _fail "timeout: expected timeout/rc=3, got $reason/$rc"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: max_iterations"
ws=$(setup_workspace)
# 两条任务，max-iter=1，happy 只勾一条
printf '%s\n' "- [ ] Task A" "- [ ] Task B" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "two tasks" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake --max-iter 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "max_iterations" && "$rc" -eq 4 ]]; then
  _pass "max_iterations: exit_reason=max_iterations, rc=4"
else
  _fail "max_iterations: expected max_iterations/rc=4, got $reason/$rc"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Exit reason: stagnated"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=stagnation bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "stagnated" && "$rc" -eq 5 ]]; then
  _pass "stagnated: exit_reason=stagnated, rc=5"
else
  _fail "stagnated: expected stagnated/rc=5, got $reason/$rc"
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
# 用 SIGTERM（macOS bash 上 INT 在等待子进程时被 deferred/ignored；TERM 立即触发 trap）
RALPH_FAKE_SCENARIO=slow RALPH_FAKE_SLEEP=30 bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null &
bg_pid=$!
sleep 2  # 等待 ralph 获取 lock 并进入 slow sleep
kill -TERM "$bg_pid" 2>/dev/null || true
wait "$bg_pid" 2>/dev/null || true
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "interrupted" ]]; then
  _pass "interrupted (post-lock): exit_reason=interrupted, run_dir exists"
else
  _fail "interrupted (post-lock): expected interrupted, got reason=$reason run_dir=$run_dir"
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
stderr_out=$(bash "$ws/.ralph/bin/ralph" run 2>&1 >/dev/null) || rc=$?
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
echo "-- Startup check: provider CLI not found (RALPH_FAKE_CLI)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(RALPH_FAKE_CLI=__nonexistent_cli_xxx__ bash "$ws/.ralph/bin/ralph" run --provider fake 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "CLI not found: rc!=0, correct stderr prefix, no run dir"
else
  _fail "CLI not found: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Startup check: UUID force fail (RALPH_UUID_FORCE_FAIL=1, provider=claude)"
ws=$(setup_workspace --provider claude)
# claude provider 需要 adapter-claude.sh；用 fake adapter 但通过 RALPH_PROVIDER=claude 触发 UUID 校验
# 由于 adapter-claude.sh 不存在，我们需要特殊处理：
# 在 ws 里创建 adapter-claude.sh stub 只设 RALPH_PROVIDER_CLI=claude
mkdir -p "$ws/.ralph/lib"
cat > "$ws/.ralph/lib/adapter-claude.sh" <<'EOF'
RALPH_PROVIDER_CLI="bash"
provider_oneshot() { return 0; }
provider_collect_session() { return 0; }
provider_diagnose() { return 0; }
EOF
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
stderr_out=$(RALPH_UUID_FORCE_FAIL=1 bash "$ws/.ralph/bin/ralph" run --provider claude 2>&1 >/dev/null) || rc=$?
runs_count=$(count_runs "$ws")
if [[ "$rc" -ne 0 && "$stderr_out" == *"ralph: startup check failed:"* && "$runs_count" -eq 0 ]]; then
  _pass "UUID force fail: rc!=0, correct stderr prefix, no run dir"
else
  _fail "UUID force fail: rc=$rc runs=$runs_count stderr=$stderr_out"
fi
cleanup_ws "$ws"

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
