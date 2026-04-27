#!/usr/bin/env bash
set -euo pipefail

# verify-debug-session-contract.sh — Structural checks for the debug session lifecycle
#
# Validates:
# - DEBUG-SESSION.md template has required sections
# - debug-session-state.sh implements all documented commands
# - write-debug-session.sh implements all modes
# - compile-debug-session-context.sh implements all modes
# - debug.md has debug_session_routing section
# - qa.md has debug_session_qa section (hidden protocol file)
# - verify.md has debug_session_uat section (hidden protocol file)

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

contains_literal() {
  local haystack="$1"
  local needle="$2"

  [[ "$haystack" == *"$needle"* ]]
}

matches_ere() {
  local haystack="$1"
  local pattern="$2"

  grep -Eq -- "$pattern" <<< "$haystack"
}

first_matching_line_number() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    index($0, needle) && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

# — Template checks —

TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"

if [ -f "$TEMPLATE" ]; then
  pass "DEBUG-SESSION.md template exists"
else
  fail "DEBUG-SESSION.md template missing"
fi

for section in "## Issue" "## Source Todo" "## Investigation" "## Plan" "## Implementation" "## QA" "## UAT"; do
  if grep -q "^${section}" "$TEMPLATE" 2>/dev/null; then
    pass "template has section: $section"
  else
    fail "template missing section: $section"
  fi
done

for field in session_id title status created updated qa_round qa_last_result uat_round uat_last_result; do
  if grep -q "^${field}:" "$TEMPLATE" 2>/dev/null; then
    pass "template has frontmatter field: $field"
  else
    fail "template missing frontmatter field: $field"
  fi
done

# — State machine script checks —

STATE_SCRIPT="$ROOT/scripts/debug-session-state.sh"

if [ -f "$STATE_SCRIPT" ]; then
  pass "debug-session-state.sh exists"
else
  fail "debug-session-state.sh missing"
fi

for cmd in start start-with-source-todo start-with-selected-todo get get-or-latest resume set-status increment-qa increment-uat clear-active list; do
  if grep -q "\"$cmd\"\\|'$cmd'\\|${cmd})" "$STATE_SCRIPT" 2>/dev/null; then
    pass "state script handles command: $cmd"
  else
    fail "state script missing command: $cmd"
  fi
done

PRINT_METADATA_BLOCK="$(awk '/print_session_metadata\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)"
if grep -Fq "printf 'session_status=%q\\n'" <<< "$PRINT_METADATA_BLOCK"; then
  pass "debug-session-state.sh metadata-read contract exports session_status"
else
  fail "debug-session-state.sh metadata-read contract missing session_status export"
fi

if grep -Fq "printf 'status=%q\\n'" <<< "$PRINT_METADATA_BLOCK"; then
  fail "debug-session-state.sh metadata-read contract still exports bare status"
else
  pass "debug-session-state.sh metadata-read contract no longer exports bare status"
fi

if contains_literal "$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)" 'echo "status=$STATUS"'; then
  pass "debug-session-state.sh set-status keeps status output contract"
else
  fail "debug-session-state.sh set-status output contract drifted from status=..."
fi

if grep -Eq 'qa_last_result:[[:space:]]+pending \| skipped_no_fix_required \| pass \| fail' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh documents skipped_no_fix_required in qa_last_result vocabulary"
else
  fail "debug-session-state.sh missing skipped_no_fix_required in qa_last_result vocabulary"
fi

if grep -Eq 'uat_last_result:[[:space:]]+pending \| skipped_no_fix_required \| pass \| issues_found' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh documents skipped_no_fix_required in uat_last_result vocabulary"
else
  fail "debug-session-state.sh missing skipped_no_fix_required in uat_last_result vocabulary"
fi

if grep -q 'normalize_completed_no_verification_results()' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh has completed no-verification normalization helper"
else
  fail "debug-session-state.sh missing completed no-verification normalization helper"
fi

if contains_literal "$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$SESSION_PATH"'; then
  pass "debug-session-state.sh set-status normalizes completed no-verification sessions before move"
