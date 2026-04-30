# On-disk paths (v1, macOS-oriented)

This table complements [cli-spec.md](cli-spec.md). **Slug** = absolute workspace root with leading `/` removed, each `/` replaced by `-`, and each `.` replaced by `-` (matches Cursor’s project folder names on disk).

| Tool | Where transcripts live | How we pick “current” |
|------|------------------------|------------------------|
| **Codex** | `$HOME/.codex/sessions/**/*.jsonl` | Prefer candidates from **`$HOME/.codex/session_index.jsonl`** (or `sessions_index.jsonl`): each `"id"` is resolved to `*<id>.jsonl` under `sessions/`, then resolved files are ordered by transcript mtime newest first. This is more reliable for active sessions because rollout files are appended while index `"updated_at"` can remain stale. If the index is missing or yields no files, order by file mtime. Then apply **skill trace** ([cli-spec.md](cli-spec.md) §5.1) unless `--skip-skill-trace`. Optional **`CODEX_HOME`** overrides the default `~/.codex` prefix for the index + `sessions/` paths. |
| **Cursor** | `$HOME/.cursor/projects/<slug>/agent-transcripts/*.jsonl` | `<slug>` as above. Candidates sorted by mtime (newest first), then **skill trace** filter ([cli-spec.md](cli-spec.md) §5.1). |
| **Claude Code** | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug>/sessions/*.jsonl` | Same `<slug>` as Cursor in v1. Same **skill trace** behavior. See [Claude directory](https://code.claude.com/docs/en/claude-directory.md). |
| **GitHub Copilot** | VS Code `User/workspaceStorage/<id>/GitHub.copilot-chat/**/*.jsonl` (and Insiders) | Scan `workspaceStorage/*/workspace.json` for project path; merge all matching `*.jsonl`, sort by mtime, then **skill trace** filter. |

## GitHub Copilot limitations

- Logs are **debug / diagnostic** JSONL from Copilot Chat, not a guaranteed full user-visible chat export. Files may be absent unless logging is enabled. See [vscode-copilot-chat PR #4347](https://github.com/microsoft/vscode-copilot-chat/pull/4347).
- Paths differ for **VS Code Insiders** (`Code - Insiders` under `Application Support`).
- If the workspace is not opened in VS Code, or `workspace.json` does not reference the path, Copilot resolution returns no candidate.

## Export location (all tools)

Resolved transcripts are **copied** (unless `--no-copy` or `--dry-run`) to:

```text
<repository-or-workspace-root>/.ai-session-logs/
```

Override with `--output-dir`. Add `.ai-session-logs/` to `.gitignore` unless you intend to commit exports.

## Example absolute paths (illustrative)

```text
~/.codex/session_index.jsonl          # append-only JSON lines: id, thread_name, updated_at
~/.codex/sessions/**/rollout-*.jsonl
/Users/you.name/project               → slug Users-you-name-project
/Users/you/.cursor/projects/Users-you-name-project/agent-transcripts/<uuid>.jsonl
/Users/you/.claude/projects/Users-you-name-project/sessions/<uuid>.jsonl
/Users/you/Library/Application Support/Code/User/workspaceStorage/<hash>/GitHub.copilot-chat/debug-logs/<id>.jsonl
```
