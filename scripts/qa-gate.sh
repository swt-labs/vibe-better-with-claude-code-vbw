#!/bin/bash
set -u
# TeammateIdle hook: Verify teammate's work via structural completion checks
# Exit 2 = block (keep working), Exit 0 = allow idle
# Exit 0 on ANY error (fail-open: never block legitimate work)

# Only apply to VBW contexts
[ ! -d ".vbw-planning" ] && exit 0

# Source shared summary-status helpers
_QG_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_QG_SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$_QG_SCRIPT_DIR/summary-utils.sh"
else
  # Safe default: treat no summaries as complete when helpers unavailable
  count_complete_summaries() { echo "0"; }
fi

# Read stdin to consume task context
cat >/dev/null 2>&1 || exit 0

# Structural Check 1: SUMMARY.md completeness
# Count plans vs summaries — if a phase has more plans than summaries
# and recent commits exist, a summary is likely missing
SUMMARY_OK=false
PLANS_TOTAL=0
SUMMARIES_TOTAL=0

for phase_dir in .vbw-planning/phases/*/; do
  [ -d "$phase_dir" ] || continue
  PLANS=$(ls -1 "$phase_dir"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  SUMMARIES=$(count_complete_summaries "$phase_dir")
  PLANS_TOTAL=$(( PLANS_TOTAL + PLANS ))
  SUMMARIES_TOTAL=$(( SUMMARIES_TOTAL + SUMMARIES ))
done

# If all plans have summaries, or no plans exist, structural check passes
if [ "$PLANS_TOTAL" -eq 0 ] || [ "$SUMMARIES_TOTAL" -ge "$PLANS_TOTAL" ]; then
  SUMMARY_OK=true
fi

NOW=$(date +%s 2>/dev/null) || exit 0
# Configurable commit recency window (default: 2 hours)
TWO_HOURS=7200
if command -v jq &>/dev/null && [ -f ".vbw-planning/config.json" ]; then
  _window=$(jq -r '.qa_commit_window_seconds // 7200' .vbw-planning/config.json 2>/dev/null)
  [ "${_window:-0}" -gt 0 ] 2>/dev/null && TWO_HOURS="$_window"
fi

# Structural Check 2: Commit format
# Check if recent commits (last 10, within 2 hours) match conventional format
FORMAT_MATCH=false
RECENT_COMMITS=$(git log --oneline -10 --format="%ct %s" 2>/dev/null) || exit 0
[ -z "$RECENT_COMMITS" ] && exit 0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
  COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)

  if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - COMMIT_TS ))
    if [ "$AGE" -le "$TWO_HOURS" ]; then
      # Check for conventional commit format: type(XX-YY):
      if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore)\([0-9]{2}-[0-9]{2}\):'; then
        FORMAT_MATCH=true
        break
      fi
    fi
  fi
done <<< "$RECENT_COMMITS"

# Decision logic
if [ "$PLANS_TOTAL" -eq 0 ]; then
  exit 0  # No plans, nothing to verify
fi

if [ "$SUMMARY_OK" = true ]; then
  exit 0  # All summaries present
fi

# Plans exist with missing summaries.
# FORMAT_MATCH gives a 1-plan grace period (Dev actively working on next plan).
# 2+ missing summaries = accumulated gap, block even with good commits.
SUMMARY_GAP=$(( PLANS_TOTAL - SUMMARIES_TOTAL ))
if [ "$FORMAT_MATCH" = true ] && [ "$SUMMARY_GAP" -le 1 ]; then
  exit 0  # Active work, at most 1 summary behind — allow
fi

echo "QA gate: SUMMARY.md gap detected ($SUMMARIES_TOTAL summaries for $PLANS_TOTAL plans)" >&2
exit 2
