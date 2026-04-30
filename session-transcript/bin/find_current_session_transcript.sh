#!/usr/bin/env bash
# Resolve current AI session *.jsonl (Codex, Cursor, Claude Code, Copilot).
# See docs/cli-spec.md. Targets macOS Bash 3.2+.

set -euo pipefail

VERSION="0.1.7"

FORCE_TOOL=""
PROJECT_ROOT_OVERRIDE=""
NO_COPY=0
SKIP_SKILL_TRACE=0

TOOL=""
SOURCE=""
CONFIDENCE=""
REASON=""
DEST=""
PROJECT_ROOT=""
SKILL_TRACE=""

usage() {
  cat <<'EOF'
Usage: bash <skill-root>/bin/find_current_session_transcript.sh [options]

Resolve the best current-session *.jsonl transcript and print KEY=value lines.
By default copies into <project-root>/.ai-session-logs/ (see --no-copy).

Options:
  -h, --help              Show this help
      --version           Print version
      --tool=NAME         codex | cursor | claude | copilot (required)
      --project-root=DIR  Workspace/repo root (default: git root or PWD)
      --no-copy           Only resolve; do not copy
      --skip-skill-trace  Pick newest jsonl only; do not require transcript text
                          matching this skill (see docs/cli-spec.md)
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SCRIPT_DIR/lib/session_transcript_common.sh"
. "$SCRIPT_DIR/lib/session_transcript_codex.sh"
. "$SCRIPT_DIR/lib/session_transcript_cursor.sh"
. "$SCRIPT_DIR/lib/session_transcript_claude.sh"
. "$SCRIPT_DIR/lib/session_transcript_copilot.sh"

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
      find_copilot_match || die "Copilot: no transcript jsonl under VS Code workspaceStorage (see docs/paths.md)"
      ;;
    *)
      die "Unknown --tool=$TOOL (use codex|cursor|claude|copilot)"
      ;;
  esac
  SOURCE="$NEWEST_JSONL"
  CONFIDENCE="high"
  REASON="tool selected via required --tool (SKILL_TRACE=${SKILL_TRACE:-})"
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
    --no-copy) NO_COPY=1 ;;
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

if [[ -z "$FORCE_TOOL" ]]; then
  printf 'ERROR: Missing required --tool (use codex|cursor|claude|copilot)\n' >&2
  exit 2
fi

PROJECT_ROOT="$(resolve_project_root)"

OUT_DIR="$PROJECT_ROOT/.ai-session-logs"

pick_forced

DEST=""
if [[ "$NO_COPY" -eq 0 ]]; then
  mkdir -p "$OUT_DIR"
  DEST="$(compute_dest_path "$SOURCE" "$OUT_DIR")"
  cp -p "$SOURCE" "$DEST"
else
  REASON="$REASON (--no-copy)"
fi

emit_output
exit 0