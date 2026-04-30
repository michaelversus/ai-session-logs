# ai-session-logs

Agent skill that finds **current session** `*.jsonl` transcripts for **Codex**, **Cursor**, **Claude Code**, and **GitHub Copilot**, then **copies exports** into your **repository/workspace root** under `.ai-session-logs/` (not your Unix home directory).

## How to use this skill

Ask your agent to use the **session-transcript** skill when you want to **locate**, **export**, or **archive** the active session log. The agent should first confirm which client/tool is in use, then resolve the bundled Bash script from the workspace root: use `session-transcript/bin/find_current_session_transcript.sh` in this repository, `.agent/skills/session-transcript/bin/find_current_session_transcript.sh` in installed agent-skill projects, and `skills/session-transcript/bin/find_current_session_transcript.sh` as a fallback for older layouts.

## How to install this skill

### Option A: skills.sh (recommended)

```bash
npx skills add https://github.com/michaelversus/ai-session-logs --skill session-transcript
```

### Option B: Claude Code plugin

**Personal usage**

1. Add the marketplace:

   ```text
   /plugin marketplace add michaelversus/ai-session-logs
   ```

2. Install the plugin (name from [.claude-plugin/plugin.json](.claude-plugin/plugin.json)):

   ```text
   /plugin install ai-session-logs@ai-session-logs
   ```

**Team / repository settings**

Add to `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "ai-session-logs@ai-session-logs": true
  },
  "extraKnownMarketplaces": {
    "ai-session-logs": {
      "source": {
        "source": "github",
        "repo": "michaelversus/ai-session-logs"
      }
    }
  }
}
```

### Option C: pi package manager

```bash
pi install https://github.com/michaelversus/ai-session-logs
```

### Option D: Manual install

1. Clone this repository.
2. Symlink or copy the `session-transcript/` directory into your tool’s skills directory (see [Cursor: Enabling Skills](https://cursor.com/docs), [Codex skills location](https://github.com/openai/codex), [Claude Code plugins](https://code.claude.com/docs)).
3. Ask your agent to use the **session-transcript** skill for transcript export tasks.

## Verify

Your agent should read [session-transcript/SKILL.md](session-transcript/SKILL.md) and run the documented layout-aware command that checks `session-transcript/bin/find_current_session_transcript.sh` first, then `.agent/skills/session-transcript/bin/find_current_session_transcript.sh`, and finally `skills/session-transcript/bin/find_current_session_transcript.sh`.

## GitHub Copilot caveat

Copilot support targets **VS Code debug JSONL** under workspace storage when present. It is **not** guaranteed to match a full chat archive. See [session-transcript/SKILL.md](session-transcript/SKILL.md) and [references/paths.md](references/paths.md).

## License

MIT — see [LICENSE](LICENSE).
