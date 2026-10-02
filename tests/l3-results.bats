#!/usr/bin/env bats
# P3-P6 / R4-R8: the real-session proof. Each L3 scenario in tools/l3-suite.sh
# writes tools/l3-results/NAME.json after a run through the real Claude Code
# TUI (docs/proof.md, D2). These tests do not run Claude Code (L1); they hold
# the committed result to the facts the requirement states. A result names its
# fixture, cost, evidence level and the facts below, taken from the record,
# git and the session logs, never from screen text.

load helper

RESULTS="$REPO_ROOT/tools/l3-results"

# result_ok NAME: the scenario exists, ran, passed, and is labelled honestly.
result_ok() {
  grep -q "^scenario_$1()" "$REPO_ROOT/tools/l3-suite.sh"
  grep -E '^ALL=' "$REPO_ROOT/tools/l3-suite.sh" | grep -qw "$1"
  local f="$RESULTS/$1.json"
  [ -f "$f" ]
  jq -e --arg n "$1" '.scenario == $n and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0)
    and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.facts | type == "object")
    and (.not_tested | type == "array")' "$f" > /dev/null
}

facts() { jq -e "$2" "$RESULTS/$1.json" > /dev/null; }

@test "R8: balanced autonomy, background QA: no Stop-hook errors, stopped at accept" {
  result_ok balanced
  facts balanced '.facts.autonomy == "balanced" and .facts.qa_background == true
    and .facts.stop_hook_errors_transcript == 0 and .facts.stop_hook_errors_debug_log == 0
    and .facts.stopped_at == "accept"'
}

@test "R4: the Docs agent built a documentation requirement and it is proved" {
  result_ok docs
  facts docs '.facts.built_by_agent_type == "docs" and .facts.check_approved == true
    and .facts.check_status == "pass" and .facts.commit_has_provenance == true
    and .facts.requirement_status == "proven"'
}

@test "R5: QA failed a deviating build, naming the deviation; the fix loop closed it" {
  result_ok qafix
  facts qafix '.facts.deviation | type == "string" and length > 0'
  facts qafix '.facts.first_qa_verdict == "fail" and (.facts.deviation as $d | .facts.first_qa_note | contains($d))
    and .facts.fix_rounds >= 1 and .facts.final_qa_verdict == "pass"
    and .facts.phase_proved == true'
}
