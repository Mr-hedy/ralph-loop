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

# first_unchecked_task <tasks_file>
# 输出第一个未勾选任务的标题（不含 "- [ ] " 前缀）
# 如无未勾选任务则输出空
first_unchecked_task() {
  local tasks_file="$1"
  [[ -f "$tasks_file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\[[[:space:]]\][[:space:]]+(.*) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$tasks_file"
}

# is_blocked_by_human <tasks_file>
# 返回 0 当第一个未勾选任务前缀是 HUMAN-（如 HUMAN-1、HUMAN-12）
# 返回 1 否则
is_blocked_by_human() {
  local tasks_file="$1"
  local first
  first="$(first_unchecked_task "$tasks_file")"
  [[ -z "$first" ]] && return 1
  [[ "$first" =~ ^HUMAN-[0-9]+ ]] && return 0
  return 1
}

# parse_current_iteration <tasks_file>
# 解析 TASKS.md 顶部 "> 当前迭代: <name>" 声明，输出 <name>
# 找不到则输出空字符串
# 注意：冒号必须是 ASCII ":"；中文全角冒号 "：" 不识别（启动校验会报错）
parse_current_iteration() {
  local tasks_file="$1"
  [[ -f "$tasks_file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\>[[:space:]]*当前迭代:[[:space:]]*([^[:space:]]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
    # 英文兼容：> Current iteration: <name>
    if [[ "$line" =~ ^\>[[:space:]]*[Cc]urrent[[:space:]]+iteration:[[:space:]]*([^[:space:]]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "$tasks_file"
}

# validate_task_prefixes <tasks_file>
# 扫描所有顶层任务（含 [x]），检查任务前缀（满足 <字母>-<数字>: 模式）必须全大写英文。
# 失败时向 stderr 输出违规清单，返回 1；通过返回 0。
# 规则：
#   - 不带前缀的任务视为默认 DEV，跳过校验（向后兼容 v0.1 已有用例）
#   - 看起来像前缀的（^[A-Za-z]+-[0-9]+:）必须前缀部分全大写
#   - 其他描述性内容（无前缀-数字-冒号结构）一律跳过
validate_task_prefixes() {
  local tasks_file="$1"
  [[ -f "$tasks_file" ]] || return 0
  local errors=()
  local lineno=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$(( lineno + 1 ))
    # 顶层 - [ ] / - [x] / - [X]
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\][[:space:]]+(.*) ]]; then
      local title="${BASH_REMATCH[1]}"
      # 像前缀的：字母+连字符+数字+冒号
      if [[ "$title" =~ ^([A-Za-z]+)-([0-9]+): ]]; then
        local prefix="${BASH_REMATCH[1]}"
        if [[ ! "$prefix" =~ ^[A-Z]+$ ]]; then
          errors+=("line ${lineno}: prefix '${prefix}-' must be all uppercase (got: ${title%%:*}:)")
        fi
      fi
    fi
  done < "$tasks_file"
  if [[ ${#errors[@]} -gt 0 ]]; then
    printf 'TASKS.md: invalid task prefix (must be UPPERCASE):\n' >&2
    printf '  %s\n' "${errors[@]}" >&2
    return 1
  fi
  return 0
}
