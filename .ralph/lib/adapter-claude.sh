#!/usr/bin/env bash
# adapter-claude.sh — Claude provider adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数契约
# stream-json 模式：stdout 是 JSONL events 流，逐行写入 provider.stdout.log
# session 文件命名遵循 docs/architecture/integrations.md §Session 文件命名约定

RALPH_PROVIDER_CLI="claude"

# ── 中立变量 → provider 原生变量翻译（adapter 配置目录翻译契约）──────────────
# 由 ralph load_env 保证 RALPH_PROVIDER_CONFIG_DIR 已 export 且 tilde 已展开。
# 仅在变量非空时才 export，避免空 CLAUDE_CONFIG_DIR 干扰 claude CLI 默认行为。
if [[ -n "${RALPH_PROVIDER_CONFIG_DIR:-}" ]]; then
  export CLAUDE_CONFIG_DIR="$RALPH_PROVIDER_CONFIG_DIR"
fi

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd claude "Claude Code CLI" \
    "npm install -g @anthropic-ai/claude-code"
  ralph_require_cmd jq "parse Claude JSON output" \
    $'macOS: brew install jq\nLinux: apt install jq'
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <round_dir>
# log_path 即 round_dir/provider.stdout.log，stream-json events 一行一行写入
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local round_dir="$3"

  local session_id
  session_id="$(ralph_uuid)"

  # session_id 写入 meta.json（meta.json 已由 run.sh 在本函数调用前建立骨架）
  update_meta_jq "$round_dir" '.session_id = $sid' --arg sid "$session_id"

  # provider_started_at（mtime fallback 锚点替代 .session_start）
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

  # --output-format stream-json: events 逐行流式输出到 stdout（不再单独写 stdout.json）
  # --verbose: stream-json 模式下需要（claude CLI 要求 stream-json 与 verbose 配对）
  # --effort 直通（none/空 → 不拼 flag；用数组避免空参数注入，SC-014-1）
  local effort="${RALPH_PROVIDER_EFFORT:-}"
  local -a claude_cmd
  claude_cmd=(
    claude -p "$(cat "$prompt_file")"
    --session-id "$session_id"
    --dangerously-skip-permissions
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep"
    --output-format stream-json
    --verbose
  )
  if [[ -n "$effort" && "$effort" != "none" ]]; then
    claude_cmd+=(--effort "$effort")
  fi

  local rc=0
  # stdout + stderr 合并写入 provider.stdout.log（stderr 罕见；diagnose 用 ^{ 前缀过滤）
  "${claude_cmd[@]}" > "$log_path" 2>>"$log_path" || rc=$?

  # 从 stream-json events 末尾找 result 事件，is_error=true 视为 provider 失败。
  # 终态字段即使 provider 返回非零也要记录，便于区分失败类型。
  if [[ -f "$log_path" ]]; then
    local _is_err
    _is_err="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
      | jq -r 'select(.type == "result") | .is_error // false' 2>/dev/null \
      | tail -1)"
    if [[ -n "$_is_err" ]]; then
      local _terminal_status="success"
      [[ "$_is_err" == "true" ]] && _terminal_status="error"
      update_meta_jq "$round_dir" '.terminal_event = "result" | .terminal_status = $s' \
        --arg s "$_terminal_status"
    fi
    [[ "$_is_err" == "true" ]] && rc=1
  fi

  return "$rc"
}

# ── provider_collect_session ─────────────────────────────────────────────────

# _claude_cwd_hash <path>
# cwd_hash 严格步骤：先 realpath 解 symlink，再字符替换（步骤顺序固定，见 PM-0002）
# 参见 docs/architecture/integrations.md §Claude Session 机制
_claude_cwd_hash() {
  local resolved
  resolved="$(realpath "$1")"
  printf '%s' "$resolved" | sed 's/[^A-Za-z0-9-]/-/g'
}

