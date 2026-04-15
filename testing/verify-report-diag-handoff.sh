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

# Extract step 1 code block (first ```bash block in the body, before any Method header)
step1_block=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method/ { exit }
  /```bash/ { in_code=1; next }
  in_code && /^[[:space:]]*```[[:space:]]*$/ { exit }
  in_code { print }
')

echo ""
echo "--- Step 1: diagnostic persistence ---"

if printf '%s\n' "$step1_block" | grep -qF 'tee "$DIAG_FILE"'; then
  pass "step 1: contains tee \"\$DIAG_FILE\" for diagnostic persistence"
else
  fail "step 1: missing tee \"\$DIAG_FILE\" in step 1 code block — diagnostics must be persisted to temp file"
fi

# --- Check 2: Method 1 appends diagnostic content from temp file ---

# Extract the Method 1 bash code block. The block starts after "**Method 1"
# header and the first ```bash delimiter, ends at the matching ```.
# The code block may be indented (e.g. 4 spaces inside a markdown list).
method1_block=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method 1/ { in_method=1 }
  in_method && /```bash/ { in_code=1; next }
  in_method && in_code && /^[[:space:]]*```[[:space:]]*$/ { exit }
  in_code { print }
')

echo ""
echo "--- Method 1: temp-file append ---"

if printf '%s\n' "$method1_block" | grep -qF 'cat "$DIAG_FILE" >> "$ISSUE_BODY_FILE"'; then
  pass "method 1: contains cat \"\$DIAG_FILE\" >> \"\$ISSUE_BODY_FILE\" append pattern"
else
  fail "method 1: missing cat \"\$DIAG_FILE\" >> \"\$ISSUE_BODY_FILE\" in Method 1 code block"
fi

# --- Check 3: Method 1 cleanup is inside an if guard (success-only) ---

echo ""
echo "--- Method 1: success-only cleanup ---"

# Within method1_block, verify rm -f "$DIAG_FILE" is between
# "if gh issue create" and "fi".

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

if printf '%s\n' "$method2_section" | grep -qF 'cat "$DIAG_FILE"'; then
  pass "method 2: references cat \"\$DIAG_FILE\" for reading diagnostics"
else
  fail "method 2: missing cat \"\$DIAG_FILE\" — must read diagnostics from temp file"
fi

# Extract Method 4 section (from "Method 4" to end of body)
method4_section=$(printf '%s\n' "$report_body" | awk '
  /\*\*Method 4/ { found=1; next }
  found { print }
')

if printf '%s\n' "$method4_section" | grep -qF 'cat "$DIAG_FILE"'; then
  pass "method 4: references cat \"\$DIAG_FILE\" for reading diagnostics"
else
  fail "method 4: missing cat \"\$DIAG_FILE\" — must read diagnostics from temp file"
fi

# --- Check 5: DIAG_FILE path uses CLAUDE_SESSION_ID:-default ---

echo ""
echo "--- DIAG_FILE path: session-scoped ---"

# Verify the session-scoped path appears in the step 1 code block
if printf '%s\n' "$step1_block" | grep -qF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt'; then
  pass "DIAG_FILE path: step 1 code block uses session-scoped path"
else
  fail "DIAG_FILE path: step 1 code block missing /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
fi

# Verify the session-scoped path appears in the Method 1 code block
if printf '%s\n' "$method1_block" | grep -qF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt'; then
  pass "DIAG_FILE path: Method 1 code block uses session-scoped path"
else
  fail "DIAG_FILE path: Method 1 code block missing /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
fi

# Verify the session-scoped path appears in Method 2 section
if printf '%s\n' "$method2_section" | grep -qF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt'; then
  pass "DIAG_FILE path: Method 2 section uses session-scoped path"
else
  fail "DIAG_FILE path: Method 2 section missing /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
fi

# Verify the session-scoped path appears in Method 4 section
if printf '%s\n' "$method4_section" | grep -qF '/tmp/vbw-diag-report-${CLAUDE_SESSION_ID:-default}.txt'; then
  pass "DIAG_FILE path: Method 4 section uses session-scoped path"
else
  fail "DIAG_FILE path: Method 4 section missing /tmp/vbw-diag-report-\${CLAUDE_SESSION_ID:-default}.txt"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
