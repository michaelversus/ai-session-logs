#!/usr/bin/env bash

run_claude_fixture_tests() {
  local proj slug

  # --- Claude forced path resolves a transcript with user messages ---
  proj="$TMP/proj6"
  mkdir -p "$proj"
  git -C "$proj" init -q
  slug="$(make_slug "$proj")"
  mkdir -p "$TMP/h6/.claude/projects/$slug/sessions"
  echo '{"role":"user","note":"session-transcript"}' >"$TMP/h6/.claude/projects/$slug/sessions/current.jsonl"
  (
    export HOME="$TMP/h6"
    out="$(bash "$SCRIPT" --project-root="$proj" --tool claude --no-copy)"
    echo "$out" | grep -q '^TOOL=claude' || err "claude forced: missing TOOL=claude"
    echo "$out" | grep -q '^SOURCE=.*current\.jsonl$' || err "claude forced: expected current.jsonl"
    pass "claude forced path resolves transcript with user messages"
  )
}