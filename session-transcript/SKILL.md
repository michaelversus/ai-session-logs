---
name: session-transcript
description: >
  Find the current AI session transcript (*.jsonl) for Codex, Cursor, Claude Code,
  or GitHub Copilot; copy an export into the repository workspace under
  .ai-session-logs/. Use when the user asks to export, back up, locate, or
  archive the active session log, or wants the path to the current transcript.
---

# Session transcript

## When to use

- Export, back up, attach, or share the **active** session log.
- Discover `SOURCE=` for a `.jsonl` transcript on disk.
- Persist a copy **inside the repository/workspace root** (default: `.ai-session-logs/`), not only under tool caches in `$HOME`.

## Before you run

1. **Working directory:** Prefer running from the **repository/workspace root**, or pass `--project-root` explicitly.
2. **Skill trace (default):** The script only exports a transcript that **already contains** the text `session-transcript` or `find_current_session_transcript` somewhere in the file (so we target sessions where this skill actually ran). It tries **newer sessions first**; if the newest has no trace, it moves to older ones. If none match, it errors unless you pass **`--skip-skill-trace`** (then it uses the newest file). Ask the user to mention the skill or run the script by name earlier in the session if exports fail.
3. **Codex:** When `~/.codex/session_index.jsonl` exists, transcript order follows that index (**last lines = newest sessions**) before the skill-trace filter; see [paths.md](../references/paths.md).
4. **Confidence:** If stdout shows `CONFIDENCE=low` or `medium`, **confirm with the user** before treating `SOURCE` as the correct session (see hybrid resolution in [cli-spec.md](../references/cli-spec.md)).
5. **GitHub Copilot:** Treat as **best-effort**; see [paths.md](../references/paths.md#github-copilot-limitations).

## Command

From the **workspace root** (paths relative to repo root):

```bash
bash scripts/find_current_session_transcript.sh
```

Default behavior: resolve the best transcript, **copy** it to `<project-root>/.ai-session-logs/`, print `TOOL=`, `SOURCE=`, `CONFIDENCE=`, `REASON=`, `PROJECT_ROOT=`, `DEST=` to stdout.

## Common flags

| Flag | Purpose |
|------|---------|
| `--tool=codex` | Skip auto-detection; only that tool. |
| `--no-copy` | Print metadata only; do not write into `.ai-session-logs/`. |
| `--dry-run` | Show intended `DEST=` without creating dirs or copying. |
| `--skip-skill-trace` | Use the newest transcript file even if it lacks the skill trace (see [cli-spec.md](../references/cli-spec.md) §5.1). |
| `--project-root=DIR` | Override git / `PWD` root used for slug + export path. |
| `--output-dir=DIR` | Override export directory (default `<root>/.ai-session-logs`). |
| `--json` | Single JSON object on stdout instead of `KEY=value` lines. |
| `-v` / `--verbose` | Extra discovery details on stderr. |

Full contract: [references/cli-spec.md](../references/cli-spec.md). On-disk layout: [references/paths.md](../references/paths.md).

## `.gitignore` (consuming projects)

Add:

```gitignore
.ai-session-logs/
```

unless the team commits exported logs on purpose.

## Examples for agents

```bash
bash scripts/find_current_session_transcript.sh --no-copy
```

```bash
bash scripts/find_current_session_transcript.sh --tool cursor --verbose
```

```bash
bash scripts/find_current_session_transcript.sh --dry-run --json
```

Parse stdout in shell:

```bash
bash scripts/find_current_session_transcript.sh --no-copy | grep '^SOURCE='
```

```bash
bash scripts/find_current_session_transcript.sh --tool cursor --skip-skill-trace --no-copy
```

## Related

- [README.md](../README.md) — install options (skills.sh, Claude plugin, pi, manual).
- [CONTRIBUTING.md](../CONTRIBUTING.md) — adding tools or changing the CLI.
