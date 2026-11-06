#!/usr/bin/env bats
# R262 (docs/workflows.md): the three behaviours 2.1.25 proved only with unit tests
# (R250 amendments, R252 queued requirements, R254 linked-worktree writes) each get a
# real-user scenario in tools/l3-suite.sh (L3, the real Claude Code TUI on a small
# project): amendfile (a file added to a plan by vbw apply --amend with the build run
# open, the approval kept, the added file in the plan's commit), queuedreq (a
# requirement added while a build runs queues, is cleared at run end, then planned and
# built later, and the first build's plans are not re-planned) and worktreewrite (a
# Dev working from a linked worktree writes into the main checkout while its build run
# is open: the guard refuses, the file is unchanged, the Dev's own plan still finishes
# in its worktree). As in tests/l3-submodule.bats these tests do not run Claude Code
# (L1): they hold each scenario's structure, and its committed result once a passing
# run wrote one (D551), to facts judged in the record, git and the transcripts, never
# on screen text.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"
THREE="amendfile queuedreq worktreewrite"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

# scenario_shape NAME: the scenario exists, is in the default list and the header, starts from a
# fresh project, runs the common checks, judges nothing on screen text and writes its result
# with its fixture, cost and verdict.
scenario_shape() {
  grep -q "^scenario_$1()" "$SUITE" || { echo "no scenario_$1"; return 1; }
  grep -E '^ALL=' "$SUITE" | grep -qw "$1" || { echo "$1 is not in ALL"; return 1; }
  sed -n '1,20p' "$SUITE" | grep -qw "$1" || { echo "$1 is not in the header"; return 1; }
  body "$1" | grep -q 'new_project' || { echo "$1 does not start from new_project"; return 1; }
  body "$1" | grep -qi 'fixture=' || { echo "$1 states no fixture"; return 1; }
  body "$1" | grep -qF 'common_checks' || { echo "$1 does not run common_checks"; return 1; }
  if body "$1" | grep -qE 'screen \|.*grep'; then echo "$1 judges on screen text"; return 1; fi
  body "$1" | grep -qE "result_write $1 \"\\\$fixture\" \"\\\$\\{cost_usd:-0\\}\" \"\\\$passed\"" || { echo "$1 does not write fixture, cost and passed"; return 1; }
}

# result_honest NAME FACT...: a committed result, when there is one, is labelled L3, passed, and states each FACT true.
result_honest() {
  local n="$1" f="$RESULTS/$1.json" k
  shift
  [ -f "$f" ] || skip "no $n result committed yet: a passing run writes it (D551)"
  jq -e --arg n "$n" '.scenario == $n and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.at | type == "string") and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)' "$f" > /dev/null
  for k in "$@"; do jq -e --arg k "$k" '.facts[$k] == true' "$f" > /dev/null || { echo "$n: fact $k is not true"; return 1; }; done
}

@test "R262: the three scenarios exist, are in the default list and the header, and write their results honestly" {
  local s
  for s in $THREE; do scenario_shape "$s"; done
}

@test "R262 amendfile: it opens a build, adds a file to its plan with vbw apply --amend, and judges the amendment's record, the kept approval, the unbroken run, plan done and the file in the plan's commit" {
  body amendfile | grep -qF -- 'apply --amend' || { echo "the scenario does not use vbw apply --amend"; false; }
  body amendfile | grep -qF 'amendments' || { echo "the amendment entry (what, at, session) is not judged"; false; }
  body amendfile | grep -qiE 'session' || { echo "the amendment's session is not judged"; false; }
  body amendfile | grep -qiE 'approv' || { echo "the approval hash is not judged"; false; }
  body amendfile | grep -qiE 'run end|ended early|lease' || { echo "the run's early end is not judged"; false; }
  body amendfile | grep -qiE 'plan done|"done"' || { echo "plan done is not judged"; false; }
  body amendfile | grep -qiE 'VBW-Plan|commit' || { echo "the plan's commit is not judged"; false; }
  local k
  for k in amendment_recorded approval_kept run_not_ended_early plan_done added_file_in_commit; do
    body amendfile | grep -qF "$k" || { echo "fact $k is not judged"; false; }
  done
}

@test "R262 queuedreq: it adds a requirement while a build runs and judges the queued mark, its clearing at run end, the later plan and build, and that the first plans were not re-planned" {
  body queuedreq | grep -qE 'spec add|spec sync|Not yet' || { echo "the scenario adds no requirement during the build"; false; }
  body queuedreq | grep -qF 'queued' || { echo "the queued mark is not judged"; false; }
  body queuedreq | grep -qiE 'run end|cleared' || { echo "the clearing at run end is not judged"; false; }
  body queuedreq | grep -qiE 're-?plan' || { echo "the first build's plans being kept is not judged"; false; }
  local k
  for k in queued_during_run cleared_at_run_end planned_later built_later first_plans_kept; do
    body queuedreq | grep -qF "$k" || { echo "fact $k is not judged"; false; }
  done
}

@test "R262 worktreewrite: a Dev in a linked worktree writes into the main checkout under its build run, and it judges the guard's refusal, the unchanged file and the Dev's finished plan" {
  body worktreewrite | grep -qF 'git worktree add' || { echo "the scenario makes no linked worktree"; false; }
  body worktreewrite | grep -qF 'VBW guard:' || { echo "the guard's refusal is not judged"; false; }
  body worktreewrite | grep -qiE 'refused|transcript' || { echo "the refused list or the transcript is not read"; false; }
  body worktreewrite | grep -qiE 'unchanged|cmp|diff --quiet|rev-parse' || { echo "the main checkout's file is not judged unchanged"; false; }
  body worktreewrite | grep -qiE 'done' || { echo "the Dev's own plan finishing is not judged"; false; }
  local k
  for k in guard_refused main_file_unchanged worktree_plan_done; do
    body worktreewrite | grep -qF "$k" || { echo "fact $k is not judged"; false; }
  done
}

@test "R262: docs/workflows.md names the three scenarios with what each judges" {
  local s
  for s in $THREE; do
    grep -qE "\`$s\`|$s scenario|scenario $s" "$REPO_ROOT/docs/workflows.md" || { echo "docs/workflows.md does not name $s"; false; }
  done
}

@test "R262: a committed result of each scenario, when there is one, is labelled honestly and states its facts true" {
  result_honest amendfile amendment_recorded approval_kept run_not_ended_early plan_done added_file_in_commit
  result_honest queuedreq queued_during_run cleared_at_run_end planned_later built_later first_plans_kept
  result_honest worktreewrite guard_refused main_file_unchanged worktree_plan_done
}
