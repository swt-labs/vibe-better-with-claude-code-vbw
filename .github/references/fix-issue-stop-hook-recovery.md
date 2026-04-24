# Fix-Issue Stop Hook: Targeting Cascade & Recovery Procedures

## Targeting Cascade

How the hook picks which PR to validate:

1. **Tier 1 — explicit state file.** If step 23a ran, `/tmp/fix-issue-vbw-state-<session_id>.json` exists and the hook validates exactly this thread's PR. The state file is deleted automatically when all gates pass.
2. **Tier 2 — transcript inference.** If no state file, the hook scans the thread's transcript JSONL for references to local worktree paths. If exactly one worktree is referenced, that worktree's PR is validated.
3. **Tier 3 — single candidate.** If only one local worktree has an open PR, it is validated.
4. **Tier 4 — strict fallback.** If multiple open-PR worktrees exist AND the transcript did not uniquely identify one AND no state file was found, the hook validates every local open-PR worktree and blocks on the first failure. This tier exists so no thread can silently complete while any local PR is unready.

## Recovery Procedures

### Blocked for pending CI

1. Extract `commit_sha`, `worktree_path`, and `recovery_command` from the block output.
2. Wait for CI by running the `recovery_command` periodically (it queries check runs for the exact commit).
3. Do NOT run `git rev-parse HEAD` from the main repo directory — the hook already ran from the worktree and provided the correct SHA.
4. Once all checks show `completed / success`, re-invoke and let the stop hook re-evaluate the remaining PR state. There is no same-SHA bypass — if another gate is still failing, the hook will continue to block until that state is cleared.

### Other block reasons

Draft PR, behind/dirty PR, stale Copilot review, active `CHANGES_REQUESTED`, unresolved review threads, CI failure: follow the instructions in the `reason` field, using `worktree_path` for all file/git operations when it is present. Typical recovery is to merge `origin/main`, resolve conflicts, address the requested review feedback, resolve the outstanding review threads, or obtain an updated review — then re-run the workflow and let the hook re-check live GitHub state.
