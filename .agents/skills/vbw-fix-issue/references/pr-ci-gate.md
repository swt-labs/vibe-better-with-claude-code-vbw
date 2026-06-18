# PR And CI Gate

1. Open the PR as draft until implementation, tests, and QA are complete.
2. PR body must include the linked issue, What/Why/How, test evidence, QA rounds, and any follow-up observations.
3. Mark the PR ready only after local tests and Codex QA are clean.
4. After the PR is ready and the current head is pushed, request remote Codex review with:

```bash
gh pr comment <pr-number> --repo swt-labs/vibe-better-with-claude-code-vbw --body '@codex review'
```

5. Post one Codex review request comment per current head. If new commits are pushed after the request, post `@codex review` again before completion.
6. Wait for GitHub Actions checks on the exact pushed head SHA. Use `.github/scripts/wait-github.py wait-ci` when a polling helper is needed.
7. If CI fails, diagnose the failing check, fix the root cause, rerun `bash testing/run-all.sh`, commit, push, and repeat the QA/CI gate as needed.
8. If `origin/main` advances or the PR is behind/dirty, merge `origin/main` in the worktree, resolve conflicts, rerun tests, commit the merge or conflict resolution, and rerun QA if code under review changed.
9. Completion requires:
   - PR is not draft;
   - no merge conflicts and not behind main;
   - an `@codex review` issue comment exists at or after the current head commit timestamp;
   - GitHub Actions checks are green on the current head;
   - no active `CHANGES_REQUESTED` review decision;
   - no unresolved review threads.
