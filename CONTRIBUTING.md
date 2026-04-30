# Contributing

## Agent Skills format

This repo follows the Agent Skills layout: skill metadata and instructions live under `session-transcript/` (see [SKILL.md](session-transcript/SKILL.md)).

## Changing the CLI

1. Update [references/cli-spec.md](references/cli-spec.md) first (treat it as the contract).
2. Change [scripts/find_current_session_transcript.sh](scripts/find_current_session_transcript.sh) to match.
3. Update [session-transcript/SKILL.md](session-transcript/SKILL.md) examples.

Use [clig.dev](https://clig.dev/) (CLI interface guidelines) when designing flag changes.

## Adding a new tool

1. Add a row to [references/paths.md](references/paths.md).
2. Add a new tool-specific shell file under `scripts/lib/` with the relevant `find_*` function and any tool-specific helpers.
3. Extend `--tool` values in the CLI spec and script.
4. Add a tool-specific test case file under `tests/cases/` and source it from `tests/run_fixtures.sh`.

## Tests

From the repository root:

```bash
bash tests/run_fixtures.sh
```

Optional: install [bats](https://github.com/bats-core/bats-core) for future richer suites; the fixture runner is Bash-only.

## Pull requests

Keep changes focused; match existing style in shell scripts (`set -euo pipefail`, quoted variables, BSD-friendly `stat`/`find`).