else
  fail "debug-session-state.sh set-status missing completed no-verification normalization"
fi

if contains_literal "$(awk '/reconcile_session_location\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$file"'; then
  pass "debug-session-state.sh reconcile path normalizes completed no-verification sessions"
else
  fail "debug-session-state.sh reconcile path missing completed no-verification normalization"
fi

if contains_literal "$(awk '/migrate_legacy_session\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$file"'; then
  pass "debug-session-state.sh legacy migration normalizes completed no-verification sessions"
else
  fail "debug-session-state.sh legacy migration missing completed no-verification normalization"
fi

# — Writer script checks —

WRITER="$ROOT/scripts/write-debug-session.sh"

if [ -f "$WRITER" ]; then
  pass "write-debug-session.sh exists"
else
  fail "write-debug-session.sh missing"
fi

for mode in source-todo investigation qa uat status; do
  if grep -q "$mode" "$WRITER" 2>/dev/null; then
    pass "writer script handles mode: $mode"
  else
    fail "writer script missing mode: $mode"
  fi
done

INVESTIGATION_BLOCK="$(awk '/investigation\)/,/;;/' "$WRITER" 2>/dev/null || true)"
if ! grep -Eq 'qa_last_result|uat_last_result' <<< "$INVESTIGATION_BLOCK"; then
  pass "write-debug-session.sh investigation mode does not mutate QA/UAT result fields"
else
  fail "write-debug-session.sh investigation mode should not mutate QA/UAT result fields"
fi

# — Context compiler checks —

COMPILER="$ROOT/scripts/compile-debug-session-context.sh"

if [ -f "$COMPILER" ]; then
  pass "compile-debug-session-context.sh exists"
else
  fail "compile-debug-session-context.sh missing"
fi

if grep -q 'Source Todo' "$COMPILER" 2>/dev/null; then
  pass "context compiler emits Source Todo content"
else
  fail "context compiler missing Source Todo content"
fi

for mode in qa uat; do
  if grep -q "$mode" "$COMPILER" 2>/dev/null; then
    pass "context compiler handles mode: $mode"
  else
    fail "context compiler missing mode: $mode"
  fi
done

if grep -Fq 'skipped — no fix required' "$COMPILER" 2>/dev/null; then
  pass "context compiler has friendly label for skipped no-fix-required results"
else
  fail "context compiler missing friendly label for skipped no-fix-required results"
fi

if grep -Fq '**QA Round:** ${QA_ROUND} (last result: ${QA_LAST_DISPLAY})' "$COMPILER" 2>/dev/null \
  && grep -Fq '**UAT Round:** ${UAT_ROUND} (last result: ${UAT_LAST_DISPLAY})' "$COMPILER" 2>/dev/null \
  && grep -Fq 'QA round ${QA_ROUND}: ${QA_LAST_DISPLAY}' "$COMPILER" 2>/dev/null; then
  pass "context compiler renders display-mapped QA/UAT result labels in all three summary sites"
else
  fail "context compiler still interpolates raw QA/UAT result labels in one or more summary sites"
fi

# — Command integration checks —

DEBUG_CMD="$ROOT/commands/debug.md"
DEBUG_PATH_A_BLOCK="$(sed -n '/^[[:space:]]*\*\*Path A:/,/^[[:space:]]*\*\*Path B:/p' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_PATH_B_BLOCK="$(sed -n '/^[[:space:]]*\*\*Path B:/,/^5\./p' "$DEBUG_CMD" 2>/dev/null || true)"

if grep -q "debug_session_routing" "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md has debug_session_routing section"
else
  fail "debug.md missing debug_session_routing section"
fi

if grep -q 'start-with-selected-todo' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md uses start-with-selected-todo for numbered todo sessions"
else
  fail "debug.md missing start-with-selected-todo numbered todo integration"
fi

if grep -q 'HEAD_BEFORE' "$DEBUG_CMD" 2>/dev/null && grep -q 'HEAD_AFTER' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md compares HEAD_BEFORE and HEAD_AFTER for investigation outcomes"
else
  fail "debug.md missing HEAD_BEFORE/HEAD_AFTER outcome comparison"
