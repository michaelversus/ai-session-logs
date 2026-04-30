#!/usr/bin/env bash

copilot_sorted_jsonl_paths() {
  local needle="$PROJECT_ROOT"
  local tmp base ws copilot_dir
  tmp="$(mktemp "${TMPDIR:-/tmp}/asl-copilot.XXXXXX")"
  local bases=(
    "$HOME/Library/Application Support/Code/User"
    "$HOME/Library/Application Support/Code - Insiders/User"
  )
  : >"$tmp"
  for base in "${bases[@]}"; do
    [[ -d "$base/workspaceStorage" ]] || continue
    for ws in "$base/workspaceStorage"/*; do
      [[ -f "$ws/workspace.json" ]] || continue
      if ! grep -Fq "$needle" "$ws/workspace.json" 2>/dev/null \
        && ! grep -Fq "file://${needle}" "$ws/workspace.json" 2>/dev/null; then
        continue
      fi
      copilot_dir="$ws/GitHub.copilot-chat"
      [[ -d "$copilot_dir" ]] || continue
      while IFS= read -r -d '' f; do
        printf '%s\t%s\n' "$(stat -f '%m' "$f" 2>/dev/null || echo 0)" "$f" >>"$tmp"
      done < <(find "$copilot_dir" -name '*.jsonl' -not -path '*/debug-logs/*' -print0 2>/dev/null)
    done
  done
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    return 1
  fi
  LC_ALL=C sort -t $'\t' -nr -k1,1 "$tmp" | while IFS= read -r line; do
    printf '%s\n' "$(echo "$line" | cut -f2-)"
  done
  rm -f "$tmp"
}

find_copilot_match() {
  NEWEST_JSONL=""
  select_jsonl_with_skill_trace_from_stream < <(copilot_sorted_jsonl_paths)
}