provider_collect_session() {
  local round_dir="$1"

  # 读取 session_id（由 provider_oneshot 写入 meta.json）
  local session_id
  session_id="$(jq -r '.session_id // empty' "$round_dir/meta.json" 2>/dev/null)"
  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    update_meta_jq "$round_dir" \
      '.capture_status = "warning" | .capture_warning = "session_id missing in meta.json"'
    touch "$round_dir/session.history.log"
    return 0
  fi

  local cwd_hash
  cwd_hash="$(_claude_cwd_hash "${_RALPH_WORKSPACE}")"
  # session root 感知 CLAUDE_CONFIG_DIR（由 RALPH_PROVIDER_CONFIG_DIR 翻译而来，REQ-022 / SC-022-3）
  local claude_root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local session_dir="$claude_root/projects/$cwd_hash"
  local expected_file="$session_dir/${session_id}.jsonl"
  local dst="$round_dir/session.claude.jsonl"

  if [[ -f "$expected_file" ]]; then
    # 精确匹配：按 session_id 定位
    cp "$expected_file" "$dst"
    update_meta_jq "$round_dir" \
      '.capture_status = "ok" | .session_source_path = $src | .session_copied_path = $dst' \
      --arg src "$expected_file" --arg dst "$dst"
  else
    # mtime 降级：用 meta.json 的 provider_started_at 作为参考时间（-1 秒缓冲，
    # 避免同秒精度 -newermt 不命中）
    local fallback_file=""
    if [[ -d "$session_dir" ]]; then
      local started_at
      started_at="$(jq -r '.provider_started_at // empty' "$round_dir/meta.json" 2>/dev/null)"
      if [[ -n "$started_at" && "$started_at" != "null" ]]; then
        # 转 BSD find -newermt 兼容格式（local "YYYY-MM-DD HH:MM:SS"），-1s 缓冲
        local started_epoch
        started_epoch="$(ralph_iso_to_epoch "$started_at")"
        local anchor_local=""
        if [[ -n "$started_epoch" ]]; then
          local buffered_iso
          buffered_iso="$(ralph_epoch_to_iso $((started_epoch - 1)))"
          anchor_local="$(ralph_iso_to_local_find_fmt "$buffered_iso")"
        fi
        local candidates=""
        if [[ -n "$anchor_local" ]]; then
          candidates="$(find "$session_dir" -maxdepth 1 -name "*.jsonl" \
            -newermt "$anchor_local" -type f 2>/dev/null)"
        fi
        if [[ -n "$candidates" ]]; then
          # xargs ls -1t 按 mtime 降序排列，取最新（find 不保证顺序）
          fallback_file="$(echo "$candidates" | xargs ls -1t 2>/dev/null | head -1)"
        fi
      fi
    fi

    if [[ -n "$fallback_file" ]]; then
      cp "$fallback_file" "$dst"
      update_meta_jq "$round_dir" \
        '.capture_status = "ok" | .capture_warning = "fallback by mtime" | .session_source_path = $src | .session_copied_path = $dst' \
        --arg src "$fallback_file" --arg dst "$dst"
    else
      update_meta_jq "$round_dir" \
        '.capture_status = "warning" | .capture_warning = "session file not found"'
    fi
  fi

  # 派生 session.history.log（人话视图，含 thinking + tool_use input 摘要）
  if [[ -f "$dst" ]]; then
    _claude_derive_history "$dst" "$round_dir/session.history.log"
  fi
  touch "$round_dir/session.history.log"   # 保证文件存在（warning 时写空文件）
  return 0
}

# ── _claude_derive_history ───────────────────────────────────────────────────
# 从 session.claude.jsonl 派生人话视图，含：
#   - [user] 文本消息
#   - [assistant] 文本回复
#   - [thinking] 思考块（保留全文，不过滤）
#   - [tool-use name=X] 工具调用 + input 摘要（完整 input 见 session.claude.jsonl）
#   - [tool-result name=X] 工具结果（截前 2000 字符）
# 替代旧 chat.log + tools.log 双视图