fi

if grep -qF 'resolution_observation' <<< "$DEBUG_PATH_B_BLOCK"; then
  pass "debug.md Path B instructs the single debugger to return resolution_observation"
else
  fail "debug.md Path B missing resolution_observation contract"
fi

if grep -Fq 'You are a hypothesis investigator, not the implementation owner.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'Do NOT edit files, apply fixes, run mutating Bash, commit, request implementation approval, or claim ownership of the final session outcome.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'Stop after diagnosis plus evidence reporting via `debugger_report`.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A investigator prompts are explicitly report-only"
else
  fail "debug.md Path A investigator prompts missing explicit report-only contract"
fi

if grep -Fq 'Wait until ALL spawned hypothesis investigators have returned `debugger_report`.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A waits for all spawned hypothesis investigators before synthesis"
else
  fail "debug.md Path A missing all-spawned-investigators synthesis barrier"
fi

if grep -Fq 'Winning hypothesis with fix: apply + commit' <<< "$DEBUG_PATH_A_BLOCK"; then
  fail "debug.md still contains winning-hypothesis apply shortcut"
else
  pass "debug.md removes winning-hypothesis apply shortcut"
fi

if grep -Fq 'If `RESOLUTION_OBSERVATION=already_fixed` or `inconclusive`: do NOT spawn an implementation owner.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A skips implementation owner for already_fixed and inconclusive"
else
  fail "debug.md Path A missing already_fixed/inconclusive no-implementation-owner guard"
fi

if grep -Fq 'If `RESOLUTION_OBSERVATION=needs_change`: spawn ONE fresh post-synthesis implementation owner via TaskCreate with `subagent_type: "vbw:vbw-debugger"` and `model: "${DEBUGGER_MODEL}"`.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'This is a new debugger instance, not one of the earlier hypothesis investigators.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A uses a fresh vbw-debugger as the sole post-synthesis implementation owner"
else
  fail "debug.md Path A missing fresh vbw-debugger implementation-owner contract"
fi

patha_teardown_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" '**Teardown phase — HARD GATE before any implementation:**')
patha_zero_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" 'Verify: after TeamDelete, there must be ZERO active teammates.')
patha_impl_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" 'If `RESOLUTION_OBSERVATION=needs_change`: spawn ONE fresh post-synthesis implementation owner')

if [ -n "$patha_teardown_line" ] && [ -n "$patha_zero_line" ] && [ -n "$patha_impl_line" ] \
  && [ "$patha_teardown_line" -lt "$patha_zero_line" ] && [ "$patha_zero_line" -lt "$patha_impl_line" ]; then
  pass "debug.md finishes teammate teardown before implementation-owner spawn"
else
  fail "debug.md does not prove teammate teardown completes before implementation-owner spawn"
fi

if grep -qF 'INVESTIGATION_OUTCOME=fixed_now' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF 'INVESTIGATION_OUTCOME=already_fixed' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF 'INVESTIGATION_OUTCOME=no_fix_yet' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md Step 5 maps fixed_now, already_fixed, and no_fix_yet outcomes"
else
  fail "debug.md Step 5 missing fixed_now/already_fixed/no_fix_yet mapping"
fi

if grep -qF 'set-status .vbw-planning complete' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md already_fixed path reuses completed-state workflow via set-status complete"
else
  fail "debug.md already_fixed path missing set-status complete workflow"
fi

DEBUG_HINT_LINE="$(awk '/^argument-hint:/{print; exit}' "$DEBUG_CMD" 2>/dev/null || true)"
if contains_literal "$DEBUG_HINT_LINE" 'bug description' \
  && contains_literal "$DEBUG_HINT_LINE" 'todo number' \
  && contains_literal "$DEBUG_HINT_LINE" '--resume' \
  && contains_literal "$DEBUG_HINT_LINE" '--session ID'; then
  pass "debug.md argument-hint advertises bug text, todo number, --resume, and --session"
