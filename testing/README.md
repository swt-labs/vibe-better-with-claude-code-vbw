# Testing Harness

This folder contains verification scripts for VBW that are safe to run locally and in CI.

## Automated checks

Run all checks:

- `bash testing/run-all.sh` — runs CI-parity shell lint, contract checks, and bats (`shellcheck` required locally)

Run individual checks:

- `bash scripts/verify-init-todo.sh`
- `bash scripts/verify-claude-bootstrap.sh`
- `bash testing/verify-bash-scripts-contract.sh`
- `bash testing/verify-commands-contract.sh`

Optional (local only, depends on your global Claude mirror state):

- `RUN_VIBE_VERIFY=1 bash testing/run-all.sh`

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
