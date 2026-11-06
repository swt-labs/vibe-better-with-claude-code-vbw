#!/usr/bin/env bats
# #735: the real-user scenario `testforms` in tools/l3-suite.sh (L3, the real
# Claude Code TUI): a monorepo with two subprojects, each with a test runner of
# its own that must start in its subproject, and one named test-file form per
# subproject with its dir, reaches a passed proof in which each subproject's test
# file ran with its own form. Judged in the record, never on screen text. These
# tests do not run Claude Code (L1): they hold the scenario's structure, and run
# its seed against the kernel.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "#735: the testforms scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_testforms()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw testforms
  sed -n '1,20p' "$SUITE" | grep -qw testforms
}

@test "#735: it judges the record's evidence, states each fact, and never reads the screen" {
  local k
  body testforms | grep -q 'result_write testforms '
  body testforms | grep -qF '.evidence.test_files'
  for k in proof_passed forms_ran command_names_forms second_proof_reused_all; do body testforms | grep -qF "$k"; done
  if body testforms | grep -qE 'screen \|.*grep'; then false; fi
}

@test "#735: its seed gives an approved contract with one form per subproject, each with its dir" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  # The seed function alone, from the suite (bash 3.2 cannot source a process substitution).
  sed -n '/^testforms_seed()/,/^}/p' "$SUITE" > "$TEST_ROOT/seed.sh"
  # shellcheck disable=SC1091 # written just above
  . "$TEST_ROOT/seed.sh"
  testforms_seed
  jq -e '.test_files == [{name: "web", dir: "apps/web", run: ["sh", "run.sh", "{file}"], files: ["apps/web/tests/*.sh"]},
    {name: "mob", dir: "apps/mob", run: ["sh", "run.sh", "{file}"], files: ["apps/mob/tests/*.sh"]}]' .vbw/record.json
  run "$VBW" show contract
  [[ "$output" != *"NOT APPROVED"* ]] || { echo "$output"; false; }
  vbw_teardown
}
