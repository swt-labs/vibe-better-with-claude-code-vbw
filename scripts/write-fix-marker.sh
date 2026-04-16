#!/usr/bin/env bash
# write-fix-marker.sh — Persist the latest fix commit for inline QA/UAT.
#
# Writes .last-fix-commit marker to the planning directory so that
# suggest-next.sh and verify.md can detect recent fix work and offer
# UAT without requiring PLAN/SUMMARY artifacts.
#
# Usage:
#   write-fix-marker.sh [planning-dir] [description]
#
# Arguments:
#   planning-dir  — path to .vbw-planning (default: .vbw-planning)
#   description   — optional human description of the fix
#
# Always exits 0 — this is a non-blocking helper.

set -u

PLANNING_DIR="${1:-.vbw-planning}"
DESCRIPTION="${2:-}"

# Validate planning dir exists
if [ ! -d "$PLANNING_DIR" ]; then
  exit 0
fi

# Require git
if ! command -v git &>/dev/null; then
  exit 0
fi

# Read HEAD commit info
commit_hash=$(git rev-parse --short HEAD 2>/dev/null) || exit 0
commit_message=$(git log --format='%s' -1 2>/dev/null) || exit 0
commit_timestamp=$(git log --format='%aI' -1 2>/dev/null) || exit 0
changed_files=$(git diff-tree --root --no-commit-id --name-only -r HEAD 2>/dev/null) || exit 0

# Fall back to commit message if no description provided
if [ -z "$DESCRIPTION" ]; then
  DESCRIPTION="$commit_message"
fi

# Write marker file (overwrite any existing marker)
marker_file="$PLANNING_DIR/.last-fix-commit"
{
  printf 'commit=%s\n' "$commit_hash"
  printf 'message=%s\n' "$commit_message"
  printf 'timestamp=%s\n' "$commit_timestamp"
  printf 'description=%s\n' "$DESCRIPTION"
  printf 'files=%s\n' "$changed_files"
} > "$marker_file" 2>/dev/null || true

exit 0
