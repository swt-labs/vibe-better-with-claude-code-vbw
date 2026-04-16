# Testing Harness

This folder contains verification scripts for VBW that are safe to run locally and in CI.

## Automated checks

Run all checks:

- `bash testing/run-all.sh` — runs CI-parity shell lint, contract checks, and bats using the same 4 shard layout and serial-bats split as CI (`jq`, `shellcheck`, and `bats` required locally)

   Local runs start from an 8-worker bats budget and auto-throttle that budget when multiple local `run-all.sh` suites overlap. To pin a different worker count explicitly, use `BATS_WORKERS=N bash testing/run-all.sh`.

Reproduce an individual CI bats shard locally:

- `files=(); while IFS= read -r file; do files+=("$file"); done < <(bash testing/list-bats-files.sh --shardable)`
- `bash testing/run-bats-shard.sh 1 4 "${files[@]}"`

Run the serial bats files locally:

- `files=(); while IFS= read -r file; do files+=("$file"); done < <(bash testing/list-bats-files.sh --serial)`
- `bats "${files[@]}"`

Run individual checks:

- `bash scripts/verify-init-todo.sh`
- `bash scripts/verify-claude-bootstrap.sh`
- `bash testing/verify-bash-scripts-contract.sh`
- `bash testing/verify-commands-contract.sh`

## Real-project smoke tests (manual)

For slash-command behavior, test in a separate sandbox repo (not this plugin repo), for example:

- `/Users/dpearson/repos/vibe-better-testing-repo`

Recommended flow:

1. Start Claude with plugin loaded and model set to haiku.
2. Run `/vbw:init`.
3. Run `/vbw:todo "Test todo"`.
4. Verify `.vbw-planning/STATE.md` contains:
   - `## Todos`
   - inserted todo item under `## Todos`
