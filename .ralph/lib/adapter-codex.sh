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
# Codex session 采集（DEV-3）：
# 1. 精确匹配：按 thread_id 在 ${CODEX_HOME:-$HOME/.codex}/sessions/ 下查找 rollout 文件名
# 2. mtime + cwd 退化：若无 thread_id 或精确匹配失败，按 mtime + 首行 cwd 筛选
# 3. 派生 session.history.log（从 provider.stdout.log --json 事件流）
provider_collect_session() {
  local iter_dir="$1"
  local meta="$iter_dir/meta.json"

  # 读取 session_id（thread_id，由 provider_oneshot 写入 meta.json）
  local session_id
  session_id="$(jq -r '.session_id // empty' "$meta" 2>/dev/null)"
  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    update_meta_jq "$iter_dir" \
      '.capture_status = "warning" | .capture_warning = "session_id missing in meta.json"'
    touch "$iter_dir/session.history.log"
    return 0
  fi

  # Session root（SC-022-5：使用 CODEX_HOME 隔离路径，不读真实 HOME）
  local codex_session_root="${CODEX_HOME:-$HOME/.codex}/sessions"
  local dst="$iter_dir/session.codex.jsonl"

  # ── Strategy 1: 按 thread_id 精确匹配文件名 ────────────────────────────────
  local found_file=""
  if [[ -d "$codex_session_root" ]]; then
    found_file="$(find "$codex_session_root" -type f -name "rollout-*-${session_id}.jsonl" 2>/dev/null | head -1)" || found_file=""
  fi

  if [[ -n "$found_file" && -f "$found_file" ]]; then
    cp "$found_file" "$dst"
    update_meta_jq "$iter_dir" \
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
      update_meta_jq "$iter_dir" \
        '.capture_status = "ok" | .capture_warning = "fallback by mtime" | .session_source_path = $src | .session_copied_path = $dst' \
        --arg src "$fallback_file" --arg dst "$dst"
    else
      update_meta_jq "$iter_dir" \
        '.capture_status = "warning" | .capture_warning = "Codex session file not found"'
    fi
  fi

  # 派生 session.history.log
  if [[ -f "$dst" ]]; then
    _codex_derive_history "$dst" "$iter_dir/session.history.log"
  fi
  touch "$iter_dir/session.history.log"
  return 0
}

# ── _codex_derive_history ────────────────────────────────────────────────────
# 从 provider.stdout.log（--json stdout 事件流）派生人话视图
# Codex rollout 文件是内部格式，可能跨版本变化；--json 事件流有文档化契约
# 输出：[user] / [assistant] / [tool-use name=X] / [tool-result name=X] 摘要
_codex_derive_history() {
  local jsonl="$1" out="$2"
  local iter_dir="${jsonl%/*}"
  local stdout_log="$iter_dir/provider.stdout.log"
  [[ -f "$stdout_log" ]] || return 0

  # 过滤 JSON 行（provider.stdout.log 含 stdout + stderr 合流）
  local jsonl_events
  jsonl_events="$(grep -E '^[[:space:]]*\{' "$stdout_log" 2>/dev/null)" || return 0
  [[ -n "$jsonl_events" ]] || return 0

  printf '%s\n' "$jsonl_events" | jq -r --slurp '
    def tool_input_summary:
      (if type == "string" then try fromjson catch . else . end) as $parsed |
      ($parsed | tostring) as $s |
      if ($s | length) > 4000 then
        ($s[0:2000] + "\n... [tool input truncated; see session.codex.jsonl for full input]\n" + $s[-1000:])
      else $s end;

    # call_id → name map（从 function_call 项提取，供 tool-result 标注）
    ([.[] | select(.type == "item.completed" and .item.type == "function_call")
      | {(.item.call_id // .item.id // ""): .item.name}] | add // {}) as $call_map |

    .[] | select(.type == "item.completed") |
    .item as $item |

    if $item.type == "message" then
      if $item.role == "user" then
        ($item.content // []) |
        if type == "array" then .[] else . end |
        if .type == "input_text" or .type == "text" then
          (.text // "") as $t |
          if ($t | length) > 0 then "[user]", $t, "" else empty end
        else empty end
      elif $item.role == "assistant" then
        ($item.content // []) |
        if type == "array" then .[] else . end |
        if .type == "output_text" or .type == "text" then
          (.text // "") as $t |
          if ($t | length) > 0 then "[assistant]", $t, "" else empty end
        else empty end
      else empty end
    elif $item.type == "function_call" then
      "[tool-use name=" + ($item.name // "?") + "]",
      ($item.arguments // "{}" | tool_input_summary),
      ""
    elif $item.type == "function_call_output" then
      "[tool-result name=" + ($call_map[$item.call_id // ""] // "unknown") + "]",
      (($item.output // "") | .[0:2000]),
      ""
    else empty end
  ' > "$out" 2>/dev/null || true
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
