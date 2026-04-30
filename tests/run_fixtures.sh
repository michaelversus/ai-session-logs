#!/usr/bin/env bash
# Bash-only fixture tests for find_current_session_transcript.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/session-transcript/bin/find_current_session_transcript.sh"
fail=0
pass() { printf 'ok: %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

TMP=""
cleanup() { [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP" || true; }
trap cleanup EXIT

TMP="$(mktemp -d)"

. "$ROOT/tests/lib/fixtures_common.sh"
. "$ROOT/tests/cases/cli_fixtures.sh"
. "$ROOT/tests/cases/codex_fixtures.sh"
. "$ROOT/tests/cases/cursor_fixtures.sh"
. "$ROOT/tests/cases/claude_fixtures.sh"
. "$ROOT/tests/cases/copilot_fixtures.sh"

run_cli_fixture_tests
run_codex_fixture_tests
run_cursor_fixture_tests
run_claude_fixture_tests
run_copilot_fixture_tests

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'All fixture tests passed.\n'
