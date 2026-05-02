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
iter_dir="${run_dir}/iterations/iter-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
meta_exit_ok=0
meta_dur_ok=0
iter_exit="$(grep '"exit_code"' "$iter_dir/meta.json" 2>/dev/null | sed 's/.*"exit_code":[[:space:]]*\([^,}]*\).*/\1/' | tr -d ' ')" || iter_exit=""
iter_dur="$(grep '"duration_ms"' "$iter_dir/meta.json" 2>/dev/null | sed 's/.*"duration_ms":[[:space:]]*\([^,}]*\).*/\1/' | tr -d ' ')" || iter_dur=""
[[ "$iter_exit" != "0" && -n "$iter_exit" ]] && meta_exit_ok=1
[[ "$iter_dur" -gt 0 ]] 2>/dev/null && meta_dur_ok=1
if [[ "$reason" == "timeout" && "$rc" -eq 3 && "$meta_exit_ok" -eq 1 && "$meta_dur_ok" -eq 1 ]]; then
  _pass "timeout: exit_reason=timeout, rc=3, meta exit_code≠0, duration_ms>0"
else
  _fail "timeout: reason=$reason rc=$rc meta_exit_ok=$meta_exit_ok meta_dur_ok=$meta_dur_ok"
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
echo "-- Stagnation: partial_progress triggers stagnated (stagnation_limit=2)"
ws=$(setup_workspace)
git -C "$ws" add . && git -C "$ws" commit -q -m "init" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=partial_progress bash "$ws/.ralph/bin/ralph" run \
  --provider fake --stagnation-limit 2 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
if [[ "$reason" == "stagnated" && "$rc" -eq 5 ]]; then
  _pass "partial_progress stagnation: exit_reason=stagnated, rc=5"
else
  _fail "partial_progress stagnation: expected stagnated/rc=5, got $reason/$rc"
fi
if command -v jq >/dev/null 2>&1; then
  sc1="$(jq '.stagnation_count // 0' "$run_dir/iterations/iter-001/meta.json" 2>/dev/null)" || sc1=0
  sc2="$(jq '.stagnation_count // 0' "$run_dir/iterations/iter-002/meta.json" 2>/dev/null)" || sc2=0
  sc3="$(jq '.stagnation_count // 0' "$run_dir/iterations/iter-003/meta.json" 2>/dev/null)" || sc3=0
  if [[ "$sc1" -eq 0 && "$sc2" -eq 1 && "$sc3" -eq 2 ]]; then
    _pass "partial_progress stagnation_count: iter1=0 iter2=1 iter3=2"
  else
    _fail "partial_progress stagnation_count: expected 0/1/2, got $sc1/$sc2/$sc3"
  fi
fi
cleanup_ws "$ws"

# ────────────────────────────────
echo ""
echo "-- Stagnation: full happy run has stagnation_count=0"
ws=$(setup_workspace)
printf '%s\n' "- [ ] Task A" > "$ws/.ralph/TASKS.md"
git -C "$ws" add . && git -C "$ws" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_FAKE_SCENARIO=happy bash "$ws/.ralph/bin/ralph" run --provider fake 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$ws")"
if [[ "$(get_exit_reason "$run_dir")" == "done" ]]; then
  if command -v jq >/dev/null 2>&1; then
    sc1="$(jq '.stagnation_count // 0' "$run_dir/iterations/iter-001/meta.json" 2>/dev/null)" || sc1=0
    if [[ "$sc1" -eq 0 ]]; then
      _pass "happy stagnation_count: exit_reason=done, stagnation_count=0"
    else
      _fail "happy stagnation_count: expected sc=0, got $sc1"
    fi
  else
    _pass "happy stagnation_count: exit_reason=done (no jq, skipping sc check)"
  fi
