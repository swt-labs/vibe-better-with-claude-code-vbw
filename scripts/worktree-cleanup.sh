#!/bin/bash
set -u
# worktree-cleanup.sh — Remove a VBW agent worktree and its branch.
# Interface: worktree-cleanup.sh <phase> <plan>
# Always exits 0 (fail-open design).

# Validate arguments
if [ "${1:-}" = "" ] || [ "${2:-}" = "" ]; then
  exit 0
fi

PHASE="$1"
PLAN="$2"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
WORKTREES_PARENT=".vbw-worktrees"
WORKTREE_DIR="${WORKTREES_PARENT}/${PHASE}-${PLAN}"
BRANCH="vbw/${PHASE}-${PLAN}"
AGENT_WORKTREES_DIR="$PLANNING_DIR/.agent-worktrees"

# Unlock the worktree if locked (locked worktrees resist single --force)
git worktree unlock "$WORKTREE_DIR" 2>/dev/null || true

# Remove the git worktree (idempotent — silently ignores if not found)
git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true

# Remove residual filesystem artifacts (e.g. .vbw-planning/, .DS_Store)
rm -rf "$WORKTREE_DIR" 2>/dev/null || true

# Prune stale git worktree metadata for directories that no longer exist
git worktree prune 2>/dev/null || true

# Belt-and-suspenders: if git porcelain failed to clean the admin dir, find and
# remove it by matching the gitdir content (not by guessing the admin dir name,
# since Git may suffix it to avoid collisions).
GIT_DIR="$(git rev-parse --git-dir 2>/dev/null)" || true
if [ -n "${GIT_DIR:-}" ] && [ -d "$GIT_DIR/worktrees" ]; then
  WORKTREE_ABS="$(cd "$(dirname "$WORKTREE_DIR")" 2>/dev/null && pwd)/$(basename "$WORKTREE_DIR")" 2>/dev/null || true
  if [ -n "${WORKTREE_ABS:-}" ]; then
    for admin_dir in "$GIT_DIR/worktrees"/*/; do
      [ -d "$admin_dir" ] || continue
      gitdir_file="${admin_dir}gitdir"
      [ -f "$gitdir_file" ] || continue
      recorded="$(cat "$gitdir_file" 2>/dev/null)" || continue
      # gitdir stores path to worktree's .git file; strip trailing /.git
      recorded_wt="${recorded%/.git}"
      # Resolve to absolute for comparison
      recorded_wt_abs="$(cd "$recorded_wt" 2>/dev/null && pwd)" 2>/dev/null || recorded_wt_abs=""
      if [ "$recorded_wt_abs" = "$WORKTREE_ABS" ] || [ "$recorded_wt" = "$WORKTREE_DIR" ]; then
        rm -rf "$admin_dir" 2>/dev/null || true
      fi
    done
  fi
fi

# Remove hidden entries from parent (macOS artifacts: .DS_Store, .localized, ._* etc.)
for entry in "$WORKTREES_PARENT"/.*; do
  case "$(basename "$entry")" in .|..) continue ;; esac
  rm -rf "$entry" 2>/dev/null || true
done
# Remove parent .vbw-worktrees/ if now empty
rmdir "$WORKTREES_PARENT" 2>/dev/null || true

# Delete the branch — now safe since git admin metadata is fully cleared
git branch -d "$BRANCH" 2>/dev/null || true

# Clear the agent-worktree mapping entry if the directory exists
if [ -d "$AGENT_WORKTREES_DIR" ]; then
  # Remove any JSON file matching the phase-plan pattern
  for f in "$AGENT_WORKTREES_DIR"/*"${PHASE}-${PLAN}"*.json; do
    [ -f "$f" ] && rm -f "$f" 2>/dev/null || true
  done
fi

exit 0
