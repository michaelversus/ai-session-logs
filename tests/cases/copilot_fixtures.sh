#!/usr/bin/env bash

run_copilot_fixture_tests() {
  local proj ws

  # --- Copilot forced path resolves transcript ---
  mkdir -p "$TMP/proj7"
  git -C "$TMP/proj7" init -q
  proj="$(cd "$TMP/proj7" && pwd -P)"
  ws="$TMP/h7/Library/Application Support/Code/User/workspaceStorage/ws1"
  mkdir -p "$ws/GitHub.copilot-chat/transcripts"
  printf '{"folder":"%s"}\n' "$proj" >"$ws/workspace.json"
  echo '{"type":"user.message","data":{"content":"session-transcript user content"}}' >"$ws/GitHub.copilot-chat/transcripts/current.jsonl"
  (
    export HOME="$TMP/h7"
    out="$(bash "$SCRIPT" --project-root="$proj" --tool copilot --no-copy)"
    echo "$out" | grep -q '^TOOL=copilot' || err "copilot forced: missing TOOL=copilot"
    echo "$out" | grep -q '^SOURCE=.*current\.jsonl$' || err "copilot forced: expected current.jsonl"
    echo "$out" | grep -q '^SKILL_TRACE=verified' || err "copilot validation: SKILL_TRACE verified"
    pass "copilot forced path resolves transcript"
  )
}