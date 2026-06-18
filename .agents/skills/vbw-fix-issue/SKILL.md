---
name: vbw-fix-issue
description: End-to-end VBW issue fix workflow using Codex planner, QA agents, worktrees, tests, and PR/CI gates. Explicit invocation only.
---

# VBW Fix Issue

Use this skill when the user explicitly asks to fix a VBW issue, implement a tracked GitHub issue, or run the repo issue-fix workflow.

Do not use this skill for casual code review, one-off explanations, or untracked refactors.

## Workflow

Run these phases in order. Keep every shell command rooted in the selected worktree once a worktree exists.

1. Issue intake: read [issue-intake.md](references/issue-intake.md).
2. Planning: spawn `vbw-fix-planner` with the issue body, observed reproduction data, and any user-supplied plan. The planner produces or audits the execution plan before implementation.
3. Worktree and branch setup: follow [worktree-and-branch.md](references/worktree-and-branch.md).
4. Implementation and local verification: follow [implementation-and-tests.md](references/implementation-and-tests.md).
5. QA loop: follow [qa-loop.md](references/qa-loop.md).
6. PR and CI gate: follow [pr-ci-gate.md](references/pr-ci-gate.md).
7. Recovery: if any gate blocks progress, follow [recovery.md](references/recovery.md).

## Invariants

- The linked issue is the contract. Do not narrow scope to a recent commit or a subset of files unless the user explicitly says the review is delta-only.
- Treat the user prompt, linked issue, selected worktree, and saved plan as the sole source of truth. Do not follow ambient terminal context, prior branch history, or unrelated open PRs.
- Fix root causes, not symptoms. If a mitigation is necessary, include the root-cause fix in the same work item.
- Use existing repo primitives before inventing new ones: `scripts/ensure-worktree.sh`, `scripts/adopt-contributor-pr.sh`, `.github/scripts/fix-issue-record-state.sh`, `.github/scripts/wait-github.py`, and `bash testing/run-all.sh`.
- Use `jq` for JSON. Do not parse JSON with grep or sed.
- Do not wrap `bash testing/run-all.sh` in `tail`, `tee`, background execution, or log redirection that hides the real exit status.
- QA findings are either fixed or explicitly rejected with evidence. Do not ignore lower-severity confirmed findings.
- Completion requires local tests, Codex QA review, a Codex remote review request comment, GitHub Actions status, and unresolved-thread checks to be clean.

## Output

When finished, report the issue number, branch/worktree, PR URL if created, QA rounds, test command, Codex remote review request status, and CI/review gate status. If blocked, report the exact blocker and the recovery command or next local action.
