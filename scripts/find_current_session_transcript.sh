#!/usr/bin/env bash
# Resolve current AI session *.jsonl (Codex, Cursor, Claude Code, Copilot).
# See references/cli-spec.md. Targets macOS Bash 3.2+.

set -euo pipefail

VERSION="0.1.4"

FORCE_TOOL=""
PROJECT_ROOT_OVERRIDE=""
OUTPUT_DIR_OVERRIDE=""
NO_COPY=0
DRY_RUN=0
JSON_OUT=0
PLAIN=0
QUIET=0
VERBOSE=0
SKIP_SKILL_TRACE=0

TOOL=""
SOURCE=""
CONFIDENCE=""
REASON=""
DEST=""
PROJECT_ROOT=""
SKILL_TRACE=""

logv() {
  if [[ "$VERBOSE" -eq 1 && "$QUIET" -eq 0 ]]; then
    printf '%s\n' "$*" >&2
  fi
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: bash scripts/find_current_session_transcript.sh [options]

Resolve the best current-session *.jsonl transcript and print KEY=value lines.
By default copies into <project-root>/.ai-session-logs/ (see --no-copy, --dry-run).

Options:
  -h, --help              Show this help
      --version           Print version
      --tool=NAME         codex | cursor | claude | copilot (default: auto)
      --project-root=DIR  Workspace/repo root (default: git root or PWD)
      --output-dir=DIR    Export directory (default: <project-root>/.ai-session-logs)
      --no-copy           Only resolve; do not copy
      --dry-run           Show DEST but do not write
      --json              Single JSON object on stdout
      --plain             Force KEY=value lines (default)
  -q, --quiet             Less stderr noise
  -v, --verbose           More stderr diagnostics
      --no-color          Reserved (no-op)
      --skip-skill-trace  Pick newest jsonl only; do not require transcript text
                          matching this skill (see references/cli-spec.md)
EOF
}

# --- path helpers (BSD / macOS) ---

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
  # Cursor (and common Claude layouts) replace "." with "-" in the slug (e.g. m.karagiorgos → m-karagiorgos).
  echo "${s//./-}"
}

# True if this transcript mentions this skill/plugin (so we prefer sessions where it ran).
transcript_contains_skill_trace() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  grep -qiE 'ai-session-logs|session-transcript|find_current_session_transcript(\.sh)?' "$f" 2>/dev/null
}

# Print *.jsonl paths under $1 (recursive), newest first. Optional $2 = CODEX thread suffix
# (filename must end with "<suffix>.jsonl").
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

# Codex: resolve rollout candidates using ~/.codex/session_index.jsonl, then order by
# rollout file mtime because active sessions are appended while session_index updated_at
# can remain stale until later.
# then fall back to mtime ordering under sessions/. See references/paths.md.
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
    logv "codex: ordering candidates via session index: $idx"
    tmpmerged="$(mktemp "${TMPDIR:-/tmp}/asl-cdx.XXXXXX")"
    _codex_paths_from_session_index "$idx" "$root" | awk '!seen[$0]++' >"$tmpmerged"
    if [[ -s "$tmpmerged" ]]; then
      cat "$tmpmerged"
      rm -f "$tmpmerged"
      return 0
    fi
    rm -f "$tmpmerged"
    logv "codex: session index yielded no matching rollout files; falling back to mtime order"
  fi
  enumerate_jsonl_paths_sorted "$root" ""
}

# Sets NEWEST_JSONL and SKILL_TRACE from sorted candidate stream (stdin = paths, newest first).
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
    logv "skip (no skill trace): $f"
  done
  [[ -n "$picked" ]] || return 1
  die "No transcript contained a session-transcript skill trace (need a line matching session-transcript or find_current_session_transcript). Tried newer sessions first. Use --skip-skill-trace to export the newest file anyway. Last tried: $picked"
}

# --- per-tool resolution (skill-trace gate unless --skip-skill-trace) ---

find_codex_match() {
  local codex_home root
  codex_home="${CODEX_HOME:-$HOME/.codex}"
  root="$codex_home/sessions"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(codex_sorted_transcript_candidates)
}

find_cursor_match() {
  local slug root
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$HOME/.cursor/projects/$slug/agent-transcripts"
  logv "cursor dir: $root"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(enumerate_jsonl_paths_sorted "$root" "")
}

