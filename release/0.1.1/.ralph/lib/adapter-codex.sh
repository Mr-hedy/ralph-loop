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

  # 从 stdout JSONL 解析 thread_id（session_id 等价物，用于 session 采集）
  local thread_id=""
  if [[ -f "$log_path" ]]; then
    thread_id="$(ralph_json_lines "$log_path" \
      | jq -r 'select(.type == "thread.started") | .thread_id // empty' 2>/dev/null \
      | head -1)" || thread_id=""
  fi
  if [[ -n "$thread_id" ]]; then
    update_meta_jq "$round_dir" '.session_id = $sid' --arg sid "$thread_id"
  fi

  # ── 终态事件契约（REQ-029）────────────────────────────────────────────────
  # 结构化终态与原始 log 分离保存；流被截断时 provider.stdout.log 仍是事实源。
  # 判定优先级：
  #   turn.completed → success
  #   turn.failed    → error（最终权威失败事件，integrations.md §错误诊断）
  #   仅 error 事件  → error + warning（retry 循环里 error 可能被覆盖，属退化路径）
  #   都没有 / 无法解析 → unknown + terminal_warning（crash、截断、未知事件）
  # rc 不得单独决定终态：terminal_status=error 时即使 CLI 进程退出码为 0 也返回非零。
  local terminal_event="" terminal_status="unknown" terminal_warning=""
  if [[ -f "$log_path" ]]; then
    local terminal_line terminal_kind=""
    terminal_line="$(ralph_json_lines "$log_path" \
      | jq -c 'select(.type == "turn.completed" or .type == "turn.failed")' 2>/dev/null \
      | tail -1)" || terminal_line=""
    if [[ -n "$terminal_line" ]]; then
      terminal_kind="$(printf '%s' "$terminal_line" | jq -r '.type' 2>/dev/null)" || terminal_kind=""
    else
      # 退化：无 turn.* 终态时，末尾 error 事件作为最后线索
      terminal_line="$(ralph_json_lines "$log_path" \
        | jq -c 'select(.type == "error")' 2>/dev/null \
        | tail -1)" || terminal_line=""
      if [[ -n "$terminal_line" ]]; then
        terminal_kind="$(printf '%s' "$terminal_line" | jq -r '.type' 2>/dev/null)" || terminal_kind=""
        terminal_warning="no turn.completed/turn.failed; degraded to trailing error event"
      fi
    fi

    if [[ -n "$terminal_kind" ]]; then
      terminal_event="$terminal_kind"
      case "$terminal_event" in
        turn.completed)
          terminal_status="success"
          ;;
        turn.failed|error)
          terminal_status="error"
          [[ "$rc" -eq 0 ]] && rc=1
          ;;
        *)
          terminal_status="unknown"
          terminal_warning="unrecognized terminal event: $terminal_event"
          ;;
      esac
    else
      terminal_warning="no terminal event in stream (crash, truncated or unknown event)"
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

# ── _codex_rollout_id ────────────────────────────────────────────────────────
# 读 rollout 首行 session_meta 的内嵌 session id（`payload.id` / `payload.thread_id`）。
#   rc=0 + 非空输出 → 首行可解析且带 id
#   rc=0 + 空输出   → 首行可解析但无 id 字段
#   rc≠0            → 首行不可读 / 为空 / 非法 JSON（截断或格式不匹配）
_codex_rollout_id() {
  local file="$1"
  local first_line
  first_line="$(head -1 "$file" 2>/dev/null)" || return 1
  [[ -n "$first_line" ]] || return 1
  printf '%s' "$first_line" | jq -r '.payload.id // .payload.thread_id // empty' 2>/dev/null
}