_claude_derive_history() {
  local jsonl="$1" out="$2"
  [[ -f "$jsonl" ]] || return 0
  jq -r --slurp '
    def text_of(c):
      if   (c | type) == "array"  then [c[] | select(.type=="text") | .text] | join("")
      elif (c | type) == "string" then c
      else "" end;

    def tool_input_summary:
      (tostring) as $s |
      if ($s | length) > 4000 then
        ($s[0:2000] + "\n... [tool input truncated; see session.claude.jsonl for full input]\n" + $s[-1000:])
      else $s end;

    # tool_use_id → name map（从 assistant 消息提取，供 tool_result 标注 name）
    ( [.[] | select(.type=="assistant") |
        (.message.content // []) |
        if type=="array" then .[] else empty end |
        select(.type=="tool_use") |
        {(.id): .name}
      ] | add // {} ) as $tools |

    .[] | . as $e |
    if .type == "user" then
      ($e.message.content) as $c |
      if ($c | type) == "string" then
        if ($c | length) > 0 then "[user] " + ($e.timestamp // ""), $c, ""
        else empty end
      elif ($c | type) == "array" then
        $c[] |
        if .type == "tool_result" then
          . as $tr |
          ($tools[$tr.tool_use_id] // "unknown") as $name |
          (text_of($tr.content // "") | .[0:2000]) as $t |
          "[tool-result name=" + $name + "] " + ($e.timestamp // ""), $t, ""
        elif .type == "text" then
          (.text // "") as $t |
          if ($t|length) > 0 then "[user] " + ($e.timestamp // ""), $t, ""
          else empty end
        else empty end
      else empty end
    elif .type == "assistant" then
      ($e.message.content // []) as $c |
      ( $c | if type=="array" then .[] else empty end ) |
      if .type == "thinking" then
        (.thinking // "") as $t |
        if ($t|length) > 0 then "[thinking] " + ($e.timestamp // ""), $t, ""
        else empty end
      elif .type == "text" then
        (.text // "") as $t |
        if ($t|length) > 0 then "[assistant] " + ($e.timestamp // ""), $t, ""
        else empty end
      elif .type == "tool_use" then
        . as $tu |
        "[tool-use name=" + ($tu.name // "?") + "] " + ($e.timestamp // ""),
        ($tu.input | tool_input_summary),
        ""
      else empty end
    else empty end
  ' "$jsonl" > "$out"
}

# ── _claude_classify_error ───────────────────────────────────────────────────
# 输入：result 字段原文；输出：错误分类标签（互斥优先级，见 docs/architecture/integrations.md）
_claude_classify_error() {
  local text="${1:-}"
  local lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  if   [[ "$lower" == *"tool_use_concurrency"* ]]; then
    printf 'concurrency'
  elif [[ "$lower" == *"unauthor"* || "$lower" == *" 401"* || "$lower" == *"invalid api key"* ]]; then
    printf 'auth'
  elif [[ "$lower" == *"429"* || "$lower" =~ rate.?limit || "$lower" == *"too many requests"* ]]; then
    printf 'rate_limit'
  elif [[ "$lower" == *"quota"* || "$lower" == *"credits exhausted"* || "$lower" == *"billing"* ]]; then
    printf 'quota'
  elif [[ "$lower" == *"econnreset"* || "$lower" == *"etimedout"* || "$lower" == *"enotfound"* || "$lower" == *"fetch failed"* || "$lower" == *"connection refused"* || "$lower" == *"network error"* ]]; then
    printf 'network'
  elif [[ "$lower" =~ (^|[^0-9])5[0-9][0-9]([^0-9]|$) || "$lower" == *"api error"* || "$lower" == *"internal server"* || "$lower" == *"service unavailable"* ]]; then
    printf 'api'
  else
    printf 'unknown'
  fi
}

# ── provider_diagnose ────────────────────────────────────────────────────────
# 从 provider.stdout.log 末尾找 result 事件（stream-json 模式）
provider_diagnose() {
  local round_dir="$1"
  local log_path="$round_dir/provider.stdout.log"

  # 读取 exit_code（provider_oneshot 回填后可用）
  local exit_code
  exit_code="$(jq -r '.exit_code // 0' "$round_dir/meta.json" 2>/dev/null)" || exit_code=0

  # log 文件不存在（CLI crash 无输出）→ unknown
  if [[ ! -f "$log_path" ]]; then
    update_meta_jq "$round_dir" \
      '.error = {"type": "unknown", "message": "no stdout log file", "raw": ""}'
    return 0
  fi

  # 找 stream-json 末尾的 result 事件
  local result_event is_error result_text
  result_event="$(grep -E '^[[:space:]]*\{' "$log_path" 2>/dev/null \
    | jq -c 'select(.type == "result")' 2>/dev/null \
    | tail -1)"

  # 没找到 result 事件（CLI 在 init / mid-stream 崩溃）
  if [[ -z "$result_event" ]]; then
    if [[ "$exit_code" == "0" ]]; then
      return 0
    fi
    update_meta_jq "$round_dir" \
      '.error = {"type": "unknown", "message": "no result event in stream", "raw": ""}'
    return 0
  fi

  is_error="$(printf '%s' "$result_event" | jq -r '.is_error // false' 2>/dev/null)" || is_error="false"
  result_text="$(printf '%s' "$result_event" | jq -r '.result // ""' 2>/dev/null)" || result_text=""

  # 正常完成：is_error=false && exit_code=0 → error 保持 null
  if [[ "$is_error" == "false" && "$exit_code" == "0" ]]; then
    return 0
  fi

  local error_type
  if [[ "$is_error" == "true" ]]; then
    error_type="$(_claude_classify_error "$result_text")"
  else
    # is_error=false 但 exit_code≠0 → CLI 自身崩溃 → unknown
    error_type="unknown"
  fi

  update_meta_jq "$round_dir" \
    '.error = {"type": $t, "message": $m, "raw": $r}' \
    --arg t "$error_type" \
    --arg m "${result_text:0:200}" \
    --arg r "${result_text:0:500}"
  return 0
}
