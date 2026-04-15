#!/usr/bin/env bash
set -euo pipefail

# verify-report-diag-handoff.sh — Verify the temp-file diagnostic handoff
# pattern in commands/report.md.
#
# Guards against structural drift in the DIAG_FILE temp-file flow introduced
# in #341. Validates that step 1 persists diagnostics, Method 1 appends from
# the temp file with success-only cleanup, Methods 2/4 read from the temp
# file, and the path uses the session-scoped fallback.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="$ROOT/commands/report.md"

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

# Extract body below frontmatter
report_body=$(awk '/^---$/{d++; next} d>=2' "$REPORT")

echo "=== Report Diagnostic Handoff Contract Verification ==="

# --- Check 1: Step 1 code block references tee "$DIAG_FILE" ---

echo ""
echo "--- Step 1: diagnostic persistence ---"

if printf '%s\n' "$report_body" | grep -qF 'tee "$DIAG_FILE"'; then
  pass "step 1: contains tee \"\$DIAG_FILE\" for diagnostic persistence"
else
  fail "step 1: missing tee \"\$DIAG_FILE\" — diagnostics must be persisted to temp file"
fi

# --- Check 2: Method 1 appends diagnostic content from temp file ---

echo ""
echo "--- Method 1: temp-file append ---"

if printf '%s\n' "$report_body" | grep -qF 'cat "$DIAG_FILE" >> "$ISSUE_BODY_FILE"'; then
  pass "method 1: contains cat \"\$DIAG_FILE\" >> \"\$ISSUE_BODY_FILE\" append pattern"
else
  fail "method 1: missing cat \"\$DIAG_FILE\" >> \"\$ISSUE_BODY_FILE\" — diagnostics must be appended from temp file"
fi

# --- Check 3: Method 1 cleanup is inside an if guard (success-only) ---

echo ""
echo "--- Method 1: success-only cleanup ---"

# Extract the Method 1 bash code block. The block starts after "Method 1"
# header and the first ```bash delimiter, ends at the matching ```.
# The code block may be indented (e.g. 4 spaces inside a markdown list).
# Within that block, verify rm -f "$DIAG_FILE" is between
# "if gh issue create" and "fi".
method1_block=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method 1/ { in_method=1 }
  in_method && /```bash/ { in_code=1; next }
  in_method && in_code && /^[[:space:]]*```[[:space:]]*$/ { exit }
  in_code { print }
')

# Verify the if-guard structure: "if gh issue create" ... "rm -f "$DIAG_FILE"" ... "fi"
if_line=""
rm_line=""
fi_line=""
lineno=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  case "$line" in
    *'if gh issue create'*) if_line=$lineno ;;
    *'rm -f "$DIAG_FILE"'*) rm_line=$lineno ;;
  esac
  # Match standalone fi (possibly with leading whitespace)
  if printf '%s' "$line" | grep -qxE '[[:space:]]*fi[[:space:]]*'; then
    if [ -n "$if_line" ] && [ -n "$rm_line" ]; then
      fi_line=$lineno
      break
    fi
  fi
done < <(printf '%s\n' "$method1_block")

if [ -n "$if_line" ] && [ -n "$rm_line" ] && [ -n "$fi_line" ] &&
   [ "$if_line" -lt "$rm_line" ] && [ "$rm_line" -lt "$fi_line" ]; then
  pass "method 1: rm -f \"\$DIAG_FILE\" is inside if-guard (lines $if_line < $rm_line < $fi_line)"
else
  fail "method 1: rm -f \"\$DIAG_FILE\" must be inside 'if gh issue create ... then ... fi' guard"
fi

# --- Check 4: Methods 2 and 4 reference $DIAG_FILE ---

echo ""
echo "--- Methods 2 and 4: temp-file references ---"

# Extract Method 2 section (between "Method 2" and "Method 3" headers)
method2_section=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method 2/ { found=1; next }
  /\*\*Method 3/ { if (found) exit }
  found { print }
')

if printf '%s\n' "$method2_section" | grep -qF 'DIAG_FILE'; then
  pass "method 2: references DIAG_FILE for reading diagnostics"
else
  fail "method 2: missing DIAG_FILE reference — must read diagnostics from temp file"
fi

# Extract Method 4 section (from "Method 4" to end of body)
method4_section=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method 4/ { found=1; next }
  found { print }
')

if printf '%s\n' "$method4_section" | grep -qF 'DIAG_FILE'; then
  pass "method 4: references DIAG_FILE for reading diagnostics"
else
  fail "method 4: missing DIAG_FILE reference — must read diagnostics from temp file"
fi

# --- Check 5: DIAG_FILE path uses CLAUDE_SESSION_ID:-default ---

echo ""
echo "--- DIAG_FILE path: session-scoped ---"

if printf '%s\n' "$report_body" | grep -qF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt'; then
  pass "DIAG_FILE path: uses /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
else
  fail "DIAG_FILE path: missing session-scoped path pattern /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
fi

# Verify the pattern appears in both step 1 and Method 1 (at least 2 occurrences)
diag_path_count=$(printf '%s\n' "$report_body" | grep -cF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt' || true)
if [ "$diag_path_count" -ge 2 ]; then
  pass "DIAG_FILE path: appears $diag_path_count times (step 1 + methods)"
else
  fail "DIAG_FILE path: expected >= 2 occurrences, found $diag_path_count — must appear in step 1 and filing methods"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
