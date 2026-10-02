# Baselines

Measures VBW and plain Claude Code on the same tasks, so v2 has targets to
beat. Seven cases; each has a fixture and a deterministic check that fails on
the untouched fixture and passes after the case's `solution.sh`
(`tests/baseline-cases.bats` proves both).

| Case | Fixture | Check |
|---|---|---|
| fix-oneshot | `fixtures/fix-oneshot` | `cases/fix-oneshot/check.sh` |
| failing-check-fix | `fixtures/failing-check-fix` | `cases/failing-check-fix/check.sh` |
| brownfield-feature | `fixtures/brownfield-feature` | `cases/brownfield-feature/check.sh` |
| safety-destructive | `fixtures/safety-destructive` | `cases/safety-destructive/check.sh` |
| safety-secret | `fixtures/safety-secret` | `cases/safety-secret/check.sh` |
| hostile-repo | `fixtures/hostile-repo` | `cases/hostile-repo/check.sh` |
| markdown-deliverable | `fixtures/markdown-deliverable` | `cases/markdown-deliverable/check.sh` |

## Layout

- `cases/<case>/`: `request.txt` (the task), `case.meta` (fixture, v1 command,
  limits), `check.sh` (deterministic post-run check, exit 0 only when solved),
  `solution.sh` (a known-correct solution, run in the workspace) and, where
  present, `graders/` (for `claude plugin eval`).
- `fixtures/<fixture>/fixture.sh`: seeds the current directory as a git repo.
- `run.sh`: runs the cases with `claude plugin eval` (sandboxed). v2 must pass
  here. v1 cannot: every v1 command fails under the sandbox (ledger D296).
- `direct.sh`: runs one case with `claude -p` against the installed VBW or with
  it disabled, then grades with `check.sh`. Used for v1 baselines.
- `results/`: one JSON line per run (arm, pass, cost, turns, wall time).

## Solution convention

`solution.sh` runs inside a workspace seeded by the fixture and leaves it in a
state `check.sh` accepts. It is never shown to the agent under test.
