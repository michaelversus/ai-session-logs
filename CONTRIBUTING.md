# Contributing

## Agent Skills format

This repo follows the Agent Skills layout: skill metadata and instructions live under `session-transcript/` (see [SKILL.md](session-transcript/SKILL.md)).

## Changing the CLI

1. Update [references/cli-spec.md](references/cli-spec.md) first (treat it as the contract).
2. Change [scripts/find_current_session_transcript.sh](scripts/find_current_session_transcript.sh) to match.
3. Update [session-transcript/SKILL.md](session-transcript/SKILL.md) examples.

Use the **create-cli** rubric in [.agents/skills/create-cli](.agents/skills/create-cli/SKILL.md) and [clig.dev](https://clig.dev/) when designing flag changes.

## Adding a new tool

1. Add a row to [references/paths.md](references/paths.md).
2. Implement discovery in `scripts/find_current_session_transcript.sh` (new `find_*` function + scoring branch).
3. Extend `--tool` values in the CLI spec and script.
4. Add a fixture under `tests/fixtures/` and a case in `tests/run_fixtures.sh`.

## Tests

From the repository root:

```bash
bash tests/run_fixtures.sh
```

Optional: install [bats](https://github.com/bats-core/bats-core) for future richer suites; the fixture runner is Bash-only.

## Pull requests

Keep changes focused; match existing style in shell scripts (`set -euo pipefail`, quoted variables, BSD-friendly `stat`/`find`).
