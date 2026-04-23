#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n "$ROOT/.ralph/bin/ralph" "$ROOT/.ralph/lib/common.sh"
"$ROOT/.ralph/bin/ralph" help >/dev/null

! grep -q "AGENTS.md" "$ROOT/README.md"
! grep -q "npm run check" "$ROOT/README.md"
! grep -q "AGENTS.md" "$ROOT/docs/README.md"
test -f "$ROOT/docs/requirements/ralph-loop/requirements.md"
test -f "$ROOT/docs/requirements.md"
test -f "$ROOT/docs/architecture/overview.md"
test -f "$ROOT/docs/architecture/integrations.md"
test -f "$ROOT/docs/architecture/security.md"
test ! -d "$ROOT/docs/ralph"
test -f "$ROOT/task.md"
test ! -d "$ROOT/ralph"
test ! -f "$ROOT/.ralph/PROMPT.md"
test ! -f "$ROOT/.ralph/TASKS.md"

echo "ralph-loop check passed"
