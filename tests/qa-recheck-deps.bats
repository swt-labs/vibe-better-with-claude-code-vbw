#!/usr/bin/env bats
# R49 (docs/proof.md): a phase is also checked again when a phase it builds on
# was checked again because its inputs changed, even if its own inputs did not.
# A phase builds on another when one of its plans comes after a plan of the
# other. The rule is transitive and survives an interrupted QA round.

load helper
load qa-recheck-helper

teardown() { vbw_teardown; }

@test "R49: a phase that builds on a re-checked phase is checked again though its own inputs did not change" {
  qa_project 2 chain
  qa_pass P1 P2
  qa_touch 1
  [ "$(listed)" = '["P1","P2"]' ]
  next_json | jq -e '.qa.recheck.P2 | any(.[]; contains("P1"))'
}

@test "R49: it is transitive: A changes, B builds on A, C builds on B, and all three are checked again" {
  qa_project 3 chain
  qa_pass P1 P2 P3
  qa_touch 1
  [ "$(listed)" = '["P1","P2","P3"]' ]
  next_json | jq -e '.qa.recheck.P3 | length > 0'
}

@test "R49: a change in the middle checks it and what builds on it, not what it builds on" {
  qa_project 3 chain
  qa_pass P1 P2 P3
  qa_touch 2
  [ "$(listed)" = '["P2","P3"]' ]
  next_json | jq -e '.qa.standing == ["P1"]'
}

@test "R49: a dependency on a phase that is not re-checked adds nothing" {
  qa_project 3 chain
  qa_pass P1 P2 P3
  qa_touch 3
  [ "$(listed)" = '["P3"]' ]
  next_json | jq -e '.qa.standing == ["P1","P2"]'
}

@test "R49: a dependent that has itself never passed is already included and listed once" {
  qa_project 3 chain
  qa_pass P1 P3
  qa_touch 1
  [ "$(listed)" = '["P1","P2","P3"]' ]
  next_json | jq -e '.qa.recheck.P2 | length >= 1'
}

@test "R49: when the changed phase passes again but its dependent was not recorded, the dependent is still checked" {
  qa_project 2 chain
  qa_pass P1 P2
  qa_touch 1
  qa_pass P1
  [ "$(listed)" = '["P2"]' ]
  next_json | jq -e '.qa.recheck.P2 | any(.[]; contains("P1"))'
}

@test "R49: when both are checked again, every pass stands and the milestone can ship" {
  qa_project 2 chain
  qa_pass P1 P2
  qa_touch 1
  qa_pass P1 P2
  [ "$(listed)" = '[]' ]
  next_json | jq -e '.action == "ship" and .qa.standing == ["P1","P2"]'
}

@test "R49: phases that build on each other in a cycle do not hang or crash, and the kernel names them" {
  qa_base 2
  jq -nc '{phases: [{id: "P1", title: "One", reqs: ["R1"], tier: "standard"}, {id: "P2", title: "Two", reqs: ["R2"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "a", reqs: ["R1"], files: ["src/p1.txt"], after: ["P2.1"]},
            {id: "P1.2", phase: "P1", title: "b", reqs: ["R1"], files: ["src/p1b.txt"], after: []},
            {id: "P2.1", phase: "P2", title: "c", reqs: ["R2"], files: ["src/p2.txt"], after: []},
            {id: "P2.2", phase: "P2", title: "d", reqs: ["R2"], files: ["src/p2b.txt"], after: ["P1.2"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/p1.sh"], files: ["tests/p1.sh"]}, {id: "C2", req: "R2", run: ["sh", "tests/p2.sh"], files: ["tests/p2.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  local f
  for f in p1 p1b p2 p2b; do printf 'x\n' > "src/$f.txt"; done
  printf 'part1\n' > src/p1.txt
  printf 'part2\n' > src/p2.txt
  git add -A && git commit -q -m "feat: all"
  edit_record '.plans |= map(.status = "done")'
  "$VBW" prove > /dev/null
  qa_pass P1 P2
  printf 'extra\n' >> src/p1.txt
  git add src/p1.txt && git commit -q -m "fix: touch"
  "$VBW" prove > /dev/null
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.qa.problems | length > 0 and any(.[]; contains("P1") and contains("P2"))'
  vbw_run show qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"P1"* && "$output" == *"P2"* ]]
}

@test "R49: a plan that comes after a plan or a phase that does not exist is reported by name, not silently dropped" {
  qa_project 2 chain
  edit_record '(.plans[] | select(.id == "P2.1")).after = ["P9.9"]'
  vbw_run next --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"P9.9"* ]]
  edit_record '(.plans[] | select(.id == "P2.1")).after = ["P1.1"] | (.plans[] | select(.id == "P2.1")).phase = "P9"'
  vbw_run next --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"P9"* ]]
}
