#!/usr/bin/env bash
# compile-fix-commit-context.sh — Produce compact QA/UAT context from fix marker.
#
# Reads .last-fix-commit marker and outputs structured context for
# QA agent consumption or UAT checkpoint generation.
#
# Usage:
#   compile-fix-commit-context.sh [planning-dir] [mode]
#
# Arguments:
#   planning-dir  — path to .vbw-planning (default: .vbw-planning)
#   mode          — qa or uat (default: qa)
#
# Output (stdout):
#   First line: fix_context=available or fix_context=empty
#   If available, followed by --- separator and markdown context block.
#
# Exit codes:
#   0 — always (non-blocking helper)

set -u

PLANNING_DIR="${1:-.vbw-planning}"
MODE="${2:-qa}"

marker_file="$PLANNING_DIR/.last-fix-commit"

# Check marker exists
if [ ! -f "$marker_file" ]; then
  echo "fix_context=empty"
  exit 0
fi

# Check staleness (24 hours = 86400 seconds); fail-closed on stat/date errors
marker_mtime=$(stat -c '%Y' "$marker_file" 2>/dev/null || stat -f '%m' "$marker_file" 2>/dev/null || echo 0)
now=$(date +%s 2>/dev/null || echo 0)

if [ "$marker_mtime" -le 0 ] || [ "$now" -le 0 ]; then
  echo "fix_context=empty"
  exit 0
fi

age=$(( now - marker_mtime ))
if [ "$age" -lt 0 ] || [ "$age" -gt 86400 ]; then
  echo "fix_context=empty"
  exit 0
fi

# Read marker fields
commit=""
message=""
timestamp=""
description=""
files=""
reading_files=false

while IFS= read -r line; do
  if [ "$reading_files" = true ]; then
    files="${files}${files:+
}${line}"
    continue
  fi
  case "$line" in
    commit=*)     commit="${line#commit=}" ;;
    message=*)    message="${line#message=}" ;;
    timestamp=*)  timestamp="${line#timestamp=}" ;;
    description=*) description="${line#description=}" ;;
    files=*)
      files="${line#files=}"
      reading_files=true
      ;;
  esac
done < "$marker_file"

# Validate minimum required fields
if [ -z "$commit" ]; then
  echo "fix_context=empty"
  exit 0
fi

# Get change summary from git if available
change_summary=""
if command -v git &>/dev/null; then
  change_summary=$(git show --stat --format='' "$commit" 2>/dev/null | tail -5) || true
fi

# Format mode title
if [ "$MODE" = "uat" ]; then
  title="Fix Commit UAT Context"
else
  title="Fix Commit QA Context"
fi

# Build file list
file_list=""
if [ -n "$files" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && file_list="${file_list}
- ${f}"
  done <<< "$files"
fi

# Output context
echo "fix_context=available"
echo "---"
echo "## ${title}"
echo ""
echo "**Commit:** ${commit} — ${message}"
if [ -n "$description" ] && [ "$description" != "$message" ]; then
  echo "**Description:** ${description}"
fi
if [ -n "$timestamp" ]; then
  echo "**Timestamp:** ${timestamp}"
fi
if [ -n "$file_list" ]; then
  echo ""
  echo "**Files changed:**${file_list}"
fi
if [ -n "$change_summary" ]; then
  echo ""
  echo "**Change summary:**"
  echo '```'
  echo "$change_summary"
  echo '```'
fi

exit 0
