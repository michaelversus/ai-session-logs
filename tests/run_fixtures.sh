#!/usr/bin/env bash
# Bash-only fixture tests for find_current_session_transcript.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/find_current_session_transcript.sh"
fail=0
pass() { printf 'ok: %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

TMP=""
cleanup() { [[ -n "${TMP:-}" && -d "$TMP" ]] && rm -rf "$TMP" || true; }
trap cleanup EXIT

TMP="$(mktemp -d)"

# --- Codex + CODEX_THREAD_ID ---
mkdir -p "$TMP/h1/.codex/sessions/2026/01/01"
echo '{"role":"user"}' >"$TMP/h1/.codex/sessions/2026/01/01/rollout-abc-mythreadid.jsonl"
mkdir -p "$TMP/proj1"
git -C "$TMP/proj1" init -q
(
  export HOME="$TMP/h1"
  export CODEX_THREAD_ID=mythreadid
  out="$(bash "$SCRIPT" --project-root="$TMP/proj1" --tool codex --no-copy)"
  echo "$out" | grep -q '^TOOL=codex' || err "codex forced: missing TOOL=codex"
  echo "$out" | grep -q '^SOURCE=.*mythreadid\.jsonl$' || err "codex forced: SOURCE should match thread id file"
  echo "$out" | grep -q '^CONFIDENCE=high' || err "codex forced: CONFIDENCE high"
  pass "codex --tool with CODEX_THREAD_ID match"
)

# --- Invalid flag exit 2 ---
if bash "$SCRIPT" --not-a-flag 2>/dev/null; then
  err "unknown flag should not succeed"
else
  ec=$?
  [[ "$ec" -eq 2 ]] || err "unknown flag exit code want 2 got $ec"
  pass "unknown flag exits 2"
fi

# --- Invalid --tool exit 2 ---
if bash "$SCRIPT" --tool=nope --no-copy 2>/dev/null; then
  err "invalid tool should not succeed"
else
  ec=$?
  [[ "$ec" -eq 2 ]] || err "invalid tool exit want 2 got $ec"
  pass "invalid --tool exits 2"
fi

# --- dry-run creates no output file ---
mkdir -p "$TMP/h2/.codex/sessions"
echo '{}' >"$TMP/h2/.codex/sessions/rollout-only.jsonl"
mkdir -p "$TMP/proj2"
git -C "$TMP/proj2" init -q
(
  export HOME="$TMP/h2"
  unset CODEX_THREAD_ID || true
  out="$(bash "$SCRIPT" --project-root="$TMP/proj2" --tool codex --dry-run)"
  echo "$out" | grep -q '^DEST=' || err "dry-run: missing DEST"
  dest="$(echo "$out" | sed -n 's/^DEST=//p')"
  [[ -f "$dest" ]] && err "dry-run: DEST file should not exist" || true
  pass "dry-run writes no file"
)

# --- Default copy creates file under project root ---
mkdir -p "$TMP/h3/.codex/sessions"
echo '{"ok":true}' >"$TMP/h3/.codex/sessions/rollout-copytest.jsonl"
mkdir -p "$TMP/proj3"
git -C "$TMP/proj3" init -q
(
  export HOME="$TMP/h3"
  unset CODEX_THREAD_ID || true
  bash "$SCRIPT" --project-root="$TMP/proj3" --tool codex >/dev/null
  shopt -s nullglob
  files=("$TMP/proj3"/.ai-session-logs/*.jsonl)
  [[ "${#files[@]}" -ge 1 ]] || err "copy: expected at least one jsonl under .ai-session-logs"
  pass "default copy writes under project .ai-session-logs"
)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'All fixture tests passed.\n'
