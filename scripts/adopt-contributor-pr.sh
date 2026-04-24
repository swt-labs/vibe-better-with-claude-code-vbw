#!/usr/bin/env bash
set -euo pipefail

# adopt-contributor-pr.sh — Fetch and check out a contributor's PR branch locally.
# Handles both same-repo and fork PRs safely, avoids overwriting local branches.
#
# Usage: bash scripts/adopt-contributor-pr.sh <PR_NUM>
# Output: key=value pairs on stdout (eval-safe):
#   CHECKOUT_BRANCH, PUSH_REMOTE, IS_FORK, PR_BRANCH, PR_AUTHOR
#   For fork PRs also: FORK_OWNER, FORK_REPO
# Exit codes: 0 = success, 1 = validation failure (stderr has details)

PR_NUM="${1:?Usage: adopt-contributor-pr.sh <PR_NUM>}"

if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
    echo "Error: PR_NUM must be a positive integer, got '$PR_NUM'" >&2
    exit 1
fi

PR_JSON=$(gh pr view "$PR_NUM" -R swt-labs/vibe-better-with-claude-code-vbw --json headRefName,headRepository,isCrossRepository,maintainerCanModify,state,author)
PR_STATE=$(printf '%s' "$PR_JSON" | jq -r '.state')
PR_BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.headRefName')
IS_FORK=$(printf '%s' "$PR_JSON" | jq -r '.isCrossRepository')
CAN_MODIFY=$(printf '%s' "$PR_JSON" | jq -r '.maintainerCanModify')
PR_AUTHOR=$(printf '%s' "$PR_JSON" | jq -r '.author.login')

# Validation gates
if [ "$PR_STATE" != "OPEN" ]; then
    echo "Error: PR #$PR_NUM is $PR_STATE — cannot push fixes to a closed or merged PR." >&2
    exit 1
fi

if [ "$IS_FORK" = "true" ] && [ "$CAN_MODIFY" = "false" ]; then
    echo "Error: PR #$PR_NUM is from a fork that does not allow maintainer pushes." >&2
    echo "Ask the contributor to enable 'Allow edits from maintainers', or implement from scratch on a new branch." >&2
    exit 1
fi

if [ "$IS_FORK" = "true" ]; then
    FORK_OWNER=$(printf '%s' "$PR_JSON" | jq -r '.headRepository.owner.login')
    FORK_REPO=$(printf '%s' "$PR_JSON" | jq -r '.headRepository.owner.login + "/" + .headRepository.name')
    git remote add "$FORK_OWNER" "https://github.com/$FORK_REPO.git" 2>/dev/null || true

    LOCAL_BRANCH="pr/${PR_AUTHOR}/${PR_NUM}"
    SUFFIX=1
    while git show-ref --verify --quiet "refs/heads/$LOCAL_BRANCH" 2>/dev/null; do
        LOCAL_BRANCH="pr/${PR_AUTHOR}/${PR_NUM}-${SUFFIX}"
        SUFFIX=$((SUFFIX + 1))
    done

    git fetch "$FORK_OWNER" "${PR_BRANCH}:${LOCAL_BRANCH}"
    git branch --set-upstream-to="$FORK_OWNER/$PR_BRANCH" "$LOCAL_BRANCH" 2>/dev/null || \
        git branch -u "$FORK_OWNER/$PR_BRANCH" "$LOCAL_BRANCH" 2>/dev/null || true
    CHECKOUT_BRANCH="$LOCAL_BRANCH"
    PUSH_REMOTE="$FORK_OWNER"

    echo "CHECKOUT_BRANCH=$CHECKOUT_BRANCH"
    echo "PUSH_REMOTE=$PUSH_REMOTE"
    echo "IS_FORK=true"
    echo "PR_BRANCH=$PR_BRANCH"
    echo "PR_AUTHOR=$PR_AUTHOR"
    echo "FORK_OWNER=$FORK_OWNER"
    echo "FORK_REPO=$FORK_REPO"
else
    REMOTE_REF="refs/remotes/origin/$PR_BRANCH"
    git fetch origin "$PR_BRANCH"
    REMOTE_SHA=$(git rev-parse "$REMOTE_REF" 2>/dev/null || echo "")

    if git show-ref --verify --quiet "refs/heads/$PR_BRANCH" 2>/dev/null; then
        LOCAL_SHA=$(git rev-parse "refs/heads/$PR_BRANCH" 2>/dev/null || echo "")
        if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
            LOCAL_BRANCH="pr/${PR_AUTHOR}/${PR_NUM}"
            SUFFIX=1
            while git show-ref --verify --quiet "refs/heads/$LOCAL_BRANCH" 2>/dev/null; do
                LOCAL_BRANCH="pr/${PR_AUTHOR}/${PR_NUM}-${SUFFIX}"
                SUFFIX=$((SUFFIX + 1))
            done
            git branch "$LOCAL_BRANCH" "$REMOTE_SHA"
            git branch --set-upstream-to="origin/$PR_BRANCH" "$LOCAL_BRANCH" 2>/dev/null || true
            CHECKOUT_BRANCH="$LOCAL_BRANCH"
        else
            CHECKOUT_BRANCH="$PR_BRANCH"
        fi
    else
        git branch "$PR_BRANCH" "$REMOTE_SHA"
        git branch --set-upstream-to="origin/$PR_BRANCH" "$PR_BRANCH" 2>/dev/null || true
        CHECKOUT_BRANCH="$PR_BRANCH"
    fi
    PUSH_REMOTE="origin"

    echo "CHECKOUT_BRANCH=$CHECKOUT_BRANCH"
    echo "PUSH_REMOTE=$PUSH_REMOTE"
    echo "IS_FORK=false"
    echo "PR_BRANCH=$PR_BRANCH"
    echo "PR_AUTHOR=$PR_AUTHOR"
fi
