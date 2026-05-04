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

not_contains_regex() {
  local haystack="$1"
  local regex="$2"

  ! contains_regex "$haystack" "$regex"
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

check_not_regex() {
  local label="$1"
  local haystack="$2"
  local regex="$3"

  if not_contains_regex "$haystack" "$regex"; then
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

SPAWN_ARG_ISOLATION_RE='(^|[^[:alnum:]_])"?isolation"?([[:space:]]*[:=][[:space:]]*"?worktree"?|[[:space:]]+worktree)([^[:alnum:]_]|$)'
SPAWN_ARG_BACKGROUND_RE='(^|[^[:alnum:]_])"?run_in_background"?([[:space:]]*[:=][[:space:]]*"?(true|false)"?|[[:space:]]+(true|false))([^[:alnum:]_]|$)'
SPAWN_ARG_TEAM_NAME_RE='(^|[^[:alnum:]_])"?team_name"?([[:space:]]*[:=]|[[:space:]]+"?[A-Za-z0-9_.-]+)([^[:alnum:]_.-]|$)'
SPAWN_ARG_NAME_RE='(^|[^[:alnum:]_])"?name"?([[:space:]]*[:=]|[[:space:]]+"?[A-Za-z0-9_.-]+)([^[:alnum:]_.-]|$)'

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
check_contains "spawn contract uses TodoWrite as sole stage progress tracker" "$UAT_BLOCK" 'TodoWrite is the only progress tracker for these stages'
check_contains "spawn contract distinguishes work-unit delegation from stage tracking" "$UAT_BLOCK" 'TaskCreate/Agent is allowed only for real Scout/Lead/Dev work-unit delegation inside the current stage'
check_contains "spawn contract requires plain sequential subagent calls" "$UAT_BLOCK" 'UAT remediation spawns are plain sequential subagent calls'
check_contains "spawn contract bans team/background/isolation metadata" "$UAT_BLOCK" 'Do not pass team metadata (`team_name`), per-agent names (`name`), `run_in_background`, or the `isolation` parameter'
check_contains "spawn contract explains unreliable worktree isolation" "$UAT_BLOCK" 'Claude Code worktree isolation is not reliable for this path'
check_contains "round metadata prohibition includes summary_path" "$UAT_BLOCK" 'round_dir`, `research_path`, `plan_path`, and `summary_path`'
check_contains "failed artifact validation blocks state advance" "$UAT_BLOCK" 'STOP without advancing state'
check_contains "UAT no-tool circuit breaker is documented" "$UAT_BLOCK" 'Subagent no-tool circuit breaker'
check_contains "UAT no-tool breaker names unavailable tool signals" "$UAT_BLOCK" 'tools, Bash, filesystem, edits, or API-session access are unavailable'
check_contains "UAT no-tool breaker stops without advancing stage" "$UAT_BLOCK" 'STOP without advancing `.uat-remediation-stage`'
check_contains "UAT no-tool breaker avoids same-prompt retry" "$UAT_BLOCK" 'do not retry the same prompt'
check_contains "UAT research site applies no-tool breaker before validation" "$UAT_BLOCK" 'If Scout returns a no-tool/tool-provisioning failure'
check_contains "UAT plan site applies no-tool breaker before validation" "$UAT_BLOCK" 'If Lead returns a no-tool/tool-provisioning failure'
check_contains "UAT execute site applies no-tool breaker before next Dev" "$UAT_BLOCK" 'If Dev returns a no-tool/tool-provisioning failure for the task'
check_regex "research stage validates exact artifact" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh research "\{round_dir\}/R\{RR\}-RESEARCH\.md"'
check_regex "plan stage validates existing plan_path" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh plan "\{plan_path\}"'
check_regex "plan stage validates exact generated plan" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh plan "\{round_dir\}/R\{RR\}-PLAN\.md"'
check_regex "execute stage validates summary_path" "$UAT_BLOCK" 'validate-uat-remediation-artifact\.sh summary "\{summary_path\}"'
check_contains "Dev writes to summary_path" "$UAT_BLOCK" 'Create {summary_path}'
check_contains "Dev appends to summary_path" "$UAT_BLOCK" 'Append your ## Task {N}: {name} section to {summary_path}'
check_not_contains "UAT block no longer relies on project-root workaround" "$UAT_BLOCK" 'Do NOT create git worktrees. Work in the project root directory.'
check_not_regex "UAT block does not include isolation argument syntax" "$UAT_BLOCK" "$SPAWN_ARG_ISOLATION_RE"
check_not_regex "UAT block does not include background argument syntax" "$UAT_BLOCK" "$SPAWN_ARG_BACKGROUND_RE"
check_not_regex "UAT block does not include team_name argument syntax" "$UAT_BLOCK" "$SPAWN_ARG_TEAM_NAME_RE"
check_not_regex "UAT block does not include per-agent name argument syntax" "$UAT_BLOCK" "$SPAWN_ARG_NAME_RE"
check_regex "spawn argument matcher catches isolation equals syntax" 'Agent isolation=worktree' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches isolation JSON syntax" 'Agent "isolation": "worktree"' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches run_in_background equals syntax" 'Agent run_in_background=true' "$SPAWN_ARG_BACKGROUND_RE"
check_regex "spawn argument matcher catches team_name bare syntax" 'Agent team_name vbw-phase-03' "$SPAWN_ARG_TEAM_NAME_RE"
check_regex "spawn argument matcher catches per-agent name bare syntax" 'Agent name dev-1' "$SPAWN_ARG_NAME_RE"
check_not_regex "per-agent name matcher ignores filename keys" 'filename: R01-PLAN.md' "$SPAWN_ARG_NAME_RE"
check_not_regex "per-agent name matcher ignores team_name keys" 'team_name: vbw-phase-03' "$SPAWN_ARG_NAME_RE"
check_not_regex "isolation matcher ignores benign prose" 'Spawn one Dev with no isolation parameter.' "$SPAWN_ARG_ISOLATION_RE"
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
