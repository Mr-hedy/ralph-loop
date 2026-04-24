#!/usr/bin/env bash
# tasks.sh — TASKS.md checklist 解析

# parse_tasks <tasks_file>
# 输出每行：<checked> <title>
# checked = 1（已勾）或 0（未勾）
parse_tasks() {
  local tasks_file="$1"
  [[ -f "$tasks_file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\[([[:space:]])\][[:space:]]+(.*) ]]; then
      printf '0 %s\n' "${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\[([xX])\][[:space:]]+(.*) ]]; then
      printf '1 %s\n' "${BASH_REMATCH[2]}"
    fi
  done < "$tasks_file"
}

# count_total <tasks_file> — 顶层 checklist 总数
count_total() {
  parse_tasks "$1" | wc -l | tr -d '[:space:]'
}

# count_checked <tasks_file> — 已勾数
count_checked() {
  local out
  out="$(parse_tasks "$1" | grep -c '^1 ')" || out=0
  echo "${out:-0}"
}
