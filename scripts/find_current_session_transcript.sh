#!/usr/bin/env bash
# Resolve current AI session *.jsonl (Codex, Cursor, Claude Code, Copilot).
# See references/cli-spec.md. Targets macOS Bash 3.2+.

set -euo pipefail

VERSION="0.1.0"

FORCE_TOOL=""
PROJECT_ROOT_OVERRIDE=""
OUTPUT_DIR_OVERRIDE=""
NO_COPY=0
DRY_RUN=0
JSON_OUT=0
PLAIN=0
QUIET=0
VERBOSE=0

TOOL=""
SOURCE=""
CONFIDENCE=""
REASON=""
DEST=""
PROJECT_ROOT=""

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

# newest *.jsonl under $1 (recursive); sets global NEWEST_JSONL NEWEST_MTIME
find_newest_jsonl_under() {
  local root="$1"
  NEWEST_JSONL=""
  NEWEST_MTIME=0
  [[ -d "$root" ]] || return 1
  while IFS= read -r -d '' f; do
    local mt
    mt="$(stat -f '%m' "$f" 2>/dev/null || echo 0)"
    if [[ "$mt" -gt "$NEWEST_MTIME" ]]; then
      NEWEST_MTIME="$mt"
      NEWEST_JSONL="$f"
    fi
  done < <(find "$root" -name '*.jsonl' -print0 2>/dev/null)
  [[ -n "$NEWEST_JSONL" ]]
}

# Pick newest among paths matching *suffix*.jsonl (suffix = thread id)
find_codex_match() {
  local root="$HOME/.codex/sessions"
  local tid="${CODEX_THREAD_ID:-}"
  NEWEST_JSONL=""
  NEWEST_MTIME=0
  [[ -d "$root" ]] || return 1
  if [[ -n "$tid" ]]; then
    while IFS= read -r -d '' f; do
      case "$f" in
        *"${tid}.jsonl") ;;
        *) continue ;;
      esac
      local mt
      mt="$(stat -f '%m' "$f" 2>/dev/null || echo 0)"
      if [[ "$mt" -gt "$NEWEST_MTIME" ]]; then
        NEWEST_MTIME="$mt"
        NEWEST_JSONL="$f"
      fi
    done < <(find "$root" -name '*.jsonl' -print0 2>/dev/null)
    [[ -n "$NEWEST_JSONL" ]] && return 0
  fi
  find_newest_jsonl_under "$root"
}

find_cursor_match() {
  local slug root
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$HOME/.cursor/projects/$slug/agent-transcripts"
  logv "cursor dir: $root"
  find_newest_jsonl_under "$root"
}

find_claude_match() {
  local base slug root
  base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  slug="$(path_slug "$PROJECT_ROOT")"
  root="$base/projects/$slug/sessions"
  logv "claude sessions dir: $root"
  find_newest_jsonl_under "$root"
}

# Match VS Code workspaceStorage folder whose workspace.json references project root
find_copilot_match() {
  local needle="$PROJECT_ROOT"
  NEWEST_JSONL=""
  NEWEST_MTIME=0
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
      local f mt
      while IFS= read -r -d '' f; do
        mt="$(stat -f '%m' "$f" 2>/dev/null || echo 0)"
        if [[ "$mt" -gt "$NEWEST_MTIME" ]]; then
          NEWEST_MTIME="$mt"
          NEWEST_JSONL="$f"
        fi
      done < <(find "$copilot_dir" -name '*.jsonl' -print0 2>/dev/null)
    done
  done
  [[ -n "$NEWEST_JSONL" ]]
}

# --- scoring (auto mode; score only, does not mutate NEWEST_JSONL) ---

codex_score_value() {
  local root="$HOME/.codex/sessions"
  local tid="${CODEX_THREAD_ID:-}"
  [[ -d "$root" ]] || {
    echo 0
    return
  }
  if [[ -n "$tid" ]] && find "$root" -name "*${tid}.jsonl" -print -quit 2>/dev/null | grep -q .; then
    echo 5
    return
  fi
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
  REASON="auto-selected ${TOOL} (scores codex=$sc cursor=$sw claude=$scl copilot=$scp)"
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
  REASON="tool forced via --tool"
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
    printf '}\n'
    return
  fi
  printf 'TOOL=%s\n' "$TOOL"
  printf 'SOURCE=%s\n' "$SOURCE"
  printf 'CONFIDENCE=%s\n' "$CONFIDENCE"
  printf 'REASON=%s\n' "$REASON"
  printf 'PROJECT_ROOT=%s\n' "$PROJECT_ROOT"
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
