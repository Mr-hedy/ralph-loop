#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# 沿用调用者的解释器；macOS 基线检查显式用 /bin/bash 启动。
syntax_bash="$BASH"
# bash -n 后的多个文件会成为首个脚本的参数，必须逐文件检查。
for shell_file in "$ROOT/.ralph/bin/ralph" "$ROOT"/.ralph/lib/*.sh \
  "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh "$ROOT"/tests/fixtures/mock-*; do
  "$syntax_bash" -n "$shell_file"
done
"$syntax_bash" "$ROOT/.ralph/bin/ralph" help >/dev/null
test -f "$ROOT/scripts/integration-test.sh"

if grep -q "npm run check" "$ROOT/README.md"; then
  echo "README.md points to an unsupported npm check command" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*![[:space:]]*grep([[:space:]]|$)' "$ROOT/scripts/check.sh"; then
  echo "check.sh contains a negated grep gate that set -e may ignore" >&2
  exit 1
fi
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
  "$ROOT/docs/architecture.md" \
  "$ROOT/docs/testing.md" \
  "$ROOT/scripts"; then
  echo "stale lowercase .spec rule reference in active files" >&2
  exit 1
fi
test -f "$ROOT/docs/features/ralph-loop/requirements.md"
test -f "$ROOT/docs/features/ralph-loop/history/index.md"
test -f "$ROOT/docs/features/vibecoding-collaboration/requirements.md"
test -f "$ROOT/docs/features/vibecoding-collaboration/solution.md"
test -f "$ROOT/docs/requirements.md"
test -f "$ROOT/docs/architecture.md"
test -f "$ROOT/docs/integrations.md"
test -f "$ROOT/docs/security.md"
test -f "$ROOT/docs/testing.md"
test ! -d "$ROOT/docs/ralph"
test ! -d "$ROOT/docs/requirements"
test ! -d "$ROOT/docs/architecture"
test ! -d "$ROOT/docs/collaboration"
test -f "$ROOT/task.md"
test ! -d "$ROOT/ralph"
test -f "$ROOT/.ralph/PROMPT.md"
test -f "$ROOT/.ralph/TASKS.md"
current_version="$(sed -n 's/^RALPH_VERSION="\([^"]*\)"$/\1/p' "$ROOT/.ralph/bin/ralph")"
[[ -n "$current_version" ]] || { echo "RALPH_VERSION not found" >&2; exit 1; }
current_release="$ROOT/release/$current_version"
bash_min_version="$(sed -n 's/^RALPH_BASH_MIN_VERSION="\([^"]*\)"$/\1/p' "$ROOT/.ralph/bin/ralph")"
[[ "$bash_min_version" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "invalid Bash minimum version" >&2; exit 1; }
# 只核对版本值和模板占位；生成说明由完整发布包比对验证。
readme_bash_version="$(grep -Eo 'Bash[[:space:]]+[0-9]+(\.[0-9]+)?\+' "$ROOT/README.md" \
  | sed 's/^Bash[[:space:]]*//; s/+$//' | sort -u)" || readme_bash_version=""
[[ "$readme_bash_version" == "$bash_min_version" ]] \
  || { echo "README Bash requirement differs from runtime minimum" >&2; exit 1; }
grep -q 'Bash[[:space:]][[:space:]]*__BASH_MIN_VERSION__+' \
  "$ROOT/templates/RELEASE-README.md" \
  || { echo "release template must generate the Bash minimum version" >&2; exit 1; }
[[ -d "$current_release/.spec" ]] || { echo "current release .spec missing: $current_release" >&2; exit 1; }
if ! diff -rq "$ROOT/.spec" "$current_release/.spec" >/dev/null; then
  echo "current release .spec is out of sync with root .spec: $current_release" >&2
  exit 1
fi
for source_file in "$ROOT/.ralph/bin/ralph" "$ROOT/.ralph/PROMPT.md" "$ROOT/.ralph/README.md" "$ROOT/.ralph/.gitignore"; do
  package_file="$current_release/${source_file#"$ROOT"/}"
  cmp -s "$source_file" "$package_file" || { echo "release file out of sync: $package_file" >&2; exit 1; }
done
for source_file in "$ROOT"/.ralph/lib/*.sh; do
  package_file="$current_release/${source_file#"$ROOT"/}"
  cmp -s "$source_file" "$package_file" || { echo "release file out of sync: $package_file" >&2; exit 1; }
done
test ! -e "$current_release/.codex"
test -f "$current_release/.agents/skills/ralph/SKILL.md"
cmp -s "$ROOT/.agents/skills/ralph/SKILL.md" "$current_release/.agents/skills/ralph/SKILL.md"
test -x "$current_release/.ralph/bin/ralph"
test -L "$current_release/CLAUDE.md"
[[ "$(readlink "$current_release/CLAUDE.md")" == AGENTS.md ]]
cmp -s "$ROOT/templates/AGENTS.md" "$current_release/AGENTS.md"
grep -Fxq "# Ralph Loop $current_version" "$current_release/README.md"
test -f "$current_release/.ralph/.env.example"
for runtime_file in .ralph/.env .ralph/status.json .ralph/lock; do
  test ! -e "$current_release/$runtime_file"
done
test ! -d "$current_release/.ralph/runs"
if grep -Eq '^[[:space:]]*-[[:space:]]+\[[ xX]\]' "$current_release/.ralph/TASKS.md"; then
  echo "release TASKS.md must be an empty initialization template" >&2
  exit 1
fi
"$syntax_bash" "$ROOT/scripts/build-release.sh" --verify >/dev/null

echo "ralph-loop check passed"