else
  fail "debug.md argument-hint missing one or more supported entry points"
fi

DEBUG_USAGE_LINES="$(grep -F 'Usage:' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_USAGE_COUNT=$(printf '%s\n' "$DEBUG_USAGE_LINES" | grep -c 'Usage:' || true)
if [ "$DEBUG_USAGE_COUNT" -ge 2 ] \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug <todo-number>' \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug --resume' \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug --session <id>' \
  && contains_literal "$DEBUG_USAGE_LINES" '[--competing|--parallel|--serial]'; then
  pass "debug.md keeps both expanded Usage strings with resume/session and ambiguity flags"
else
  fail "debug.md missing expanded Usage strings with resume/session and ambiguity flags"
fi

if grep -Fq 'No active debug session to resume. Use `/vbw:debug --session <id>` to open a specific session' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md resume stop message advertises session override and new-session entry points"
else
  fail "debug.md resume stop message still uses freeform-only guidance"
fi

if grep -Fq 'This debug session is already complete. Use `/vbw:debug --session <id>` to inspect another session' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md complete-session stop message advertises session override and new-session entry points"
else
  fail "debug.md complete-session stop message still uses freeform-only guidance"
fi

if grep -Fq 'Use `session_status` for lifecycle checks after `eval`; do not rely on a bare `status` variable.' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md names the safe debug-session helper contract explicitly"
else
  fail "debug.md missing explicit session_status helper contract"
fi

if grep -Fq 'session_status=qa_pending' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=qa_failed' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=uat_pending' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=uat_failed' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=complete' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md lifecycle routing keys off session_status for metadata-read helpers"
else
  fail "debug.md lifecycle routing not fully aligned to session_status contract"
fi

debug_complete_matches=$(grep -nF 'bash "{plugin-root}/scripts/debug-session-state.sh" set-status .vbw-planning complete' "$DEBUG_CMD" 2>/dev/null || true)
debug_pg_matches=$(grep -nF 'PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"' "$DEBUG_CMD" 2>/dev/null || true)
debug_commit_matches=$(grep -nF 'bash "$PG_SCRIPT" commit-boundary "complete debug session" .vbw-planning/config.json' "$DEBUG_CMD" 2>/dev/null || true)
debug_warning_matches=$(grep -nF 'VBW: planning-git.sh unavailable; skipping planning git boundary commit' "$DEBUG_CMD" 2>/dev/null || true)

debug_complete_first=$(printf '%s\n' "$debug_complete_matches" | sed -n '1s/:.*//p')
debug_complete_second=$(printf '%s\n' "$debug_complete_matches" | sed -n '2s/:.*//p')
debug_complete_third=$(printf '%s\n' "$debug_complete_matches" | sed -n '3s/:.*//p')

debug_pg_first=$(printf '%s\n' "$debug_pg_matches" | sed -n '1s/:.*//p')
debug_pg_second=$(printf '%s\n' "$debug_pg_matches" | sed -n '2s/:.*//p')
debug_pg_third=$(printf '%s\n' "$debug_pg_matches" | sed -n '3s/:.*//p')

debug_commit_first=$(printf '%s\n' "$debug_commit_matches" | sed -n '1s/:.*//p')
debug_commit_second=$(printf '%s\n' "$debug_commit_matches" | sed -n '2s/:.*//p')
debug_commit_third=$(printf '%s\n' "$debug_commit_matches" | sed -n '3s/:.*//p')

debug_warning_first=$(printf '%s\n' "$debug_warning_matches" | sed -n '1s/:.*//p')
debug_warning_second=$(printf '%s\n' "$debug_warning_matches" | sed -n '2s/:.*//p')
debug_warning_third=$(printf '%s\n' "$debug_warning_matches" | sed -n '3s/:.*//p')

