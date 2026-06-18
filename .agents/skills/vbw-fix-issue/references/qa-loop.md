# QA Loop

Every QA round is a fresh full-contract review of the branch tip.

1. Spawn `vbw-qa-investigator` with:
   - issue number and full issue body;
   - worktree absolute path;
   - branch or PR number;
   - test evidence;
   - instruction that this is latest GPT x-high full-contract review, not delta-only review.
2. For nontrivial or high-risk changes, require at least one additional clean `vbw-qa-investigator` round on the latest branch tip after the first clean round. Do not spawn a separate model-pinned QA agent.
3. Treat confirmed `contract` and `regression` findings at any severity as work to resolve. Treat `observation` findings as separate tracked follow-up candidates unless the issue scope requires fixing them now.
4. Before fixing QA findings, ask `vbw-fix-planner` to plan the remediation when findings touch multiple files, shared behavior, or workflow contracts.
5. After legitimate findings are fixed, run `bash testing/run-all.sh`, commit the fix, and start a fresh QA round.
6. Exit the QA loop only when all required latest GPT x-high QA rounds are clean and the test suite passes.
