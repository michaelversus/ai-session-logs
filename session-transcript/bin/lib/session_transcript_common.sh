#!/usr/bin/env bash

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

resolve_project_root() {
  if [[ -n "$PROJECT_ROOT_OVERRIDE" ]]; then
    (cd "$PROJECT_ROOT_OVERRIDE" && pwd -P)
    return
  fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi
  pwd -P 2>/dev/null || pwd
}

path_slug() {
  local d s
  d="$(cd "$1" && pwd -P 2>/dev/null)" || d="$(cd "$1" && pwd)"
  d="${d#/}"
  s="${d//\//-}"
  # Cursor (and common Claude layouts) replace "." with "-" in the slug (e.g. m.karagiorgos -> m-karagiorgos).
  echo "${s//./-}"
}

transcript_contains_skill_trace() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  grep -qiE 'ai-session-logs|session-transcript|find_current_session_transcript(\.sh)?' "$f" 2>/dev/null
}

enumerate_jsonl_paths_sorted() {
  local root="$1"
  local tid_suffix="${2:-}"
  [[ -d "$root" ]] || return 1
  while IFS= read -r -d '' f; do
    if [[ -n "$tid_suffix" ]]; then
      case "$f" in
        *"${tid_suffix}.jsonl") ;;
        *) continue ;;
      esac
    fi
    printf '%s\t%s\n' "$(stat -f '%m' "$f" 2>/dev/null || echo 0)" "$f"
  done < <(find "$root" -name '*.jsonl' -print0 2>/dev/null) | LC_ALL=C sort -t $'\t' -nr -k1,1 | while IFS= read -r line; do
    printf '%s\n' "$(echo "$line" | cut -f2-)"
  done
}

select_jsonl_with_skill_trace_from_stream() {
  local f picked=""
  SKILL_TRACE=""
  if [[ "$SKIP_SKILL_TRACE" -eq 1 ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ -f "$f" ]] || continue
      NEWEST_JSONL="$f"
      SKILL_TRACE=skipped
      return 0
    done
    return 1
  fi
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "$f" ]] || continue
    if [[ -z "$picked" ]]; then
      picked="$f"
    fi
    if transcript_contains_skill_trace "$f"; then
      NEWEST_JSONL="$f"
      SKILL_TRACE=verified
      return 0
    fi
  done
  [[ -n "$picked" ]] || return 1
  die "No transcript contained a session-transcript skill trace (need a line matching session-transcript or find_current_session_transcript). Tried newer sessions first. Use --skip-skill-trace to export the newest file anyway. Last tried: $picked"
}

compute_dest_path() {
  local src="$1" dest_dir="$2"
  local base dest
  base="$(basename "$src")"
  dest="$dest_dir/$base"
  if [[ -e "$dest" ]]; then
    dest="$dest_dir/${base%.jsonl}-$(date +%Y%m%d%H%M%S).jsonl"
  fi
  printf '%s' "$dest"
}

emit_output() {
  printf 'TOOL=%s\n' "$TOOL"
  printf 'VERSION=%s\n' "$VERSION"
  printf 'SOURCE=%s\n' "$SOURCE"
  printf 'CONFIDENCE=%s\n' "$CONFIDENCE"
  printf 'REASON=%s\n' "$REASON"
  printf 'PROJECT_ROOT=%s\n' "$PROJECT_ROOT"
  printf 'SKILL_TRACE=%s\n' "${SKILL_TRACE:-}"
  if [[ -n "$DEST" ]]; then
    printf 'DEST=%s\n' "$DEST"
  fi
}