else
  _fail "happy stagnation_count: expected exit_reason=done"
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
iter_dir="${run_dir}/iterations/iter-001"
reason="$(get_exit_reason "$run_dir" 2>/dev/null)"
stdout_ok=0
# stream-json 模式：provider.stdout.log 含 result 事件，is_error=false
[[ -f "$iter_dir/provider.stdout.log" ]] && \
  grep -E '^\{' "$iter_dir/provider.stdout.log" 2>/dev/null \
  | jq -r 'select(.type == "result") | .is_error' 2>/dev/null \
  | grep -q '^false$' && stdout_ok=1
session_ok=0
grep -qE '"session_id":[[:space:]]*"[0-9a-f-]{36}"' "$iter_dir/meta.json" 2>/dev/null && session_ok=1
history_ok=0
# session.history.log 取代 chat.log + tools.log，含 user / assistant / thinking / tool-use / tool-result
[[ -f "$iter_dir/session.history.log" ]] && \
  grep -q '\[user\]' "$iter_dir/session.history.log" && \
  grep -q '\[assistant\]' "$iter_dir/session.history.log" && \
  grep -q '\[thinking\]' "$iter_dir/session.history.log" && \
  grep -q '\[tool-use name=' "$iter_dir/session.history.log" && \
  grep -q '\[tool-result name=' "$iter_dir/session.history.log" && history_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$stdout_ok" -eq 1 && "$session_ok" -eq 1 \
   && "$history_ok" -eq 1 ]]; then
  _pass "claude happy: exit 0, done, stream-json result event, session_id UUID, session.history.log derived"
else
  _fail "claude happy: rc=$rc reason=$reason stdout_ok=$stdout_ok session_ok=$session_ok history_ok=$history_ok"
