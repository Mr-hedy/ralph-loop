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
    # 路径类变量值的 tilde 展开（^~/ → $HOME/）
    # .env 不经 shell 解析，~ 不会自动展开；通用规则覆盖所有以 ~/ 开头的值
    # 注意：${val#~/} 会触发 bash tilde-expand，必须用 ${val#\~/} 转义
    if [[ "$val" == "~/"* ]]; then
      val="${HOME}/${val#\~/}"
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

# ── ISO 时间戳 → epoch seconds（跨平台：BSD/GNU date）──────────────────────────
ralph_iso_to_epoch() {
  local iso="$1"
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null \
    || date -u -d "$iso" +%s 2>/dev/null
}

# ── epoch seconds → ISO8601 UTC（跨平台）──────────────────────────────────────
ralph_epoch_to_iso() {
  local epoch="$1"
  date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}

# ── ISO 8601 UTC → "YYYY-MM-DD HH:MM:SS" 本地时间（BSD find -newermt 兼容格式）
# BSD find 在 macOS 上不接受 T 分隔符或 Z 后缀，只接受 local time；GNU find 也支持。
ralph_iso_to_local_find_fmt() {
  local iso="$1"
  local epoch
  epoch="$(ralph_iso_to_epoch "$iso")"
  [[ -n "$epoch" ]] || return 1
  date -r "$epoch" +"%Y-%m-%d %H:%M:%S" 2>/dev/null \
    || date -d "@$epoch" +"%Y-%m-%d %H:%M:%S" 2>/dev/null
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
# 返回自 since_sha 以来变更的文件列表（已提交 ∪ 未提交），过滤 .ralph/ 路径
ralph_changed_files() {
  local since_sha="$1"
  {
    if [[ -n "$since_sha" ]]; then
      git diff --name-only "$since_sha" HEAD 2>/dev/null || true
    fi
    git status --porcelain 2>/dev/null | awk '{print $NF}' || true
  } | grep -v '^\.ralph/' | sort -u || true
}

# ── Worktree fingerprint（stagnation 判据用）────────────────────────────────
# 返回 git ls-files -s + git status -z 的 sha256 摘要，用于本轮 vs 上轮对比。
# 跨平台：sha256sum（Linux/coreutils）→ shasum -a 256（macOS 内置）→ 无 sha 时返回唯一随机值（无 sha 可用时 stagnation 检测安全降级：永不误判）。
ralph_worktree_fingerprint() {
  {
    git ls-files -s 2>/dev/null | grep -v $'\t\.ralph/' || true
    git status -z 2>/dev/null | tr '\0' '\n' | grep -v '\.ralph/' || true
  } | {
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 | cut -d' ' -f1
    else
      echo "nosha-$$-$RANDOM"
    fi
  }
}

# ── 依赖校验框架 ────────────────────────────────────────────────────────────────
# 全局积累数组；由 ralph_require_cmd 写入，ralph_report_missing_deps 读取并打印
_RALPH_MISSING_CMDS=()
_RALPH_MISSING_PURPOSES=()
_RALPH_MISSING_HINTS=()

# ralph_require_cmd <cmd> <purpose> <install_hint> [min_version]
# 检查 cmd 是否在 PATH 中；不在则追加进全局数组，不立即 fail。
# min_version 预留位：本期传值会被忽略。
ralph_require_cmd() {
  local cmd="$1"
  local purpose="$2"
  local install_hint="$3"
  # $4 = min_version; reserved, not implemented
  if ! command -v "$cmd" >/dev/null 2>&1; then
    _RALPH_MISSING_CMDS+=("$cmd")
    _RALPH_MISSING_PURPOSES+=("$purpose")
    _RALPH_MISSING_HINTS+=("$install_hint")
  fi
}

# ralph_report_missing_deps
# 若数组非空，按统一格式打印所有缺失依赖到 stderr，返回 1。
# 格式：ralph: missing dependency: <cmd> (<purpose>)\n  <install_hint line>...
ralph_report_missing_deps() {
  [[ "${#_RALPH_MISSING_CMDS[@]}" -eq 0 ]] && return 0
  local i hline
  for i in "${!_RALPH_MISSING_CMDS[@]}"; do
    printf 'ralph: missing dependency: %s (%s)\n' \
      "${_RALPH_MISSING_CMDS[$i]}" "${_RALPH_MISSING_PURPOSES[$i]}" >&2
    if [[ -n "${_RALPH_MISSING_HINTS[$i]}" ]]; then
      while IFS= read -r hline; do
        [[ -n "$hline" ]] && printf '  %s\n' "$hline" >&2
      done <<< "${_RALPH_MISSING_HINTS[$i]}"
    fi
  done
  return 1
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