if [ -n "$debug_complete_first" ] && [ -n "$debug_complete_second" ] && [ -z "$debug_complete_third" ] && \
   [ -n "$debug_pg_first" ] && [ -n "$debug_pg_second" ] && [ -z "$debug_pg_third" ] && \
   [ -n "$debug_commit_first" ] && [ -n "$debug_commit_second" ] && [ -z "$debug_commit_third" ] && \
   [ -n "$debug_warning_first" ] && [ -n "$debug_warning_second" ] && [ -z "$debug_warning_third" ] && \
   [ "$debug_complete_first" -lt "$debug_pg_first" ] && [ "$debug_pg_first" -lt "$debug_commit_first" ] && [ "$debug_commit_first" -lt "$debug_warning_first" ] && \
   [ "$debug_complete_second" -lt "$debug_pg_second" ] && [ "$debug_pg_second" -lt "$debug_commit_second" ] && [ "$debug_commit_second" -lt "$debug_warning_second" ]; then
  pass "debug.md completion paths run planning boundary commit immediately after set-status complete"
else
  fail "debug.md completion paths missing ordered planning boundary commit after set-status complete"
fi

if grep -Fq "already_fixed = 'Already fixed before this investigation — no new fix commit was required." "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'already_fixed = "Already fixed on the current branch — no new fix commit was required;' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md already_fixed wording distinguishes fix commits from planning-artifact commits"
else
  fail "debug.md already_fixed wording still blurs fix commits and planning-artifact commits"
fi

if grep -Fq "already_fixed = 'Already fixed before this investigation — no new commit created.'" "$DEBUG_CMD" 2>/dev/null \
  || grep -Fq 'already_fixed = "Already fixed on the current branch — no new commit created"' "$DEBUG_CMD" 2>/dev/null; then
  fail "debug.md still contains stale already_fixed wording that claims no commit was created"
else
  pass "debug.md removes stale already_fixed no-new-commit wording"
fi

if grep -qF 'For `no_fix_yet`' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF '`investigating`' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md no_fix_yet path keeps the session investigating"
else
  fail "debug.md no_fix_yet path missing investigating-state guidance"
fi

QA_CMD="$ROOT/commands/qa.md"
if grep -q "debug_session_qa" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug_session_qa section"
else
  fail "qa.md missing debug_session_qa section"
fi

if grep -Fq 'use `session_status` for lifecycle checks after `eval`.' "$QA_CMD" 2>/dev/null \
  && grep -Fq 'use `session_status` for routing after `eval`.' "$QA_CMD" 2>/dev/null \
  && grep -Fq 'exported `session_status` is `qa_pending` or `qa_failed`' "$QA_CMD" 2>/dev/null; then
  pass "qa.md debug-session override uses the explicit session_status helper contract"
else
  fail "qa.md debug-session override missing explicit session_status helper contract"
fi

VERIFY_CMD="$ROOT/commands/verify.md"
if grep -q "debug_session_uat" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug_session_uat section"
else
  fail "verify.md missing debug_session_uat section"
fi

if grep -Fq 'use `session_status` for lifecycle checks after `eval`.' "$VERIFY_CMD" 2>/dev/null \
  && grep -Fq 'use `session_status` for routing after `eval`.' "$VERIFY_CMD" 2>/dev/null \
  && grep -Fq 'exported `session_status` is `uat_pending` or `uat_failed`' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md debug-session override uses the explicit session_status helper contract"
else
  fail "verify.md debug-session override missing explicit session_status helper contract"
fi

# — Agent integration checks —

DEBUGGER_AGENT="$ROOT/agents/vbw-debugger.md"
if grep -q "Standalone Debug Session" "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "vbw-debugger.md has standalone debug session section"
else
  fail "vbw-debugger.md missing standalone debug session section"
fi

DEBUGGER_TEAMMATE_BLOCK="$(sed -n '/## Teammate Mode/,/^## /p' "$DEBUGGER_AGENT" 2>/dev/null || true)"

if grep -Fq 'When `/vbw:debug` Path A spawns you as a hypothesis investigator' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq 'overrides any conflicting implementation language' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "vbw-debugger.md teammate mode explicitly defers to /vbw:debug orchestration"
else
  fail "vbw-debugger.md teammate mode missing /vbw:debug orchestration override"
fi

