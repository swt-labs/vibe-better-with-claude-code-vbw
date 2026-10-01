#!/usr/bin/env bats
# vbw show: human views rendered from the record and git trailers.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  jq '.requirements = [
        {id:"R1", text:"Pay by card", proof:"auto", status:"proven", milestone: "M1"},
        {id:"R2", text:"Feels trustworthy", proof:"human", status:"open", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["npm","test","--","tests/pay test.js"], files:["tests/pay test.js"]}]
      | .phases = [{id:"P1", title:"Payments", reqs:["R1","R2"], milestone: "M1"}]
      | .plans = [
          {id:"P1.1", phase:"P1", title:"Card form", reqs:["R1"], files:["src/pay.js"], after:[], status:"done"},
          {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["src/receipt.js"], after:["P1.1"], status:"planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  mkdir -p src && printf 'pay\n' > src/pay.js
  "$VBW" commit P1.1 "feat(pay): card form" > /dev/null
}

teardown() { vbw_teardown; }

@test "show roadmap lists phases and plans with status and dependencies" {
  vbw_run show roadmap
  [ "$status" -eq 0 ]
  [[ "$output" == *"M1 First milestone"* ]]
  [[ "$output" == *"P1 Payments [building]"* ]]
  [[ "$output" == *"P1.1 Card form [done]"* ]]
  [[ "$output" == *"P1.2 Receipt [planned] after P1.1"* ]]
}

@test "show phase lists its requirements and plans with files" {
  vbw_run show phase P1
  [ "$status" -eq 0 ]
  [[ "$output" == *"R1 [auto, proven] Pay by card"* ]]
  [[ "$output" == *"R2 [human, open] Feels trustworthy"* ]]
  [[ "$output" == *"src/receipt.js"* ]]
}

@test "show req lists its checks, plans and commits from trailers" {
  vbw_run show req R1
  [ "$status" -eq 0 ]
  [[ "$output" == *"R1 [auto, proven] Pay by card"* ]]
  [[ "$output" == *"C1 npm test -- 'tests/pay test.js' [protects tests/pay test.js]"* ]]
  [[ "$output" == *"P1.1"* ]]
  [[ "$output" == *"$(git rev-parse --short HEAD) feat(pay): card form"* ]]
}

@test "show evidence says when nothing has been proved yet" {
  vbw_run show evidence
  [ "$status" -eq 0 ]
  [[ "$output" == *"no proof run yet"* ]]
}

@test "unknown views and ids are errors" {
  vbw_run show phase P9
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown phase P9"* ]]
  vbw_run show req R9
  [ "$status" -eq 1 ]
  vbw_run show nonsense
  [ "$status" -eq 2 ]
}

@test "show req matches requirement ids exactly (R1 is not R12)" {
  jq '.requirements += [{id:"R12", text:"Refunds", proof:"auto", status:"open", milestone: "M1"}]
      | .plans += [{id:"P1.3", phase:"P1", title:"Refund", reqs:["R12"], files:["src/refund.js"], after:[], status:"planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r2.json" && cp "$TEST_ROOT/r2.json" .vbw/record.json
  printf 'refund\n' > src/refund.js
  "$VBW" commit P1.3 "feat(pay): refunds" > /dev/null
  vbw_run show req R1
  [[ "$output" != *"refunds"* ]]
  vbw_run show req R12
  [[ "$output" == *"refunds"* ]]
}

@test "a phase's status is derived from its plans" {
  jq '.plans[1].status = "done"' .vbw/record.json > "$TEST_ROOT/d.json" && cp "$TEST_ROOT/d.json" .vbw/record.json
  vbw_run show roadmap
  [[ "$output" == *"P1 Payments [built]"* ]]
  jq '.plans[].status = "planned"' .vbw/record.json > "$TEST_ROOT/d.json" && cp "$TEST_ROOT/d.json" .vbw/record.json
  vbw_run show phase P1
  [[ "$output" == *"P1 Payments [planned]"* ]]
}
