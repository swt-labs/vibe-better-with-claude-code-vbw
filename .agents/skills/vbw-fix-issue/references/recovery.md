# Recovery

If a gate blocks completion, use the structured blocker as the source of truth.

- Draft PR: mark ready only after local tests and Codex QA are clean.
- Behind or dirty PR: merge `origin/main`, resolve conflicts, run `bash testing/run-all.sh`, commit, push, and rerun QA when the reviewed code changed.
- Missing Codex remote review request: from the worktree, run `gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'`.
- Pending CI: wait for the exact head SHA checks to finish.
- Failed CI: inspect the failing check output, fix the root cause, rerun local tests, commit, push, and repeat QA/CI.
- Active changes requested or unresolved review threads: address each thread or reply with evidence, then resolve the thread only after the issue is actually handled.
- Missing worktree state: reselect or recreate the worktree; do not validate from the main checkout.

If the workflow state is ambiguous, stop and report the branch, PR number, worktree path, and the command that failed.
