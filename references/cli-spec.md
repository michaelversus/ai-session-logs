# CLI specification: `find_current_session_transcript.sh`

Designed against [clig.dev](https://clig.dev/) (CLI interface guidelines).

## 1. Name

`find_current_session_transcript.sh` (invoked as `bash scripts/find_current_session_transcript.sh` from the **repository/workspace root**, or with `--project-root`).

## 2. One-liner

Resolve the best `*.jsonl` transcript for the current AI coding session (Codex, Cursor, Claude Code, or GitHub Copilot), print machine-readable fields, and **by default copy** that file into `<project-root>/.ai-session-logs/`.

## 3. USAGE

```text
bash scripts/find_current_session_transcript.sh [options]
```

No subcommands.

## 4. Global flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `-h`, `--help` | flag | — | Print usage to stdout and exit `0`. Other flags ignored. |
| `--version` | flag | — | Print semver to stdout and exit `0`. |
| `--tool` | string | (auto) | Force tool: `codex`, `cursor`, `claude`, `copilot`. Skip scoring. |
| `--project-root` | path | auto | Repository/workspace root. **Auto:** `git rev-parse --show-toplevel` when inside a git work tree, else current working directory (`PWD`). |
| `--output-dir` | path | `<project-root>/.ai-session-logs` | Directory for exported copies (created if missing). |
| `--no-copy` | flag | off | Only resolve and print metadata; do not write a copy under the workspace. |
| `--dry-run` | flag | off | Show intended `DEST=` path but do not create dirs or copy (implies no side effects except reads). |
| `--json` | flag | off | Print one JSON object on stdout instead of `KEY=value` lines (stderr rules unchanged). |
| `--plain` | flag | off | Force `KEY=value` lines on stdout (default for non-interactive use; see I/O contract). |
| `-q`, `--quiet` | flag | off | Suppress non-essential stderr (errors still print to stderr). |
| `-v`, `--verbose` | flag | off | Extra stderr diagnostics (discovery paths, scores). |
| `--no-color` | flag | off | Reserved; script output is not colored in v1. |
| `--skip-skill-trace` | flag | off | Take the **newest** candidate `*.jsonl` only. Default behavior walks candidates **newest first** and picks the first file whose contents match a **skill trace** (see §5.1). |

## 5. I/O contract

### 5.1 Skill trace (default)

Before accepting a transcript, the script **scans file contents** (line-oriented `grep`) for evidence this skill or plugin was used in that session:

- Case-insensitive match for **`ai-session-logs`**, **`session-transcript`**, or **`find_current_session_transcript`** (optional `.sh`).

Candidates for the chosen tool are ordered **by modification time, newest first**. The script **skips** newer files that lack the trace and continues until it finds a match.

If **no** candidate contains the trace, the script **exits with an error** (and a message suggesting `--skip-skill-trace`). There is **no silent fallback** to an untraced newest file.

With **`--skip-skill-trace`**, the first candidate (newest) is used and stdout includes `SKILL_TRACE=skipped`.

### 5.2 stdout / stderr

- **stdout**
  - Default (no `--json`): **stable `KEY=value` lines** (one key per line), suitable for agents and `grep`:
    - `TOOL=codex|cursor|claude|copilot`
    - `SOURCE=/absolute/path/to/file.jsonl`
    - `CONFIDENCE=high|medium|low`
    - `REASON=short human explanation`
    - `PROJECT_ROOT=/absolute/...`
    - `SKILL_TRACE=verified|skipped` (verified = trace matched; skipped = `--skip-skill-trace`)
    - When copy runs or `--dry-run` with copy enabled: `DEST=/absolute/...`
  - With `--json`: single JSON object with the same fields (string values, booleans as JSON booleans if needed).
- **stderr**
  - Diagnostics, warnings, verbose trace (`-v`), and all fatal errors.
- **Environment**
  - Respect `NO_COLOR` (no-op in v1), `TERM=dumb` (treated like non-verbose human context for future; v1 ignores for output mode).
- **TTY**
  - v1 always emits machine-friendly stdout by default (agents are the primary consumer). `-v` controls stderr noise only.

## 6. Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success: resolved (and copied unless `--no-copy` / `--dry-run`). |
| `1` | Runtime failure (no candidate file, copy failed, unreadable paths). |
| `2` | Invalid usage (unknown flag, bad `--tool` value). |

## 7. Env vars (read-only; discovery)

| Variable | Used for |
|----------|----------|
| `PWD` | Fallback project root when not in a git repo. |
| `CLAUDE_CONFIG_DIR` | Claude Code: override `~/.claude` base. |
| `CODEX_HOME` | Optional. Directory that contains `session_index.jsonl` and `sessions/` (default: `$HOME/.codex`). |
| `HOME` | Base for tool caches (`~/.codex`, `~/.cursor`, etc.). |

**Precedence:** CLI flags override env-derived defaults. No config file in v1.

## 8. Safety

- **Non-destructive source:** never modifies files under tool home dirs; only reads.
- **Writes:** only under `--output-dir` (default `.ai-session-logs` in project root). `mkdir -p` as needed.
- **`--dry-run`:** no mkdir/copy; still resolves and prints intended `DEST`.
- **No prompts** in v1 (`--no-input` not required yet; reserved for future interactive disambiguation).

## 9. Shell completion

Not bundled in v1. Optional: document `--tool` static completions in README later.

## 10. Examples

```bash
# From repo root: auto-detect tool, copy to ./.ai-session-logs/
bash scripts/find_current_session_transcript.sh
```

```bash
bash scripts/find_current_session_transcript.sh --tool codex --verbose
```

```bash
bash scripts/find_current_session_transcript.sh --project-root /path/to/repo --no-copy
```

```bash
bash scripts/find_current_session_transcript.sh --tool cursor --skip-skill-trace --no-copy
```

```bash
bash scripts/find_current_session_transcript.sh --dry-run --json
```

```bash
bash scripts/find_current_session_transcript.sh --output-dir /path/to/repo/custom-logs
```

```bash
cd /path/to/repo && bash /path/to/ai-session-logs/scripts/find_current_session_transcript.sh --plain
```

```bash
bash scripts/find_current_session_transcript.sh --tool claude 2>/dev/null | grep '^SOURCE='
```

## 11. Confidence rules (resolver)

- **high:** `--tool` set and file found.
- **medium:** auto mode, winner by score but close runner-up or heuristic only (e.g. newest file in Cursor dir).
- **low:** weak signals, tie, or fallback to “newest among all tools’ candidates”.

When `CONFIDENCE` is not `high`, the **agent** should confirm with the user before treating `SOURCE` as authoritative.
