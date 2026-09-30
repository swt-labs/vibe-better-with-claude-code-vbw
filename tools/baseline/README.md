# Baselines

Measures VBW and plain Claude Code on the same tasks, before v2 code exists, so
v2 has targets to beat.

- `cases/<name>/`: `request.txt` (the task), `case.meta` (fixture, v1 command,
  limits), `graders/` (for `claude plugin eval`), `check.sh` (deterministic
  post-run check for `direct.sh`).
- `fixtures/<name>/fixture.sh`: seeds the workspace (a git repo; plus a minimal
  `.vbw-planning/` for v1 when `v1-defaults.json` sits beside it).
- `run.sh`: runs the cases with `claude plugin eval` (sandboxed). v2 must pass
  here. v1 cannot: every v1 command fails under the sandbox (ledger D296).
- `direct.sh`: runs one case with `claude -p` against the installed VBW or with
  it disabled, then grades with `check.sh`. Used for v1 baselines.
- `results/`: one JSON line per run (arm, pass, cost, turns, wall time).
