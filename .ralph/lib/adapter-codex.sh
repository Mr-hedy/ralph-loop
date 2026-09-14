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
# <prompt_file> <log_path> <round_dir>
# log_path 即 round_dir/provider.stdout.log，--json JSONL events 逐行写入
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local round_dir="$3"

  local provider_started_at
  provider_started_at="$(ralph_timestamp)"
  update_meta_jq "$round_dir" '.provider_started_at = $ts' --arg ts "$provider_started_at"

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
  # --sandbox danger-full-access: ralph oneshot protocol requires git add/commit;
  # workspace-write cannot create .git/index.lock in real Codex CLI runs.
  # -c model_reasoning_effort=<value>: effort（none/空 → 不拼 flag）
  # --model <value>: model selection（空 → 不拼 flag）
  local effort="${RALPH_PROVIDER_EFFORT:-}"
  local model="${RALPH_PROVIDER_MODEL:-}"
  local -a codex_cmd
  codex_cmd=(
    codex exec --json
    -C "${RALPH_WORKSPACE:-.}"
    --sandbox danger-full-access
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
    update_meta_jq "$round_dir" '.session_id = $sid' --arg sid "$thread_id"
  fi

  # Preserve the structured terminal event separately from the raw log. The
  # raw provider.stdout.log remains the source of truth if the stream is cut.
  local terminal_event terminal_status
  terminal_event="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
    | jq -r 'select(.type == "turn.completed" or .type == "turn.failed" or .type == "error") | .type' 2>/dev/null | tail -1)" || terminal_event=""
  case "$terminal_event" in
    turn.completed) terminal_status="success" ;;
    turn.failed|error) terminal_status="error" ;;
    *) terminal_status="" ;;
  esac
  if [[ -n "$terminal_event" ]]; then
    update_meta_jq "$round_dir" '.terminal_event = $e | .terminal_status = $s' \
      --arg e "$terminal_event" --arg s "$terminal_status"
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
# Codex session 采集（DEV-3）：
# 1. 精确匹配：按 thread_id 在 ${CODEX_HOME:-$HOME/.codex}/sessions/ 下查找 rollout 文件名
# 2. mtime + cwd 退化：若无 thread_id 或精确匹配失败，按 mtime + 首行 cwd 筛选
# 3. 派生 session.history.log（从 provider.stdout.log --json 事件流）
provider_collect_session() {
  local round_dir="$1"
  local meta="$round_dir/meta.json"

  # 读取 session_id（thread_id，由 provider_oneshot 写入 meta.json）
  local session_id
  session_id="$(jq -r '.session_id // empty' "$meta" 2>/dev/null)"
  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    update_meta_jq "$round_dir" \
      '.capture_status = "warning" | .capture_warning = "session_id missing in meta.json"'
    _codex_derive_history "$round_dir/session.codex.jsonl" "$round_dir/session.history.log"
    touch "$round_dir/session.history.log"
    return 0
  fi

  # Session root（SC-022-5：使用 CODEX_HOME 隔离路径，不读真实 HOME）
  local codex_session_root="${CODEX_HOME:-$HOME/.codex}/sessions"
  local dst="$round_dir/session.codex.jsonl"

  # ── Strategy 1: 按 thread_id 精确匹配文件名 ────────────────────────────────
  local found_file=""
  if [[ -d "$codex_session_root" ]]; then
    found_file="$(find "$codex_session_root" -type f -name "rollout-*-${session_id}.jsonl" 2>/dev/null | head -1)" || found_file=""
  fi

  # Also inspect archived rollouts and validate the embedded id. Newer Codex
  # builds maintain additional metadata layers, so filename-only matching is
  # intentionally not the sole capture strategy.
  if [[ -z "$found_file" ]]; then
    local codex_root="${CODEX_HOME:-$HOME/.codex}"
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      local embedded_id
      embedded_id="$(head -1 "$candidate" 2>/dev/null | jq -r '.payload.id // .payload.thread_id // empty' 2>/dev/null)" || embedded_id=""
      if [[ "$embedded_id" == "$session_id" ]]; then
        found_file="$candidate"
        break
      fi
    done < <(find "$codex_root/sessions" "$codex_root/archived_sessions" -type f -name 'rollout-*.jsonl' 2>/dev/null)
  fi

  if [[ -n "$found_file" && -f "$found_file" ]]; then
    cp "$found_file" "$dst"
    update_meta_jq "$round_dir" \
      '.capture_status = "ok" | .session_source_path = $src | .session_copied_path = $dst' \
      --arg src "$found_file" --arg dst "$dst"
  else
    # ── Strategy 2: mtime + cwd 退化 ──────────────────────────────────────────
    local started_at
    started_at="$(jq -r '.provider_started_at // empty' "$meta" 2>/dev/null)"
    local fallback_file=""

    if [[ -n "$started_at" && "$started_at" != "null" && -d "$codex_session_root" ]]; then
      local started_epoch buffered_iso anchor_local
      started_epoch="$(ralph_iso_to_epoch "$started_at")"
      if [[ -n "$started_epoch" ]]; then
        buffered_iso="$(ralph_epoch_to_iso $((started_epoch - 1)))"
        anchor_local="$(ralph_iso_to_local_find_fmt "$buffered_iso")"
        if [[ -n "$anchor_local" ]]; then
          local candidates
          candidates="$(find "$codex_session_root" -type f -name "rollout-*.jsonl" \
            -newermt "$anchor_local" 2>/dev/null)" || candidates=""

          if [[ -n "$candidates" ]]; then
            # 优先匹配首行 session_meta.payload.cwd == workspace
            local workspace="${_RALPH_WORKSPACE:-$(ralph_workspace_root)}"
            for f in $candidates; do
              local first_line_cwd
              first_line_cwd="$(head -1 "$f" 2>/dev/null | jq -r '.payload.cwd // empty' 2>/dev/null)" || continue
              if [[ "$first_line_cwd" == "$workspace" ]]; then
                fallback_file="$f"
                break
              fi
            done
            # 无 cwd 匹配 → 取 mtime 最新
            if [[ -z "$fallback_file" ]]; then
              fallback_file="$(echo "$candidates" | xargs ls -1t 2>/dev/null | head -1)"
            fi
          fi
        fi
      fi
    fi

    if [[ -n "$fallback_file" && -f "$fallback_file" ]]; then
      cp "$fallback_file" "$dst"
      update_meta_jq "$round_dir" \
        '.capture_status = "ok" | .capture_warning = "fallback by mtime" | .session_source_path = $src | .session_copied_path = $dst' \
        --arg src "$fallback_file" --arg dst "$dst"
    else
      update_meta_jq "$round_dir" \
        '.capture_status = "warning" | .capture_warning = "Codex session file not found"'
    fi
  fi

  # 派生 session.history.log（从 provider.stdout.log 事件流，不依赖 session 文件）
  _codex_derive_history "$dst" "$round_dir/session.history.log"
  touch "$round_dir/session.history.log"
  return 0
}

