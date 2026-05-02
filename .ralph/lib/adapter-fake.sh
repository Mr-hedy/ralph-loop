#!/usr/bin/env bash
# adapter-fake.sh — T1 集成测试用 fake adapter
# source 本文件后即设置 RALPH_PROVIDER_CLI；三函数契约

RALPH_PROVIDER_CLI="${RALPH_FAKE_CLI:-bash}"
_RALPH_PP_DONE=0  # partial_progress 状态跟踪；每次 adapter 被 source 时重置

# ── provider_check_deps ──────────────────────────────────────────────────────
provider_check_deps() {
  ralph_require_cmd "$RALPH_PROVIDER_CLI" "fake provider CLI" \
    "test fake; override via RALPH_FAKE_CLI"
}

# ── provider_oneshot ─────────────────────────────────────────────────────────
# <prompt_file> <log_path> <iter_dir>
provider_oneshot() {
  local prompt_file="$1"
  local log_path="$2"
  local iter_dir="$3"
  local scenario="${RALPH_FAKE_SCENARIO:-happy}"
  local sleep_sec="${RALPH_FAKE_SLEEP:-0}"

  mkdir -p "$iter_dir"
  touch "$log_path"

  case "$scenario" in
    happy)
      # 勾选 TASKS.md 中第 1 条未勾选任务
      local tasks_file="${RALPH_WORKSPACE:-.}/.ralph/TASKS.md"
      if [[ -f "$tasks_file" ]]; then
        # 找到第一条 - [ ] 行并替换为 - [x]
        local found=0
        local tmpout
        tmpout="$(mktemp)"
        while IFS= read -r line || [[ -n "$line" ]]; do
          if [[ "$found" -eq 0 && "$line" =~ ^([[:space:]]*-[[:space:]]+)\[[[:space:]]\](.*)$ ]]; then
            printf '%s[x]%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$tmpout"
            found=1
          else
            printf '%s\n' "$line" >> "$tmpout"
          fi
        done < "$tasks_file"
        mv "$tmpout" "$tasks_file"
      fi
      echo "fake: happy scenario completed" | tee -a "$log_path"
      return 0
      ;;
    stagnation)
      # 不改 TASKS.md，不改 git，正常退出
      echo "fake: stagnation scenario" | tee -a "$log_path"
      return 0
      ;;
    crash)
      # 非零退出，无结构化错误
      echo "fake: crash scenario" | tee -a "$log_path"
      return 1
      ;;
    api-error)
      # 非零退出 + stderr 含 api 关键字
      local api_msg="fake: api error occurred: api request failed"
      echo "$api_msg" >> "$log_path"
      echo "$api_msg" >&2
      return 1
      ;;
    partial_progress)
      # iter 1：标记第 1 条任务 + 写一个文件（使 worktree fingerprint 变化）
      # iter 2+：什么都不做（触发 stagnation 累加）
      if [[ "${_RALPH_PP_DONE:-0}" -eq 0 ]]; then
        local tasks_file="${RALPH_WORKSPACE:-.}/.ralph/TASKS.md"
        if [[ -f "$tasks_file" ]]; then
          local found=0 tmpout
          tmpout="$(mktemp)"
          while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$found" -eq 0 && "$line" =~ ^([[:space:]]*-[[:space:]]+)\[[[:space:]]\](.*)$ ]]; then
              printf '%s[x]%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" >> "$tmpout"
              found=1
            else
              printf '%s\n' "$line" >> "$tmpout"
            fi
          done < "$tasks_file"
          mv "$tmpout" "$tasks_file"
        fi
        printf 'partial-progress-iter1\n' > "${RALPH_WORKSPACE:-.}/pp-test-file.txt"
        _RALPH_PP_DONE=1
      fi
      echo "fake: partial_progress scenario (done=$_RALPH_PP_DONE)" | tee -a "$log_path"
      return 0
      ;;
    slow)
      # sleep 远超 timeout；用于 timeout 用例
      local actual_sleep="${sleep_sec:-30}"
      echo "fake: slow scenario, sleeping ${actual_sleep}s" | tee -a "$log_path"
      sleep "$actual_sleep"
      return 0
      ;;
    *)
      echo "fake: unknown scenario: $scenario" >&2
      return 1
      ;;
  esac
}

# ── provider_collect_session ─────────────────────────────────────────────────
provider_collect_session() {
  local iter_dir="$1"
  # fake: 写占位派生视图
  touch "$iter_dir/session.history.log"
  # 更新 meta.json capture_status（若已存在）
  local meta="$iter_dir/meta.json"
  if [[ -f "$meta" ]]; then
    sed -i.bak 's|"capture_status": ".*"|"capture_status": "ok"|' "$meta" 2>/dev/null || true
    rm -f "${meta}.bak"
  fi
  return 0
}

# ── provider_diagnose ────────────────────────────────────────────────────────
provider_diagnose() {
  local iter_dir="$1"
  local log_file="$iter_dir/provider.stdout.log"
  local meta="$iter_dir/meta.json"
  [[ -f "$meta" ]] || return 0

  local exit_code=0
  # 从 meta.json 读取 exit_code
  if [[ -f "$meta" ]]; then
    exit_code="$(grep '"exit_code"' "$meta" | grep -o '[0-9]*' | head -1)" || exit_code=0
  fi

  local error_json="null"
  if [[ "${exit_code:-0}" -ne 0 ]]; then
    if [[ -f "$log_file" ]] && grep -qi "api" "$log_file" 2>/dev/null; then
      error_json='{"type":"api","message":"api error detected","raw":""}'
    else
      error_json='{"type":"unknown","message":"provider exited non-zero","raw":""}'
    fi
  fi

  # 更新 meta.json error 字段（保留尾逗号，与 update_meta_field 模式一致）
  local err_val="$error_json"
  sed -i.bak -E "s|\"error\": [^,}]*(,?)\$|\"error\": ${err_val}\1|" "$meta" 2>/dev/null || true
  rm -f "${meta}.bak"
  return 0
}
