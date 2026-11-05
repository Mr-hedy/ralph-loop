#!/usr/bin/env bash
# adapter-antigravity.sh — Antigravity CLI (agy) provider adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数/四函数契约
# stream-json 模式：stdout 是 NDJSON 流，逐行写入 provider.stdout.log
# 会话文件存储于 ${ANTIGRAVITY_APP_DATA_DIR:-$HOME/.gemini/antigravity}/brain/<id>/

RALPH_PROVIDER_CLI="agy"

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd "${RALPH_PROVIDER_CLI:-agy}" "Antigravity CLI" \
    "See https://www.antigravity.google/docs/cli"
  ralph_require_cmd jq "parse Antigravity JSON output" \
    $'macOS: brew install jq\nLinux: apt install jq'

  # REQ-052: 显式设置 RALPH_PROVIDER_CONFIG_DIR 时，若无已验证的原生配置域覆盖方式，启动前失败
  if [[ -n "${RALPH_PROVIDER_CONFIG_DIR:-}" ]]; then
    printf 'ralph: startup check failed: provider antigravity does not support custom RALPH_PROVIDER_CONFIG_DIR (no verified config dir override for agy)\n' >&2
    return 1
  fi
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <round_dir>
# log_path 即 round_dir/provider.stdout.log，stream-json NDJSON events 逐行写入
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local round_dir="$3"

  local provider_started_at
  provider_started_at="$(ralph_timestamp)"
  update_meta_jq "$round_dir" '.provider_started_at = $ts' --arg ts "$provider_started_at"

  touch "$log_path"

  # ARG_MAX guard：命令行参数上限保护，PROMPT 过大时给出明确错误
  local _prompt_size
  _prompt_size="$(wc -c < "$prompt_file" 2>/dev/null)" || _prompt_size=0
  if [[ "${_prompt_size:-0}" -gt 900000 ]]; then
    printf 'ralph: prompt file too large (%s bytes); keep PROMPT.md under 900KB\n' "$_prompt_size" >&2
    return 1
  fi

  # agy print 命令构造（REQ-048 / REQ-049）
  # --output-format stream-json: 输出包含 init, step_update, result 的 NDJSON
  # --dangerously-skip-permissions: 自动批准工具调用，保证无人值守完成文件读写、测试与 git 操作
  # --model <value>: 模型参数（空时不传）
  # --effort <value>: Ralph 共同推理强度（low|medium|high，空或 none 时不传）
  local effort="${RALPH_PROVIDER_EFFORT:-}"
  local model="${RALPH_PROVIDER_MODEL:-}"
  local -a agy_cmd
  agy_cmd=(
    "${RALPH_PROVIDER_CLI:-agy}"
    --output-format stream-json
    --dangerously-skip-permissions
  )
  if [[ -n "$model" ]]; then
    agy_cmd+=(--model "$model")
  fi
  if [[ -n "$effort" && "$effort" != "none" ]]; then
    agy_cmd+=(--effort "$effort")
  fi
  agy_cmd+=(--print "$(cat "$prompt_file")")

  local rc=0
  "${agy_cmd[@]}" > "$log_path" 2>&1 || rc=$?

  # 从 stdout NDJSON 解析 conversation_id 作为 session_id
  local conversation_id=""
  if [[ -f "$log_path" ]]; then
    conversation_id="$(ralph_json_lines "$log_path" \
      | jq -r 'select(.event == "init" or .conversation_id != null) | .conversation_id // empty' 2>/dev/null \
      | head -1)" || conversation_id=""
  fi
  if [[ -n "$conversation_id" ]]; then
    update_meta_jq "$round_dir" '.session_id = $sid' --arg sid "$conversation_id"
  fi

  # ── 终态事件契约（REQ-051 / SC-051-1）────────────────────────────────────────
  # 结构化终态与原始 log 分离保存，进程退出码不能单独决定完成
  local terminal_event="" terminal_status="unknown" terminal_warning=""
  if [[ -f "$log_path" ]]; then
    local result_line=""
    result_line="$(ralph_json_lines "$log_path" \
      | jq -c 'select(.event == "result")' 2>/dev/null \
      | tail -1)" || result_line=""

    if [[ -n "$result_line" ]]; then
      terminal_event="result"
      local res_status="" has_denied=0 has_error=0 err_type="" err_msg=""
      res_status="$(printf '%s' "$result_line" | jq -r '(.result.status // .status // "")' 2>/dev/null)" || res_status=""
      has_denied="$(printf '%s' "$result_line" | jq -r 'if (((.result.denied_actions // .denied_actions // []) | length) > 0) then 1 else 0 end' 2>/dev/null)" || has_denied=0

      # 严格按错误字段的结构判定是否存在错误对象/非空字符串（REQ-051 / SC-051-1）
      has_error="$(printf '%s' "$result_line" | jq -r '
        (.result.error // .error // null) as $e |
        if $e == null then 0
        elif ($e | type) == "string" then (if ($e | length) > 0 then 1 else 0 end)
        elif ($e | type) == "object" then (if ($e | keys | length) > 0 then 1 else 0 end)
        else 0 end' 2>/dev/null)" || has_error=0

      err_type="$(printf '%s' "$result_line" | jq -r '
        (.result.error // .error // null) as $e |
        if ($e | type) == "object" then ($e.type // "") else "" end' 2>/dev/null)" || err_type=""

      err_msg="$(printf '%s' "$result_line" | jq -r '
        (.result.error // .error // null) as $e |
        if ($e | type) == "object" then
          if (($e.message // "") | length) > 0 then $e.message
          elif (($e.type // "") | length) > 0 then ("error type: " + $e.type)
          else ($e | tostring) end
        elif ($e | type) == "string" then $e
        else "" end' 2>/dev/null)" || err_msg=""

      if [[ "$has_denied" -eq 1 ]]; then
        terminal_status="error"
        terminal_warning="tool execution denied by policy (denied_actions non-empty)"
        [[ "$rc" -eq 0 ]] && rc=1
      elif [[ "$has_error" -eq 1 ]]; then
        terminal_status="error"
        terminal_warning="error present in result event: ${err_msg:-error object present}"
        [[ "$rc" -eq 0 ]] && rc=1
      elif [[ "$res_status" == "SUCCESS" ]]; then
        terminal_status="success"
      elif [[ "$res_status" == "ERROR" ]]; then
        terminal_status="error"
        [[ "$rc" -eq 0 ]] && rc=1
      else
        terminal_status="unknown"
        terminal_warning="unrecognized result status: $res_status"
        [[ "$rc" -eq 0 ]] && rc=1
      fi
    else
      terminal_warning="no result event in stream (crash, truncated or unknown event)"
      [[ "$rc" -eq 0 ]] && rc=1
    fi
  else
    terminal_warning="no stdout log file"
  fi

  update_meta_jq "$round_dir" \
    '.terminal_event = (if $e == "" then null else $e end)
     | .terminal_status = $s
     | .terminal_warning = (if $w == "" then null else $w end)' \
    --arg e "$terminal_event" --arg s "$terminal_status" --arg w "$terminal_warning"

  return "$rc"
}

# 验证候选会话文件是否安全且真实属于当前会话（SC-050-1: 防会话目录/文件符号链接跨会话误采）
_antigravity_safe_session_file() {
  local file="$1"
  local brain_dir="$2"
  local session_id="$3"

  [[ -d "$brain_dir" ]] || return 1
  [[ -f "$file" && -s "$file" && ! -L "$file" ]] || return 1

  local session_dir="$brain_dir/$session_id"
  [[ -d "$session_dir" && ! -L "$session_dir" ]] || return 1

  local real_brain=""
  if command -v realpath >/dev/null 2>&1; then
    real_brain="$(realpath "$brain_dir" 2>/dev/null)" || return 1
  elif command -v python3 >/dev/null 2>&1; then
    real_brain="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$brain_dir" 2>/dev/null)" || return 1
  else
    real_brain="$(cd "$brain_dir" 2>/dev/null && pwd -P)" || return 1
  fi
  [[ -n "$real_brain" ]] || return 1

  local expected_canonical="$real_brain/$session_id"
  local real_session="" real_file=""
  if command -v realpath >/dev/null 2>&1; then
    real_session="$(realpath "$session_dir" 2>/dev/null)" || return 1
    real_file="$(realpath "$file" 2>/dev/null)" || return 1
  elif command -v python3 >/dev/null 2>&1; then
    real_session="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$session_dir" 2>/dev/null)" || return 1
    real_file="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$file" 2>/dev/null)" || return 1
  else
    real_session="$(cd "$session_dir" 2>/dev/null && pwd -P)" || return 1
    real_file="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)/$(basename "$file")" || return 1
  fi

  # 1. 会话目录物理路径必须严格匹配规范路径 $real_brain/$session_id（防 session_dir 软链）
  [[ "$real_session" == "$expected_canonical" ]] || return 1
  # 2. 真实文件物理路径必须严格位于 expected_canonical 目录下（防文件或中间层软链）
  [[ "$real_file" == "$expected_canonical/"* ]] || return 1
  # 3. 真实文件本身不是软链接
  [[ -f "$real_file" && ! -L "$real_file" ]] || return 1

  return 0
}

# ── provider_collect_session ─────────────────────────────────────────────────
# 尽力采集原生 transcript（REQ-050 / SC-050-1）并派生 session.history.log
# 只有在路径或内容与 session_id 严格一致时才复制，禁止按 mtime 误采其他会话
provider_collect_session() {
  local round_dir="$1"
  local meta="$round_dir/meta.json"

  local session_id=""
  session_id="$(jq -r '.session_id // empty' "$meta" 2>/dev/null)" || session_id=""

  # 若 oneshot 进程异常被中断未能回填 session_id，尽力从 provider.stdout.log 兜底提取
  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    if [[ -f "$round_dir/provider.stdout.log" ]]; then
      session_id="$(ralph_json_lines "$round_dir/provider.stdout.log" \
        | jq -r 'select(.event == "init" or .conversation_id != null) | .conversation_id // empty' 2>/dev/null \
        | head -1)" || session_id=""
      if [[ -n "$session_id" ]]; then
        update_meta_jq "$round_dir" '.session_id = $sid' --arg sid "$session_id"
      fi
    fi
  fi

  # 若 terminal_status 尚未写入，同样从 provider.stdout.log 兜底补齐
  local cur_term=""
  cur_term="$(jq -r '.terminal_status // empty' "$meta" 2>/dev/null)" || cur_term=""
  if [[ -z "$cur_term" && -f "$round_dir/provider.stdout.log" ]]; then
    local result_line=""
    result_line="$(ralph_json_lines "$round_dir/provider.stdout.log" \
      | jq -c 'select(.event == "result")' 2>/dev/null \
      | tail -1)" || result_line=""
    if [[ -n "$result_line" ]]; then
      local res_status="" has_denied=0 has_error=0 err_msg=""
      res_status="$(printf '%s' "$result_line" | jq -r '(.result.status // .status // "")' 2>/dev/null)" || res_status=""
      has_denied="$(printf '%s' "$result_line" | jq -r 'if (((.result.denied_actions // .denied_actions // []) | length) > 0) then 1 else 0 end' 2>/dev/null)" || has_denied=0
      has_error="$(printf '%s' "$result_line" | jq -r '
        (.result.error // .error // null) as $e |
        if $e == null then 0
        elif ($e | type) == "string" then (if ($e | length) > 0 then 1 else 0 end)
        elif ($e | type) == "object" then (if ($e | keys | length) > 0 then 1 else 0 end)
        else 0 end' 2>/dev/null)" || has_error=0
      err_msg="$(printf '%s' "$result_line" | jq -r '
        (.result.error // .error // null) as $e |
        if ($e | type) == "object" then
          if (($e.message // "") | length) > 0 then $e.message
          elif (($e.type // "") | length) > 0 then ("error type: " + $e.type)
          else ($e | tostring) end
        elif ($e | type) == "string" then $e
        else "" end' 2>/dev/null)" || err_msg=""

      if [[ "$has_denied" -eq 1 ]]; then
        update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = "error" | .terminal_warning = "tool execution denied by policy (denied_actions non-empty)"'
      elif [[ "$has_error" -eq 1 ]]; then
        update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = "error" | .terminal_warning = ("error present in result event: " + $e)' --arg e "${err_msg:-error object present}"
      elif [[ "$res_status" == "SUCCESS" ]]; then
        update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = "success"'
      elif [[ "$res_status" == "ERROR" ]]; then
        update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = "error"'
      else
        update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = "unknown" | .terminal_warning = ("unrecognized result status: " + $s)' --arg s "$res_status"
      fi
    fi
  fi

  local dst="$round_dir/session.antigravity.jsonl"

  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    update_meta_jq "$round_dir" \
      '.capture_status = "warning" | .capture_warning = "missing session_id in round metadata"'
  elif [[ ! "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    update_meta_jq "$round_dir" \
      '.capture_status = "warning" | .capture_warning = ($w + $sid)' \
      --arg w "invalid or unsafe session_id format: " --arg sid "$session_id"
  else
    local candidate=""
    local base_dirs=()
    if [[ -n "${ANTIGRAVITY_APP_DATA_DIR:-}" ]]; then
      base_dirs+=("$ANTIGRAVITY_APP_DATA_DIR")
    fi
    base_dirs+=(
      "$HOME/.gemini/antigravity-cli"
      "$HOME/.gemini/antigravity"
    )
    local base=""
    for base in "${base_dirs[@]}"; do
      local brain_dir="$base/brain"
      local expected_dir="$brain_dir/$session_id"
      local log_file="$expected_dir/.system_generated/logs/transcript.jsonl"
      local full_file="$expected_dir/.system_generated/logs/transcript_full.jsonl"

      if _antigravity_safe_session_file "$log_file" "$brain_dir" "$session_id"; then
        candidate="$log_file"
        break
      elif _antigravity_safe_session_file "$full_file" "$brain_dir" "$session_id"; then
        candidate="$full_file"
        break
      fi
    done

    if [[ -n "$candidate" && -f "$candidate" && -s "$candidate" && ! -L "$candidate" ]]; then
      if rm -f "$dst" 2>/dev/null && cp "$candidate" "$dst" 2>/dev/null && [[ -f "$dst" && -s "$dst" ]]; then
        update_meta_jq "$round_dir" \
          '.capture_status = "ok" | .capture_warning = null | .session_source_path = $src | .session_copied_path = $dst' \
          --arg src "$candidate" --arg dst "$dst"
      else
        update_meta_jq "$round_dir" \
          '.capture_status = "warning" | .capture_warning = ($w + $sid)' \
          --arg w "failed to copy session file or invalid target for conversation " --arg sid "$session_id"
      fi
    else
      update_meta_jq "$round_dir" \
        '.capture_status = "warning" | .capture_warning = ($w + $sid)' \
        --arg w "native transcript not found or empty for conversation " --arg sid "$session_id"
    fi
  fi

  # 从 provider.stdout.log 派生可读历史
  _antigravity_derive_history "$round_dir/provider.stdout.log" "$round_dir/session.history.log"
  touch "$round_dir/session.history.log"
  return 0
}

# ── _antigravity_derive_history ──────────────────────────────────────────────
# 从 provider.stdout.log（stream-json NDJSON 流）派生人类视图
_antigravity_derive_history() {
  local stdout_log="$1" out="$2"
  [[ -f "$stdout_log" ]] || return 0

  local jsonl_events
  jsonl_events="$(ralph_json_lines "$stdout_log")" || return 0
  [[ -n "$jsonl_events" ]] || return 0

  printf '%s\n' "$jsonl_events" | jq -r --slurp '
    .[] |
    if .event == "init" then
      "[session] " + (.conversation_id // "")
    elif .event == "step_update" and (((.step_update.agent_response.text_delta // .agent_response.text_delta // .step_update.text_delta // .text_delta // "") | length) > 0) then
      "[assistant] " + (.step_update.agent_response.text_delta // .agent_response.text_delta // .step_update.text_delta // .text_delta)
    elif .event == "step_update" and (((.step_update.tool_name // .tool_name // "") | length) > 0) then
      if ((.step_update.state // .state // "") == "DONE" and ((.step_update.tool_info.output // .tool_info.output // "") != "")) then
        "[tool-result] " + (((.step_update.tool_info.output // .tool_info.output) | tostring) | if length > 4000 then .[0:2000] + "\n... [truncated]\n" + .[-1000:] else . end)
      else
        "[tool-use name=" + (.step_update.tool_name // .tool_name) + "] " + (((.step_update.tool_info // .tool_info // {}) | tostring) | if length > 4000 then .[0:2000] + "\n... [truncated]\n" + .[-1000:] else . end)
      end
    elif .event == "step_update" and ((.step_update.subagent_info // .subagent_info // null) != null) then
      "[subagent] " + ((.step_update.subagent_info // .subagent_info) | tostring)
    elif .event == "result" then
      "[result] status=" + (.result.status // .status // "unknown")
    else empty end
  ' > "$out" 2>/dev/null || true
}

# ── _antigravity_classify_error ──────────────────────────────────────────────
_antigravity_classify_error() {
  local text="${1:-}"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if   [[ "$lower" == *"401"* || "$lower" == *"unauthor"* || "$lower" == *"not authenticated"* || "$lower" == *"not logged in"* || "$lower" == *"auth"* ]]; then
    printf 'auth'
  elif [[ "$lower" == *"429"* || "$lower" =~ rate.?limit || "$lower" == *"too many requests"* ]]; then
    printf 'rate_limit'
  elif [[ "$lower" == *"quota"* || "$lower" == *"credits exhausted"* || "$lower" == *"billing"* || "$lower" == *"resource has been exhausted"* ]]; then
    printf 'quota'
  elif [[ "$lower" == *"econnreset"* || "$lower" == *"enotfound"* || "$lower" == *"etimedout"* \
      || "$lower" == *"connection refused"* || "$lower" == *"network error"* || "$lower" == *"fetch failed"* ]]; then
    printf 'network'
  elif [[ "$lower" =~ (^|[^0-9])5[0-9][0-9]([^0-9]|$) || "$lower" == *"api error"* || "$lower" == *"internal server"* || "$lower" == *"service unavailable"* ]]; then
    printf 'api'
  elif [[ "$lower" == *"permission"* || "$lower" == *"denied"* || "$lower" == *"rejected"* ]]; then
    printf 'permission'
  else
    printf 'unknown'
  fi
}

# ── provider_diagnose ────────────────────────────────────────────────────────
# 从 provider.stdout.log 末尾提取结构化错误
provider_diagnose() {
  local round_dir="$1"
  local log_path="$round_dir/provider.stdout.log"

  local exit_code
  exit_code="$(jq -r '.exit_code // 0' "$round_dir/meta.json" 2>/dev/null)" || exit_code=0

  if [[ ! -f "$log_path" ]]; then
    update_meta_jq "$round_dir" \
      '.error = {"type": "unknown", "message": "no stdout log file", "raw": ""}'
    return 0
  fi

  local result_event=""
  result_event="$(ralph_json_lines "$log_path" \
    | jq -c 'select(.event == "result")' 2>/dev/null \
    | tail -1)" || result_event=""

  if [[ -z "$result_event" ]]; then
    if [[ "$exit_code" == "0" ]]; then
      return 0
    fi
    update_meta_jq "$round_dir" \
      '.error = {"type": "unknown", "message": "no result event in stream", "raw": ""}'
    return 0
  fi

  local res_status="" has_denied=0 has_error=0 err_msg="" err_type=""
  res_status="$(printf '%s' "$result_event" | jq -r '(.result.status // .status // "")' 2>/dev/null)" || res_status=""
  has_denied="$(printf '%s' "$result_event" | jq -r 'if (((.result.denied_actions // .denied_actions // []) | length) > 0) then 1 else 0 end' 2>/dev/null)" || has_denied=0

  has_error="$(printf '%s' "$result_event" | jq -r '
    (.result.error // .error // null) as $e |
    if $e == null then 0
    elif ($e | type) == "string" then (if ($e | length) > 0 then 1 else 0 end)
    elif ($e | type) == "object" then (if ($e | keys | length) > 0 then 1 else 0 end)
    else 0 end' 2>/dev/null)" || has_error=0

  err_type="$(printf '%s' "$result_event" | jq -r '
    (.result.error // .error // null) as $e |
    if ($e | type) == "object" then ($e.type // "") else "" end' 2>/dev/null)" || err_type=""

  err_msg="$(printf '%s' "$result_event" | jq -r '
    (.result.error // .error // null) as $e |
    if ($e | type) == "object" then
      if (($e.message // "") | length) > 0 then $e.message
      elif (($e.type // "") | length) > 0 then ("error type: " + $e.type)
      else ($e | tostring) end
    elif ($e | type) == "string" then $e
    else "" end' 2>/dev/null)" || err_msg=""

  # 正常完成且无软拒绝且无错误且退出码为 0
  if [[ "$res_status" == "SUCCESS" && "$has_denied" -eq 0 && "$has_error" -eq 0 && "$exit_code" == "0" ]]; then
    return 0
  fi

  local classified_type="unknown"
  if [[ "$has_denied" -eq 1 ]]; then
    classified_type="permission"
    if [[ -z "$err_msg" ]]; then
      err_msg="$(printf '%s' "$result_event" | jq -r '((.result.denied_actions // .denied_actions)[0].reason // "tool execution denied")' 2>/dev/null)"
    fi
  elif [[ -n "$err_type" ]]; then
    case "$err_type" in
      auth|quota|rate_limit|network|api|permission) classified_type="$err_type" ;;
      *) classified_type="$(_antigravity_classify_error "$err_msg")" ;;
    esac
  elif [[ -n "$err_msg" ]]; then
    classified_type="$(_antigravity_classify_error "$err_msg")"
  elif [[ "$res_status" != "SUCCESS" && "$res_status" != "ERROR" && -n "$res_status" ]]; then
    classified_type="unknown"
    err_msg="unrecognized result status: $res_status"
  fi

  if [[ -z "$err_msg" && "$has_error" -eq 1 ]]; then
    err_msg="error object present without message"
  fi

  update_meta_jq "$round_dir" \
    '.error = {"type": $t, "message": $m, "raw": $r}' \
    --arg t "$classified_type" \
    --arg m "${err_msg:0:200}" \
    --arg r "${err_msg:0:500}"
  return 0
}
