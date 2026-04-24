#!/usr/bin/env bash
# session.sh — meta.json 读写骨架 + 派生视图 stub

# write_meta <iter_dir> <json_fragment>
# 写或合并 iter_dir/meta.json；json_fragment 是完整 JSON 对象字符串
write_meta() {
  local iter_dir="$1"
  local json="$2"
  mkdir -p "$iter_dir"
  printf '%s\n' "$json" > "$iter_dir/meta.json"
}

# init_meta <iter_dir> <iteration> <provider> <exit_code> <duration_ms>
# 写初始 meta.json 骨架
init_meta() {
  local iter_dir="$1"
  local iteration="$2"
  local provider="$3"
  local exit_code="$4"
  local duration_ms="$5"
  mkdir -p "$iter_dir"
  cat > "$iter_dir/meta.json" <<EOF
{
  "iteration": ${iteration},
  "provider": "$(ralph_json_escape "$provider")",
  "session_id": null,
  "session_source_path": null,
  "session_copied_path": null,
  "capture_status": "ok",
  "capture_warning": null,
  "exit_code": ${exit_code},
  "duration_ms": ${duration_ms},
  "error": null,
  "changed_files": [],
  "tasks_before": null,
  "tasks_after": null,
  "stagnation_count": 0
}
EOF
}

# update_meta_field <iter_dir> <field> <json_value>
# 用 sed 原地替换 meta.json 中的 "field": <oldval> 行；仅适用于简单标量字段
# 保留原有尾逗号（非末尾字段有逗号，末尾字段无逗号）
update_meta_field() {
  local iter_dir="$1"
  local field="$2"
  local json_val="$3"
  local meta="$iter_dir/meta.json"
  [[ -f "$meta" ]] || return 1
  # [^,}]* 匹配标量值（到逗号或右花括号为止），(,?) 捕获可选尾逗号并原样保留
  sed -i.bak -E "s|\"${field}\": [^,}]*(,?)\$|\"${field}\": ${json_val}\1|" "$meta" 2>/dev/null || true
  rm -f "${meta}.bak"
}
