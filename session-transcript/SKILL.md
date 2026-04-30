---
name: session-transcript
description: >
  Find the current AI session transcript (*.jsonl) for Codex, Cursor, Claude Code,
  or GitHub Copilot; copy an export into the repository workspace under
  .ai-session-logs/. Use when the user asks to export, back up, locate, or
  archive the active session log, or wants the path to the current transcript.
  Always ask which client/tool is in use and pass --tool explicitly.
---

# Session transcript

## When to use

- Export, back up, attach, or share the **active** session log.
- Discover `SOURCE=` for a `.jsonl` transcript on disk.
- Persist a copy **inside the repository/workspace root** (default: `.ai-session-logs/`), not only under tool caches in `$HOME`.

## Before you run

1. **Pick the tool first:** Ask the user which client/tool produced the current session and pass that value via **`--tool`**. Supported values are `codex`, `cursor`, `claude`, and `copilot`.
2. **Working directory:** Prefer running from the **repository/workspace root**, or pass `--project-root` explicitly.
3. **Skill trace (default):** The script only exports a transcript that **already contains** the text `ai-session-logs`, `session-transcript`, or `find_current_session_transcript` somewhere in the file (so we target sessions where this skill actually ran). It tries **newer sessions first**; if the newest has no trace, it moves to older ones. If none match, it errors unless you pass **`--skip-skill-trace`** (then it uses the newest file). Ask the user to mention the skill/plugin name or run the script by name earlier in the session if exports fail.
4. **Codex:** When `~/.codex/session_index.jsonl` exists, the script resolves indexed sessions to rollout files and orders those files by transcript mtime (**newest writes first**) before the skill-trace filter. This handles active sessions whose rollout file is being appended while the index `updated_at` is stale; see [paths.md](../references/paths.md).
5. **GitHub Copilot:** Treat as **best-effort**; prefer `GitHub.copilot-chat/transcripts/*.jsonl` and remember that `debug-logs/**` is diagnostic only; see [paths.md](../references/paths.md).

## Command

Prefer resolving the repository root first, then invoke the script by absolute path so agents do not depend on their current working directory:

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool codex
```

Default behavior: resolve the best transcript, **copy** it to `<project-root>/.ai-session-logs/`, print `TOOL=`, `SOURCE=`, `CONFIDENCE=`, `REASON=`, `PROJECT_ROOT=`, `SKILL_TRACE=`, `DEST=` to stdout.

Replace `codex` with the actual tool the user confirmed.

## After you run it

Do not assume the next action from the script result alone. After every run, show the resolved `TOOL`, `SOURCE`, `CONFIDENCE`, and `DEST` or `PROJECT_ROOT` when relevant, then ask the user to choose the next step.

Final validation: do not treat the run as successful unless the resolved `SOURCE` contains one or more distinctive substrings from the **current user request** or another very recent user message from this conversation. The agent knows the live prompt text; the shell script does not. This validation must happen **after** the script resolves `SOURCE`, not inside the script.

Use this validation recipe:

1. Pick **1 to 3 exact snippets** from the latest user message.
2. Prefer distinctive phrases, not generic words such as `file`, `script`, `log`, or `jsonl`.
3. Search those snippets in `SOURCE` using exact-string matching.
4. If **at least one** snippet matches, treat that as strong evidence that the resolved transcript is the correct one.
5. If **none** of the snippets match, treat the result as unverified and ask the user whether to re-run with another tool or stop.

Practical guidance:

- If the latest user message is short, use the whole sentence.
- If it is long, lift a distinctive clause from the middle of the message.
- Prefer `rg -F` or another exact-string search over regex when checking the resolved file.
- If the newest user message is too short or too generic, use the previous recent user message instead.

Use a short option list such as:

1. Use this transcript result.
2. Re-run with a specific tool such as `--tool copilot`.
3. Re-run with `--skip-skill-trace`.
4. Stop without taking further action.

If the client is **VS Code GitHub Copilot**, prefer presenting these as an explicit option picker rather than a freeform follow-up.

If the resolved file does **not** contain the current user-message text you checked for, present that failure, do not continue with export or analysis as if it were the correct chat transcript, and ask the user whether to re-run with another tool or stop.

## Common flags

| Flag | Purpose |
|------|---------|
| `--tool=NAME` | Required. Use `codex`, `cursor`, `claude`, or `copilot`. |
| `--no-copy` | Print metadata only; do not write into `.ai-session-logs/`. |
| `--skip-skill-trace` | Use the newest transcript file even if it lacks the skill trace (see [cli-spec.md](../references/cli-spec.md) §5.1). |
| `--project-root=DIR` | Override git / `PWD` root used for slug + export path. |

Full contract: [references/cli-spec.md](../references/cli-spec.md). On-disk layout: [references/paths.md](../references/paths.md).

## Examples for agents

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool codex --no-copy
```

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool copilot --no-copy
```

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool claude --no-copy
```

Parse stdout in shell:

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool codex --no-copy | grep '^SOURCE='
```

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool cursor --skip-skill-trace --no-copy
```

```bash
bash "$(git rev-parse --show-toplevel)/scripts/find_current_session_transcript.sh" --tool copilot --skip-skill-trace --no-copy
```

## Related

- [README.md](../README.md) — install options (skills.sh, Claude plugin, pi, manual).
- [CONTRIBUTING.md](../CONTRIBUTING.md) — adding tools or changing the CLI.
