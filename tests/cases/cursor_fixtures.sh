#!/usr/bin/env bash

run_cursor_fixture_tests() {
  local proj slug

  # --- Skill trace: skip newer without trace, pick older with trace (Cursor) ---
  proj="$TMP/wstrace"
  mkdir -p "$proj"
  git -C "$proj" init -q
  slug="$(make_slug "$proj")"
  mkdir -p "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1"
  mkdir -p "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2"
  echo '{"role":"user","n":"newest","no":"trace-here"}' >"$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1/newest.jsonl"
  echo '{"role":"user","n":"older","use":"session-transcript"}' >"$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2/older.jsonl"
  touch -t 205001010000 "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d1/newest.jsonl"
  touch -t 202001010000 "$TMP/h4/.cursor/projects/$slug/agent-transcripts/d2/older.jsonl"
  (
    export HOME="$TMP/h4"
    out="$(bash "$SCRIPT" --project-root="$proj" --tool cursor --no-copy)"
    echo "$out" | grep -q '^SOURCE=.*older\.jsonl$' || err "cursor trace: expected older.jsonl with skill trace"
    echo "$out" | grep -q '^SKILL_TRACE=verified' || err "cursor trace: SKILL_TRACE verified"
    pass "cursor prefers older transcript that contains skill trace"
  )

  # --- Skill trace accepts package/plugin name ---
  mkdir -p "$TMP/h4b/.cursor/projects/$slug/agent-transcripts"
  echo '{"role":"user","n":"package","use":"ai-session-logs"}' >"$TMP/h4b/.cursor/projects/$slug/agent-transcripts/package-name.jsonl"
  (
    export HOME="$TMP/h4b"
    out="$(bash "$SCRIPT" --project-root="$proj" --tool cursor --no-copy)"
    echo "$out" | grep -q '^SOURCE=.*package-name\.jsonl$' || err "package trace: expected ai-session-logs transcript"
    echo "$out" | grep -q '^SKILL_TRACE=verified' || err "package trace: SKILL_TRACE verified"
    pass "skill trace accepts ai-session-logs package name"
  )

  (
    export HOME="$TMP/h4"
    out="$(bash "$SCRIPT" --project-root="$proj" --tool cursor --no-copy --skip-skill-trace)"
    echo "$out" | grep -q '^SOURCE=.*newest\.jsonl$' || err "skip trace: expected newest.jsonl"
    echo "$out" | grep -q '^SKILL_TRACE=skipped' || err "skip trace: SKILL_TRACE skipped"
    pass "cursor --skip-skill-trace picks newest"
  )
}