# ── _codex_scan_rollouts ─────────────────────────────────────────────────────
# 按内嵌 session id 扫描 rollout 候选（REQ-030）。活动 sessions/ 与归档
# archived_sessions/ 走同一套候选发现 + 同一套 id 校验，避免两条路径强度不一致。
# <session_id> <mode> <root>...
#   mode=exact → 只扫文件名含 session_id 的 rollout（快路径）
#   mode=other → 扫其余 rollout（归档 rollout 文件名通常不含 id）
# 结果经全局变量返回；调用方**不得**放进 $() 子 shell，否则计数丢失：
#   _CODEX_SCAN_RESULT     命中的 rollout 路径（未命中为空）
#   _CODEX_SCAN_MISMATCH   首行有 id 但不是本 session 的候选数
#   _CODEX_SCAN_NOID       首行可解析但无 id 字段的候选数
#   _CODEX_SCAN_UNREADABLE 首行不可解析（截断 / 非法 JSON）的候选数
_codex_scan_rollouts() {
  local session_id="$1"
  local mode="$2"
  shift 2

  _CODEX_SCAN_RESULT=""
  _CODEX_SCAN_MISMATCH=0
  _CODEX_SCAN_NOID=0
  _CODEX_SCAN_UNREADABLE=0

  local -a find_args
  find_args=(-type f)
  if [[ "$mode" == "exact" ]]; then
    find_args+=(-name "rollout-*-${session_id}.jsonl")
  else
    find_args+=(-name 'rollout-*.jsonl' ! -name "rollout-*-${session_id}.jsonl")
  fi

  local root candidate embedded
  for root in "$@"; do
    [[ -d "$root" ]] || continue
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      if embedded="$(_codex_rollout_id "$candidate")"; then
        if [[ "$embedded" == "$session_id" ]]; then
          _CODEX_SCAN_RESULT="$candidate"
          return 0
        fi
        if [[ -n "$embedded" ]]; then
          _CODEX_SCAN_MISMATCH=$((_CODEX_SCAN_MISMATCH + 1))
        else
          _CODEX_SCAN_NOID=$((_CODEX_SCAN_NOID + 1))
        fi
      else
        _CODEX_SCAN_UNREADABLE=$((_CODEX_SCAN_UNREADABLE + 1))
      fi
    done < <(find "$root" "${find_args[@]}" 2>/dev/null)
  done
  return 0
}

