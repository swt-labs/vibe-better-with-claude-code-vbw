# Worktree And Branch

Use a dedicated worktree for all issue work. Prefer the existing helper:

```bash
bash scripts/ensure-worktree.sh <branch-name>
```

Rules:

- Branch names use the repo convention `codex/<short-issue-slug>` unless the user requested a specific branch.
- Worktrees live under `../<repo-name>-worktrees/<branch-name-with-slashes-flattened>/`.
- If adopting an existing contributor PR, use `scripts/adopt-contributor-pr.sh` instead of creating an independent branch.
- After the worktree exists, run every git/test/edit command from the worktree absolute path.
- Do not remove worktrees at the end. Cleanup is handled by `git merged`.
- If a branch is already checked out in a different worktree, stop and report the mismatch rather than force-moving it.

Record PR/worktree state with `.github/scripts/fix-issue-record-state.sh` only when the active runtime uses the local stop-hook state file. Codex workflows should still include the branch, worktree, and PR number in their final evidence.
