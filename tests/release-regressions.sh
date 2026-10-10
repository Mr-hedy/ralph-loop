#!/usr/bin/env bash
# 由 integration-test.sh source；复用其 workspace、计数与失败汇总。
run_release_regressions() {
  local ws rc run_dir target mutation provider_rc format input_blob expected_blob mutated_path mutation_kept
  local version package stderr_out watch_out
  version="$(sed -n 's/^RALPH_VERSION="\([^"]*\)"$/\1/p' "$REPO_ROOT/.ralph/bin/ralph")"
  package="$REPO_ROOT/release/$version"
  mkdir -p "$REPO_ROOT/.tmp"
  echo "-- Release regressions: protocol integrity and watch details"

  # 冻结前两次 ID 时钟采样，证明同秒重跑保留两个独立 run 及原始结果。
  ws="$(mktemp -d "$REPO_ROOT/.tmp/run-id-release.XXXXXX")"
  cp -R "$package/." "$ws/"
  git -C "$ws" init -q
  cat > "$ws/date-hook.sh" <<'HOOK'
date() {
  if [[ "${1:-}" == -u && "${2:-}" == '+%Y%m%d-%H%M%S' ]]; then
    local sequence=0
    [[ ! -f "$RALPH_TEST_DATE_COUNT" ]] || read -r sequence < "$RALPH_TEST_DATE_COUNT"
    sequence=$(( sequence + 1 ))
    printf '%s\n' "$sequence" > "$RALPH_TEST_DATE_COUNT"
    if [[ "$sequence" -le 2 ]]; then printf '20000101-000000\n'; else printf '20000101-000001\n'; fi
  else command date "$@"; fi
}
HOOK
  rc=0
  env BASH_ENV="$ws/date-hook.sh" RALPH_TEST_DATE_COUNT="$ws/date-count" \
    RALPH_PROVIDER=fake RALPH_FAKE_CLI="$TEST_BASH" RALPH_PROVIDER_CONFIG_DIR="" \
    "$TEST_BASH" "$ws/.ralph/bin/ralph" run > "$ws/out-first" 2> "$ws/err-first" || rc=$?
  run_dir="$(latest_run_dir "$ws")"
  cp "$run_dir/result.json" "$ws/first-result.json"
  local first_run_dir="$run_dir"
  env BASH_ENV="$ws/date-hook.sh" RALPH_TEST_DATE_COUNT="$ws/date-count" \
    RALPH_PROVIDER=fake RALPH_FAKE_CLI="$TEST_BASH" RALPH_PROVIDER_CONFIG_DIR="" \
    "$TEST_BASH" "$ws/.ralph/bin/ralph" run > "$ws/out-second" 2> "$ws/err-second" || rc=$?
  if [[ "$rc" -eq 0 && "$(count_runs "$ws")" -eq 2 ]] \
    && cmp -s "$first_run_dir/result.json" "$ws/first-result.json"; then
    _pass "release run ID: same-second rerun retains two directories and original terminal evidence"
  else
    _fail "release run ID: rc=$rc retained runs=$(count_runs "$ws")"
  fi
  cleanup_ws "$ws"

  # 在隔离的构建根测试完整包校验，不能让同字节的外部软链或其他 skill 混入。
  ws="$(mktemp -d "$REPO_ROOT/.tmp/package-verify.XXXXXX")"
  mkdir -p "$ws/scripts" "$ws/.ralph" "$ws/.agents/skills/ralph" "$ws/release"
  cp "$REPO_ROOT/scripts/build-release.sh" "$ws/scripts/"
  cp -R "$REPO_ROOT/.ralph/bin" "$REPO_ROOT/.ralph/lib" "$ws/.ralph/"
  cp "$REPO_ROOT/.ralph/PROMPT.md" "$REPO_ROOT/.ralph/README.md" "$REPO_ROOT/.ralph/.gitignore" "$ws/.ralph/"
  cp -R "$REPO_ROOT/.spec" "$REPO_ROOT/templates" "$ws/"
  cp "$REPO_ROOT/.agents/skills/ralph/SKILL.md" "$ws/.agents/skills/ralph/"
  cp -R "$package" "$ws/release/$version"
  git -C "$ws" init -q
  "$TEST_BASH" "$ws/scripts/build-release.sh" --verify > "$ws/verify-before" 2>&1
  mv "$ws/release/$version/.ralph/bin/ralph" "$ws/external-cli"
  ln -s "$ws/external-cli" "$ws/release/$version/.ralph/bin/ralph"
  rc=0
  "$TEST_BASH" "$ws/scripts/build-release.sh" --verify > "$ws/verify-symlink" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _pass "release verification rejects byte-identical external CLI symlink"
  else
    _fail "release verification accepted an external CLI symlink"
  fi
  rm "$ws/release/$version/.ralph/bin/ralph"
  mv "$ws/external-cli" "$ws/release/$version/.ralph/bin/ralph"
  mkdir "$ws/release/$version/.agents/skills/unreleased"
  printf 'not authorized for this release\n' > "$ws/release/$version/.agents/skills/unreleased/SKILL.md"
  rc=0
  "$TEST_BASH" "$ws/scripts/build-release.sh" --verify > "$ws/verify-extra" 2>&1 || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    _pass "release verification rejects an additional unshipped skill"
  else
    _fail "release verification accepted an additional skill"
  fi
  cleanup_ws "$ws"

  ws="$(setup_workspace)"
  printf '\nunauthorized change\n' >> "$ws/.ralph/PROMPT.md"
  rc=0
  "$TEST_BASH" "$ws/.ralph/bin/ralph" run --provider fake > "$ws/out" 2> "$ws/err" || rc=$?
  if [[ "$rc" -eq 1 && "$(count_runs "$ws")" -eq 0 && ! -e "$ws/.ralph/lock" && ! -e "$ws/.ralph/status.json" ]]; then
    _pass "protocol startup: modified source rejected before run and lock"
  else
    _fail "protocol startup: rc=$rc runs=$(count_runs "$ws")"
  fi
  cleanup_ws "$ws"

  for target in source snapshot; do
    for mutation in modified removed unreadable; do
      for provider_rc in 0 1; do
        ws="$(setup_workspace)"
        printf '%s\n' '- [ ] DEV-1: test protocol' > "$ws/.ralph/TASKS.md"
        ln -sf "$REPO_ROOT/tests/fixtures/mock-protocol-adapter" "$ws/.ralph/lib/adapter-fake.sh"
        rc=0
        env RALPH_TEST_SOURCE_ROOT="$REPO_ROOT" RALPH_TEST_PROTOCOL_TARGET="$target" \
          RALPH_TEST_PROTOCOL_MUTATION="$mutation" RALPH_TEST_PROTOCOL_RC="$provider_rc" \
          RALPH_LOOP_RETRY_SCHEDULE="0 0" \
          "$TEST_BASH" "$ws/.ralph/bin/ralph" run --provider fake --max-retry 2 > "$ws/out" 2> "$ws/err" || rc=$?
        run_dir="$(latest_run_dir "$ws")"
        mutated_path="$ws/.ralph/PROMPT.md"
        [[ "$target" != "snapshot" ]] || mutated_path="$run_dir/protocol.md"
        mutation_kept=0
        case "$mutation" in
          modified) grep -q 'changed by test' "$mutated_path" && mutation_kept=1 ;;
          removed) [[ ! -e "$mutated_path" ]] && mutation_kept=1 ;;
          unreadable) [[ ! -r "$mutated_path" ]] && mutation_kept=1 ;;
        esac
        if [[ "$rc" -eq 8 && ! -e "$ws/.ralph/lock" && -s "$ws/business.txt" \
             && "$mutation_kept" -eq 1 \
             && "$(wc -l < "$ws/provider-calls.txt" | tr -d ' ')" -eq 1 ]] \
          && jq -e '.exit_reason == "protocol_changed" and .last_error.type == "protocol_changed" and .rounds == 1' "$run_dir/result.json" >/dev/null \
          && jq -e '.state == "finished" and .exit_reason == "protocol_changed"' "$ws/.ralph/status.json" >/dev/null \
          && jq -e '.error.type == "protocol_changed"' "$run_dir/rounds/round-001/meta.json" >/dev/null; then
          _pass "protocol $target/$mutation rc=$provider_rc: exit 8 before done/retry, one dispatch, work kept, lock released"
        else
          _fail "protocol $target/$mutation rc=$provider_rc: rc=$rc run_dir=$run_dir"
          cat "$ws/err"
        fi
        cleanup_ws "$ws"
      done
    done
  done

  # 注入发生在最后一次完整性检查之后、cat 实际读取时的失败。
  for mutation in removed corrupt_read; do
    ws="$(setup_workspace)"
    printf '%s\n' '- [ ] DEV-1: test read failure' > "$ws/.ralph/TASKS.md"
    ln -sf "$REPO_ROOT/tests/fixtures/mock-protocol-adapter" "$ws/.ralph/lib/adapter-fake.sh"
    cat > "$ws/read-hook.sh" <<'HOOK'
