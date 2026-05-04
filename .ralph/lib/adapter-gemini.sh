#!/usr/bin/env bash
# adapter-gemini.sh — Gemini CLI provider adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数契约
# stream-json 模式：stdout 是 JSONL events 流，逐行写入 provider.stdout.log
# session 文件命名遵循 docs/architecture/integrations.md §iter 目录文件结构

RALPH_PROVIDER_CLI="gemini"

# ── 中立变量 → provider 原生变量翻译（adapter 配置目录翻译契约，REQ-022）──
# 由 ralph load_env 保证 RALPH_PROVIDER_CONFIG_DIR 已 export 且 tilde 已展开。
# 仅在变量非空时才 export，避免空 GEMINI_CLI_HOME 干扰 gemini CLI 默认行为。
if [[ -n "${RALPH_PROVIDER_CONFIG_DIR:-}" ]]; then
  export GEMINI_CLI_HOME="$RALPH_PROVIDER_CONFIG_DIR"
fi

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd gemini "Gemini CLI" \
    "npm install -g @google/gemini-cli"
  ralph_require_cmd jq "parse Gemini JSON output" \
    $'macOS: brew install jq\nLinux: apt install jq'
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <iter_dir>
# log_path 即 iter_dir/provider.stdout.log，stream-json events 逐行写入
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

  # Gemini oneshot 命令构造（I4 DEV-1 校准后契约）
  # -p <prompt>: inline prompt（non-interactive，与 Claude -p / Codex exec 等价）
  # --approval-mode=yolo: auto-approve（替代已废弃的 --yolo，见 integrations.md §Gemini CLI）
  # --output-format stream-json: JSONL events 流（与 Claude/Codex 对齐）
  # --model <value>: model selection（空 → 不拼 flag）
  # 不传 --thinking-budget（不是 CLI flag；thinkingBudget 仅在 settings.json 的 modelConfigs 内）
  # 不传 --resume（ralph 默认 fresh oneshot）
  # effort 不传递（Gemini CLI 无 CLI 入口，见 integrations.md §Gemini Effort 映射）
  local model="${RALPH_MODEL:-}"
  local -a gemini_cmd
  gemini_cmd=(
    gemini -p "$(cat "$prompt_file")"
    --approval-mode yolo
    --output-format stream-json
  )
  if [[ -n "$model" ]]; then
    gemini_cmd+=(--model "$model")
  fi

  local rc=0
  # stdout + stderr 合并写入 provider.stdout.log
  "${gemini_cmd[@]}" > "$log_path" 2>>"$log_path" || rc=$?

  # 从 stream-json init 事件解析 session_id（session 采集精确匹配锚点）
  # grep `^\{`：只匹配列首 {（真实 stream-json 事件）；跳过 stderr 中缩进的 { 噪音行
  if [[ -f "$log_path" ]]; then
    local _gemini_sid=""
    _gemini_sid="$(grep -E '^\{' "$log_path" 2>/dev/null \
      | jq -r 'select(.type == "init") | (.session_id // .sessionId // empty)' 2>/dev/null \
      | head -1)" || _gemini_sid=""
    if [[ -n "$_gemini_sid" ]]; then
      update_meta_jq "$iter_dir" '.session_id = $sid' --arg sid "$_gemini_sid"
    fi
  fi

  return "$rc"
}

