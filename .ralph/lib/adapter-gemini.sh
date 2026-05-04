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

  return "$rc"
}

# ── provider_collect_session ─────────────────────────────────────────────────
# DEV-3 将实现完整 session 采集（精确匹配 / mtime fallback / history 派生）
# 此处为 DEV-2 最小桩：设置 capture_status 并保证 session.history.log 存在
provider_collect_session() {
  local iter_dir="$1"
  update_meta_jq "$iter_dir" '.capture_status = "pending"'
  touch "$iter_dir/session.history.log"
  return 0
}

# ── provider_diagnose ────────────────────────────────────────────────────────
# DEV-4 将实现完整错误诊断（stream-json 事件 + stderr 关键字匹配）
# 此处为 DEV-2 最小桩：不做诊断
provider_diagnose() {
  local iter_dir="$1"
  return 0
}
