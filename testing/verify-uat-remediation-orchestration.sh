#!/usr/bin/env bash
set -euo pipefail

# verify-uat-remediation-orchestration.sh — Contract checks for UAT remediation orchestration.
#
# These checks protect the host-root artifact path contract used when Scout,
# Lead, and Dev agents run from Claude sidechain CWDs.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIBE_FILE="$ROOT/commands/vibe.md"
VALIDATOR="$ROOT/scripts/validate-uat-remediation-artifact.sh"

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

contains_literal() {
  local haystack="$1"
  local needle="$2"

  grep -Fq -- "$needle" <<< "$haystack"
}

contains_regex() {
  local haystack="$1"
  local regex="$2"

  grep -Eq -- "$regex" <<< "$haystack"
}

not_contains_literal() {
  local haystack="$1"
  local needle="$2"

  ! contains_literal "$haystack" "$needle"
}

check_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if contains_literal "$haystack" "$needle"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_regex() {
  local label="$1"
  local haystack="$2"
  local regex="$3"

  if contains_regex "$haystack" "$regex"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if not_contains_literal "$haystack" "$needle"; then
    pass "$label"
  else
    fail "$label"
  fi
}

UAT_BLOCK=$(awk '
  /^### Mode: UAT Remediation[[:space:]]*$/ { in_block = 1 }
  /^### Mode: Milestone UAT Recovery[[:space:]]*$/ { in_block = 0 }
  in_block { print }
' "$VIBE_FILE")

if [ -z "$UAT_BLOCK" ]; then
  fail "vibe.md exposes a UAT Remediation block"
else
  pass "vibe.md exposes a UAT Remediation block"
fi

if [ -f "$VALIDATOR" ]; then
  pass "artifact validator script exists"
else
  fail "artifact validator script missing"
fi

check_contains "state metadata documents summary_path" "$UAT_BLOCK" 'summary_path=<path>'
check_contains "metadata paths are host-repository absolute paths" "$UAT_BLOCK" 'absolute host-repository path'
check_contains "artifact contract names sidechain CWDs" "$UAT_BLOCK" '.claude/worktrees/agent-*'
check_contains "artifact contract passes exact paths to all agents" "$UAT_BLOCK" 'pass these exact paths to every Scout/Lead/Dev prompt'
check_contains "artifact contract validates legacy metadata paths directly" "$UAT_BLOCK" 'validate that exact metadata path directly instead of rewriting it to `round_dir` or searching for alternatives'
check_contains "round metadata prohibition includes summary_path" "$UAT_BLOCK" 'round_dir`, `research_path`, `plan_path`, and `summary_path`'
check_contains "failed artifact validation blocks state advance" "$UAT_BLOCK" 'STOP without advancing state'
check_regex "research stage validates exact artifact" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh research "\{round_dir\}/R\{RR\}-RESEARCH\.md"'
check_regex "plan stage validates existing plan_path" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh plan "\{plan_path\}"'
check_regex "plan stage validates exact generated plan" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh plan "\{round_dir\}/R\{RR\}-PLAN\.md"'
check_regex "execute stage validates summary_path" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh summary "\{summary_path\}"'
check_contains "Dev writes to summary_path" "$UAT_BLOCK" 'Create {summary_path}'
check_contains "Dev appends to summary_path" "$UAT_BLOCK" 'Append your ## Task {N}: {name} section to {summary_path}'
check_not_contains "UAT block no longer relies on project-root workaround" "$UAT_BLOCK" 'Do NOT create git worktrees. Work in the project root directory.'
check_not_contains "UAT block no longer uses broad skill preselection" "$UAT_BLOCK" 'select all materially helpful installed skills'
check_contains "Lead avoids implementation-heavy preselection" "$UAT_BLOCK" 'Do not preselect implementation-heavy skills'
check_contains "Dev uses task-specific skills" "$UAT_BLOCK" 'select the task-specific skills listed in the remediation plan'

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "==============================="
  echo "TOTAL: $PASS PASS, $FAIL FAIL"
  echo "==============================="
  exit 1
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="
echo "All UAT remediation orchestration contract checks passed."
exit 0
