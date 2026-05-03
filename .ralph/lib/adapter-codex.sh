#!/usr/bin/env bash
# adapter-codex.sh — Codex CLI provider adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数契约
# --json 模式：stdout 是 JSONL events 流，逐行写入 provider.stdout.log
# session 文件命名遵循 docs/architecture/integrations.md §Session 文件命名约定

RALPH_PROVIDER_CLI="codex"

# ── 中立变量 → provider 原生变量翻译（adapter 配置目录翻译契约，SC-022-4）──
# 由 ralph load_env 保证 RALPH_PROVIDER_CONFIG_DIR 已 export 且 tilde 已展开。
# 仅在变量非空时才 export，避免空 CODEX_HOME 干扰 codex CLI 默认行为。
if [[ -n "${RALPH_PROVIDER_CONFIG_DIR:-}" ]]; then
  export CODEX_HOME="$RALPH_PROVIDER_CONFIG_DIR"
fi

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd codex "Codex CLI" \
    "npm install -g @openai/codex"
  ralph_require_cmd jq "parse Codex JSON output" \
    $'macOS: brew install jq\nLinux: apt install jq'
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <iter_dir>
# log_path 即 iter_dir/provider.stdout.log，--json JSONL events 逐行写入
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local iter_dir="$3"

  local provider_started_at
  provider_started_at="$(ralph_timestamp)"
  update_meta_jq "$iter_dir" '.provider_started_at = $ts' --arg ts "$provider_started_at"

  touch "$log_path"

  # ARG_MAX guard：命令行参数上限约 1MB；prompt 过大时报清晰错误而非静默崩溃
  local _prompt_size
  _prompt_size="$(wc -c < "$prompt_file" 2>/dev/null)" || _prompt_size=0
  if [[ "${_prompt_size:-0}" -gt 900000 ]]; then
    printf 'ralph: prompt file too large (%s bytes); keep PROMPT.md under 900KB\n' "$_prompt_size" >&2
    return 1
  fi

  # Codex exec 命令构造（DEV-1 校准后契约）
  # --json: JSONL events to stdout (thread.started / turn.started / item.started /
  #         item.completed / turn.completed / turn.failed / error)
  # -C <workspace>: workspace root
  # --sandbox workspace-write: sandbox mode（替代已废弃的 --full_auto）
  # -c model_reasoning_effort=<value>: effort（none/空 → 不拼 flag）
  # --model <value>: model selection（空 → 不拼 flag）
  local effort="${RALPH_EFFORT:-}"
  local model="${RALPH_MODEL:-}"
  local -a codex_cmd
  codex_cmd=(
    codex exec --json
    -C "${RALPH_WORKSPACE:-.}"
    --sandbox workspace-write
  )
  if [[ -n "$model" ]]; then
    codex_cmd+=(--model "$model")
  fi
  if [[ -n "$effort" && "$effort" != "none" ]]; then
    codex_cmd+=(-c "model_reasoning_effort=$effort")
  fi
  codex_cmd+=("$(cat "$prompt_file")")

  local rc=0
  # stdout + stderr 合并写入 provider.stdout.log
  "${codex_cmd[@]}" > "$log_path" 2>>"$log_path" || rc=$?

  # 从 stdout JSONL 解析 thread_id（session_id 等价物，用于 DEV-3 session 采集）
  local thread_id=""
  if [[ -f "$log_path" ]]; then
    thread_id="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
      | jq -r 'select(.type == "thread.started") | .thread_id // empty' 2>/dev/null \
      | head -1)" || thread_id=""
  fi
  if [[ -n "$thread_id" ]]; then
    update_meta_jq "$iter_dir" '.session_id = $sid' --arg sid "$thread_id"
  fi

  # Codex turn.failed 事件检测（相当于 Claude 的 result.is_error）
  # turn.failed 是最终权威失败事件（integrations.md §错误诊断）
  if [[ "$rc" -eq 0 && -f "$log_path" ]]; then
    local _has_failure
    _has_failure="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
      | jq -r 'select(.type == "turn.failed") | .type // empty' 2>/dev/null \
      | head -1)" || _has_failure=""
    [[ -n "$_has_failure" ]] && rc=1
  fi

  return "$rc"
}

# ── provider_collect_session ─────────────────────────────────────────────────
# DEV-3 实现完整 session 采集（thread_id 精确匹配 / mtime fallback / history 派生）
# 本版为 stub：保证函数存在、写空 session.history.log、meta capture_status = pending
provider_collect_session() {
  local iter_dir="$1"
  touch "$iter_dir/session.history.log"
  local meta="$iter_dir/meta.json"
  if [[ -f "$meta" ]]; then
    update_meta_jq "$iter_dir" \
      '.capture_status = "pending" | .capture_warning = "session capture stub (DEV-3)"' 2>/dev/null || true
  fi
  return 0
}

# ── provider_diagnose ────────────────────────────────────────────────────────
# DEV-4 实现完整 Codex 错误分类（turn.failed / error 事件关键字匹配）
# 本版为 stub：exit_code 非 0 写 unknown 错误，exit_code=0 不写 error
provider_diagnose() {
  local iter_dir="$1"
  local meta="$iter_dir/meta.json"
  [[ -f "$meta" ]] || return 0

  local exit_code=0
  exit_code="$(jq -r '.exit_code // 0' "$meta" 2>/dev/null)" || exit_code=0

  if [[ "$exit_code" -ne 0 ]]; then
    update_meta_jq "$iter_dir" \
      '.error = {"type": "unknown", "message": "provider exited non-zero (diagnose stub, DEV-4)", "raw": ""}'
  fi
  return 0
}
