#!/usr/bin/env bash
set -euo pipefail

# verify-pipefail-safety.sh — Focused guard against early-closing verifier pipelines
#
# Related: #535

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

assert_no_match() {
  local rel_path="$1"
  local pattern="$2"
  local label="$3"
  local file="$ROOT/$rel_path"
  local match=""
  local grep_status=0

  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    fail "$label (target missing or unreadable: $rel_path)"
    return
  fi

  if match="$(grep -nE "$pattern" "$file" 2>/dev/null)"; then
    grep_status=0
  else
    grep_status=$?
  fi

  if [ "$grep_status" -eq 1 ]; then
    pass "$label"
    return
  fi

  if [ "$grep_status" -ne 0 ]; then
    fail "$label (grep error on: $rel_path)"
    return
  fi

  local first_line="${match%%$'\n'*}"
  fail "$label (found: $first_line)"
}

assert_no_quiet_grep_pipe() {
  local rel_path="$1"
  local producer_pattern="$2"
  local label="$3"
  local file="$ROOT/$rel_path"
  local match=""
  local awk_status=0
  local first_line=""

  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    fail "$label (target missing or unreadable: $rel_path)"
    return
  fi

  if match="$(awk -v producer="$producer_pattern" '
    function has_quiet_grep(line) {
      return line ~ /(^|[^|])[|][[:space:]]*grep([[:space:]]|$)/ \
        && (line ~ /[[:space:]]--(quiet|silent)([[:space:]]|$)/ \
          || line ~ /[[:space:]]-[^[:space:]]*q[^[:space:]]*([[:space:]]|$)/)
    }

    $0 ~ producer && has_quiet_grep($0) {
      printf "%d:%s\n", NR, $0
      exit
    }
  ' "$file" 2>/dev/null)"; then
    awk_status=0
  else
    awk_status=$?
  fi

  if [ "$awk_status" -ne 0 ]; then
    fail "$label (awk scan error on: $rel_path)"
    return
  fi

  if [ -z "$match" ]; then
    pass "$label"
    return
  fi

  first_line="${match%%$'\n'*}"
  fail "$label (found: $first_line)"
}

echo "=== Pipefail safety verification ==="

assert_no_quiet_grep_pipe \
  "testing/verify-commands-contract.sh" \
  'printf .*' \
  "commands-contract avoids printf-to-grep early-close pipelines"

assert_no_match \
  "testing/verify-commands-contract.sh" \
  'printf .*[[:space:]][|][[:space:]]*awk .*(exit|print NR)' \
  "commands-contract avoids printf-to-awk early-exit lookups"

assert_no_quiet_grep_pipe \
  "testing/verify-commands-contract.sh" \
  'awk .*' \
  "commands-contract avoids awk-to-grep early-close pipelines"

assert_no_match \
  "testing/verify-commands-contract.sh" \
  'printf .*[[:space:]][|][[:space:]]*sed .*[[:space:]][|][[:space:]]*head([[:space:]]+(-n[[:space:]]*1|-[[:space:]]*1))' \
  "commands-contract avoids printf-to-sed-to-head extraction pipelines"

assert_no_quiet_grep_pipe \
  "testing/verify-commands-contract.sh" \
  'sed .*' \
  "commands-contract avoids sed-to-grep early-close pipelines"

assert_no_quiet_grep_pipe \
  "testing/verify-commands-contract.sh" \
  'grep .*' \
  "commands-contract avoids grep-to-grep early-close pipelines"

assert_no_quiet_grep_pipe \
  "testing/verify-debug-session-contract.sh" \
  'printf .*' \
  "debug-session-contract avoids printf-to-grep early-close pipelines"

assert_no_match \
  "testing/verify-debug-session-contract.sh" \
  'printf .*[[:space:]][|][[:space:]]*awk .*(exit|print NR)' \
  "debug-session-contract avoids printf-to-awk early-exit lookups"

assert_no_quiet_grep_pipe \
  "testing/verify-debug-session-contract.sh" \
  'awk .*' \
  "debug-session-contract avoids awk-to-grep early-close pipelines"

assert_no_quiet_grep_pipe \
  "testing/verify-debug-session-contract.sh" \
  'sed .*' \
  "debug-session-contract avoids sed-to-grep early-close pipelines"

assert_no_quiet_grep_pipe \
  "testing/verify-debug-session-contract.sh" \
  'grep .*' \
  "debug-session-contract avoids grep-to-grep early-close pipelines"

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "Pipefail safety checks passed."
