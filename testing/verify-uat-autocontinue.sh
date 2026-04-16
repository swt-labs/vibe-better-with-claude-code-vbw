#!/usr/bin/env bash
set -euo pipefail

# verify-uat-autocontinue.sh — Contract tests for UAT remediation auto-continuation
#
# Validates that the verify.md ↔ vibe.md signal flow for auto-continuing
# remediation rounds has the required structural elements.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

# 1. verify.md contains remediation_continue signal with issues payload
if grep -q 'remediation_continue=true.*issues=' "$ROOT/commands/verify.md"; then
  pass "verify.md contains remediation_continue signal with issues payload"
else
  fail "verify.md missing remediation_continue=true issues={N} signal"
fi

# 2. verify.md has orchestrated vs standalone mode split
if grep -q 'Orchestrated mode' "$ROOT/commands/verify.md" && grep -q 'Standalone mode' "$ROOT/commands/verify.md"; then
  pass "verify.md has orchestrated/standalone mode split"
else
  fail "verify.md missing orchestrated/standalone mode split"
fi

# 3. vibe.md contains cap-reached banner
if grep -q 'Reached maximum UAT remediation rounds' "$ROOT/commands/vibe.md"; then
  pass "vibe.md contains cap-reached banner"
else
  fail "vibe.md missing cap-reached banner"
fi

# 4. vibe.md contains transition banner with issue count
if grep -q 'Re-verification found {N} issue' "$ROOT/commands/vibe.md"; then
  pass "vibe.md contains transition banner with issue count"
else
  fail "vibe.md missing transition banner with issue count"
fi

# 5. vibe.md calls needs-round in auto-continuation path
if grep -q 'uat-remediation-state.sh needs-round' "$ROOT/commands/vibe.md"; then
  pass "vibe.md calls needs-round in auto-continuation path"
else
  fail "vibe.md missing needs-round call in auto-continuation path"
fi

# 6. vibe.md resolves the UAT cap via shared helper-backed decision mode
if grep -q 'resolve-uat-remediation-round-limit.sh --next-round-decision' "$ROOT/commands/vibe.md" && grep -q 'max_uat_remediation_rounds' "$ROOT/commands/vibe.md"; then
  pass "vibe.md resolves the UAT remediation round cap via shared decision helper"
else
  fail "vibe.md missing shared helper-backed max_uat_remediation_rounds handling"
fi

# 7. defaults.json contains max_uat_remediation_rounds=false
if jq -e '.max_uat_remediation_rounds == false' "$ROOT/config/defaults.json" >/dev/null 2>&1; then
  pass "defaults.json contains max_uat_remediation_rounds=false"
else
  fail "defaults.json missing max_uat_remediation_rounds=false"
fi

# 8. vibe.md and verify.md both handle cap_reached explicitly
if grep -q 'skipped=cap_reached' "$ROOT/commands/vibe.md" && grep -q 'skipped=cap_reached' "$ROOT/commands/verify.md"; then
  pass "vibe.md and verify.md both handle cap_reached"
else
  fail "vibe.md or verify.md missing cap_reached handling"
fi

# 9. verify.md standalone mode uses the shared helper before needs-round
if grep -q 'resolve-uat-remediation-round-limit.sh --next-round-decision' "$ROOT/commands/verify.md"; then
  pass "verify.md standalone mode uses the shared cap decision helper"
else
  fail "verify.md standalone mode missing shared cap decision helper"
fi

# 10. verify.md orchestrated mode does NOT invoke needs-round
# (needs-round is called by vibe.md after cap check, not by verify.md in orchestrated mode)
# Check that the orchestrated block doesn't contain a bash code block with needs-round
orchestrated_block=$(sed -n '/Orchestrated mode/,/Standalone mode/p' "$ROOT/commands/verify.md")
if echo "$orchestrated_block" | grep -q 'uat-remediation-state.sh needs-round'; then
  fail "verify.md orchestrated mode should NOT invoke needs-round (vibe.md handles it)"
else
  pass "verify.md orchestrated mode correctly defers needs-round to caller"
fi

# 11. vibe.md Step 4: cap check (current-round) appears BEFORE needs-round call
# Structural ordering: the LLM must read the current round and check the cap
# before calling needs-round, which mutates state.
_cap_line=$(grep -n 'uat-remediation-state.sh current-round' "$ROOT/commands/vibe.md" | head -1 | cut -d: -f1)
_needs_line=$(grep -n 'uat-remediation-state.sh needs-round' "$ROOT/commands/vibe.md" | head -1 | cut -d: -f1)
if [ -n "$_cap_line" ] && [ -n "$_needs_line" ] && [ "$_cap_line" -lt "$_needs_line" ]; then
  pass "vibe.md: cap check (current-round) appears before needs-round call"
else
  fail "vibe.md: cap check must appear BEFORE needs-round call in Step 4 (cap@${_cap_line:-?} vs needs@${_needs_line:-?})"
fi

# 12. vibe.md documents the real prepare-reverification archived/skipped contract
if grep -q 'archived=kept|in-round-dir|<original-uat-basename>' "$ROOT/commands/vibe.md" \
  && grep -q 'skipped=already_archived|ready_for_verify|cap_reached' "$ROOT/commands/vibe.md"; then
  pass "vibe.md documents the real prepare-reverification archived/skipped contract"
else
  fail "vibe.md missing the real prepare-reverification archived/skipped contract"
fi

# 13. verify.md explicitly handles skipped=ready_for_verify and flat-layout archived basenames
if grep -q 'skipped=ready_for_verify' "$ROOT/commands/verify.md" \
  && grep -q 'archived=in-round-dir' "$ROOT/commands/verify.md" \
  && grep -q 'original phase-root UAT basename' "$ROOT/commands/verify.md"; then
  pass "verify.md explicitly handles skipped=ready_for_verify and flat-layout archived basenames"
else
  fail "verify.md missing skipped=ready_for_verify or flat-layout archived basename handling"
fi

# 14. vibe.md and verify.md fail-close on empty cap-check helper output
# Both command files must instruct the LLM to STOP (no state mutation) when
# _cap_reached or _cap_decision is empty — matching the fail-close hardening
# in phase-detect.sh and prepare-reverification.sh.
if grep -q '_cap_reached.*empty\|_cap_decision.*empty' "$ROOT/commands/vibe.md" \
  && grep -q 'no state mutation on error' "$ROOT/commands/vibe.md"; then
  pass "vibe.md fail-closes on empty/malformed cap-check helper output"
else
  fail "vibe.md missing fail-close guard for empty cap-check helper output"
fi
if grep -q '_cap_reached.*empty\|_cap_decision.*empty' "$ROOT/commands/verify.md" \
  && grep -q 'no state mutation on error' "$ROOT/commands/verify.md"; then
  pass "verify.md fail-closes on empty/malformed cap-check helper output"
else
  fail "verify.md missing fail-close guard for empty cap-check helper output"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All UAT auto-continuation contract checks passed."
exit 0
