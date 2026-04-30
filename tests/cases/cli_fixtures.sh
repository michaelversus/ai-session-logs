#!/usr/bin/env bash

run_cli_fixture_tests() {
  # --- Invalid flag exit 2 ---
  if bash "$SCRIPT" --not-a-flag 2>/dev/null; then
    err "unknown flag should not succeed"
  else
    ec=$?
    [[ "$ec" -eq 2 ]] || err "unknown flag exit code want 2 got $ec"
    pass "unknown flag exits 2"
  fi

  # --- Missing --tool exit 2 ---
  if bash "$SCRIPT" --no-copy 2>/dev/null; then
    err "missing --tool should not succeed"
  else
    ec=$?
    [[ "$ec" -eq 2 ]] || err "missing --tool exit want 2 got $ec"
    pass "missing --tool exits 2"
  fi

  # --- Invalid --tool exit 2 ---
  if bash "$SCRIPT" --tool=nope --no-copy 2>/dev/null; then
    err "invalid tool should not succeed"
  else
    ec=$?
    [[ "$ec" -eq 2 ]] || err "invalid tool exit want 2 got $ec"
    pass "invalid --tool exits 2"
  fi
}