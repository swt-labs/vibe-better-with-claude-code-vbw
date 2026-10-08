#!/usr/bin/env bats
# R113 (L1): VBW's own files under .vbw/ (the spec, the record) never make QA
# check a passed phase again, even when a plan lists one of them; a change to
# the phase's other files still does.

load helper
load qa-recheck-helper
load qa-skip-helper

setup() {
  qa_base 1
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Part", reqs: ["R1"], goal: "The part works", criteria: ["the part file says its name"], tier: "standard"}],
           plans: [{id: "P1.1", phase: "P1", title: "Write the part", reqs: ["R1"], files: ["src/p1.txt", ".vbw/spec.md"], after: [], tasks: ["write part one and name it in the spec"]}],
           checks: [{id: "C1", req: "R1", run: ["sh", "tests/p1.sh"], files: ["tests/p1.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'part1\n' > src/p1.txt
  "$VBW" commit P1.1 "feat(part): part one" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove --full > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
}
teardown() { vbw_teardown; }

@test "R113: an edit to .vbw/spec.md, listed in the plan, does not list the passed phase again" {
  printf '\n## Notes\n\nA note.\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add .vbw/spec.md && git commit -q -m "docs(spec): a note"
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c '.qa.recheck'; false; }
  [ "$(standing)" = '["P1"]' ]
}

@test "R113: a change to the phase's own source file still lists it again" {
  printf 'part1\n# more\n' > src/p1.txt
  git add src/p1.txt && git commit -q -m "feat(part): more"
  [ "$(rechecked)" = '["P1"]' ] || { next_json | jq -c '.qa.recheck'; false; }
}
