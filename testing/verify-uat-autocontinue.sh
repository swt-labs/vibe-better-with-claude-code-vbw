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

# 1. verify.md contains remediation_continue signal
if grep -q 'remediation_continue=true' "$ROOT/commands/verify.md"; then
  pass "verify.md contains remediation_continue signal"
else
  fail "verify.md missing remediation_continue signal"
fi

# 2. verify.md has orchestrated vs standalone mode split
if grep -q 'Orchestrated mode' "$ROOT/commands/verify.md" && grep -q 'Standalone mode' "$ROOT/commands/verify.md"; then
  pass "verify.md has orchestrated/standalone mode split"
else
  fail "verify.md missing orchestrated/standalone mode split"
fi

# 3. vibe.md contains cap-reached banner
if grep -q 'Reached maximum remediation rounds' "$ROOT/commands/vibe.md"; then
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

# 6. vibe.md reads max_remediation_rounds from config
if grep -q 'max_remediation_rounds' "$ROOT/commands/vibe.md"; then
  pass "vibe.md reads max_remediation_rounds from config"
else
  fail "vibe.md missing max_remediation_rounds config read"
fi

# 7. defaults.json contains max_remediation_rounds
if jq -e '.max_remediation_rounds' "$ROOT/config/defaults.json" >/dev/null 2>&1; then
  pass "defaults.json contains max_remediation_rounds"
else
  fail "defaults.json missing max_remediation_rounds"
fi

# 8. verify.md orchestrated mode does NOT invoke needs-round
# (needs-round is called by vibe.md after cap check, not by verify.md in orchestrated mode)
# Check that the orchestrated block doesn't contain a bash code block with needs-round
orchestrated_block=$(sed -n '/Orchestrated mode/,/Standalone mode/p' "$ROOT/commands/verify.md")
if echo "$orchestrated_block" | grep -q 'uat-remediation-state.sh needs-round'; then
  fail "verify.md orchestrated mode should NOT invoke needs-round (vibe.md handles it)"
else
  pass "verify.md orchestrated mode correctly defers needs-round to caller"
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
