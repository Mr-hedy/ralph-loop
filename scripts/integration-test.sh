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
[[ -f "$iter_dir/session.claude.stdout.json" ]] && \
  grep -q '"is_error":false' "$iter_dir/session.claude.stdout.json" 2>/dev/null && stdout_ok=1
session_ok=0
grep -qE '"session_id":[[:space:]]*"[0-9a-f-]{36}"' "$iter_dir/meta.json" 2>/dev/null && session_ok=1
chat_ok=0
[[ -f "$iter_dir/chat.log" ]] && \
  grep -q '\[user\]' "$iter_dir/chat.log" && \
  grep -q '\[assistant\]' "$iter_dir/chat.log" && \
  grep -q '\[tool-result name=' "$iter_dir/chat.log" && \
  ! grep -q '\[thinking\]' "$iter_dir/chat.log" && chat_ok=1
tools_ok=0
[[ -f "$iter_dir/tools.log" ]] && grep -q 'Bash' "$iter_dir/tools.log" && tools_ok=1
if [[ "$rc" -eq 0 && "$reason" == "done" && "$stdout_ok" -eq 1 && "$session_ok" -eq 1 \
   && "$chat_ok" -eq 1 && "$tools_ok" -eq 1 ]]; then
  _pass "claude happy: exit 0, done, stdout.json ok, session_id UUID, chat.log+tools.log derived"
else
  _fail "claude happy: rc=$rc reason=$reason stdout_ok=$stdout_ok session_ok=$session_ok chat_ok=$chat_ok tools_ok=$tools_ok"
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
jsonl_ok=0; capture_ok=0; chat_ok=0; tools_ok=0
[[ -f "$iter_dir/session.claude.jsonl" ]] && jsonl_ok=1
grep -q '"capture_status": "ok"' "$iter_dir/meta.json" 2>/dev/null && capture_ok=1
[[ -f "$iter_dir/chat.log" ]] && grep -q '\[user\]' "$iter_dir/chat.log" \
  && grep -q '\[tool-result name=' "$iter_dir/chat.log" \
  && ! grep -q '\[thinking\]' "$iter_dir/chat.log" && chat_ok=1
[[ -f "$iter_dir/tools.log" ]] && grep -q 'Bash' "$iter_dir/tools.log" && tools_ok=1
if [[ "$jsonl_ok" -eq 1 && "$capture_ok" -eq 1 && "$chat_ok" -eq 1 && "$tools_ok" -eq 1 ]]; then
  _pass "session collect happy: jsonl ok, capture_status=ok, chat.log+tools.log derived"
else
  _fail "session collect happy: jsonl_ok=$jsonl_ok capture_ok=$capture_ok chat_ok=$chat_ok tools_ok=$tools_ok"
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
no_jsonl=0; warn_ok=0; empty_views_ok=0
[[ ! -f "$iter_dir/session.claude.jsonl" ]] && no_jsonl=1
grep -q '"capture_status": "warning"' "$iter_dir/meta.json" 2>/dev/null && warn_ok=1
# 派生视图文件存在但内容为空（warning 时不派生）
[[ -f "$iter_dir/chat.log" && ! -s "$iter_dir/chat.log" ]] && \
  [[ -f "$iter_dir/tools.log" && ! -s "$iter_dir/tools.log" ]] && empty_views_ok=1
if [[ "$no_jsonl" -eq 1 && "$warn_ok" -eq 1 && "$empty_views_ok" -eq 1 ]]; then
  _pass "session missing: no session.claude.jsonl, capture_status=warning, empty chat/tools logs"
else
  _fail "session missing: no_jsonl=$no_jsonl warn_ok=$warn_ok empty_views_ok=$empty_views_ok"
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
if [[ "$rc" -eq 0 && "$version_out" == *"0.1.0-dev"* ]]; then
  _pass "ralph --version: exit 0, contains 0.1.0-dev"
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

echo ""
echo "-- ralph status (not implemented, exit 0 with placeholder help)"
rc=0
status_out=$(bash "$REPO_ROOT/.ralph/bin/ralph" status 2>/dev/null) || rc=$?
if [[ "$rc" -eq 0 && "$status_out" == *"v0.1"* ]]; then
  _pass "ralph status: exit 0, contains 'v0.1'"
else
  _fail "ralph status: rc=$rc out=$status_out"
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
