#!/usr/bin/env bash
set -u

# delta-files.sh [phase-dir] [plan-path]
# Outputs changed files (one per line) for delta context compilation.
# Sources: git diff, plan's files_modified, prior SUMMARY.md files_modified.
# Outputs empty list on any error (graceful fallback).

PHASE_DIR="${1:-.}"
PLAN_PATH="${2:-}"
PHASE_DIR_EXPLICIT=0
PLAN_PATH_EXPLICIT=0

if [ $# -ge 1 ]; then
  PHASE_DIR_EXPLICIT=1
fi

if [ $# -ge 2 ]; then
  PLAN_PATH_EXPLICIT=1
fi

resolve_git_root_for_delta() {
  local candidate candidate_dir

  for candidate in "$PLAN_PATH" "$PHASE_DIR"; do
    [ -n "$candidate" ] || continue
    [ -e "$candidate" ] || continue

    candidate_dir="$candidate"
    [ -d "$candidate_dir" ] || candidate_dir=$(dirname "$candidate_dir")

    if git -C "$candidate_dir" rev-parse --is-inside-work-tree &>/dev/null; then
      git -C "$candidate_dir" rev-parse --show-toplevel 2>/dev/null || return 0
      return 0
    fi
  done

  if [ "$PHASE_DIR_EXPLICIT" -ne 1 ] && [ "$PLAN_PATH_EXPLICIT" -ne 1 ] && command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    git rev-parse --show-toplevel 2>/dev/null || return 0
    return 0
  fi

  return 1
}

TARGET_GIT_ROOT=$(resolve_git_root_for_delta || true)

# --- Strategy 1: git diff from last tag/merge-base ---
if [ -n "$TARGET_GIT_ROOT" ]; then
  # Changed files in working tree + staged
  CHANGED=$(git -C "$TARGET_GIT_ROOT" diff --name-only HEAD 2>/dev/null || true)
  STAGED=$(git -C "$TARGET_GIT_ROOT" diff --name-only --cached 2>/dev/null || true)

  if [ -n "$CHANGED" ] || [ -n "$STAGED" ]; then
    { echo "$CHANGED"; echo "$STAGED"; } | sort -u | grep -v '^$'
    exit 0
  fi

  # If no uncommitted changes, get files changed in recent commits (since last tag)
  LAST_TAG=$(git -C "$TARGET_GIT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$LAST_TAG" ]; then
    git -C "$TARGET_GIT_ROOT" diff --name-only "$LAST_TAG"..HEAD 2>/dev/null | sort -u | grep -v '^$'
    exit 0
  fi

  # Fallback: last 5 commits
  git -C "$TARGET_GIT_ROOT" diff --name-only HEAD~5..HEAD 2>/dev/null | sort -u | grep -v '^$' || true
  exit 0
fi

# --- Strategy 2: Extract from SUMMARY.md files (no git) ---
if [ -d "$PHASE_DIR" ]; then
  for summary in "$PHASE_DIR"/*-SUMMARY.md; do
    [ -f "$summary" ] || continue
    sed -n '/^## Files Modified/,/^## /p' "$summary" 2>/dev/null | grep '^- ' | sed 's/^- //' | sed 's/ (.*)$//'
  done | sort -u | grep -v '^$'
  exit 0
fi

# --- No sources available ---
exit 0
