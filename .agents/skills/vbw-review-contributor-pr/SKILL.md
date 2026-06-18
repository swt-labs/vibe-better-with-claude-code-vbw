---
name: vbw-review-contributor-pr
description: Review a contributor PR against an independent VBW fix plan, tests, QA evidence, and repo conventions. Explicit invocation only.
---

# VBW Review Contributor PR

Use this skill when the user explicitly asks to review an external or contributor PR for this repo.

## Workflow

1. Identify the PR and linked issue. If multiple PRs reference the issue, ask which PR to review.
2. Read the issue body before reading the contributor diff. The issue is the verification contract.
3. Spawn `vbw-fix-planner` with the issue body only. Do not include the contributor branch, diff, files changed, or PR narrative. The planner output is the blind baseline.
4. Check out or enter the contributor branch worktree. Prefer `scripts/adopt-contributor-pr.sh` or existing worktree helpers over inline worktree logic.
5. Run `bash testing/run-all.sh` from the worktree and keep the result as review evidence.
6. Read the PR diff and the full contents of changed files from the worktree.
7. Compare the implementation against [blind-baseline-review.md](references/blind-baseline-review.md).
8. Spawn `vbw-qa-investigator` for a latest GPT x-high full-contract review of the contributor branch.
9. Merge duplicate findings from the baseline comparison and QA report.
10. Submit a GitHub PR review with `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
11. When a remote Codex review request is required, post `gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'`. This does not replace the local blind-baseline review verdict.

## Output

The review must identify the PR number, linked issue, test result, planner baseline status, QA status, final verdict, and every blocking finding with file/line evidence.
