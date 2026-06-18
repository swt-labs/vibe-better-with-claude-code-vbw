# Blind Baseline Review

Compare the contributor implementation against the issue contract and the independent planner baseline.

Evaluate these dimensions:

- Root cause: fixes the underlying invariant or contract, not a narrow symptom.
- Architecture: uses repo patterns and avoids duplication, silent fallbacks, and brittle special cases.
- Completeness: satisfies every acceptance criterion from the issue.
- Conventions: follows `AGENTS.md`, including bash, JSON, naming, dependency, and commit rules.
- Brownfield handling: preserves existing installations and generated artifacts when formats or state change.
- Test coverage: includes the right tier of tests for the changed artifact type.
- Scope discipline: avoids unrelated refactors and feature expansion.

Verdict rules:

- `APPROVE`: issue contract satisfied, tests pass, QA is clean, and no blocking baseline concerns remain.
- `REQUEST_CHANGES`: any acceptance criterion is missing, tests fail, QA has blocking findings, or the approach is materially weaker than the baseline.
- `COMMENT`: review is informational, blocked by missing context, or the PR is outside the expected issue-fix path.
