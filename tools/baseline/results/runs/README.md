# Benchmark results

One JSON file per run, written by `tools/baseline/bench.sh` and checked by
`tools/baseline/verify-results.sh` (84 runs: 7 cases, plain Claude Code and
VBW 2, Sonnet 5.5 and Opus 5.5, 3 runs each).

| Field | Meaning |
|---|---|
| `arm` | `plain` (Claude Code, VBW not loaded, headless `claude -p`) or `vbw2` (the TUI driven as a user through `/vbw:vibe`) |
| `model`, `case`, `run` | which run this is |
| `pass` | the case's `check.sh` passed on the finished workspace |
| `tokens` | all tokens of the session, prompt-cache reads included (main session and subagents for VBW 2) |
| `cost_usd` | the session's cost as Claude Code reports it |
| `user_inputs` | answers and approvals the user gave after the request (0 for plain) |
| `level` | `L2` for plain (headless), `L3` for VBW 2 (driven as a user) |
| `vbw_engaged` | VBW 2 only, from the harness fix onward: whether the session set VBW up |
| `rerun_of` | this record replaces the named one; `regraded: true` means the same run graded again by a corrected check (same tokens, cost and inputs) |

A record named in another record's `rerun_of` is superseded; it stays for the
history and is not counted.
