#!/usr/bin/env bats
# vbw next: the lifecycle decision table in docs/next.md, row by row.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  BASE="$TEST_ROOT/base.json"
  # A fully built and proven milestone: every row's condition is false, so each
  # test flips exactly the fields its row needs.
  jq '.requirements = [
        {id:"R1", text:"Pay", proof:"auto", checks:["C1"], status:"proven"},
        {id:"R2", text:"Trustworthy", proof:"human", checks:[], status:"accepted"}]
      | .checks = [{id:"C1", req:"R1", kind:"spec", path:".vbw/checks/C1.json"}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], status:"built"}]
      | .plans = [
          {id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"},
          {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["b.js"], after:["P1.1"], status:"done"},
          {id:"P1.3", phase:"P1", title:"Email", reqs:["R1"], files:["c.js"], after:[], status:"done"}]
      | .contract = {hash: ("a" * 64), approved_at: "2026-10-01T09:00:00Z"}' \
    .vbw/record.json > "$BASE"
}

teardown() { vbw_teardown; }

# next_after FILTER: apply FILTER to the base record and print vbw next --json.
next_after() {
  jq "$1" "$BASE" > .vbw/record.json
  "$VBW" next --json < /dev/null
}

@test "row 1: a shipped milestone asks for the next milestone" {
  run next_after '.milestone.status = "shipped"'
  echo "$output" | jq -e '.action == "milestone" and .gate == true'
}

@test "row 2: no requirements asks for the spec" {
  run next_after '.requirements = [] | .checks = [] | .phases = [] | .plans = [] | .contract = {hash:null, approved_at:null}'
  echo "$output" | jq -e '.action == "spec" and .gate == true'
}

@test "row 3: requirements without checks or phases need planning" {
  run next_after '.checks = [] | .requirements[0].checks = [] | .contract = {hash:null, approved_at:null}'
  echo "$output" | jq -e '.action == "plan" and .gate == false'
  run next_after '.phases = [] | .plans = []'
  echo "$output" | jq -e '.action == "plan"'
}

@test "row 4: an unapproved contract is a human gate" {
  run next_after '.contract = {hash:null, approved_at:null}'
  echo "$output" | jq -e '.action == "approve" and .gate == true'
}

@test "row 5: a blocked plan is a human gate naming it" {
  run next_after '.plans[1].status = "blocked"'
  echo "$output" | jq -e '.action == "unblock" and .gate == true and .detail.plans == ["P1.2"]'
}

@test "row 6: build the ready wave only (dependencies respected)" {
  run next_after '.plans |= map(.status = "planned")'
  echo "$output" | jq -e '.action == "build" and .gate == false and .detail.plans == ["P1.1","P1.3"]'
  run next_after '.plans[1].status = "planned"'
  echo "$output" | jq -e '.detail.plans == ["P1.2"]'
}

@test "rows 7 and 8: escalated fixes gate, open fixes are worked" {
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:3, status:"escalated", note:"C1"}]'
  echo "$output" | jq -e '.action == "escalate" and .gate == true and .detail.fixes == ["F1"]'
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:1, status:"open", note:"C1"}]'
  echo "$output" | jq -e '.action == "fix" and .gate == false and .detail.fixes == ["F1"]'
}

@test "row 9: unproven auto requirements are proved (including after a fix)" {
  run next_after '.requirements[0].status = "open"'
  echo "$output" | jq -e '.action == "prove" and .gate == false'
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:1, status:"fixed", note:"C1"}]'
  echo "$output" | jq -e '.action == "prove"'
}

@test "row 10: open human requirements go to acceptance" {
  run next_after '.requirements[1].status = "open"'
  echo "$output" | jq -e '.action == "accept" and .gate == true and .detail.requirements == ["R2"]'
}

@test "row 11: a rejected human requirement becomes a fix" {
  run next_after '.requirements[1].status = "rejected"'
  echo "$output" | jq -e '.action == "fix" and .gate == false and .detail.requirements == ["R2"]'
}

@test "row 12: everything proven and accepted is ready to ship" {
  run next_after '.'
  echo "$output" | jq -e '.action == "ship" and .gate == true'
}

@test "the human form prints one instruction line" {
  jq '.contract = {hash:null, approved_at:null}' "$BASE" > .vbw/record.json
  vbw_run next
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"approve"* ]]
}
