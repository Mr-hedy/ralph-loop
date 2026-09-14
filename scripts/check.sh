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

echo "ralph-loop check passed"
