#!/usr/bin/env bash
set -euo pipefail

# verify-statusline-429-backoff.sh — Contract tests for #249
# Verifies: 429 → ratelimited status, failure backoff (300s), DISABLE_NONESSENTIAL_TRAFFIC

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SL="$ROOT/scripts/vbw-statusline.sh"

PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL + 1)); }

# --- Test 1: 429 handled distinctly from generic failure ---
if grep -q 'HTTP_CODE.*=.*"429"' "$SL" && grep -q 'FETCH_OK="ratelimited"' "$SL"; then
  pass "429 maps to FETCH_OK=ratelimited (not fail)"
else
  fail "429 maps to FETCH_OK=ratelimited (not fail)"
fi

# --- Test 2: ratelimited state renders actionable message ---
if grep -q 'FETCH_OK.*=.*"ratelimited"' "$SL" && grep -q 'rate limited.*re-login' "$SL"; then
  pass "ratelimited state renders actionable re-login message"
else
  fail "ratelimited state renders actionable re-login message"
fi

# --- Test 3: backoff reads previous FETCH_OK from slow cache ---
if grep -q '_PREV_STATUS.*awk.*SLOW_CF' "$SL"; then
  pass "backoff reads previous status from slow cache"
else
  fail "backoff reads previous status from slow cache"
fi

# --- Test 4: backoff escalates TTL on fail or ratelimited (not notraffic — user-intentional) ---
if grep -q '_PREV_STATUS.*=.*"fail"\|_PREV_STATUS.*=.*"ratelimited"' "$SL" \
   && ! grep -q '_PREV_STATUS.*=.*"notraffic".*_SLOW_TTL' "$SL" \
   && grep -q '_SLOW_TTL=300' "$SL"; then
  pass "backoff escalates TTL to 300s on persistent failure/ratelimited only"
else
  fail "backoff escalates TTL to 300s on persistent failure/ratelimited only"
fi

# --- Test 5: default slow TTL is 60s ---
if grep -q '_SLOW_TTL=60' "$SL"; then
  pass "default slow cache TTL is 60s"
else
  fail "default slow cache TTL is 60s"
fi

# --- Test 6: CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC respected ---
if grep -q 'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' "$SL"; then
  pass "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is checked"
else
  fail "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC is checked"
fi

# --- Test 7: notraffic skips usage fetch entirely ---
if grep -q 'FETCH_OK="notraffic"' "$SL" && grep -q '"$FETCH_OK" = "notraffic"' "$SL"; then
  pass "notraffic status skips usage fetch"
else
  fail "notraffic status skips usage fetch"
fi

# --- Test 8: notraffic renders informational message ---
if grep -q 'nonessential traffic disabled' "$SL"; then
  pass "notraffic state renders informational message"
else
  fail "notraffic state renders informational message"
fi

# --- Test 9: ratelimited/fail retry message says 5m (not 60s) ---
if grep -q 'retry in 5m' "$SL" && ! grep -q 'retry in 60s' "$SL"; then
  pass "retry message says 5m (not 60s) for both fail and ratelimited"
else
  fail "retry message says 5m (not 60s) for both fail and ratelimited"
fi

# --- Test 10: notraffic guard covers version check curl (QA round 1 F1) ---
# The version check curl must be inside the else branch of the notraffic guard,
# so it's skipped when nonessential traffic is disabled.
# Verify: "notraffic guard" comment closing comes AFTER the REMOTE_VER curl line.
_NOTRAFFIC_LINE=$(grep -n 'end: notraffic guard' "$SL" | head -1 | cut -d: -f1)
_VERSION_CURL_LINE=$(grep -n 'raw.githubusercontent.com.*VERSION' "$SL" | head -1 | cut -d: -f1)
if [ -n "$_NOTRAFFIC_LINE" ] && [ -n "$_VERSION_CURL_LINE" ] \
   && [ "$_VERSION_CURL_LINE" -lt "$_NOTRAFFIC_LINE" ] 2>/dev/null; then
  pass "notraffic guard covers version check curl"
else
  fail "notraffic guard covers version check curl"
fi

# --- Test 11: notraffic guard covers token lookups (QA round 1 F3) ---
# Token Priority 1 (VBW_OAUTH_TOKEN) must be inside the else branch of notraffic guard.
_TOKEN_P1_LINE=$(grep -n 'VBW_OAUTH_TOKEN' "$SL" | head -1 | cut -d: -f1)
_NOTRAFFIC_ELSE_LINE=$(grep -n 'skip token lookup.*version check' "$SL" | head -1 | cut -d: -f1)
if [ -n "$_TOKEN_P1_LINE" ] && [ -n "$_NOTRAFFIC_ELSE_LINE" ] \
   && [ "$_TOKEN_P1_LINE" -gt "$_NOTRAFFIC_ELSE_LINE" ] 2>/dev/null; then
  pass "notraffic guard covers token lookups"
else
  fail "notraffic guard covers token lookups"
fi

# --- Test 12: notraffic flag bypasses backoff TTL via shared helper (#249 QA R3/R4) ---
# The helper must check both env var AND settings.json, and the pre-backoff
# block must call it (not just inline the env var check).
if grep -q '_resolve_notraffic' "$SL" \
   && grep -q '_NOTRAFFIC_ACTIVE.*_SLOW_TTL=60' "$SL" \
   && grep -q 'settings.json' "$SL"; then
  pass "notraffic helper resolves env var + settings.json before backoff"
else
  fail "notraffic helper resolves env var + settings.json before backoff"
fi

# --- Test 13: unknown FETCH_OK values get catch-all rendering (#249 QA R3 F3) ---
# The final else in the rendering chain must NOT assume API key;
# it should render a neutral fallback for unknown/corrupt values.
if grep -q 'Limits: unavailable' "$SL"; then
  pass "unknown FETCH_OK values render neutral catch-all"
else
  fail "unknown FETCH_OK values render neutral catch-all"
fi

# --- Test 14: noauth state explicitly handled before catch-all ---
if grep -q 'FETCH_OK.*=.*"noauth"' "$SL" && grep -q 'using API key' "$SL"; then
  pass "noauth state renders API-key message before catch-all"
else
  fail "noauth state renders API-key message before catch-all"
fi

echo ""
echo "TOTAL: $PASS PASS, $FAIL FAIL"
[ "$FAIL" -eq 0 ] || exit 1
