#!/usr/bin/env bash
set -u

# delta-files.sh [phase-dir] [plan-path]
# Outputs changed files (one per line) for delta context compilation.
# Sources: git diff, plan's files_modified, prior SUMMARY.md files_modified.
# Outputs empty list on any error (graceful fallback).

PHASE_DIR="${1:-.}"

# --- Strategy 1: git diff from last tag/merge-base ---
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  # Changed files in working tree + staged
  CHANGED=$(git diff --name-only HEAD 2>/dev/null || true)
  STAGED=$(git diff --name-only --cached 2>/dev/null || true)

  if [ -n "$CHANGED" ] || [ -n "$STAGED" ]; then
    { echo "$CHANGED"; echo "$STAGED"; } | sort -u | grep -v '^$'
    exit 0
  fi

  # If no uncommitted changes, get files changed in recent commits (since last tag)
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$LAST_TAG" ]; then
    git diff --name-only "$LAST_TAG"..HEAD 2>/dev/null | sort -u | grep -v '^$'
    exit 0
  fi

  # Fallback: last 5 commits
  git diff --name-only HEAD~5..HEAD 2>/dev/null | sort -u | grep -v '^$' || true
  exit 0
fi

# --- Strategy 2: Extract from SUMMARY.md files (no git) ---
if [ -d "$PHASE_DIR" ]; then
  # Scan flat root + wave-subdir + remediation-round SUMMARYs, globally deduplicated
  {
    for summary in "$PHASE_DIR"/*-SUMMARY.md; do
      [ -f "$summary" ] || continue
      sed -n '/^## Files Modified/,/^## /p' "$summary" 2>/dev/null | grep '^- ' | sed 's/^- //' | sed 's/ (.*)$//'
    done
    for summary in "$PHASE_DIR"/P*-*-wave/*-SUMMARY.md; do
      [ -f "$summary" ] || continue
      sed -n '/^## Files Modified/,/^## /p' "$summary" 2>/dev/null | grep '^- ' | sed 's/^- //' | sed 's/ (.*)$//'
    done
    for summary in "$PHASE_DIR"/remediation/P*-*-round/*-SUMMARY.md; do
      [ -f "$summary" ] || continue
      sed -n '/^## Files Modified/,/^## /p' "$summary" 2>/dev/null | grep '^- ' | sed 's/^- //' | sed 's/ (.*)$//'
    done
  } | sort -u | grep -v '^$'
  exit 0
fi

# --- No sources available ---
exit 0
