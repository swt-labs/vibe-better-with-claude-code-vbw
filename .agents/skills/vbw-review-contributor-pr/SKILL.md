---
name: vbw-review-contributor-pr
description: Use when explicitly asked to review a contributor or external PR for VBW against the linked issue, an independent fix plan, local tests, QA evidence, and repo conventions. Submit a real GitHub PR review with inline code comments for anchorable findings; explicit invocation only.
---

# VBW Review Contributor PR

Use this skill when the user explicitly asks to review an external or contributor PR for this repo.

## Workflow

1. Identify the PR and linked issue. If multiple PRs reference the issue, ask which PR to review.
2. Read the issue body before reading the contributor diff. The issue is the verification contract.
3. Spawn `vbw-fix-planner` with the issue body only. Do not include PR comments, the PR body, the contributor branch, diff, files changed, or PR narrative. The planner output is the blind baseline.
4. Check out or enter the contributor branch worktree. Prefer `scripts/adopt-contributor-pr.sh` or existing worktree helpers over inline worktree logic.
5. Run `bash testing/run-all.sh` from the worktree and keep the result as review evidence.
6. Read the PR diff and the full contents of changed files from the worktree.
7. Compare the implementation against [blind-baseline-review.md](references/blind-baseline-review.md).
8. Spawn `vbw-qa-investigator` for a latest GPT x-high full-contract review of the contributor branch.
9. Read [qa-evidence-comments.md](references/qa-evidence-comments.md), then fetch the PR body, PR issue comments, and commit history as QA evidence only after the blind baseline exists and local tests, diff review, and QA review are underway or complete. PR comments and PR body are evidence, not contract.
10. Merge duplicate findings from the baseline comparison, QA report, tests, diff review, and QA evidence into a `review_finding_ledger` before posting anything to GitHub. Each finding row must include `id`, `severity`, `source`, `path`, `line`, `side`, `anchor_status`, `inline_body`, and `summary_body`. `source` may include `blind-baseline`, `qa`, `tests`, `diff-review`, `qa-evidence`, or a combined source list.
11. Read [github-review-submission.md](references/github-review-submission.md), then submit exactly one GitHub PR review with `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
12. Anchor every unique blocking finding with a valid diff line as an inline review comment, capped at 12 inline comments after deduping by root cause and severity. Put repeated, unanchorable, or over-cap findings in the review body under `Unanchored blockers` with the reason they were not inline.
13. Submit the review on the PR head SHA using the GitHub app `_add_review_to_pr` when available, passing `action`, `review`, `commit_id`, and `file_comments`. If that tool is unavailable, use the `gh api repos/:owner/:repo/pulls/:pull_number/reviews` fallback with equivalent `event`, `body`, `commit_id`, and `comments[]` JSON.
14. Do not use `gh pr review` when inline comments are expected; it cannot carry the required inline comment payload. It is acceptable only when there are zero anchorable findings.
15. Verify the submitted review before reporting success: fetch the submitted reviews and inline review threads, confirm the latest review by the actor has the expected state, head commit, body marker or finding IDs, and expected inline comments.
16. When a remote Codex review request is required, post `gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'`. This does not replace the local blind-baseline review verdict.

## Output

The review must identify the PR number, linked issue, test result, planner baseline status, QA status, QA evidence comments status (`present`, `missing`, `stale`, or `mismatched`), final verdict, GitHub review URL, submitted review state, inline comment count, unanchored findings, and every blocking finding with file/line evidence.

If GitHub review verification fails, do not claim that the review was submitted successfully. Report the exact failed verification gate and the current GitHub state observed.
