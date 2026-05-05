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

check_before() {
  local label="$1"
  local haystack="$2"
  local before="$3"
  local after="$4"
  local before_line after_line

  before_line=$(grep -nF -- "$before" <<< "$haystack" | head -n 1 | cut -d: -f1 || true)
  after_line=$(grep -nF -- "$after" <<< "$haystack" | head -n 1 | cut -d: -f1 || true)

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_literal_before_regex() {
  local label="$1"
  local haystack="$2"
  local before="$3"
  local after_regex="$4"
  local before_line after_line

  before_line=$(grep -nF -- "$before" <<< "$haystack" | head -n 1 | cut -d: -f1 || true)
  after_line=$(grep -nE -- "$after_regex" <<< "$haystack" | head -n 1 | cut -d: -f1 || true)

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

extract_uat_subsection() {
  local heading="$1"

  awk -v heading="$heading" '
    /^### Mode: UAT Remediation[[:space:]]*$/ { in_uat = 1 }
    /^### Mode: Milestone UAT Recovery[[:space:]]*$/ { in_uat = 0; in_section = 0 }
    in_uat && $0 ~ ("^#### " heading "[[:space:]]*$") { in_section = 1 }
    in_uat && in_section && /^#### / && $0 !~ ("^#### " heading "[[:space:]]*$") { in_section = 0 }
    in_uat && in_section { print }
  ' "$VIBE_FILE"
}

UAT_BLOCK=$(awk '
  /^### Mode: UAT Remediation[[:space:]]*$/ { in_block = 1 }
  /^### Mode: Milestone UAT Recovery[[:space:]]*$/ { in_block = 0 }
  in_block { print }
' "$VIBE_FILE")

FIX_BLOCK=$(awk '
  /^### Mode: UAT Remediation[[:space:]]*$/ { in_uat = 1 }
  /^### Mode: Milestone UAT Recovery[[:space:]]*$/ { in_uat = 0; in_fix = 0 }
  in_uat && /^#### fix[[:space:]]*$/ { in_fix = 1 }
  in_uat && /^### Fallback remediation summary[[:space:]]*$/ { in_fix = 0 }
  in_uat && in_fix { print }
' "$VIBE_FILE")

UAT_RESEARCH_BLOCK=$(extract_uat_subsection research)
UAT_PLAN_BLOCK=$(extract_uat_subsection plan)
UAT_EXECUTE_BLOCK=$(extract_uat_subsection execute)

SPAWN_ARG_ISOLATION_RE='(^|[^[:alnum:]_])"?isolation"?([[:space:]]*[:=][[:space:]]*"?[^"[:space:]]+"?|[[:space:]]+(worktree|"?\{[A-Za-z0-9_:-]+\}"?|"?\$[A-Za-z_][A-Za-z0-9_]*"?|"?\$\{[A-Za-z_][A-Za-z0-9_]*\}"?))([^[:alnum:]_]|$)'
SPAWN_ARG_BACKGROUND_RE='(^|[^[:alnum:]_])"?run_in_background"?([[:space:]]*[:=][[:space:]]*"?[^"[:space:]]+"?|[[:space:]]+(true|false|"?\{[A-Za-z0-9_:-]+\}"?|"?\$[A-Za-z_][A-Za-z0-9_]*"?|"?\$\{[A-Za-z_][A-Za-z0-9_]*\}"?))([^[:alnum:]_]|$)'
SPAWN_ARG_TEAM_NAME_RE='(^|[^[:alnum:]_])"?team_name"?([[:space:]]*[:=]|[[:space:]]+"?[A-Za-z0-9_.-]+)([^[:alnum:]_.-]|$)'
SPAWN_ARG_NAME_RE='(^|[^[:alnum:]_])"?name"?([[:space:]]*[:=]|[[:space:]]+"?[A-Za-z0-9_.-]+)([^[:alnum:]_.-]|$)'
SPAWN_ARG_CWD_RE='(^|[^[:alnum:]_])"?(cwd|working_dir|workingDirectory|workdir)"?([[:space:]]*[:=][[:space:]]*"?([^"[:space:]]+|\{[A-Za-z0-9_:-]+\}|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})"?|[[:space:]]+"?([./~][^"[:space:]]*|[[:alnum:]_-]+/[^"[:space:]]*|\{[A-Za-z0-9_:-]+\}|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})"?)'

if [ -z "$UAT_BLOCK" ]; then
  fail "vibe.md exposes a UAT Remediation block"
else
  pass "vibe.md exposes a UAT Remediation block"
fi

if [ -z "$FIX_BLOCK" ]; then
  fail "vibe.md exposes a UAT Remediation fix block"
else
  pass "vibe.md exposes a UAT Remediation fix block"
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
check_contains "spawn contract bans team/background/isolation/cwd metadata" "$UAT_BLOCK" 'Do not pass team metadata (`team_name`), per-agent names (`name`), `run_in_background`, `isolation`, or worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`)'
check_contains "spawn contract explains unreliable worktree isolation" "$UAT_BLOCK" 'Claude Code worktree isolation and spawn cwd handoffs are not reliable for this path'
check_contains "spawn contract explains unreliable cwd handoffs" "$UAT_BLOCK" 'spawn cwd handoffs are not reliable for this path'
check_contains "round metadata prohibition includes summary_path" "$UAT_BLOCK" 'round_dir`, `research_path`, `plan_path`, and `summary_path`'
check_contains "failed artifact validation blocks state advance" "$UAT_BLOCK" 'STOP without advancing state'
check_contains "UAT no-tool circuit breaker is documented" "$UAT_BLOCK" 'Subagent no-tool circuit breaker'
check_contains "UAT no-tool breaker names unavailable tool signals" "$UAT_BLOCK" 'tools, shell/Bash, filesystem, edits, or API-session access are unavailable'
check_not_contains "UAT no-tool breaker avoids Bash-only wording" "$UAT_BLOCK" 'tools, Bash, filesystem, edits, or API-session access are unavailable'
check_contains "UAT no-tool breaker stops without advancing stage" "$UAT_BLOCK" 'STOP without advancing `.uat-remediation-stage`'
check_contains "UAT no-tool breaker avoids same-prompt retry" "$UAT_BLOCK" 'do not retry the same prompt'
check_contains "UAT research site applies no-tool breaker before validation" "$UAT_BLOCK" 'If Scout returns a no-tool/tool-provisioning failure'
check_contains "UAT plan site applies no-tool breaker before validation" "$UAT_BLOCK" 'If Lead returns a no-tool/tool-provisioning failure'
check_contains "UAT execute site applies no-tool breaker before next Dev" "$UAT_BLOCK" 'If Dev returns a no-tool/tool-provisioning failure for the task'
check_literal_before_regex "UAT research no-tool guard appears before research validation" "$UAT_RESEARCH_BLOCK" 'If Scout returns a no-tool/tool-provisioning failure' 'validate-uat-remediation-artifact\.sh research "\{round_dir\}/R\{RR\}-RESEARCH\.md"'
check_before "UAT research no-tool guard appears before state advance" "$UAT_RESEARCH_BLOCK" 'If Scout returns a no-tool/tool-provisioning failure' 'uat-remediation-state.sh advance "$PHASE_DIR"'
check_literal_before_regex "UAT plan no-tool guard appears before plan validation" "$UAT_PLAN_BLOCK" 'If Lead returns a no-tool/tool-provisioning failure' 'validate-uat-remediation-artifact\.sh plan "\{round_dir\}/R\{RR\}-PLAN\.md"'
check_before "UAT plan no-tool guard appears before state advance" "$UAT_PLAN_BLOCK" 'If Lead returns a no-tool/tool-provisioning failure' 'uat-remediation-state.sh advance "$PHASE_DIR"'
check_before "UAT execute no-tool guard appears before frontmatter finalization" "$UAT_EXECUTE_BLOCK" 'If Dev returns a no-tool/tool-provisioning failure for the task' '**Frontmatter finalization:**'
check_literal_before_regex "UAT execute no-tool guard appears before summary validation" "$UAT_EXECUTE_BLOCK" 'If Dev returns a no-tool/tool-provisioning failure for the task' 'validate-uat-remediation-artifact\.sh summary'
check_before "UAT execute no-tool guard appears before state advance" "$UAT_EXECUTE_BLOCK" 'If Dev returns a no-tool/tool-provisioning failure for the task' 'uat-remediation-state.sh advance "$PHASE_DIR"'
check_contains "UAT fix site applies no-tool breaker" "$FIX_BLOCK" 'If the quick-fix Dev return reports that tools, shell/Bash, filesystem, edits, or API-session access are unavailable'
check_contains "UAT fix no-tool breaker stops without advancing stage" "$FIX_BLOCK" 'STOP without advancing `.uat-remediation-stage`'
check_contains "UAT fix no-tool breaker avoids same-prompt retry" "$FIX_BLOCK" 'do not retry the same prompt'
check_contains "UAT fix no-tool breaker blocks re-verification" "$FIX_BLOCK" 'do not enter re-verification'
check_before "UAT fix no-tool guard appears before state advance" "$FIX_BLOCK" 'If the quick-fix Dev return reports that tools, shell/Bash, filesystem, edits, or API-session access are unavailable' 'uat-remediation-state.sh advance "$PHASE_DIR"'
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
check_not_regex "UAT block does not include worktree cwd argument syntax" "$UAT_BLOCK" "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches isolation equals syntax" 'Agent isolation=worktree' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches isolation JSON syntax" 'Agent "isolation": "worktree"' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches isolation placeholder syntax" 'Agent isolation="{mode}"' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches isolation braced variable equals syntax" 'Agent isolation=${MODE}' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches isolation braced variable bare syntax" 'Agent isolation ${MODE}' "$SPAWN_ARG_ISOLATION_RE"
check_regex "spawn argument matcher catches run_in_background equals syntax" 'Agent run_in_background=true' "$SPAWN_ARG_BACKGROUND_RE"
check_regex "spawn argument matcher catches run_in_background variable syntax" 'Agent run_in_background="$FLAG"' "$SPAWN_ARG_BACKGROUND_RE"
check_regex "spawn argument matcher catches run_in_background braced variable equals syntax" 'Agent run_in_background=${FLAG}' "$SPAWN_ARG_BACKGROUND_RE"
check_regex "spawn argument matcher catches run_in_background braced variable bare syntax" 'Agent run_in_background ${FLAG}' "$SPAWN_ARG_BACKGROUND_RE"
check_regex "spawn argument matcher catches team_name bare syntax" 'Agent team_name vbw-phase-03' "$SPAWN_ARG_TEAM_NAME_RE"
check_regex "spawn argument matcher catches per-agent name bare syntax" 'Agent name dev-1' "$SPAWN_ARG_NAME_RE"
check_regex "spawn argument matcher catches generic cwd syntax" 'Agent cwd=/repo' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches cwd braced variable equals syntax" 'Agent cwd=${PHASE_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches cwd braced variable bare syntax" 'Agent cwd ${PHASE_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches generic working_dir syntax" 'Agent "working_dir": "/repo"' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches working_dir braced variable syntax" 'Agent working_dir=${ROUND_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches generic workingDirectory syntax" 'Agent workingDirectory /repo' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workingDirectory braced variable syntax" 'Agent workingDirectory ${ROUND_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches generic workdir syntax" 'Agent workdir ./tmp' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workdir braced variable equals syntax" 'Agent workdir=${PHASE_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workdir braced variable bare syntax" 'Agent workdir ${PHASE_DIR}' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches cwd placeholder syntax" 'Agent cwd="{round_dir}"' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches working_dir placeholder syntax" 'Agent working_dir="{summary_path}"' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workdir variable syntax" 'Agent workdir="$PHASE_DIR"' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches cwd sidechain syntax" 'Agent cwd=.claude/worktrees/agent-1' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches working_dir vbw-worktree syntax" 'Agent "working_dir": ".vbw-worktrees/dev-01"' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workingDirectory sidechain syntax" 'Agent workingDirectory=/repo/.claude/worktrees/agent-1' "$SPAWN_ARG_CWD_RE"
check_regex "spawn argument matcher catches workdir vbw-worktree syntax" 'Agent workdir .vbw-worktrees/dev-01' "$SPAWN_ARG_CWD_RE"
check_not_regex "per-agent name matcher ignores filename keys" 'filename: R01-PLAN.md' "$SPAWN_ARG_NAME_RE"
check_not_regex "per-agent name matcher ignores team_name keys" 'team_name: vbw-phase-03' "$SPAWN_ARG_NAME_RE"
check_not_regex "isolation matcher ignores benign prose" 'Spawn one Dev with no isolation parameter.' "$SPAWN_ARG_ISOLATION_RE"
check_not_regex "cwd matcher ignores field-list prose" 'worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`)' "$SPAWN_ARG_CWD_RE"
check_not_regex "cwd matcher ignores generic prohibition prose" 'Do not pass cwd fields.' "$SPAWN_ARG_CWD_RE"
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
