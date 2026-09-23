#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n "$ROOT/.ralph/bin/ralph" \
  "$ROOT/.ralph/lib/common.sh" \
  "$ROOT/.ralph/lib/tasks.sh" \
  "$ROOT/.ralph/lib/session.sh" \
  "$ROOT/.ralph/lib/adapter-claude.sh" \
  "$ROOT/.ralph/lib/adapter-codex.sh" \
  "$ROOT/.ralph/lib/adapter-fake.sh" \
  "$ROOT/.ralph/lib/run.sh"
"$ROOT/.ralph/bin/ralph" help >/dev/null
test -f "$ROOT/scripts/integration-test.sh"
# 测试层语法检查（QA-1）：集成测试脚本与 mock fixture 都是 bash 脚本，
# 语法错误在测试运行期会表现为难以定位的用例失败，提前到静态检查。
bash -n "$ROOT/scripts/integration-test.sh" \
  "$ROOT/tests/fixtures/mock-claude" \
  "$ROOT/tests/fixtures/mock-codex" \
  "$ROOT/tests/fixtures/mock-gemini"

! grep -q "AGENTS.md" "$ROOT/README.md"
! grep -q "npm run check" "$ROOT/README.md"
! grep -q "AGENTS.md" "$ROOT/docs/README.md"
# Spec assets use uppercase filenames; docs and runtime naming are separate contracts.
for spec_rule in ADVERSARIAL-REVIEW ARCHITECTURE DOCS REQUIREMENTS REVIEW ROADMAP SOLUTION TASKS TESTING TROUBLESHOOTING; do
  test -f "$ROOT/.spec/rules/$spec_rule.md"
done
for spec_template in DOCS-README REQUIREMENTS SOLUTION TESTING TROUBLESHOOTING; do
  test -f "$ROOT/.spec/rules/templates/$spec_template.md"
done
while IFS= read -r spec_file; do
  spec_name="${spec_file##*/}"
  case "$spec_name" in
    *.md) spec_stem="${spec_name%.md}" ;;
    *)
      echo "unexpected .spec filename extension: $spec_file" >&2
      exit 1
      ;;
  esac
  spec_upper="$(printf '%s' "$spec_stem" | tr '[:lower:]' '[:upper:]')"
  if [[ "$spec_stem" != "$spec_upper" ]]; then
    echo "uppercase .spec filename required: $spec_file" >&2
    exit 1
  fi
done < <(find "$ROOT/.spec/rules" -maxdepth 2 -type f)
# Active entrypoints must use the current uppercase rule paths. Historical
# checkpoints, research notes, and immutable archives may retain old paths.
if grep -REn '\.spec/rules/(adversarial-review|architecture|docs|requirements|review|roadmap|solution|tasks|testing)\.md' \
  "$ROOT/.ralph/TASKS.md" \
  "$ROOT/.ralph/PROMPT.md" \
  "$ROOT/AGENTS.md" \
  "$ROOT/README.md" \
  "$ROOT/docs/README.md" \
  "$ROOT/docs/architecture/overview.md" \
  "$ROOT/docs/architecture/testing.md" \
  "$ROOT/scripts"; then
  echo "stale lowercase .spec rule reference in active files" >&2
  exit 1
fi
test -f "$ROOT/docs/requirements/ralph-loop/requirements.md"
test -f "$ROOT/docs/requirements.md"
test -f "$ROOT/docs/architecture/overview.md"
test -f "$ROOT/docs/architecture/integrations.md"
test -f "$ROOT/docs/architecture/security.md"
test ! -d "$ROOT/docs/ralph"
test -f "$ROOT/task.md"
test ! -d "$ROOT/ralph"
test -f "$ROOT/.ralph/PROMPT.md"
test -f "$ROOT/.ralph/TASKS.md"
current_version="$(sed -n 's/^RALPH_VERSION="\([^"]*\)"$/\1/p' "$ROOT/.ralph/bin/ralph")"
[[ -n "$current_version" ]] || { echo "RALPH_VERSION not found" >&2; exit 1; }
current_release="$ROOT/release/$current_version"
[[ -d "$current_release/.spec" ]] || { echo "current release .spec missing: $current_release" >&2; exit 1; }
if ! diff -rq "$ROOT/.spec" "$current_release/.spec" >/dev/null; then
  echo "current release .spec is out of sync with root .spec: $current_release" >&2
  exit 1
fi

echo "ralph-loop check passed"
