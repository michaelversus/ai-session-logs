#!/usr/bin/env bash

run_codex_fixture_tests() {
  # --- Codex + session index match ---
  mkdir -p "$TMP/h1/.codex"
  echo '{"id":"mythreadid","thread_name":"fixture","updated_at":"2026-01-01T00:00:00Z"}' >"$TMP/h1/.codex/session_index.jsonl"
  mkdir -p "$TMP/h1/.codex/sessions/2026/01/01"
  echo '{"role":"user","note":"session-transcript"}' >"$TMP/h1/.codex/sessions/2026/01/01/rollout-abc-mythreadid.jsonl"
  mkdir -p "$TMP/proj1"
  git -C "$TMP/proj1" init -q
  (
    export HOME="$TMP/h1"
    unset CODEX_THREAD_ID || true
    out="$(bash "$SCRIPT" --project-root="$TMP/proj1" --tool codex --no-copy)"
    echo "$out" | grep -q '^TOOL=codex' || err "codex forced: missing TOOL=codex"
    echo "$out" | grep -q '^SOURCE=.*mythreadid\.jsonl$' || err "codex forced: SOURCE should match indexed file"
    echo "$out" | grep -q '^CONFIDENCE=high' || err "codex forced: CONFIDENCE high"
    echo "$out" | grep -q '^SKILL_TRACE=verified' || err "codex forced: SKILL_TRACE verified"
    pass "codex --tool with session index match"
  )

  # --- Codex ignores CODEX_THREAD_ID without skill trace ---
  mkdir -p "$TMP/h1b/.codex/sessions/2026/01/01"
  echo '{"role":"user","note":"no trace here"}' >"$TMP/h1b/.codex/sessions/2026/01/01/rollout-abc-activethread.jsonl"
  mkdir -p "$TMP/proj1b"
  git -C "$TMP/proj1b" init -q
  (
    export HOME="$TMP/h1b"
    export CODEX_THREAD_ID=activethread
    if bash "$SCRIPT" --project-root="$TMP/proj1b" --tool codex --no-copy 2>/dev/null; then
      err "codex trace: CODEX_THREAD_ID without trace should not bypass skill trace"
    else
      pass "codex CODEX_THREAD_ID does not bypass skill trace"
    fi
  )

  # --- Default copy creates file under project root ---
  mkdir -p "$TMP/h3/.codex/sessions"
  echo '{"role":"user","ok":true,"skill":"session-transcript"}' >"$TMP/h3/.codex/sessions/rollout-copytest.jsonl"
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

  # --- Codex live transcript mtime beats stale session_index updated_at ---
  mkdir -p "$TMP/h5/.codex/sessions"
  echo '{"id":"newidx","thread_name":"new","updated_at":"2026-01-02T00:00:00Z"}' >"$TMP/h5/.codex/session_index.jsonl"
  echo '{"id":"oldidx","thread_name":"old","updated_at":"2020-01-01T00:00:00Z"}' >>"$TMP/h5/.codex/session_index.jsonl"
  echo '{"role":"user","x":1,"use":"session-transcript"}' >"$TMP/h5/.codex/sessions/rollout-oldidx.jsonl"
  echo '{"role":"user","x":2,"use":"session-transcript"}' >"$TMP/h5/.codex/sessions/rollout-newidx.jsonl"
  touch -t 205001010000 "$TMP/h5/.codex/sessions/rollout-oldidx.jsonl"
  touch -t 202001010000 "$TMP/h5/.codex/sessions/rollout-newidx.jsonl"
  mkdir -p "$TMP/proj5"
  git -C "$TMP/proj5" init -q
  (
    export HOME="$TMP/h5"
    unset CODEX_THREAD_ID || true
    out="$(bash "$SCRIPT" --project-root="$TMP/proj5" --tool codex --no-copy)"
    echo "$out" | grep -q '^SOURCE=.*rollout-oldidx\.jsonl$' || err "codex index: expected newer mtime session (oldidx) despite stale updated_at"
    pass "codex transcript mtime preferred over stale session_index updated_at"
  )
}