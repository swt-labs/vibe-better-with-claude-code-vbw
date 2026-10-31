#!/usr/bin/env bats
# R238 (#732, #737, D542): the real-user scenario `submodule` in tools/l3-suite.sh (L3,
# the real Claude Code TUI): a small project with one git submodule (a repository kept
# inside a folder of another; the outer project stores only a pointer, one commit id, to
# it) whose file a plan changes. The user types /vbw:vibe and answers with the
# recommendation through plan, build, proof and ship. Judged in git and the record, never
# on screen: the plan's commit landed in the submodule with its VBW-Plan trailer, the
# project's pointer to the submodule did not move (#737's design, docs/workflows.md
# 'Submodules'), the proof ran the check inside the submodule from the clean copy, and a
# file the user had staged in each repository is still staged and uncommitted. As in
# tests/l3-mapnotrun.bats these tests do not run Claude Code (L1): they hold the
# scenario's structure, and its committed result once a run wrote one, to facts.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }
seed() { sed -n '/^submodule_seed()/,/^}/p' "$SUITE"; }

@test "R238: the submodule scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_submodule()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw submodule
  sed -n '1,20p' "$SUITE" | grep -qw submodule
}

@test "R238: it seeds one submodule on a branch with git submodule add, a check inside it, and a staged uncommitted file in each repository" {
  [ -n "$(body submodule)" ]
  body submodule | grep -q 'result_write submodule '
  body submodule | grep -qi 'fixture='
  [ -n "$(seed)" ] || { echo "no submodule_seed function"; false; }
  seed | grep -q 'git submodule add' || { echo "the seed does not add a submodule"; false; }
  seed | grep -qE 'sub/greet\.sh|greet\.sh' || { echo "the seed has no greet.sh in the submodule"; false; }
  seed | grep -qF 'test.sh' || { echo "the seed has no test inside the submodule"; false; }
  seed | grep -qF 'show-toplevel' || { echo "the seeded test does not print its git toplevel"; false; }
  seed | grep -qF 'sh sub/test.sh' || { echo "the spec does not name the check inside the submodule"; false; }
  [ "$(seed | grep -cE 'git (-C [^ ]+ )?add ')" -ge 2 ] || { echo "the seed does not stage a file in each repository"; false; }
  ! seed | grep -qE 'detach|--detach' || { echo "the submodule is detached"; false; }
}

@test "R238: it judges the plan's commit in the submodule, the unmoved pointer, the check run in the clean copy's submodule and the staged files, in git and the record, never on screen" {
  body submodule | grep -qF 'VBW-Plan: ' || { echo "the plan's commit trailer is not judged"; false; }
  body submodule | grep -qF -- '--show-toplevel' || { echo "the check's toplevel is not judged"; false; }
  body submodule | grep -qF 'git status' || { echo "git status is not judged"; false; }
  body submodule | grep -qF '.vbw/runtime/proof' || { echo "the clean copy's path is not judged"; false; }
  body submodule | grep -qF 'common_checks' || { echo "common_checks is not run"; false; }
  if body submodule | grep -qE 'screen \|.*grep'; then echo "judged on screen text"; false; fi
  local k
  for k in plan_commit_in_submodule pointer_unmoved check_ran_in_copy_submodule staged_files_untouched; do
    body submodule | grep -qF "$k" || { echo "fact $k is not judged"; false; }
  done
  for k in nested detached 'both repositories' 'vbw auto'; do
    body submodule | grep -qiF "$k" || { echo "not_tested does not name: $k"; false; }
  done
}

@test "R238: docs/proof.md names the submodule scenario with what it judges, where mapnotrun is named" {
  grep -n 'mapnotrun' "$REPO_ROOT/docs/proof.md" > /dev/null || { echo "docs/proof.md no longer names mapnotrun"; false; }
  grep -qE '`?submodule`? scenario|scenario `?submodule`?' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not name the submodule scenario"; false; }
  grep -i 'submodule' "$REPO_ROOT/docs/proof.md" | grep -qiE 'pointer|VBW-Plan|staged' || { echo "docs/proof.md does not say what the scenario judges"; false; }
}

@test "R238: a committed result of the submodule scenario, when there is one, is labelled honestly and states the four facts true" {
  local f="$RESULTS/submodule.json"
  # What a run will write is held to the same label before any result exists.
  sed -n '/^result_write()/,/^}/p' "$SUITE" | grep -qF 'evidence_level: "L3"' || { echo "result_write does not label results L3"; false; }
  body submodule | grep -qE 'result_write submodule "\$fixture" "\$\{cost_usd:-0\}" "\$passed"' || { echo "the scenario does not write fixture, cost and passed"; false; }
  [ -f "$f" ] || skip "no submodule result committed yet: a run writes it"
  jq -e '.scenario == "submodule" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)
    and .facts.plan_commit_in_submodule == true and .facts.pointer_unmoved == true
    and .facts.check_ran_in_copy_submodule == true and .facts.staged_files_untouched == true
    and (.facts | (.plan_commit // .submodule_commit // .commit_ids) | type == "string" or type == "object" or type == "array")' "$f"
}