if grep -Fq 'Teammate mode ends at diagnosis plus `debugger_report`.' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq '`resolution_observation` does NOT grant fix authority.' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "vbw-debugger.md teammate mode ends at diagnosis and keeps resolution observations analysis-only"
else
  fail "vbw-debugger.md teammate mode missing diagnosis-only boundary or analysis-only resolution language"
fi

if grep -Fq '`/vbw:debug` owns synthesis, session status, teardown, and any later implementation handoff.' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq 'That implementation owner is not this teammate.' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "vbw-debugger.md teammate mode reserves implementation ownership for a fresh post-synthesis owner"
else
  fail "vbw-debugger.md teammate mode missing fresh post-synthesis ownership boundary"
fi

QA_AGENT="$ROOT/agents/vbw-qa.md"
if grep -q "Debug Session QA" "$QA_AGENT" 2>/dev/null; then
  pass "vbw-qa.md has debug session QA section"
else
  fail "vbw-qa.md missing debug session QA section"
fi

# — Guard ordering checks (R2-01, R2-02) —

if grep -q "Debug session override" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug session override in Guard"
else
  fail "qa.md missing debug session override in Guard"
fi

if grep -q "Debug session override" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug session override in Guard"
else
  fail "verify.md missing debug session override in Guard"
fi

# — UAT template completeness (R2-03) —

if grep -q '"result"' "$VERIFY_CMD" 2>/dev/null && grep -q 'pass|issues_found' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md UAT template includes result field"
else
  fail "verify.md UAT template missing result field"
fi

# — Agent status alignment (R2-04) —

if grep -q 'qa_pending' "$DEBUGGER_AGENT" 2>/dev/null && ! grep -q 'fix_applied' "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "vbw-debugger.md uses qa_pending (not fix_applied) for post-fix status"
else
  fail "vbw-debugger.md should use qa_pending for post-fix status, not fix_applied"
fi

# — Template remediation history section (CM1-02) —

TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"
if grep -q '## Remediation History' "$TEMPLATE" 2>/dev/null; then
  pass "DEBUG-SESSION.md template has Remediation History section"
else
  fail "DEBUG-SESSION.md template missing Remediation History section"
fi

# — Guard phase_count condition (CM1-01) —

if grep -q 'phase_count=0' "$QA_CMD" 2>/dev/null || grep -q 'phase_count' "$QA_CMD" 2>/dev/null; then
  pass "qa.md debug session guard checks phase_count"
else
  fail "qa.md debug session guard does not check phase_count"
fi

if grep -q 'phase_count=0' "$VERIFY_CMD" 2>/dev/null || grep -q 'phase_count' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md debug session guard checks phase_count"
else
  fail "verify.md debug session guard does not check phase_count"
fi

# — Writer handles skip and user_response (CM1-03) —

if grep -q 'skip' "$WRITER" 2>/dev/null && grep -q 'user_response' "$WRITER" 2>/dev/null; then
  pass "write-debug-session.sh handles skip result and user_response"
else
  fail "write-debug-session.sh missing skip or user_response handling"
fi

# — Lifecycle integration test exists (CM1-04) —

if [ -f "$ROOT/tests/debug-session-lifecycle.bats" ]; then
  pass "debug-session-lifecycle.bats end-to-end test exists"
else
  fail "debug-session-lifecycle.bats missing"
fi

# — suggest-next.sh qa path handles standalone debug sessions (CM2-01) —

if grep -q 'phase_count.*0.*debugging' "$ROOT/scripts/suggest-next.sh" 2>/dev/null || \
   grep -q '_qa_debug_handled' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh qa branch has standalone debug-session detection"
else
  fail "suggest-next.sh qa branch missing standalone debug-session detection"
fi

# — qa.md routing decision supports --session flag alongside phase_count (CM2-02, CM3-01) —

if grep -q 'phase_count=0.*--session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md debug-session routing decision supports --session flag"
else
  fail "qa.md debug-session routing decision missing --session flag support"
fi

# — verify.md routing decision supports --session flag alongside phase_count (CM2-02, CM3-01) —

