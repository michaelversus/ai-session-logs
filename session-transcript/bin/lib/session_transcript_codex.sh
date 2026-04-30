#!/usr/bin/env bash

_codex_paths_from_session_index() {
  local idx="$1" root="$2"
  awk '
    {
      id = ""
      updated = ""
      if (match($0, /"id"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        id = substr($0, RSTART, RLENGTH)
        sub(/^.*"id"[[:space:]]*:[[:space:]]*"/, "", id)
        sub(/"$/, "", id)
      }
      if (match($0, /"updated_at"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        updated = substr($0, RSTART, RLENGTH)
        sub(/^.*"updated_at"[[:space:]]*:[[:space:]]*"/, "", updated)
        sub(/"$/, "", updated)
      }
      if (id != "") {
        printf "%s\t%09d\t%s\n", updated, NR, id
      }
    }
  ' "$idx" | while IFS=$'\t' read -r updated line id; do
    local f mtime
    f="$(find "$root" -name "*${id}.jsonl" 2>/dev/null | head -1)"
    [[ -z "$f" || ! -f "$f" ]] && continue
    mtime="$(stat -f '%m' "$f" 2>/dev/null || echo 0)"
    printf '%s\t%s\t%s\t%s\n' "$mtime" "$updated" "$line" "$f"
  done | LC_ALL=C sort -t $'\t' -nr -k1,1 -r -k2,2 -k3,3 | while IFS=$'\t' read -r _mtime _updated _line f; do
    printf '%s\n' "$f"
  done
}

codex_sorted_transcript_candidates() {
  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local root="$codex_home/sessions"
  local idx=""
  local tmpmerged
  for cand in "$codex_home/session_index.jsonl" "$codex_home/sessions_index.jsonl"; do
    [[ -f "$cand" ]] && {
      idx="$cand"
      break
    }
  done
  if [[ -n "$idx" && -s "$idx" ]]; then
    tmpmerged="$(mktemp "${TMPDIR:-/tmp}/asl-cdx.XXXXXX")"
    _codex_paths_from_session_index "$idx" "$root" | awk '!seen[$0]++' >"$tmpmerged"
    if [[ -s "$tmpmerged" ]]; then
      cat "$tmpmerged"
      rm -f "$tmpmerged"
      return 0
    fi
    rm -f "$tmpmerged"
  fi
  enumerate_jsonl_paths_sorted "$root" ""
}

find_codex_match() {
  local codex_home root
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  root="$codex_home/sessions"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(codex_sorted_transcript_candidates)
}