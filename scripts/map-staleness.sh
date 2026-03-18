#!/usr/bin/env bash
# Checks codebase map staleness by diffing META.md git_hash against HEAD.
# Output: key-value pairs on stdout. Exit 0 always.
set -euo pipefail

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

# Skip during compaction — post-compact.sh handles the compact SessionStart.
if [[ -f "$PLANNING_DIR/.compaction-marker" ]]; then
  _cm_ts=$(cat "$PLANNING_DIR/.compaction-marker" 2>/dev/null || echo 0)
  _cm_now=$(date +%s 2>/dev/null || echo 0)
  if (( _cm_now - _cm_ts < 60 )); then
    exit 0
  fi
fi

META="$PLANNING_DIR/codebase/META.md"

# Detect hook context: when stdout is not a terminal, we're called as a hook.
# In hook mode, only JSON goes to stdout; diagnostics go to stderr.
IS_HOOK=false
[ -t 1 ] || IS_HOOK=true

# Helper: emit diagnostic lines to the right destination
_diag() { if [[ "$IS_HOOK" == true ]]; then echo "$@" >&2; else echo "$@"; fi; }

# No map
if [[ ! -f "$META" ]]; then
  _diag "status: no_map"
  exit 0
fi

# No git
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  _diag "status: no_git"
  exit 0
fi

# Parse META.md
git_hash=$(grep '^git_hash:' "$META" | awk '{print $2}')
file_count=$(grep '^file_count:' "$META" | awk '{print $2}')
mapped_at=$(grep '^mapped_at:' "$META" | awk '{print $2}')

# Validate parsed values
if [[ -z "$git_hash" || -z "$file_count" || "$file_count" -eq 0 ]]; then
  _diag "status: no_map"
  exit 0
fi

# Verify the stored hash exists in this repo
if ! git cat-file -e "$git_hash" 2>/dev/null; then
  _diag "status: stale"
  _diag "staleness: 100%"
  _diag "changed: unknown"
  _diag "total: $file_count"
  _diag "since: $mapped_at"
  if [[ "$IS_HOOK" == true ]]; then
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Codebase map is stale (100% files changed). Run /vbw:map --incremental to refresh.\"}}"
  fi
  exit 0
fi

# Count changed files since map was created
changed=$(git diff --name-only "$git_hash"..HEAD 2>/dev/null | wc -l | tr -d ' ')

# Calculate staleness percentage
staleness=$(( changed * 100 / file_count ))

if [[ "$staleness" -gt 30 ]]; then
  status="stale"
else
  status="fresh"
fi

_diag "status: $status"
_diag "staleness: ${staleness}%"
_diag "changed: $changed"
_diag "total: $file_count"
_diag "since: $mapped_at"

# When called as a SessionStart hook, output hookSpecificOutput JSON only
if [[ "$status" == "stale" ]] && [[ "$IS_HOOK" == true ]]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Codebase map is stale (${staleness}% files changed). Run /vbw:map --incremental to refresh.\"}}"
fi