# ── _gemini_derive_history ────────────────────────────────────────────────────
# 从 provider.stdout.log（stream-json 事件流）派生人话视图
# 真实 CLI 事件类型（QA-2 验证）：init / message / result / tool_use / tool_result
# 输出：[assistant] 文本摘要
_gemini_derive_history() {
  local session_file="$1" out="$2"
  local iter_dir="${session_file%/*}"
  local stdout_log="$iter_dir/provider.stdout.log"
  [[ -f "$stdout_log" ]] || return 0

  # 过滤 JSON 行：只匹配列首 {（真实 stream-json 事件）
  local jsonl_events
  jsonl_events="$(grep -E '^\{' "$stdout_log" 2>/dev/null)" || return 0
  [[ -n "$jsonl_events" ]] || return 0

  printf '%s\n' "$jsonl_events" | jq -r --slurp '
    .[] |
    if .type == "message" and (.role // "") == "assistant" and (.text // "") != "" then
      "[assistant]",
      .text,
      ""
    elif .type == "result" and (.text // "") != "" then
      "[assistant]",
      .text,
      ""
    else empty end
  ' > "$out" 2>/dev/null || true
}

# ── provider_collect_session ─────────────────────────────────────────────────
# Gemini session 采集（DEV-3）：
# 1. 精确匹配：按 session_id 在 ${GEMINI_CLI_HOME:-$HOME}/.gemini/tmp/*/chats/ 下查找 sessionId 匹配的 JSON 文件
# 2. mtime 退化：按 provider_started_at 时间戳筛选，取 mtime 最新
# 3. 派生 session.history.log（从 provider.stdout.log stream-json 事件流）
provider_collect_session() {
  local iter_dir="$1"
  local meta="$iter_dir/meta.json"
  local gemini_root="${GEMINI_CLI_HOME:-$HOME}/.gemini"
  local dst="$iter_dir/session.gemini.json"

  # 读取 session_id（从 init 事件，由 provider_oneshot 写入 meta.json）
  local session_id
  session_id="$(jq -r '.session_id // empty' "$meta" 2>/dev/null)"

  local found_file=""

  # ── Strategy 1: 按 session_id 精确匹配 JSON 文件内容 ────────────────────────
  if [[ -n "$session_id" && "$session_id" != "null" && -d "$gemini_root/tmp" ]]; then
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      local file_sid
      file_sid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)" || continue
      if [[ "$file_sid" == "$session_id" ]]; then
        found_file="$f"
        break
      fi
    done < <(find "$gemini_root/tmp" -path '*/chats/*.json' -type f 2>/dev/null)
  fi

  if [[ -n "$found_file" && -f "$found_file" ]]; then
    cp "$found_file" "$dst"
    update_meta_jq "$iter_dir" \
      '.capture_status = "ok" | .session_source_path = $src | .session_copied_path = $dst' \
      --arg src "$found_file" --arg dst "$dst"
  else
    # ── Strategy 2: mtime fallback ──────────────────────────────────────────
    local fallback_file=""
    local started_at
    started_at="$(jq -r '.provider_started_at // empty' "$meta" 2>/dev/null)"

    if [[ -n "$started_at" && "$started_at" != "null" && -d "$gemini_root/tmp" ]]; then
      local started_epoch buffered_iso anchor_local
      started_epoch="$(ralph_iso_to_epoch "$started_at")"
      if [[ -n "$started_epoch" ]]; then
        buffered_iso="$(ralph_epoch_to_iso $((started_epoch - 1)))"
        anchor_local="$(ralph_iso_to_local_find_fmt "$buffered_iso")"
        if [[ -n "$anchor_local" ]]; then
          local mtime_candidates=""
          mtime_candidates="$(find "$gemini_root/tmp" -path '*/chats/*.json' -type f \
            -newermt "$anchor_local" 2>/dev/null)" || mtime_candidates=""
          if [[ -n "$mtime_candidates" ]]; then
            fallback_file="$(echo "$mtime_candidates" | xargs ls -1t 2>/dev/null | head -1)"
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
      local warning_msg="Gemini session file not found"
      if [[ -z "$session_id" || "$session_id" == "null" ]]; then
        warning_msg="session_id missing in meta.json"
      fi
      update_meta_jq "$iter_dir" \
        '.capture_status = "warning" | .capture_warning = $msg' \
        --arg msg "$warning_msg"
    fi
  fi

  # 派生 session.history.log（从 provider.stdout.log 事件流，不依赖 session 文件）
  _gemini_derive_history "$dst" "$iter_dir/session.history.log"
  touch "$iter_dir/session.history.log"
  return 0
}

# ── _gemini_classify_error ───────────────────────────────────────────────────
# 输入：error message 原文；输出：错误分类标签（互斥优先级，见 integrations.md §错误诊断（续 Gemini））
_gemini_classify_error() {
  local text="${1:-}"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if   [[ "$lower" == *" 401"* || "$lower" == *"unauthor"* || "$lower" == *"not logged in"* ]]; then
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
# Gemini 错误分类（error 事件 / stderr 关键字回退）
provider_diagnose() {
  local iter_dir="$1"
  local meta="$iter_dir/meta.json"
  local log_path="$iter_dir/provider.stdout.log"

  [[ -f "$meta" ]] || return 0

  local exit_code
  exit_code="$(jq -r '.exit_code // 0' "$meta" 2>/dev/null)" || exit_code=0

  # exit_code=0 → 正常完成，不写 error
  if [[ "$exit_code" -eq 0 ]]; then
    return 0
  fi

  # log 文件不存在（CLI crash 无输出）→ unknown
  if [[ ! -f "$log_path" ]]; then
    update_meta_jq "$iter_dir" \
      '.error = {"type": "unknown", "message": "no stdout log file", "raw": ""}'
    return 0
  fi

  # 优先查找 error 事件（stream-json 结构化错误）
  local error_msg=""
  local error_event
  error_event="$(grep -E '^\{' "$log_path" 2>/dev/null \
    | jq -c 'select(.type == "error")' 2>/dev/null \
    | tail -1)" || error_event=""

  if [[ -n "$error_event" ]]; then
    error_msg="$(printf '%s' "$error_event" \
      | jq -r 'if .error | type == "object" then .error.message // "" elif .error | type == "string" then .error else .message // "" end' 2>/dev/null)" || error_msg=""
  fi

  # 回退：从 stderr 非 JSON 行提取
  if [[ -z "$error_msg" ]]; then
    error_msg="$(grep -vE '^\{' "$log_path" 2>/dev/null | head -5 | tr '\n' ' ')" || error_msg=""
  fi

  local error_type
  error_type="$(_gemini_classify_error "${error_msg:-}")"

  update_meta_jq "$iter_dir" \
    '.error = {"type": $t, "message": $m, "raw": $r}' \
    --arg t "$error_type" \
    --arg m "${error_msg:0:200}" \
    --arg r "${error_msg:0:500}"
  return 0
}
