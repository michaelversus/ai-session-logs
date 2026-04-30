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
mkdir -p "$TMP/h1/.codex"
echo '{"id":"mythreadid","thread_name":"fixture","updated_at":"2026-01-01T00:00:00Z"}' >"$TMP/h1/.codex/session_index.jsonl"
mkdir -p "$TMP/h1/.codex/sessions/2026/01/01"
echo '{"role":"user","note":"session-transcript"}' >"$TMP/h1/.codex/sessions/2026/01/01/rollout-abc-mythreadid.jsonl"
mkdir -p "$TMP/proj1"
git -C "$TMP/proj1" init -q
(
  export HOME="$TMP/h1"
  export CODEX_THREAD_ID=mythreadid
  out="$(bash "$SCRIPT" --project-root="$TMP/proj1" --tool codex --no-copy)"
  echo "$out" | grep -q '^TOOL=codex' || err "codex forced: missing TOOL=codex"
  echo "$out" | grep -q '^SOURCE=.*mythreadid\.jsonl$' || err "codex forced: SOURCE should match thread id file"
  echo "$out" | grep -q '^CONFIDENCE=high' || err "codex forced: CONFIDENCE high"
  echo "$out" | grep -q '^SKILL_TRACE=verified' || err "codex forced: SKILL_TRACE verified"
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
echo '{"x":1,"use":"session-transcript"}' >"$TMP/h2/.codex/sessions/rollout-only.jsonl"
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
echo '{"ok":true,"skill":"session-transcript"}' >"$TMP/h3/.codex/sessions/rollout-copytest.jsonl"
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

# --- Skill trace: skip newer without trace, pick older with trace (Cursor) ---
PROJ="$TMP/wstrace"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
slug="$(cd "$PROJ" && pwd -P)"
slug="${slug#/}"
slug="${slug//\//-}"
slug="${slug//./-}"
mkdir -p "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1"
mkdir -p "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2"
echo '{"n":"newest","no":"trace-here"}' >"$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1/newest.jsonl"
echo '{"n":"older","use":"session-transcript"}' >"$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2/older.jsonl"
touch -t 205001010000 "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1/newest.jsonl"
touch -t 202001010000 "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2/older.jsonl"
(
  export HOME="$TMP/h4"
  out="$(bash "$SCRIPT" --project-root="$PROJ" --tool cursor --no-copy)"
  echo "$out" | grep -q '^SOURCE=.*older\.jsonl$' || err "cursor trace: expected older.jsonl with skill trace"
  echo "$out" | grep -q '^SKILL_TRACE=verified' || err "cursor trace: SKILL_TRACE verified"
  pass "cursor prefers older transcript that contains skill trace"
)

(
  export HOME="$TMP/h4"
  out="$(bash "$SCRIPT" --project-root="$PROJ" --tool cursor --no-copy --skip-skill-trace)"
  echo "$out" | grep -q '^SOURCE=.*newest\.jsonl$' || err "skip trace: expected newest.jsonl"
  echo "$out" | grep -q '^SKILL_TRACE=skipped' || err "skip trace: SKILL_TRACE skipped"
  pass "cursor --skip-skill-trace picks newest"
)

# --- Codex session_index.jsonl order beats mtime (both have skill trace) ---
mkdir -p "$TMP/h5/.codex/sessions"
echo '{"id":"oldidx","thread_name":"old","updated_at":"2020-01-01T00:00:00Z"}' >"$TMP/h5/.codex/session_index.jsonl"
echo '{"id":"newidx","thread_name":"new","updated_at":"2026-01-02T00:00:00Z"}' >>"$TMP/h5/.codex/session_index.jsonl"
echo '{"x":1,"use":"session-transcript"}' >"$TMP/h5/.codex/sessions/rollout-oldidx.jsonl"
echo '{"x":2,"use":"session-transcript"}' >"$TMP/h5/.codex/sessions/rollout-newidx.jsonl"
touch -t 205001010000 "$TMP/h5/.codex/sessions/rollout-oldidx.jsonl"
touch -t 202001010000 "$TMP/h5/.codex/sessions/rollout-newidx.jsonl"
mkdir -p "$TMP/proj5"
git -C "$TMP/proj5" init -q
(
  export HOME="$TMP/h5"
  unset CODEX_THREAD_ID || true
  out="$(bash "$SCRIPT" --project-root="$TMP/proj5" --tool codex --no-copy)"
  echo "$out" | grep -q '^SOURCE=.*rollout-newidx\.jsonl$' || err "codex index: expected newer-index session (newidx) despite older mtime"
  pass "codex session_index order preferred over mtime"
)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
printf 'All fixture tests passed.\n'