# ── _codex_derive_history ────────────────────────────────────────────────────
# 从 provider.stdout.log（--json stdout 事件流）派生人话视图
# 真实 Codex CLI --json 事件类型：agent_message / command_execution 等
# 输出：[assistant] / [tool-use name=Bash] / [tool-result name=Bash] 摘要
_codex_derive_history() {
  local jsonl="$1" out="$2"
  local round_dir="${jsonl%/*}"
  local stdout_log="$round_dir/provider.stdout.log"
  [[ -f "$stdout_log" ]] || return 0

  # 过滤 JSON 行（provider.stdout.log 含 stdout + stderr 合流）
  local jsonl_events
  jsonl_events="$(grep -E '^[[:space:]]*\{' "$stdout_log" 2>/dev/null)" || return 0
  [[ -n "$jsonl_events" ]] || return 0

  printf '%s\n' "$jsonl_events" | jq -r --slurp '
    .[] |
    if .type == "item.completed" and (.item.type // "") == "agent_message" then
      "[assistant]",
      (.item.text // ""),
      ""
    elif .type == "item.started" and (.item.type // "") == "command_execution" then
      "[tool-use name=Bash]",
      (.item.command // "" | if length > 4000 then .[0:2000] + "\n... [tool input truncated; see provider.stdout.log for full input]\n" + .[-1000:] else . end),
      ""
    elif .type == "item.completed" and (.item.type // "") == "command_execution" then
      "[tool-result name=Bash]",
      ((.item.output // .item.stdout // "") | .[0:2000]),
      ""
    else empty end
  ' > "$out" 2>/dev/null || true
}

# ── _codex_classify_error ───────────────────────────────────────────────────
# 输入：error message 原文；输出：错误分类标签（互斥优先级，见 integrations.md §错误诊断）
_codex_classify_error() {
  local text="${1:-}"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if   [[ "$lower" == *" 401"* || "$lower" == *"unauthor"* || "$lower" == *"invalid api key"* || "$lower" == *"not logged in"* ]]; then
    printf 'auth'
  elif [[ "$lower" == *" 429"* || "$lower" =~ rate.?limit || "$lower" == *"too many requests"* ]]; then
    printf 'rate_limit'
  elif [[ "$lower" == *"quota"* || "$lower" == *"credits exhausted"* || "$lower" == *"billing"* ]]; then
    printf 'quota'
  elif [[ "$lower" == *"econnreset"* || "$lower" == *"enotfound"* || "$lower" == *"etimedout"* \
      || "$lower" == *"connection refused"* || "$lower" == *"network error"* || "$lower" == *"fetch failed"* ]]; then
    printf 'network'
  elif [[ "$lower" =~ (^|[^0-9])5[0-9][0-9]([^0-9]|$) || "$lower" == *"api error"* || "$lower" == *"internal server"* || "$lower" == *"service unavailable"* ]]; then
    printf 'api'
  else
    printf 'unknown'
  fi
}

# ── provider_diagnose ────────────────────────────────────────────────────────
# Codex 错误分类（turn.failed 权威 / error 事件回退 / stderr 回退）
provider_diagnose() {
  local round_dir="$1"
  local meta="$round_dir/meta.json"
  local log_path="$round_dir/provider.stdout.log"

  [[ -f "$meta" ]] || return 0

  local exit_code
  exit_code="$(jq -r '.exit_code // 0' "$meta" 2>/dev/null)" || exit_code=0

  # exit_code=0 → 正常完成，不写 error
  if [[ "$exit_code" -eq 0 ]]; then
    return 0
  fi

  # log 文件不存在（CLI crash 无输出）→ unknown
  if [[ ! -f "$log_path" ]]; then
    update_meta_jq "$round_dir" \
      '.error = {"type": "unknown", "message": "no stdout log file", "raw": ""}'
    return 0
  fi

  # 优先查找 turn.failed 事件（最终权威，integrations.md §错误诊断）
  local error_msg=""
  local failed_event
  failed_event="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
    | jq -c 'select(.type == "turn.failed")' 2>/dev/null \
    | tail -1)" || failed_event=""

  if [[ -n "$failed_event" ]]; then
    error_msg="$(printf '%s' "$failed_event" \
      | jq -r 'if .error | type == "object" then .error.message // "" elif .error | type == "string" then .error else .message // "" end' 2>/dev/null)" || error_msg=""
  fi

  # 回退：查找 error 事件（可能被 retry 覆盖，但仍是线索）
  if [[ -z "$error_msg" ]]; then
    local error_event
    error_event="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
      | jq -c 'select(.type == "error")' 2>/dev/null \
      | tail -1)" || error_event=""

    if [[ -n "$error_event" ]]; then
      error_msg="$(printf '%s' "$error_event" \
        | jq -r 'if .error | type == "object" then .error.message // "" elif .error | type == "string" then .error else .message // "" end' 2>/dev/null)" || error_msg=""
    fi
  fi

  # 回退：从 stderr 非 JSON 行提取
  if [[ -z "$error_msg" ]]; then
    error_msg="$(grep -vE '^[[:space:]]*\{' "$log_path" 2>/dev/null | head -5 | tr '\n' ' ')" || error_msg=""
  fi

  local error_type
  error_type="$(_codex_classify_error "${error_msg:-}")"

  update_meta_jq "$round_dir" \
    '.error = {"type": $t, "message": $m, "raw": $r}' \
    --arg t "$error_type" \
    --arg m "${error_msg:0:200}" \
    --arg r "${error_msg:0:500}"
  return 0
}