find_claude_match() {
  local base slug root
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$base/projects/$slug/sessions"
  logv "claude sessions dir: $root"
  NEWEST_JSONL=""
  [[ -d "$root" ]] || return 1
  select_jsonl_with_skill_trace_from_stream < <(enumerate_jsonl_paths_sorted "$root" "")
}

# All Copilot jsonl candidates for this workspace, newest first (merged across storage folders).
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
      done < <(find "$copilot_dir" -name '*.jsonl' -print0 2>/dev/null)
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

# --- scoring (auto mode; score only, does not mutate NEWEST_JSONL) ---

codex_score_value() {
  local root="${CODEX_HOME:-$HOME/.codex}/sessions"
  [[ -d "$root" ]] || {
    echo 0
    return
  }
  if find "$root" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
    echo 1
  else
    echo 0
  fi
}

cursor_score_value() {
  local slug root
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$HOME/.cursor/projects/$slug/agent-transcripts"
  [[ -d "$root" ]] || {
    echo 0
    return
  }
  if find "$root" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
    echo 3
  else
    echo 0
  fi
}

claude_score_value() {
  local base slug root
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$base/projects/$slug/sessions"
  [[ -d "$root" ]] || {
    echo 0
    return
  }
  if find "$root" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
    echo 3
  else
    echo 0
  fi
}

copilot_score_value() {
  local needle="$PROJECT_ROOT"
  local bases=(
    "$HOME/Library/Application Support/Code/User"
    "$HOME/Library/Application Support/Code - Insiders/User"
  )
  local base ws copilot_dir
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
      if find "$copilot_dir" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
        echo 2
        return
      fi
    done
  done
  echo 0
}

bump_score() {
  local name="$1" s="$2"
  if [[ "$s" -gt "$best" ]]; then
    second=$best
    best=$s
    tool=$name
  elif [[ "$s" -gt "$second" ]]; then
    second=$s
  fi
}

pick_auto() {
  local sc sw scl scp

  sc="$(codex_score_value)"
  sw="$(cursor_score_value)"
  scl="$(claude_score_value)"
  scp="$(copilot_score_value)"
  logv "scores codex=$sc cursor=$sw claude=$scl copilot=$scp"

  best=-1
  second=-1
  tool=""

  bump_score codex "$sc"
  bump_score cursor "$sw"
  bump_score claude "$scl"
  bump_score copilot "$scp"

  if [[ "$best" -le 0 ]]; then
    die "No transcript candidates found for any tool."
  fi

  if [[ "$second" -lt 0 ]]; then
    second=0
  fi

  if [[ "$best" -ge 5 ]]; then
    CONFIDENCE="high"
  elif [[ "$best" -ge 3 && $((best - second)) -ge 2 ]]; then
    CONFIDENCE="medium"
  elif [[ "$best" -ge 2 && $((best - second)) -ge 1 ]]; then
    CONFIDENCE="medium"
  else
    CONFIDENCE="low"
  fi

  TOOL="$tool"
  case "$TOOL" in
    codex) find_codex_match || die "Codex: no jsonl" ;;
    cursor) find_cursor_match || die "Cursor: no jsonl for slug $(path_slug "$PROJECT_ROOT")" ;;
    claude) find_claude_match || die "Claude: no jsonl for project" ;;
    copilot) find_copilot_match || die "Copilot: no debug jsonl for workspace" ;;
  esac
  SOURCE="$NEWEST_JSONL"
  REASON="auto-selected ${TOOL} (scores codex=$sc cursor=$sw claude=$scl copilot=$scp; SKILL_TRACE=${SKILL_TRACE:-})"
}

pick_forced() {
  TOOL="$FORCE_TOOL"
  case "$TOOL" in
    codex)
      find_codex_match || die "Codex: no transcript under ~/.codex/sessions"
      ;;
    cursor)
      find_cursor_match || die "Cursor: no transcript under ~/.cursor/projects/$(path_slug "$PROJECT_ROOT")/agent-transcripts"
      ;;
    claude)
      find_claude_match || die "Claude Code: no transcript under sessions/"
      ;;
    copilot)
      find_copilot_match || die "Copilot: no debug jsonl under VS Code workspaceStorage (see references/paths.md)"
      ;;
    *)
      die "Unknown --tool=$TOOL (use codex|cursor|claude|copilot)"
      ;;
  esac
  SOURCE="$NEWEST_JSONL"
  CONFIDENCE="high"
  REASON="tool forced via --tool (SKILL_TRACE=${SKILL_TRACE:-})"
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

