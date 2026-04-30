#!/usr/bin/env bash

find_cursor_match() {
  local slug root
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$HOME/.cursor/projects/$slug/agent-transcripts"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(enumerate_jsonl_paths_sorted "$root" "")
}