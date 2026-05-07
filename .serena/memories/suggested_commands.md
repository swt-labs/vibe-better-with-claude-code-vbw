# Suggested commands

- Run all checks: `bash testing/run-all.sh` (run directly; do not pipe through tail/tee wrappers).
- Verify bash/script contracts: `bash testing/verify-bash-scripts-contract.sh`.
- Verify command frontmatter: `bash testing/verify-commands-contract.sh`.
- Verify hook event names: `bash testing/verify-hook-event-name.sh`.
- Verify plugin root resolution: `bash testing/verify-plugin-root-resolution.sh`.
- Verify LSP-first policy: `bash testing/verify-lsp-first-policy.sh`.
- Verify init workflow: `bash scripts/verify-init-todo.sh`.
- Verify Claude bootstrap: `bash scripts/verify-claude-bootstrap.sh`.
- Verify version sync: `bash scripts/bump-version.sh --verify`.
- Resolve local debug target: `bash scripts/resolve-debug-target.sh repo`.
- Common git commands: `git status`, `git diff`, `git branch --show-current`, `git log --oneline`, `git fetch --prune`.
- Cleanup merged branches/worktrees after PR merge: `git merged`.
- Cleanup branches whose remote tracking branch is gone: `git cleanup`.