# ── _codex_capture_diag ──────────────────────────────────────────────────────
# 生成采集诊断摘要（REQ-030 "留下明确诊断"）；三项计数皆为 0 时输出空串
_codex_capture_diag() {
  local mismatch="${1:-0}"
  local noid="${2:-0}"
  local unreadable="${3:-0}"

  local -a parts
  parts=()
  [[ "$mismatch" -gt 0 ]] && parts+=("${mismatch} rollout(s) carry a different session id")
  [[ "$noid" -gt 0 ]] && parts+=("${noid} rollout(s) have no embedded session id")
  [[ "$unreadable" -gt 0 ]] && parts+=("${unreadable} rollout(s) unreadable (truncated or invalid session_meta)")
  [[ ${#parts[@]} -gt 0 ]] || return 0

  local IFS='; '
  printf '%s' "${parts[*]}"
}

# ── provider_collect_session ─────────────────────────────────────────────────
# Codex session 采集（DEV-3 / DEV-4）：
# 1. 文件名精确匹配（快路径）→ 仍须按首行内嵌 id 校验内容，文件名与内容不符不采信
# 2. 活动 + 归档全量扫描 → 按首行内嵌 id 校验后复制
# 3. mtime + cwd 退化 → 活动 + 归档目录都参与；已确知属于其他 session 的候选排除
# 中途任何一步失败都只写 capture_status / capture_warning 诊断，不阻塞 oneshot
# 4. 派生 session.history.log（从 provider.stdout.log --json 事件流）
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
  # 活动 sessions/ 与归档 archived_sessions/ 同为采集候选目录（REQ-030）
  local codex_root="${CODEX_HOME:-$HOME/.codex}"
  local codex_session_root="$codex_root/sessions"
  local codex_archived_root="$codex_root/archived_sessions"
  local dst="$round_dir/session.codex.jsonl"

  local -a scan_roots
  scan_roots=()
  [[ -d "$codex_session_root" ]] && scan_roots+=("$codex_session_root")
  [[ -d "$codex_archived_root" ]] && scan_roots+=("$codex_archived_root")

  local found_file=""
  local mismatch=0 noid=0 unreadable=0
  if [[ ${#scan_roots[@]} -gt 0 ]]; then
    # ── Strategy 1: 文件名精确匹配（快路径），仍按内嵌 id 校验 ─────────────────
    _codex_scan_rollouts "$session_id" exact "${scan_roots[@]}"
    found_file="$_CODEX_SCAN_RESULT"
    mismatch=$((mismatch + _CODEX_SCAN_MISMATCH))
    noid=$((noid + _CODEX_SCAN_NOID))
    unreadable=$((unreadable + _CODEX_SCAN_UNREADABLE))

    # ── Strategy 2: 活动 + 归档全量扫描，按内嵌 id 校验 ───────────────────────
    # 归档 rollout 文件名通常不含 thread_id，只有首行内嵌 id 可用。
    # Strategy 1 已扫过的同名文件在此排除，避免诊断计数重复。
    if [[ -z "$found_file" ]]; then
      _codex_scan_rollouts "$session_id" other "${scan_roots[@]}"
      found_file="$_CODEX_SCAN_RESULT"
      mismatch=$((mismatch + _CODEX_SCAN_MISMATCH))
      noid=$((noid + _CODEX_SCAN_NOID))
      unreadable=$((unreadable + _CODEX_SCAN_UNREADABLE))
    fi
  fi

  local diag
  diag="$(_codex_capture_diag "$mismatch" "$noid" "$unreadable")"

  if [[ -n "$found_file" && -f "$found_file" ]]; then
    cp "$found_file" "$dst"
    update_meta_jq "$round_dir" \
      '.capture_status = "ok" | .session_source_path = $src | .session_copied_path = $dst' \
      --arg src "$found_file" --arg dst "$dst"
  else
    # ── Strategy 3: mtime + cwd 退化（活动 + 归档目录都参与）───────────────────
    # 首行有 id 且 != session_id 的候选明确属于其他 session，一律不参与降级；
    # 首行不可解析的候选保留为"未知来源"，仍可作为 mtime 降级证据并留诊断。
    local started_at
    started_at="$(jq -r '.provider_started_at // empty' "$meta" 2>/dev/null)" || started_at=""
    local fallback_file=""

    if [[ -n "$started_at" && "$started_at" != "null" && ${#scan_roots[@]} -gt 0 ]]; then
      local started_epoch buffered_iso anchor_local
      started_epoch="$(ralph_iso_to_epoch "$started_at")" || started_epoch=""
      if [[ -n "$started_epoch" ]]; then
        buffered_iso="$(ralph_epoch_to_iso $((started_epoch - 1)))"
        anchor_local="$(ralph_iso_to_local_find_fmt "$buffered_iso")"
        if [[ -n "$anchor_local" ]]; then
          local candidates
          candidates="$(find "${scan_roots[@]}" -type f -name "rollout-*.jsonl" \
            -newermt "$anchor_local" 2>/dev/null)" || candidates=""

          if [[ -n "$candidates" ]]; then
            local workspace="${_RALPH_WORKSPACE:-$(ralph_workspace_root)}"
            local best_cwd="" kept="" f cid first_line_cwd
            while IFS= read -r f; do
              [[ -n "$f" ]] || continue
              cid="$(_codex_rollout_id "$f")" || cid=""
              # 首行有 id 且不是本 session → 明确属于其他 session，不参与降级
              if [[ -n "$cid" && "$cid" != "$session_id" ]]; then
                continue
              fi
              # Tier 1：降级期内出现的同 id rollout（权威）
              if [[ "$cid" == "$session_id" ]]; then
                fallback_file="$f"
                break
              fi
              # Tier 2：首行 cwd == workspace
              first_line_cwd="$(head -1 "$f" 2>/dev/null | jq -r '.payload.cwd // empty' 2>/dev/null)" || first_line_cwd=""
              if [[ -z "$best_cwd" && "$first_line_cwd" == "$workspace" ]]; then
                best_cwd="$f"
              fi
              kept="${kept}${f}"$'\n'
            done <<< "$candidates"

            # Tier 3：无 id / 无 cwd 命中 → 取 mtime 最新
            if [[ -z "$fallback_file" && -n "$best_cwd" ]]; then
              fallback_file="$best_cwd"
            fi
            if [[ -z "$fallback_file" && -n "$kept" ]]; then
              fallback_file="$(printf '%s' "$kept" | xargs ls -1t 2>/dev/null | head -1)" || fallback_file=""
            fi
          fi
        fi
      fi
    fi

    if [[ -n "$fallback_file" && -f "$fallback_file" ]]; then
      local fallback_warning="fallback by mtime"
      if [[ -n "$diag" ]]; then
        fallback_warning="fallback by mtime; $diag"
      fi
      cp "$fallback_file" "$dst"
      update_meta_jq "$round_dir" \
        '.capture_status = "ok" | .capture_warning = $w | .session_source_path = $src | .session_copied_path = $dst' \
        --arg w "$fallback_warning" --arg src "$fallback_file" --arg dst "$dst"
    else
      local miss_warning="Codex session file not found"
      if [[ -n "$diag" ]]; then
        miss_warning="Codex session file not found: $diag"
      fi
      update_meta_jq "$round_dir" \
        '.capture_status = "warning" | .capture_warning = $w' \
        --arg w "$miss_warning"
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

  # 过滤 JSON 行（provider.stdout.log 含 stdout + stderr 合流；ralph_json_lines
  # 跳过截断/非法行，避免 jq --slurp 因单行损坏而丢掉整段事件流）
  local jsonl_events
  jsonl_events="$(ralph_json_lines "$stdout_log")" || return 0
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
  failed_event="$(ralph_json_lines "$log_path" \
    | jq -c 'select(.type == "turn.failed")' 2>/dev/null \
    | tail -1)" || failed_event=""

  if [[ -n "$failed_event" ]]; then
    error_msg="$(printf '%s' "$failed_event" \
      | jq -r 'if .error | type == "object" then .error.message // "" elif .error | type == "string" then .error else .message // "" end' 2>/dev/null)" || error_msg=""
  fi

  # 回退：查找 error 事件（可能被 retry 覆盖，但仍是线索）
  if [[ -z "$error_msg" ]]; then
    local error_event
    error_event="$(ralph_json_lines "$log_path" \
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
