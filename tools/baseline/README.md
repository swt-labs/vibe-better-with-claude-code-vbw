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

## Adaptive rigor (R29)

The adaptive set is VBW 2 with automatic rigor on the seven cases and both
models: 14 cells, one record per run in `results/adaptive/`.

- Run a cell: `BENCH_RUNS_DIR=tools/baseline/results/adaptive bash tools/baseline/bench.sh vbw2 MODEL CASE 1`.
  The record adds `rigor` (the workspace's `settings.rigor`, `auto` when
  unset), `round` (`BENCH_ROUND`, default 0) and `tiers` (the phases' tiers
  read from the workspace record).
- A tuning round reruns cells with `BENCH_ROUND=1` (or 2), written as
  `vbw2-MODEL-CASE-1-rN.json`. At most 2 rounds; each is described in
  `results/adaptive/tuning.md` on a line `Round N: what changed and its result`.
  The highest round of a cell is its final state.
- Plain baseline: `BENCH_RUNS_DIR=tools/baseline/results/plain-ui bash tools/baseline/bench.sh plain-ui MODEL CASE N`
  drives plain Claude Code in the same interactive app as the vbw2 arm: same
  settings and sandbox, the plugin not loaded (`tools/l3.sh start ... plain`),
  the request typed, questions answered with the recommended option, finished
  when idle with no question on screen. Its record is arm `plain`, level L3,
  with tokens from the transcripts and cost from `/cost`. Why: the headless
  `claude -p` arm starts from a different base context than the app, so its
  cost is not like for like. Every test session, both arms, excludes this
  repository's own `CLAUDE.md` and `AGENTS.md` (`claudeMdExcludes`); a fixture's
  own instruction files still load. Plain records of level L2 or L3 are accepted.
- Verify: `bash tools/baseline/verify-adaptive.sh [--table] [ADAPTIVE_DIR [PLAIN_DIR [DOC]]]`.
  It needs all 14 cells valid (level L3, rigor auto, non-empty tiers) and a
  `Miss: CASE MODEL: ...` line in `docs/benchmark.md` for every failed case or
  cost above twice plain's. Plain cost is the mean over the case's plain runs
  (`results/plain-ui/`) of the latest rerun of each. `--table` prints one markdown
  row per cell, which the doc's "Adaptive rigor" section quotes.
