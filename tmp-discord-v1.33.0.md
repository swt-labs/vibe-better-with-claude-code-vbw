# VBW v1.33.0 — Discord update draft

VBW `v1.33.0` is out.

This release is a mix of real workflow upgrades, cleaner remediation handling, better statusline behavior, and a pile of reliability fixes for long-running team sessions.

## What’s new

### Smarter UAT remediation flow
We shipped a much cleaner remediation system for failed UAT rounds.

- Remediation artifacts now live in dedicated `remediation/round-XX/` directories instead of cluttering the phase root.
- Each round gets its own research, plan, summary, and UAT files.
- Remediation planning/execution is now self-contained and sequential, so it no longer inherits the normal team/wave behavior in weird ways.
- Re-verification now targets the latest remediation round instead of re-reading stale phase-level files.

If you’ve ever had remediation rounds get messy or hard to reason about, this should feel a lot better.

### Better statusline behavior
The statusline got a meaningful upgrade.

- Added new display controls for hiding limits, hiding them only for API-key sessions, hiding the build/agent line in tmux, or collapsing to a single line in tmux.
- The `[VBW]` badge now reflects whether VBW context is actually active in the current session.
- Statusline progress is more accurate after reset/undo and better at reflecting remediation/UAT lifecycle states.
- First render is more reliable and avoids some cold-start weirdness.

### Easier local development for contributors
For people hacking on VBW itself:

- Added `scripts/dev-setup.sh`
- Added an optional `claude-vbw` launcher

That makes it much easier to set up, tear down, and launch a local VBW checkout for development and testing.

## Workflow improvements

- QA now writes `VERIFICATION.md` through `write-verification.sh` directly instead of relying on the old heredoc escape-hatch pattern.
- Forced skill evaluation for spawned agents now works much more reliably. We moved skill injection to `SubagentStart`, which fixes cases where subagents and team workflows would silently miss the skills they were supposed to have.
- Agent turn-limit handling was tightened so "unlimited" agents don’t get accidentally capped by frontmatter defaults.
- VBW now warns when GSD is installed alongside it, which should help avoid cross-wired `/gsd:*` vs `/vbw:*` workflows.
- `/vbw:todo` and `/vbw:list-todos` now fail cleanly in restricted modes with a clear explanation instead of just behaving badly.

## Reliability fixes

This release also ships a bunch of under-the-hood fixes that matter in real use:

- Fixed stale `.context-usage` state so new sessions don’t inherit bogus high-context warnings.
- Added explicit `shutdown_response` handling so team shutdowns are more reliable.
- Cleaned up stale/orphaned VBW team directories to prevent ghost agent labels in Claude Code.
- Improved worktree cleanup so locked worktrees and stale metadata are removed properly.
- Added cleanup for dead entries in `.agent-pids`.
- Added protection for tmux panes that get stuck during compaction.
- Hardened linked-issue enforcement in CI with better matching, better messages, and clearer rules.

## Short version

`v1.33.0` makes VBW better at:

- handling remediation rounds
- showing accurate session state
- surviving long-running team workflows
- cleaning up after itself
- making contributor setup less annoying

If you’ve been using VBW heavily, this one should feel noticeably smoother.
