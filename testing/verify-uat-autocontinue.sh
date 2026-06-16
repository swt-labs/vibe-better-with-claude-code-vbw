#!/usr/bin/env bash
set -euo pipefail

# verify-uat-autocontinue.sh — Contract tests for UAT remediation auto-continuation
#
# Validates that the verify.md ↔ vibe.md signal flow for auto-continuing
# remediation rounds has the required structural elements.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0
VIBE_VERIFY_STEP4_BLOCK=$(sed -n '/4\. \*\*UAT Remediation Auto-Continuation:/,/### Mode: Add Phase/p' "$ROOT/commands/vibe.md")

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

# 5. vibe.md Step 4 routes auto-continuation through prepare-reverification
if echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'prepare-reverification.sh'; then
  pass "vibe.md Step 4 routes auto-continuation through prepare-reverification.sh"
else
  fail "vibe.md Step 4 missing prepare-reverification.sh transition"
fi

# 6. vibe.md Step 4 explains why prepare-reverification owns this transition
if echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'finalizes and validates the active UAT before state mutation' \
  && echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'direct .*needs-round.*not the transition path'; then
  pass "vibe.md Step 4 documents prepare-reverification transition ownership"
else
  fail "vibe.md Step 4 missing prepare-reverification transition rationale"
fi

# 7. defaults.json contains max_uat_remediation_rounds=false
if jq -e '.max_uat_remediation_rounds == false' "$ROOT/config/defaults.json" >/dev/null 2>&1; then
  pass "defaults.json contains max_uat_remediation_rounds=false"
else
  fail "defaults.json missing max_uat_remediation_rounds=false"
fi

# 8. vibe.md Verify Step 4 and verify.md both handle cap_reached explicitly
if echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q '_skipped=cap_reached' \
  && echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'Reached maximum UAT remediation rounds' \
  && echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'Do NOT re-enter remediation' \
  && grep -q 'skipped=cap_reached' "$ROOT/commands/verify.md"; then
  pass "vibe.md Step 4 and verify.md both handle cap_reached"
else
  fail "vibe.md Step 4 or verify.md missing cap_reached handling"
fi

# 9. verify.md standalone mode uses the shared helper before needs-round
if grep -Eq 'resolve-uat-remediation-round-limit\.sh"? --next-round-decision' "$ROOT/commands/verify.md"; then
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

# 11. vibe.md Step 4 does not directly call needs-round; prepare-reverification owns mutation
if echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'uat-remediation-state.sh needs-round'; then
  fail "vibe.md Step 4 must not directly call uat-remediation-state.sh needs-round"
else
  pass "vibe.md Step 4 avoids direct needs-round mutation"
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

# 14. vibe.md and verify.md fail-close on malformed transition helper output
# vibe.md Step 4 must stop when prepare-reverification fails or emits malformed output;
# verify.md standalone mode still stops on malformed cap-helper output.
if echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'prepare-reverification.*exits nonzero' \
  && echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'malformed' \
  && echo "$VIBE_VERIFY_STEP4_BLOCK" | grep -q 'STOP'; then
  pass "vibe.md Step 4 fail-closes on nonzero/malformed prepare output"
else
  fail "vibe.md Step 4 missing fail-close guard for nonzero/malformed prepare output"
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
