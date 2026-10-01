# Implementation And Tests

1. Implement from the accepted planner output and the issue contract.
2. Before modifying a named shell function or shared script behavior, run the repo code-intelligence impact path required by `AGENTS.md`.
3. Keep changes scoped to the issue. Avoid unrelated refactors, version bumps, changelog edits, and generated metadata churn.
4. Add or update tests at the right tier:
   - Bash behavior: BATS tests.
   - Markdown, JSON, YAML, and workflow structure: contract tests in `tests/` (`standards.bats`, `skills.bats`, `workflows.bats`, `record.bats`).
   - LLM-consumed prompt behavior: a real-user scenario (`tools/l3.sh`, `tools/l3-suite.sh`) on a sandbox project.
5. Run the authoritative verification command from the worktree:

```bash
bash tools/test.sh
```

Do not pipe, tail, tee, background, or otherwise wrap that command.

6. Commit atomically with the repo format `{type}({scope}): {description}` and stage files explicitly.
