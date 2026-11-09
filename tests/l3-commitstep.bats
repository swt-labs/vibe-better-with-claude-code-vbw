#!/usr/bin/env bats
# R287 (field report 2026-11-09): a commit of VBW's own files that the project's commit check
# refuses becomes vbw next's commit step, and VBW never skips the project's hooks. The real-user
# scenario commitstep (tools/l3-suite.sh, L3: the real Claude Code on a small project whose
# pre-commit hook refuses the record) judges it in the runtime files, git and the transcripts,
# never on screen text. These tests do not run Claude Code (L1): they hold the scenario's
# structure, and its committed result once a passing run wrote one (D551), to those facts.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/commitstep.json"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R287 commitstep: the scenario is in the default list and the header, seeds an approved plan behind a hook that refuses the record, and writes its result" {
  grep -q '^scenario_commitstep()' "$SUITE" || { echo "no scenario_commitstep"; false; }
  grep -E '^ALL=' "$SUITE" | grep -qw commitstep || { echo "commitstep is not in ALL"; false; }
  sed -n '1,20p' "$SUITE" | grep -qw commitstep || { echo "commitstep is not in the header"; false; }
  body commitstep | grep -q 'new_project' || { echo "it does not start from new_project"; false; }
  body commitstep | grep -q 'greet_plan_seed' || { echo "it does not seed an approved plan"; false; }
  body commitstep | grep -q 'commitstep_hook' || { echo "it installs no refusing hook"; false; }
  sed -n '/^commitstep_hook()/,/^}/p' "$SUITE" | grep -qF "grep -qx '.vbw/record.json'" || { echo "the hook does not refuse a commit holding the record"; false; }
  if body commitstep | grep -qE 'screen \|.*grep'; then echo "it judges on screen text"; false; fi
  body commitstep | grep -qE 'result_write commitstep "\$fixture" "\$\{cost_usd:-0\}" "\$passed"' || { echo "it does not write fixture, cost and passed"; false; }
}

@test "R287 commitstep: it judges the kept refusal and the hook's words, the commit step, the words read by the session, no skipped hook, and the step's end once the check passes" {
  local b
  b=$(body commitstep)
  printf '%s\n' "$b" | grep -qF 'commit-failed.json' || { echo "the kept refusal is not judged"; false; }
  printf '%s\n' "$b" | grep -qF 'output/commit-failed.log' || { echo "the kept hook words are not judged"; false; }
  printf '%s\n' "$b" | grep -qF '= commit ]' || { echo "the commit step is not judged"; false; }
  printf '%s\n' "$b" | grep -qF 'transcript_tool_output' || { echo "the words the session read are not judged"; false; }
  printf '%s\n' "$b" | grep -qF -- '--no-verify' || { echo "a skipped hook is not judged"; false; }
  printf '%s\n' "$b" | grep -qF 'rm -f' || { echo "the check never passes again"; false; }
  printf '%s\n' "$b" | grep -qF '!= commit ]' || { echo "the step's end is not judged"; false; }
}

@test "R287 commitstep: the committed result passed at L3 and states every fact, no hook skipped" {
  [ -f "$RESULT" ] || skip "no commitstep result committed yet: a passing run writes it (D551)"
  jq -e '.scenario == "commitstep" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.not_tested | type == "array" and length > 0)
    and .facts.failure_kept and .facts.hook_words_kept and .facts.commit_step and .facts.hook_words_in_session
    and .facts.hooks_bypassed == false
    and .facts.step_left_after_check_passes and .facts.failure_cleared and .facts.record_committed_after' "$RESULT" > /dev/null \
    || { jq . "$RESULT"; false; }
}
