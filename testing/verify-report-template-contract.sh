#!/usr/bin/env bash
set -euo pipefail

# verify-report-template-contract.sh — Verify /vbw:report template alignment,
# classification criteria, and label routing.
#
# Guards against structural drift between commands/report.md and the GitHub
# issue templates introduced in #340.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REPORT="$ROOT/commands/report.md"
BUG_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/bug_report.md"
FEATURE_TEMPLATE="$ROOT/.github/ISSUE_TEMPLATE/feature_request.md"

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

# --- Extract example blocks from report.md ---

# Bug example block: from <example> containing "Classification: bug" to </example>
bug_block=$(awk '
  /<example>/ { capture=1; buf=""; next }
  /<\/example>/ { if (capture && found) { print buf }; capture=0; found=0; next }
  capture { buf = buf "\n" $0; if (/Classification: bug/) found=1 }
' "$REPORT")

# Feature example block: from <example> containing "Classification: feature" to </example>
feature_block=$(awk '
  /<example>/ { capture=1; buf=""; next }
  /<\/example>/ { if (capture && found) { print buf }; capture=0; found=0; next }
  capture { buf = buf "\n" $0; if (/Classification: feature/) found=1 }
' "$REPORT")

echo "=== Report Template Contract Verification ==="

# --- Example tag structure ---

example_open=$(grep -c '<example>' "$REPORT" || true)
example_close=$(grep -c '</example>' "$REPORT" || true)

if [ "$example_open" -ge 2 ]; then
  pass "report: has >= 2 <example> tags ($example_open found)"
else
  fail "report: expected >= 2 <example> tags, found $example_open"
fi

if [ "$example_close" -ge 2 ]; then
  pass "report: has >= 2 </example> tags ($example_close found)"
else
  fail "report: expected >= 2 </example> tags, found $example_close"
fi

# --- Bug report section header alignment ---

echo ""
echo "--- Bug report template alignment ---"

while IFS= read -r header; do
  [ -z "$header" ] && continue
  if printf '%s' "$bug_block" | grep -qF "$header"; then
    pass "bug example: contains $header"
  else
    fail "bug example: missing $header from bug_report.md template"
  fi
done < <(grep -oE '\*\*[^*]+\*\*' "$BUG_TEMPLATE")

# --- Feature request section header alignment ---

echo ""
echo "--- Feature request template alignment ---"

while IFS= read -r header; do
  [ -z "$header" ] && continue
  if printf '%s' "$feature_block" | grep -qF "$header"; then
    pass "feature example: contains $header"
  else
    fail "feature example: missing $header from feature_request.md template"
  fi
done < <(grep -oE '\*\*[^*]+\*\*' "$FEATURE_TEMPLATE")

# --- Classification criteria presence ---

echo ""
echo "--- Classification criteria ---"

report_body=$(awk '/^---$/{d++; next} d>=2' "$REPORT")

if printf '%s\n' "$report_body" | grep -i 'bug' | grep -qiE 'broken|error|unexpected|crash|regression'; then
  pass "classification: bug criteria include behavioral keywords"
else
  fail "classification: bug criteria missing behavioral keywords (broken/error/unexpected/crash/regression)"
fi

if printf '%s\n' "$report_body" | grep -i 'feature' | grep -qiE 'missing|improvement|new capability|change'; then
  pass "classification: feature criteria include behavioral keywords"
else
  fail "classification: feature criteria missing behavioral keywords (missing/improvement/new capability/change)"
fi

# --- Label routing ---

echo ""
echo "--- Label routing ---"

if printf '%s\n' "$report_body" | grep -qE -- '--label bug|"bug"|\[\"bug\"\]|label.*bug'; then
  pass "label routing: bug label present"
else
  fail "label routing: missing bug label in filing methods"
fi

if printf '%s\n' "$report_body" | grep -qE -- '--label enhancement|"enhancement"|\[\"enhancement\"\]|label.*enhancement'; then
  pass "label routing: enhancement label present"
else
  fail "label routing: missing enhancement label in filing methods"
fi

# --- Template filename references in fallback URLs ---

if printf '%s\n' "$report_body" | grep -qF 'bug_report.md'; then
  pass "fallback: references bug_report.md template"
else
  fail "fallback: missing bug_report.md template reference"
fi

if printf '%s\n' "$report_body" | grep -qF 'feature_request.md'; then
  pass "fallback: references feature_request.md template reference"
else
  fail "fallback: missing feature_request.md template reference"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All report template contract checks passed."
exit 0