if grep -q 'phase_count=0.*--session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md debug-session routing decision supports --session flag"
else
  fail "verify.md debug-session routing decision missing --session flag support"
fi

# — suggest-next-debug-session.bats covers qa context (CM2-03) —

if grep -q 'suggest-next qa.*pass.*debug session' "$ROOT/tests/suggest-next-debug-session.bats" 2>/dev/null; then
  pass "suggest-next-debug-session.bats covers qa pass with debug session"
else
  fail "suggest-next-debug-session.bats missing qa pass with debug session test"
fi

# — Guard sections support --session escape hatch (CM3-01) —

if grep -q '\-\-session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md guard mentions --session flag"
else
  fail "qa.md guard missing --session flag"
fi

if grep -q '\-\-session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md guard mentions --session flag"
else
  fail "verify.md guard missing --session flag"
fi

# — suggest-next.sh routes debug sessions to /vbw:debug --resume (CM3-01) —

if grep -q 'vbw:debug --resume' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh routes debug sessions to /vbw:debug --resume"
else
  fail "suggest-next.sh missing /vbw:debug --resume routing for debug sessions"
fi

# — suggest-next.sh qa/verify debug handlers guard on phase_count=0 (CM7-01) —

if grep -q 'phase_count.*0.*debugging' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh qa/verify debug handlers guard on phase_count=0"
else
  fail "suggest-next.sh qa/verify debug handlers not guarded by phase_count=0"
fi

# — Frontmatter-scoped field updates via awk (CM3-02, Copilot-C1-02/03) —

if ! grep -q "sed -i ''" "$ROOT/scripts/debug-session-state.sh" 2>/dev/null; then
  pass "debug-session-state.sh uses portable sed (no BSD-only -i '')"
else
  fail "debug-session-state.sh uses non-portable sed -i ''"
fi

if grep -q 'in_fm' "$ROOT/scripts/debug-session-state.sh" 2>/dev/null; then
  pass "debug-session-state.sh uses awk-based frontmatter-scoped field updates"
else
  fail "debug-session-state.sh missing awk-based frontmatter scoping"
fi

if ! grep -q "sed -i ''" "$ROOT/scripts/write-debug-session.sh" 2>/dev/null; then
  pass "write-debug-session.sh uses portable sed (no BSD-only -i '')"
else
  fail "write-debug-session.sh uses non-portable sed -i ''"
fi

if grep -q 'in_fm' "$ROOT/scripts/write-debug-session.sh" 2>/dev/null; then
  pass "write-debug-session.sh uses awk-based frontmatter-scoped field updates"
else
  fail "write-debug-session.sh missing awk-based frontmatter scoping"
fi

# — Command inline QA/UAT lifecycle (CM4-01, CM4-02) —

if grep -q 'debug_inline_qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md has inline QA section (debug_inline_qa)"
else
  fail "debug.md missing inline QA section (debug_inline_qa)"
fi

if grep -q 'debug_inline_uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md has inline UAT section (debug_inline_uat)"
else
  fail "debug.md missing inline UAT section (debug_inline_uat)"
fi

if contains_literal "$(awk '
  BEGIN { delim=0 }
  /^---$/ {
    delim++
    if (delim == 2) exit
    next
  }
  delim == 1 { print }
' "$ROOT/commands/debug.md" 2>/dev/null || true)" 'AskUserQuestion'; then
  pass "debug.md frontmatter includes AskUserQuestion tool"
else
  fail "debug.md frontmatter missing AskUserQuestion tool"
fi

if grep -q '\-\-session.*Run UAT on the debug fix' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md next-step for PASS includes --session"
else
  fail "qa.md next-step for PASS missing --session flag"
fi

if grep -q 'qa_pending.*debug_inline_qa\|fix_applied.*debug_inline_qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume routing for qa_pending/fix_applied enters inline QA"
else
  fail "debug.md resume routing for qa_pending/fix_applied missing inline QA entry"
fi

if grep -q 'session_status=uat_pending.*debug_inline_uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume routing for uat_pending enters inline UAT"
else
  fail "debug.md resume routing for uat_pending missing inline UAT entry"
