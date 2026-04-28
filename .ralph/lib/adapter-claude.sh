#!/usr/bin/env bash
# adapter-claude.sh — Claude provider adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数契约
# session 文件命名遵循 docs/architecture/integrations.md §Session 文件命名约定

RALPH_PROVIDER_CLI="claude"

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd claude "Claude Code CLI" \
    "npm install -g @anthropic-ai/claude-code"
  ralph_require_cmd jq "parse Claude JSON output" \
    $'macOS: brew install jq\nLinux: apt install jq'
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <iter_dir>
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local iter_dir="$3"

  local session_id
  session_id="$(ralph_uuid)"

  # session_id 写入 meta.json（meta.json 已由 run.sh 在本函数调用前建立骨架）
  update_meta_jq "$iter_dir" '.session_id = $sid' --arg sid "$session_id"

  local stdout_file="$iter_dir/session.claude.stdout.json"
  touch "$log_path"
  touch "$iter_dir/.session_start"   # mtime anchor: before provider CLI starts

  # ARG_MAX guard：命令行参数上限约 1MB；prompt 过大时报清晰错误而非静默崩溃
  local _prompt_size
  _prompt_size="$(wc -c < "$prompt_file" 2>/dev/null)" || _prompt_size=0
  if [[ "${_prompt_size:-0}" -gt 900000 ]]; then
    printf 'ralph: prompt file too large (%s bytes); keep PROMPT.md under 900KB\n' "$_prompt_size" >&2
    return 1
  fi

  local rc=0
  claude -p "$(cat "$prompt_file")" \
    --session-id "$session_id" \
    --dangerously-skip-permissions \
    --allowedTools "Bash,Read,Edit,Write,Glob,Grep" \
    --output-format json \
    > "$stdout_file" 2>>"$log_path" || rc=$?

  # stdout 同步追加到 log（保持全量日志约定）
  cat "$stdout_file" >> "$log_path" 2>/dev/null || true

  # is_error:true 视为 provider 失败（即使 CLI exit 0，错误信息在 JSON 中）
  if [[ "$rc" -eq 0 && -f "$stdout_file" ]]; then
    local _is_err
    _is_err="$(jq -r '.is_error // false' "$stdout_file" 2>/dev/null)" || _is_err="false"
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
  local iter_dir="$1"

  # 读取 session_id（由 provider_oneshot 写入 meta.json）
  local session_id
  session_id="$(jq -r '.session_id // empty' "$iter_dir/meta.json" 2>/dev/null)"
  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    update_meta_jq "$iter_dir" \
      '.capture_status = "warning" | .capture_warning = "session_id missing in meta.json"'
    touch "$iter_dir/chat.log" "$iter_dir/tools.log"
    return 0
  fi

  local cwd_hash
  cwd_hash="$(_claude_cwd_hash "${_RALPH_WORKSPACE}")"
  local session_dir="$HOME/.claude/projects/$cwd_hash"
  local expected_file="$session_dir/${session_id}.jsonl"
  local dst="$iter_dir/session.claude.jsonl"

  if [[ -f "$expected_file" ]]; then
    # 精确匹配：按 session_id 定位
    cp "$expected_file" "$dst"
    update_meta_jq "$iter_dir" \
      '.capture_status = "ok" | .session_source_path = $src | .session_copied_path = $dst' \
      --arg src "$expected_file" --arg dst "$dst"
  else
    # mtime 降级：找 session_dir 下比 meta.json 新的最新 .jsonl
    local fallback_file=""
    if [[ -d "$session_dir" ]]; then
      local ref_file="$iter_dir/.session_start"
      [[ -f "$ref_file" ]] || ref_file="$iter_dir/meta.json"
      local candidates
      candidates="$(find "$session_dir" -maxdepth 1 -name "*.jsonl" \
        -newer "$ref_file" -type f 2>/dev/null)"
      if [[ -n "$candidates" ]]; then
        # xargs ls -1t 按 mtime 降序排列，取最新（find 不保证顺序）
        fallback_file="$(echo "$candidates" | xargs ls -1t 2>/dev/null | head -1)"
      fi
    fi

    if [[ -n "$fallback_file" ]]; then
      cp "$fallback_file" "$dst"
      update_meta_jq "$iter_dir" \
        '.capture_status = "ok" | .capture_warning = "fallback by mtime" | .session_source_path = $src | .session_copied_path = $dst' \
        --arg src "$fallback_file" --arg dst "$dst"
    else
      update_meta_jq "$iter_dir" \
        '.capture_status = "warning" | .capture_warning = "session file not found"'
    fi
  fi

  # 派生视图（capture_status=ok 时 JSONL 已复制）
  if [[ -f "$dst" ]]; then
    _claude_derive_chat "$dst" "$iter_dir/chat.log"
    _claude_derive_tools "$dst" "$iter_dir/tools.log"
  fi
  touch "$iter_dir/chat.log" "$iter_dir/tools.log"   # 保证文件存在（warning 时写空文件）
  return 0
}

