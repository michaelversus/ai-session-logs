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
2. **Confidence:** If stdout shows `CONFIDENCE=low` or `medium`, **confirm with the user** before treating `SOURCE` as the correct session (see hybrid resolution in [cli-spec.md](../references/cli-spec.md)).
3. **GitHub Copilot:** Treat as **best-effort**; see [paths.md](../references/paths.md#github-copilot-limitations).

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

## Related

- [README.md](../README.md) — install options (skills.sh, Claude plugin, pi, manual).
- [CONTRIBUTING.md](../CONTRIBUTING.md) — adding tools or changing the CLI.