fi

# — QA agent persistence contract separates phase-scoped from debug-session (CM5-01) —

if grep -q 'Phase-Scoped QA' "$ROOT/agents/vbw-qa.md" 2>/dev/null; then
  pass "vbw-qa.md persistence section scoped to phase QA"
else
  fail "vbw-qa.md persistence section not scoped to phase QA"
fi

if grep -q 'Debug-session QA exception' "$ROOT/agents/vbw-qa.md" 2>/dev/null || \
   grep -q 'debug-session QA.*do NOT use.*write-verification' "$ROOT/agents/vbw-qa.md" 2>/dev/null; then
  pass "vbw-qa.md explicitly exempts debug-session QA from write-verification.sh"
else
  fail "vbw-qa.md missing debug-session QA exception from write-verification.sh"
fi

# — Resume-context handoff injects FAILURE_CONTEXT into debugger prompt (CM6-01) —

if grep -q 'FAILURE_CONTEXT.*compile-debug-session-context' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume captures FAILURE_CONTEXT from compile-debug-session-context.sh"
else
  fail "debug.md resume missing FAILURE_CONTEXT capture from compile-debug-session-context.sh"
fi

if grep -q 'Previous QA failed.*FAILURE_CONTEXT' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume injects QA failure context into debugger prompt"
else
  fail "debug.md resume missing QA failure context injection"
fi

if grep -q 'Previous UAT failed.*FAILURE_CONTEXT' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume injects UAT failure context into debugger prompt"
else
  fail "debug.md resume missing UAT failure context injection"
fi

# — Resume paths pass correct mode to compile-debug-session-context.sh (CM8-01) —

if grep -q 'compile-debug-session-context\.sh.*qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md qa_failed resume passes 'qa' mode to compile-debug-session-context.sh"
else
  fail "debug.md qa_failed resume missing 'qa' mode argument"
fi

if grep -q 'compile-debug-session-context\.sh.*uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md uat_failed resume passes 'uat' mode to compile-debug-session-context.sh"
else
  fail "debug.md uat_failed resume missing 'uat' mode argument"
fi

# — Active/completed directory layout (issue #386) —

if grep -q 'ACTIVE_DIR=' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh defines ACTIVE_DIR"
else
  fail "debug-session-state.sh missing ACTIVE_DIR definition"
fi

if grep -q 'COMPLETED_DIR=' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh defines COMPLETED_DIR"
else
  fail "debug-session-state.sh missing COMPLETED_DIR definition"
fi

if grep -q 'migrate_legacy_session' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh has migrate_legacy_session function"
else
  fail "debug-session-state.sh missing migrate_legacy_session function"
fi

# Verify the set-status branch specifically handles complete → move to COMPLETED_DIR
_set_status_block="$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)"
if matches_ere "$_set_status_block" '"\$STATUS" = "complete"' && \
   matches_ere "$_set_status_block" 'safe_move_session.*\$COMPLETED_DIR'; then
  pass "debug-session-state.sh set-status branch moves complete sessions to COMPLETED_DIR"
else
  fail "debug-session-state.sh set-status branch does not move complete sessions to COMPLETED_DIR"
fi

# list command should output both location fields for dual-directory listings
_list_block="$(awk '/list\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)"
if contains_literal "$_list_block" '|active' && \
   contains_literal "$_list_block" '|completed'; then
  pass "debug-session-state.sh list outputs both active and completed location fields"
else
  fail "debug-session-state.sh list missing location field in output (must include both |active and |completed)"
fi

# safe_move_session helper with destination-exists guard
if grep -q 'safe_move_session()' "$STATE_SCRIPT" 2>/dev/null && \
   contains_literal "$(awk '/safe_move_session\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'return 1'; then
  pass "debug-session-state.sh has safe_move_session helper with collision guard"
else
  fail "debug-session-state.sh missing safe_move_session helper or collision guard"
fi

# — Summary —

echo ""
echo "=== Debug Session Contract: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