# ── _claude_derive_chat / _claude_derive_tools ───────────────────────────────
# 从 session.claude.jsonl 派生人类可读视图，schema 遵循 docs/architecture/overview.md §派生视图

_claude_derive_chat() {
  local jsonl="$1" out="$2"
  [[ -f "$jsonl" ]] || return 0
  jq -r --slurp '
    def text_of(c):
      if   (c | type) == "array"  then [c[] | select(.type=="text") | .text] | join("")
      elif (c | type) == "string" then c
      else "" end;

    # tool_use_id → name map（从 assistant 消息提取）
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
      (text_of($e.message.content // [])) as $t |
      if ($t|length) > 0 then
        "[assistant] " + ($e.timestamp // ""), $t, ""
      else empty end
    else empty end
  ' "$jsonl" > "$out"
}

_claude_derive_tools() {
  local jsonl="$1" out="$2"
  [[ -f "$jsonl" ]] || return 0
  jq -r --slurp '
    # tool_use_id → tool_use 对象 map
    ( [.[] | select(.type=="assistant") |
        (.message.content // []) |
        if type=="array" then .[] else empty end |
        select(.type=="tool_use") |
        {(.id): .}
      ] | add // {} ) as $tuses |

    .[] | . as $e |
    select(.type=="user") |
    (($e.message.content) | if type=="array" then .[] else empty end) |
    select(.type=="tool_result") |
    . as $tr |
    ($tuses[$tr.tool_use_id]) as $tu |
    ($tu.name // "unknown") as $name |
    ($tu.input | tostring | .[0:80]) as $in |
    ( if ($tr.content | type) == "array" then
        [$tr.content[] | select(.type=="text") | .text] | join("")
      else ($tr.content // "") | tostring end
    | .[0:80]) as $out |
    ($e.timestamp // "?") + "  " + $name + "  " + $in + "  " + $out
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
  elif [[ "$lower" =~ (^|[^0-9])5[0-9][0-9]([^0-9]|$) || "$lower" == *"api error"* || "$lower" == *"internal server"* || "$lower" == *"service unavailable"* ]]; then
    printf 'api'
  else
    printf 'unknown'
  fi
}

# ── provider_diagnose ────────────────────────────────────────────────────────
provider_diagnose() {
  local iter_dir="$1"
  local stdout_file="$iter_dir/session.claude.stdout.json"

  # 读取 exit_code（provider_oneshot 回填后可用）
  local exit_code
  exit_code="$(jq -r '.exit_code // 0' "$iter_dir/meta.json" 2>/dev/null)" || exit_code=0

  # stdout 文件不存在（CLI crash 无输出）→ unknown
  if [[ ! -f "$stdout_file" ]]; then
    update_meta_jq "$iter_dir" \
      '.error = {"type": "unknown", "message": "no stdout file", "raw": ""}'
    return 0
  fi

  local is_error result_text
  is_error="$(jq -r '.is_error // false' "$stdout_file" 2>/dev/null)" || is_error="false"
  result_text="$(jq -r '.result // ""' "$stdout_file" 2>/dev/null)" || result_text=""

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

  update_meta_jq "$iter_dir" \
    '.error = {"type": $t, "message": $m, "raw": $r}' \
    --arg t "$error_type" \
    --arg m "${result_text:0:200}" \
    --arg r "${result_text:0:500}"
  return 0
}
