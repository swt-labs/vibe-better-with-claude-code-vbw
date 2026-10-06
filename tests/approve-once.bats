#!/usr/bin/env bats
# R79 (docs/proof.md): the test-file edits made while building a phase are
# approved together once, before the phase is proved, instead of one approval
# for each edit. While only the bytes of check files differ from what was
# approved, vbw check and the build go on (the files are named as waiting);
# vbw next asks for the one approval just before proof, and vbw prove stops
# and names the files that wait. A change to the contract's structure
# (requirements, checks, plans) still needs approval first. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/receipt.sh"], files:["tests/receipt.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"planned"},
                {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["src/receipt.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

edit_record() { jq "$1" .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json; }

# built: both plans done, the work committed.
built() {
  printf 'paid\n' > src/pay.txt
  printf 'sent\n' > src/receipt.txt
  git add src && git commit -q -m "feat: built"
  edit_record '.plans |= map(.status = "done")'
}

@test "R79: while only check-file bytes differ from what was approved, the build goes on" {
  printf '# a Dev-reviewed tweak\n' >> tests/pay.sh
  vbw_run next --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1","P1.2"]' || { echo "$output"; false; }
}

@test "R79: vbw check still runs, and names the test files that wait for approval" {
  printf 'paid\n' > src/pay.txt
  printf '# a tweak\n' >> tests/pay.sh
  vbw_run check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"tests/pay.sh"* ]]
  [[ "$output" == *"waiting for approval"* ]]
}

@test "R79: the one approval is asked for before the phase is proved, naming every edited test file" {
  built
  printf '# tweak 1\n' >> tests/pay.sh
  printf '# tweak 2\n' >> tests/receipt.sh
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve" and .gate == true and .detail.files == ["tests/pay.sh","tests/receipt.sh"]' || { echo "$output"; false; }
  echo "$output" | jq -e '.instruction | contains("tests/pay.sh") and contains("tests/receipt.sh")' || { echo "$output"; false; }
}

@test "R79: proof stops and says which test files are waiting; nothing is proved" {
  built
  printf '# tweak 1\n' >> tests/pay.sh
  printf '# tweak 2\n' >> tests/receipt.sh
  vbw_run prove
  [ "$status" -ne 0 ]
  [[ "$output" == *"waiting for approval"* ]]
  [[ "$output" == *"tests/pay.sh"* ]]
  [[ "$output" == *"tests/receipt.sh"* ]]
  jq -e '.evidence == null' .vbw/record.json
}

@test "R79: one approval covers all the edits, and the proof then runs" {
  built
  printf '# tweak 1\n' >> tests/pay.sh
  printf '# tweak 2\n' >> tests/receipt.sh
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true and (.evidence.checks | keys) == ["C1","C2"]' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action != "approve"'
}

@test "R79: a change to the contract's structure still needs approval before anything is built" {
  edit_record '.checks[0].run = ["sh","tests/pay.sh","extra"]'
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve" and .gate == true' || { echo "$output"; false; }
  vbw_run check C1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not approved"* ]]
}

@test "R79: a contract that was never approved still needs approval first, whatever its files" {
  rm -f "$(git rev-parse --git-common-dir)/vbw/consent.json"
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve" and .gate == true' || { echo "$output"; false; }
  vbw_run check C1
  [ "$status" -ne 0 ]
}