json_escape() {
  local s=$1 out="" i c
  out=""
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *) out+="$c" ;;
    esac
  done
  printf '"%s"' "$out"
}

emit_output() {
  if [[ "$JSON_OUT" -eq 1 ]]; then
    printf '{"TOOL":%s,"SOURCE":%s,"CONFIDENCE":%s,"REASON":%s' \
      "$(json_escape "$TOOL")" "$(json_escape "$SOURCE")" "$(json_escape "$CONFIDENCE")" "$(json_escape "$REASON")"
    if [[ -n "$PROJECT_ROOT" ]]; then
      printf ',"PROJECT_ROOT":%s' "$(json_escape "$PROJECT_ROOT")"
    fi
    if [[ -n "$DEST" ]]; then
      printf ',"DEST":%s' "$(json_escape "$DEST")"
    fi
    printf ',"SKILL_TRACE":%s' "$(json_escape "${SKILL_TRACE:-}")"
    printf '}\n'
    return
  fi
  printf 'TOOL=%s\n' "$TOOL"
  printf 'SOURCE=%s\n' "$SOURCE"
  printf 'CONFIDENCE=%s\n' "$CONFIDENCE"
  printf 'REASON=%s\n' "$REASON"
  printf 'PROJECT_ROOT=%s\n' "$PROJECT_ROOT"
  printf 'SKILL_TRACE=%s\n' "${SKILL_TRACE:-}"
  if [[ -n "$DEST" ]]; then
    printf 'DEST=%s\n' "$DEST"
  fi
}

# --- main ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --version)
      printf '%s\n' "$VERSION"
      exit 0
      ;;
    --tool=*)
      FORCE_TOOL="${1#*=}"
      ;;
    --tool)
      FORCE_TOOL="$2"
      shift
      ;;
    --project-root=*)
      PROJECT_ROOT_OVERRIDE="${1#*=}"
      ;;
    --project-root)
      PROJECT_ROOT_OVERRIDE="$2"
      shift
      ;;
    --output-dir=*)
      OUTPUT_DIR_OVERRIDE="${1#*=}"
      ;;
    --output-dir)
      OUTPUT_DIR_OVERRIDE="$2"
      shift
      ;;
    --no-copy) NO_COPY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --json) JSON_OUT=1 ;;
    --plain) PLAIN=1 ;;
    -q | --quiet) QUIET=1 ;;
    -v | --verbose) VERBOSE=1 ;;
    --no-color) ;;
    --skip-skill-trace) SKIP_SKILL_TRACE=1 ;;
    *)
      printf 'ERROR: Unknown option: %s (try --help)\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -n "$FORCE_TOOL" ]]; then
  FORCE_TOOL="$(printf '%s' "$FORCE_TOOL" | tr '[:upper:]' '[:lower:]')"
  case "$FORCE_TOOL" in
    codex | cursor | claude | copilot) ;;
    *)
      printf 'ERROR: Invalid --tool=%s (use codex|cursor|claude|copilot)\n' "$FORCE_TOOL" >&2
      exit 2
      ;;
  esac
fi

PROJECT_ROOT="$(resolve_project_root)"
logv "PROJECT_ROOT=$PROJECT_ROOT"

OUT_DIR="${OUTPUT_DIR_OVERRIDE:-$PROJECT_ROOT/.ai-session-logs}"

if [[ -n "$FORCE_TOOL" ]]; then
  pick_forced
else
  pick_auto
fi

DEST=""
if [[ "$NO_COPY" -eq 0 ]]; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    DEST="$(compute_dest_path "$SOURCE" "$OUT_DIR")"
    REASON="$REASON (dry-run: no copy performed)"
  else
    mkdir -p "$OUT_DIR"
    DEST="$(compute_dest_path "$SOURCE" "$OUT_DIR")"
    cp -p "$SOURCE" "$DEST"
  fi
else
  REASON="$REASON (--no-copy)"
fi

emit_output
exit 0