fi
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
iter_dir="${run_dir}/iterations/iter-001"
jsonl_ok=0; capture_ok=0; history_ok=0
[[ -f "$iter_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$iter_dir/meta.json" 2>/dev/null && capture_ok=1
# session.history.log 含 thinking + 完整 tool_use input（不再过滤）
[[ -f "$iter_dir/session.history.log" ]] && \
  grep -q '\[user\]' "$iter_dir/session.history.log" \
  && grep -q '\[thinking\]' "$iter_dir/session.history.log" \
  && grep -q '\[tool-use name=Bash\]' "$iter_dir/session.history.log" \
  && grep -q '\[tool-result name=Bash\]' "$iter_dir/session.history.log" && history_ok=1
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
iter_dir="${run_dir}/iterations/iter-001"
jsonl_ok=0; capture_ok=0; src_ok=0; home_clean=1
[[ -f "$iter_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$iter_dir/meta.json" 2>/dev/null && capture_ok=1
# session_source_path 应在 custom_cfg/projects/ 下
src_path="$(jq -r '.session_source_path // ""' "$iter_dir/meta.json" 2>/dev/null)"
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
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude --max-iter 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
iter_dir="${run_dir}/iterations/iter-001"
jsonl_ok=0; warn_ok=0
[[ -f "$iter_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"fallback by mtime"' "$iter_dir/meta.json" 2>/dev/null && warn_ok=1
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
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude --max-iter 1 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"
iter_dir="${run_dir}/iterations/iter-001"
no_jsonl=0; warn_ok=0; empty_history_ok=0
[[ ! -f "$iter_dir/session.claude.jsonl" ]] && no_jsonl=1
grep -q '"capture_status": "warning"' "$iter_dir/meta.json" 2>/dev/null && warn_ok=1
# 派生视图文件存在但内容为空（warning 时不派生）
[[ -f "$iter_dir/session.history.log" && ! -s "$iter_dir/session.history.log" ]] && empty_history_ok=1
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
  local iter_dir="$1"
  # stream-json 模式：从 provider.stdout.log 末尾的 result 事件取 _received_effort
  grep -E '^\{' "$iter_dir/provider.stdout.log" 2>/dev/null \
    | jq -r 'select(.type == "result") | ._received_effort // ""' 2>/dev/null \
    | tail -1
}

echo ""
echo "-- SC-014-1: RALPH_EFFORT=low → --effort low"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_EFFORT=low \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; iter_dir="${run_dir}/iterations/iter-001"
rcv="$(get_received_effort "$iter_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "low" ]]; then
  _pass "SC-014-1 effort=low: --effort low received by mock-claude"
else
  _fail "SC-014-1 effort=low: expected low, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_EFFORT=medium → --effort medium"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_EFFORT=medium \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; iter_dir="${run_dir}/iterations/iter-001"
rcv="$(get_received_effort "$iter_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "medium" ]]; then
  _pass "SC-014-1 effort=medium: --effort medium received by mock-claude"
else
  _fail "SC-014-1 effort=medium: expected medium, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_EFFORT=high → --effort high"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_EFFORT=high \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; iter_dir="${run_dir}/iterations/iter-001"
rcv="$(get_received_effort "$iter_dir")"
if [[ "$rc" -eq 0 && "$rcv" == "high" ]]; then
  _pass "SC-014-1 effort=high: --effort high received by mock-claude"
else
  _fail "SC-014-1 effort=high: expected high, got rcv=$rcv rc=$rc"
fi
cleanup_claude_ws

echo ""
echo "-- SC-014-1: RALPH_EFFORT=none → --effort not passed"
setup_claude_workspace
printf '%s\n' "- [ ] Task A" > "$SETUP_CLAUDE_WS/.ralph/TASKS.md"
git -C "$SETUP_CLAUDE_WS" add . && git -C "$SETUP_CLAUDE_WS" commit -q -m "single task" 2>/dev/null || true
rc=0
RALPH_MOCK_CLAUDE_SCENARIO=happy RALPH_EFFORT=none \
  env PATH="$SETUP_CLAUDE_BIN:$PATH" HOME="$SETUP_CLAUDE_HOME" \
  bash "$SETUP_CLAUDE_WS/.ralph/bin/ralph" run --provider claude 2>/dev/null || rc=$?
run_dir="$(latest_run_dir "$SETUP_CLAUDE_WS")"; iter_dir="${run_dir}/iterations/iter-001"
rcv="$(get_received_effort "$iter_dir")"
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
if [[ "$rc" -eq 0 && "$run_help_out" == *"--provider"* && "$run_help_out" == *"--max-iter"* ]]; then
  _pass "ralph run --help: exit 0, contains flag names"
else
  _fail "ralph run --help: rc=$rc out=$run_help_out"
fi

# ────────────────────────────────
# SC-023: status 集成测试（QA-1）
# ────────────────────────────────

echo ""
echo "-- SC-023-1: ralph status plain text — all 14 field labels + checked progress"
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
  "iteration": 3,
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
for f in run_id: run_dir: workspace: provider: model: effort: started_at: updated_at: iteration: iteration_name: state: tasks: exit_reason: last_error:; do
  if [[ "$status_out" != *"$f"* ]]; then
    fields_ok=0
    break
  fi
done
checked_ok=0
[[ "$status_out" == *"2 / 5 checked"* ]] && checked_ok=1
if [[ "$rc" -eq 0 && "$fields_ok" -eq 1 && "$checked_ok" -eq 1 ]]; then
  _pass "SC-023-1: 14 field labels + '2 / 5 checked' present, exit 0"
else
  _fail "SC-023-1: rc=$rc fields_ok=$fields_ok checked_ok=$checked_ok"
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
  "iteration": 3,
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
echo "-- SC-024-2: watch run_id switch separator + tail target switch"
ws=$(setup_workspace)
cat > "$ws/.ralph/status.json" <<'SJEOF'
{
  "run_id": "20260501-120000-aaa1111",
  "run_dir": ".ralph/runs/20260501-120000-aaa1111",
  "workspace": "/tmp/test-ws",
  "provider": "fake",
  "model": "test",
  "effort": "high",
  "started_at": "2026-05-01T12:00:00Z",
  "updated_at": "2026-05-01T12:01:00Z",
  "iteration": 1,
  "iteration_name": "I1",
  "state": "running",
  "tasks_total": 2,
  "tasks_checked": 0,
  "exit_reason": null,
  "last_error": null
}
SJEOF
run_a_dir="$ws/.ralph/runs/20260501-120000-aaa1111/iterations/iter-001"
mkdir -p "$run_a_dir"
echo "log from run A" > "$run_a_dir/log"
# Source libs and init watch state (direct function test)
# shellcheck source=/dev/null
source "$REPO_ROOT/.ralph/lib/status.sh"
# shellcheck source=/dev/null
source "$REPO_ROOT/.ralph/lib/watch.sh"
_RALPH_TAIL_OFFSET=0
_RALPH_TAIL_PREV_PATH=""
_RALPH_WATCH_RUN_ID=""
tmpout=$(mktemp)
# Frame 1: establish run A, tail its iter log
_ralph_watch_tail_draw "$ws" "$ws/.ralph/status.json" >> "$tmpout"
# Switch to run B
cat > "$ws/.ralph/status.json" <<'SJEOF'
{
  "run_id": "20260501-130000-bbb2222",
  "run_dir": ".ralph/runs/20260501-130000-bbb2222",
  "workspace": "/tmp/test-ws",
  "provider": "fake",
  "model": "test",
  "effort": "high",
  "started_at": "2026-05-01T13:00:00Z",
  "updated_at": "2026-05-01T13:01:00Z",
  "iteration": 1,
  "iteration_name": "I1",
  "state": "running",
  "tasks_total": 3,
  "tasks_checked": 1,
  "exit_reason": null,
  "last_error": null
}
SJEOF
run_b_dir="$ws/.ralph/runs/20260501-130000-bbb2222/iterations/iter-001"
mkdir -p "$run_b_dir"
echo "log from run B" > "$run_b_dir/log"
# Frame 2: run_id changed → separator + new tail target
_ralph_watch_tail_draw "$ws" "$ws/.ralph/status.json" >> "$tmpout"
separator_ok=0; log_a_ok=0; log_b_ok=0; trunc_ok=0
grep -q "─── new run:" "$tmpout" && separator_ok=1
grep -q "log from run A" "$tmpout" && log_a_ok=1
grep -q "log from run B" "$tmpout" && log_b_ok=1
grep -q "20260501-130\.\.\." "$tmpout" && trunc_ok=1
if [[ "$separator_ok" -eq 1 && "$log_a_ok" -eq 1 && "$log_b_ok" -eq 1 && "$trunc_ok" -eq 1 ]]; then
  _pass "SC-024-2: run_id switch → separator + truncated id + both iter logs"
else
  _fail "SC-024-2: sep=$separator_ok logA=$log_a_ok logB=$log_b_ok trunc=$trunc_ok"
fi
rm -f "$tmpout"
cleanup_ws "$ws"

echo ""
echo "-- SC-024-4: watch non-TTY fallback → status output + exit 0"
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
  "iteration": 3,
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
has_fields=0
if echo "$watch_out" | grep -q "run_id:" && echo "$watch_out" | grep -q "state:"; then
  has_fields=1
fi
if [[ "$rc" -eq 0 && "$has_fields" -eq 1 ]]; then
  _pass "SC-024-4: watch non-TTY → status-like output, exit 0"
else
  _fail "SC-024-4: rc=$rc has_fields=$has_fields"
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
# 验证未调用 provider（无 iter-001 目录或 iter 目录中无 log）
if [[ ! -d "$run_dir/iterations/iter-001" ]]; then
  _pass "blocked_by_human: no iteration directory created (provider not called)"
else
  _fail "blocked_by_human: iteration directory created (should not call provider)"
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
