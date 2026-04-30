# On-disk paths (v1, macOS-oriented)

This table complements [cli-spec.md](cli-spec.md). **Slug** = absolute workspace root with leading `/` removed, each `/` replaced by `-`, and each `.` replaced by `-` (matches Cursor’s project folder names on disk).

| Tool | Where transcripts live | How we pick “current” |
|------|------------------------|------------------------|
| **Codex** | `$HOME/.codex/sessions/**/*.jsonl` | If `CODEX_THREAD_ID` is set, prefer any `*${CODEX_THREAD_ID}.jsonl`; else newest by mtime under `sessions`. |
| **Cursor** | `$HOME/.cursor/projects/<slug>/agent-transcripts/*.jsonl` | `<slug>` = absolute project root with leading `/` removed, each `/` replaced by `-`, and each `.` replaced by `-` (matches Cursor’s on-disk folder names). Newest `*.jsonl` by mtime. |
| **Claude Code** | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slug>/sessions/*.jsonl` | Same `<slug>` rule as Cursor in v1 (verify against your `~/.claude/projects` if paths differ). Newest by mtime. See [Claude directory](https://code.claude.com/docs/en/claude-directory.md). |
| **GitHub Copilot** | VS Code `User/workspaceStorage/<id>/GitHub.copilot-chat/**/*.jsonl` (and Insiders) | Scan `workspaceStorage/*/workspace.json` for a line containing the project path (or `file://` + path); then newest jsonl under that workspace’s `GitHub.copilot-chat`. |

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
/Users/you.name/project               → slug Users-you-name-project
/Users/you/.cursor/projects/Users-you-project/agent-transcripts/<uuid>.jsonl
/Users/you/.claude/projects/Users-you-project/sessions/<uuid>.jsonl
/Users/you/Library/Application Support/Code/User/workspaceStorage/<hash>/GitHub.copilot-chat/debug-logs/<id>.jsonl
```
