#!/usr/bin/env bash
set -euo pipefail

# ensure-worktree.sh — Resolve or create a canonical worktree for a branch.
# Handles: existing worktrees, legacy slash-named worktrees, conflicts, creation.
#
# Usage: bash scripts/ensure-worktree.sh <branch-name>
# Output on success: prints the absolute worktree path on stdout.
# Exit codes: 0 = success (prints worktree path on stdout), 1 = error (stderr has details)

branch="${1:?Usage: ensure-worktree.sh <branch-name>}"

git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || exit 1
repo_root=$(cd "$git_common_dir/.." && pwd) || exit 1
repo_name=$(basename "$repo_root")
worktree_base="$(cd "$repo_root/.." && pwd)/${repo_name}-worktrees"
worktree_name=$(printf '%s' "$branch" | tr '/' '-')
target_worktree="${worktree_base}/${worktree_name}"
legacy_worktree="${worktree_base}/${branch}"
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
current_toplevel=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
branch_worktree=""
target_worktree_branch=""
wt_path=""

while IFS= read -r line; do
    case "$line" in
        worktree\ *)
            wt_path="${line#worktree }"
            ;;
        branch\ refs/heads/*)
            wt_branch="${line#branch refs/heads/}"
            if [ "$wt_branch" = "$branch" ]; then
                branch_worktree="$wt_path"
            fi
            if [ "$wt_path" = "$target_worktree" ]; then
                target_worktree_branch="$wt_branch"
            fi
            ;;
        '')
            wt_path=""
            ;;
    esac
done < <(git worktree list --porcelain 2>/dev/null)

if [ "$current_toplevel" = "$target_worktree" ] && [ "$current_branch" = "$branch" ]; then
    cd "$target_worktree" || exit 1
elif [ "$current_toplevel" = "$legacy_worktree" ] && [ "$current_branch" = "$branch" ]; then
    cd "$legacy_worktree" || exit 1
elif [ -n "$branch_worktree" ] && [ "$branch_worktree" = "$target_worktree" ]; then
    cd "$target_worktree" || exit 1
elif [ -n "$branch_worktree" ] && [ "$branch_worktree" = "$legacy_worktree" ]; then
    cd "$legacy_worktree" || exit 1
elif [ -n "$branch_worktree" ]; then
    echo "Branch '$branch' is already checked out in a different worktree: $branch_worktree" >&2
    echo "Expected canonical path: $target_worktree" >&2
    exit 1
elif [ -n "$target_worktree_branch" ] && [ "$target_worktree_branch" != "$branch" ]; then
    echo "Target worktree path is already used by branch '$target_worktree_branch': $target_worktree" >&2
    exit 1
elif [ -e "$target_worktree" ]; then
    echo "Target worktree path exists but is not a registered worktree: $target_worktree" >&2
    echo "Clean it up manually before retrying." >&2
    exit 1
else
    mkdir -p "$worktree_base"
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        git worktree add "$target_worktree" "$branch" || exit 1
        cd "$target_worktree" || exit 1
    else
        git fetch origin || exit 1
        git worktree add --detach "$target_worktree" origin/main || exit 1
        cd "$target_worktree" || exit 1
        git switch -c "$branch" --no-track || exit 1
    fi
fi

echo "$PWD"