cat() {
  if [[ "${1:-}" == */protocol.md ]]; then
    if [[ "$RALPH_TEST_READ_MUTATION" == "removed" ]]; then
      rm -f "$1"
      command cat "$@"
    else
      printf 'corrupted read\n'
    fi
  else
    command cat "$@"
  fi
}
HOOK
    rc=0
    env BASH_ENV="$ws/read-hook.sh" RALPH_TEST_READ_MUTATION="$mutation" RALPH_TEST_SOURCE_ROOT="$REPO_ROOT" \
      "$TEST_BASH" "$ws/.ralph/bin/ralph" run --provider fake > "$ws/out" 2> "$ws/err" || rc=$?
    run_dir="$(latest_run_dir "$ws")"
    if [[ "$rc" -eq 8 && ! -e "$ws/provider-calls.txt" && ! -e "$ws/.ralph/lock" ]] \
      && jq -e '.rounds == 0 and .exit_reason == "protocol_changed"' "$run_dir/result.json" >/dev/null \
      && jq -e '.state == "finished" and .exit_reason == "protocol_changed"' "$ws/.ralph/status.json" >/dev/null; then
      _pass "protocol read $mutation: no dispatch, result/status finished and lock released"
    else
      _fail "protocol read $mutation: rc=$rc run_dir=$run_dir"
      cat "$ws/err"
    fi
    cleanup_ws "$ws"
  done

  for format in sha1 sha256; do
    ws="$(setup_workspace --no-git)"
    if ! git -C "$ws" init -q --object-format="$format"; then
      _fail "protocol $format: Git object format unavailable"
      cleanup_ws "$ws"
      continue
    fi
    printf '%s\n' '- [ ] DEV-1: verify input' > "$ws/.ralph/TASKS.md"
    ln -sf "$REPO_ROOT/tests/fixtures/mock-protocol-adapter" "$ws/.ralph/lib/adapter-fake.sh"
    rc=0
    env RALPH_TEST_SOURCE_ROOT="$REPO_ROOT" RALPH_TEST_PROTOCOL_MUTATION=none \
      "$TEST_BASH" "$ws/.ralph/bin/ralph" run --provider fake > "$ws/out" 2> "$ws/err" || rc=$?
    run_dir="$(latest_run_dir "$ws")"
    expected_blob="$(git -C "$ws" hash-object --no-filters "$ws/.ralph/PROMPT.md")"
    input_blob="$(head -n "$(wc -l < "$ws/.ralph/PROMPT.md" | tr -d ' ')" "$ws/observed-input.txt" | git -C "$ws" hash-object --stdin)"
    if [[ "$rc" -eq 0 && "$input_blob" == "$expected_blob" && ! -e "$ws/.ralph/lock" ]] \
      && cmp "$ws/.ralph/PROMPT.md" "$run_dir/protocol.md" \
      && grep -q '^<ralph-runtime>$' "$ws/observed-input.txt" \
      && jq -e '.exit_reason == "done"' "$run_dir/result.json" >/dev/null; then
      _pass "protocol $format: snapshot and actual oneshot input match, runtime block present"
    else
      _fail "protocol $format: rc=$rc input=$input_blob expected=$expected_blob"
    fi
    cleanup_ws "$ws"
  done

  ws="$(mktemp -d "$REPO_ROOT/.tmp/watch-release.XXXXXX")"
  # 详情与紧凑 watch 都直接使用完整发布包，而非源码软链。
  cp -R "$package/." "$ws/"
  git -C "$ws" init -q
  if python3 "$REPO_ROOT/tests/watch-details-pty.py" "$ws" "$TEST_BASH" > "$ws/pty.log" 2>&1; then
    cat "$ws/pty.log"
    _pass "release watch details: snapshot, events, transient/corrupt status, partial lines, retry rotation, round/run switches, finish and Ctrl-C; compact rotation"
  else
    _fail "release watch details: CLI/TTY regression failed"
    cat "$ws/pty.log"
  fi
  cleanup_ws "$ws"
}
