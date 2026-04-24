#!/usr/bin/env bash

# ── 基础错误函数 ────────────────────────────────────────────────────────────

ralph_die() {
  echo "ralph: $*" >&2
  exit 1
}

ralph_usage_error() {
  echo "ralph: $*" >&2
  exit 2
}

ralph_abs_dir() {
  local path="$1"
  mkdir -p "$path" || return 1
  cd "$path" >/dev/null 2>&1 && pwd -P
}

# ── Workspace 自定位 ────────────────────────────────────────────────────────
# 调用方：source 本文件后调用 ralph_workspace_root
# 返回：workspace 根（.ralph/lib/../../ = workspace）
ralph_workspace_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  cd "$lib_dir/../.." && pwd -P
}

# ── .env 加载 ───────────────────────────────────────────────────────────────
# 只读 RALPH_* key；剥离值两端单/双引号；不 source；忽略注释和空行
# 用法：load_env <env_file>
# 副作用：export 各 RALPH_* 变量（仅当变量当前未设或值为空时才从文件读取，
#          以保证 CLI flag > 进程 env > .env 优先级）
load_env() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0
  local line key raw_val val
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 跳过注释和空行
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    # 只处理 RALPH_* 赋值行
    [[ "$line" =~ ^[[:space:]]*(RALPH_[A-Z_]+)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    raw_val="${BASH_REMATCH[2]}"
    # 剥离两端引号（单引号或双引号）
    if [[ "$raw_val" =~ ^\'(.*)\'$ ]] || [[ "$raw_val" =~ ^\"(.*)\"$ ]]; then
      val="${BASH_REMATCH[1]}"
    else
      val="$raw_val"
    fi
    # 优先级：进程 env > .env（仅当未设时才赋值）
    if [[ -z "${!key+x}" ]] || [[ -z "${!key}" ]]; then
      export "$key=$val"
    fi
  done < "$env_file"
}

# ── UUID 生成 ───────────────────────────────────────────────────────────────
# 三路 fallback；支持 RALPH_UUID_FORCE_FAIL=1 测试钩子
ralph_uuid() {
  if [[ "${RALPH_UUID_FORCE_FAIL:-}" == "1" ]]; then
    echo "ralph: startup check failed: UUID generation failed (RALPH_UUID_FORCE_FAIL=1)" >&2
    return 1
  fi
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import uuid; print(uuid.uuid4())"
    return 0
  fi
  echo "ralph: startup check failed: UUID generation failed (no uuidgen / /proc / python3)" >&2
  return 1
}

# ── ISO8601 时间戳 ──────────────────────────────────────────────────────────
ralph_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ── run_id 生成 ─────────────────────────────────────────────────────────────
# 格式：YYYYMMDD-HHMMSS-<7位 git short sha>；无提交时用 nogit
ralph_run_id() {
  local ts short_sha
  ts="$(date -u +"%Y%m%d-%H%M%S")"
  short_sha="$(git rev-parse --short=7 HEAD 2>/dev/null)" || short_sha="nogit"
  echo "${ts}-${short_sha}"
}

# ── lock 封装（跨平台：noclobber + PID 文件）────────────────────────────────
# 用法：ralph_lock_acquire <lock_file>
# 返回 0 = 成功；1 = 已被占用（locked）
# lock_file 内容为持有进程 PID，释放时删除文件
ralph_lock_acquire() {
  local lock_file="$1"
  mkdir -p "$(dirname "$lock_file")"
  # set -o noclobber 使 > 对已存在文件失败（原子性由 O_CREAT|O_EXCL 保证）
  if ( set -o noclobber; echo "$$" > "$lock_file" ) 2>/dev/null; then
    return 0
  fi
  # 文件存在；检查持有者进程是否仍活着
  local owner_pid
  owner_pid="$(cat "$lock_file" 2>/dev/null)" || return 1
  if [[ -n "$owner_pid" ]] && kill -0 "$owner_pid" 2>/dev/null; then
    return 1  # 进程仍活着，锁有效
  fi
  # Stale lock：持有者已死；v0.1 不自动清理，返回 locked 让用户手动处理
  return 1
}

ralph_lock_release() {
  local lock_file="$1"
  rm -f "$lock_file" 2>/dev/null || true
}

# ── changed_files 收集 ──────────────────────────────────────────────────────
# 返回自 start_sha 以来变更的文件列表（已提交 ∪ 未提交），过滤 .ralph/ 路径
ralph_changed_files() {
  local start_sha="$1"
  {
    if [[ -n "$start_sha" ]]; then
      git diff --name-only "$start_sha" HEAD 2>/dev/null || true
    fi
    git status --porcelain 2>/dev/null | awk '{print $NF}' || true
  } | grep -v '^\.ralph/' | sort -u || true
}

# ── 最小 JSON emit helpers ───────────────────────────────────────────────────
# 把字符串转义为 JSON 字符串值（不含两端引号）
ralph_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# JSON null-or-string：若值为空输出 null，否则输出 "value"
ralph_json_str() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(ralph_json_escape "$v")"
  fi
}

# JSON null-or-number：若值为空输出 null，否则直接输出数字
ralph_json_num() {
  local v="$1"
  if [[ -z "$v" ]]; then
    printf 'null'
  else
    printf '%s' "$v"
  fi
}
