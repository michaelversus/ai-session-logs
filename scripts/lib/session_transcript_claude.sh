#!/usr/bin/env bash

find_claude_match() {
  local base slug root
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$base/projects/$slug/sessions"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(enumerate_jsonl_paths_sorted "$root" "")
}