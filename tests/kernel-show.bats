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
  [[ "$output" == *"rigor | qa"* ]]
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

@test "show decisions lists each decision with its reason" {
  vbw_run show decisions
  [[ "$output" == *"no decisions recorded yet"* ]]
  "$VBW" decide "Stripe for payments" "the team knows it" > /dev/null
  "$VBW" decide "No dark mode yet" > /dev/null
  vbw_run show decisions
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "D1 Stripe for payments (why: the team knows it)" ]
  [ "${lines[1]}" = "D2 No dark mode yet" ]
}

@test "show requirements lists proof, status, milestone, and whether the work is built" {
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone:"M1"},
                       {id:"R2", text:"Looks right", proof:"human", status:"open", milestone:"M1"}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone:"M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["a"], after:[], status:"done"},
                  {id:"P1.2", phase:"P1", title:"Look", reqs:["R2"], files:["b"], after:[], status:"planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run show requirements
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "R1 [auto, proven] Pay (M1, built)" ]
  [ "${lines[1]}" = "R2 [human, open] Looks right (M1)" ]
}

@test "show phase and contract print a phase's tier and reasons, and nothing for a phase without one" {
  vbw_run show phase P1
  [[ "$output" != *"tier:"* ]]
  vbw_run show contract
  [[ "$output" != *"phases:"* ]]
  jq '.phases[0] += {tier:"standard", predicted:"express", reasons:["requirements: 2","risk: none"]}' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run show phase P1
  [[ "$output" == *"tier: standard (predicted express)"* ]]
  [[ "$output" == *"  - risk: none"* ]]
  vbw_run show contract
  [[ "$output" == *"  P1 standard: requirements: 2; risk: none"* ]]
}

@test "show req prints a requirement's rules, and show contract --changes reports rule changes" {
  set_rules() { jq --argjson r "$1" '.requirements[0].rules = $r | .checks |= (if any(.[]; .id == "C2") then . else . + [{id:"C2", req:"R1", run:["true"]}] end)' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json; }
  set_rules '[{"text": "A payment succeeds", "check": "C1"}]'
  vbw_run show req R1
  [[ "$output" == *"rule: A payment succeeds -> C1"* ]]
  vbw_run show contract
  [[ "$output" == *"R1 [auto] Pay by card"*"rule: A payment succeeds -> C1"* ]]
  # The snapshot an approval would have taken.
  jq -c '{requirements: (.requirements | map({key: .id, value: ({text, proof} + (if has("rules") then {rules} else {} end))}) | from_entries),
          checks: (.checks | map({key: .id, value: .}) | from_entries),
          plans: (.plans | map({key: .id, value: del(.status, .note)}) | from_entries),
          commands: .commands, files: {}}' .vbw/record.json > .vbw/runtime/approved-contract.json
  set_rules '[{"text": "A payment succeeds", "check": "C2"}, {"text": "Paying twice is refused", "check": "C1"}]'
  vbw_run show contract --changes
  [[ "$output" == *"changed rule R1: A payment succeeds -> C2 (was C1)"* ]]
  [[ "$output" == *"added rule R1: Paying twice is refused -> C1"* ]]
  set_rules '[]'
  vbw_run show contract --changes
  [[ "$output" == *"removed rule R1: A payment succeeds"* ]]
}

@test "show contract lists the saved test results folders, and --changes names a changed list" {
  # The snapshot an approval would have taken, with results only when present.
  snapshot() {
    jq -c '{requirements: (.requirements | map({key: .id, value: ({text, proof} + (if has("rules") then {rules} else {} end))}) | from_entries),
            checks: (.checks | map({key: .id, value: .}) | from_entries),
            plans: (.plans | map({key: .id, value: del(.status, .note)}) | from_entries),
            commands: .commands, files: {}} + (if .project.results then {results: .project.results} else {} end)' \
      .vbw/record.json > .vbw/runtime/approved-contract.json
  }
  set_results() { jq "$1" .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json; }
  snapshot
  vbw_run show contract --changes
  [[ "$output" == *"no changes since the last approval"* ]]
  set_results '.project.results = ["results/"]'
  vbw_run show contract
  [[ "$output" == *"saved test results folders: results/"* ]]
  vbw_run show contract --changes
  [[ "$output" == *"saved test results folders: results/ (was none)"* ]]
  snapshot
  set_results '.project.results = ["results/", "reports/"]'
  vbw_run show contract --changes
  [[ "$output" == *"saved test results folders: results/, reports/ (was results/)"* ]]
  snapshot
  set_results '.project |= del(.results)'
  vbw_run show contract
  [[ "$output" != *"saved test results folders"* ]]
  vbw_run show contract --changes
  [[ "$output" == *"saved test results folders: none (was results/, reports/)"* ]]
}
