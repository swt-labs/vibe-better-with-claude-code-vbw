#!/usr/bin/env bats
# vbw show: human views rendered from the record and git trailers. A
# requirement's commits are those of the record's own history (docs/proof.md,
# "Whose commits VBW judges"): an older commit whose VBW-Req trailer names an
# id the record uses again is an old roadmap's, not the requirement's.

load helper
load fixture-helper

# Hand edits of the record keep the protected list in step with the checks (R150), as the approved check files do.
KEEP_PROTECTED='if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end'

# The planned payments project with P1.1 committed, built once per file.
setup_file() { fixture_build show show_project; }
setup() { fixture_copy show; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

show_project() {
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
    .vbw/record.json > "$TEST_ROOT/r.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r.json" > .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  mkdir -p src && printf 'pay\n' > src/pay.js
  "$VBW" commit P1.1 "feat(pay): card form" > /dev/null
}

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
    .vbw/record.json > "$TEST_ROOT/r2.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r2.json" > .vbw/record.json
  printf 'refund\n' > src/refund.js
  "$VBW" commit P1.3 "feat(pay): refunds" > /dev/null
  vbw_run show req R1
  [[ "$output" != *"refunds"* ]]
  vbw_run show req R12
  [[ "$output" == *"refunds"* ]]
}

@test "show req leaves out an old roadmap's commit naming the same id, older than the record" {
  # A new root commit grafted under the first one (git replace), so every
  # commit the record names keeps its hash.
  local root old
  root=$(git rev-list --max-parents=0 HEAD)
  old=$(git commit-tree "$(git mktree < /dev/null)" -m "feat(pay): an old roadmap's card form" -m "VBW-Req: R1")
  git replace --graft "$root" "$old"
  git log --format='%(trailers:key=VBW-Req,valueonly)' | grep -qx 'R1'
  vbw_run show req R1
  [[ "$output" == *"feat(pay): card form"* ]] || { echo "$output"; false; }
  [[ "$output" != *"an old roadmap's card form"* ]] || { echo "$output"; false; }
}

@test "a phase's status is derived from its plans" {
  jq '.plans[1].status = "done"' .vbw/record.json > "$TEST_ROOT/d.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/d.json" > .vbw/record.json
  vbw_run show roadmap
  [[ "$output" == *"P1 Payments [built]"* ]]
  jq '.plans[].status = "planned"' .vbw/record.json > "$TEST_ROOT/d.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/d.json" > .vbw/record.json
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
    .vbw/record.json > "$TEST_ROOT/r.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r.json" > .vbw/record.json
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
  jq '.phases[0] += {tier:"standard", predicted:"express", reasons:["requirements: 2","risk: none"]}' .vbw/record.json > "$TEST_ROOT/r.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r.json" > .vbw/record.json
  vbw_run show phase P1
  [[ "$output" == *"tier: standard (predicted express)"* ]]
  [[ "$output" == *"  - risk: none"* ]]
  vbw_run show contract
  [[ "$output" == *"  P1 standard: requirements: 2; risk: none"* ]]
}

@test "show req prints a requirement's rules, and show contract --changes reports rule changes" {
  set_rules() { jq --argjson r "$1" '.requirements[0].rules = $r | .checks |= (if any(.[]; .id == "C2") then . else . + [{id:"C2", req:"R1", run:["true"]}] end)' .vbw/record.json > "$TEST_ROOT/r.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r.json" > .vbw/record.json; }
  set_rules '[{"text": "A payment succeeds", "check": "C1"}, {"text": "Cash is refused", "check": "C1", "retired": "cash is taken now"}]'
  vbw_run show req R1
  [[ "$output" == *"rule R1.1: A payment succeeds -> C1"*"rule R1.2 retired: Cash is refused (cash is taken now)"* ]] || { echo "$output"; false; }
  vbw_run show contract
  [[ "$output" == *"R1 [auto] Pay by card"*"rule R1.1: A payment succeeds -> C1"* ]] || { echo "$output"; false; }
  set_rules '[{"text": "A payment succeeds", "check": "C1"}]'
  # The snapshot an approval would have taken.
  jq -c '{requirements: (.requirements | map({key: .id, value: ({text, proof} + (if has("rules") then {rules} else {} end))}) | from_entries),
          checks: (.checks | map({key: .id, value: .}) | from_entries),
          plans: (.plans | map({key: .id, value: del(.status, .note)}) | from_entries),
          commands: .commands, files: {}}' .vbw/record.json > .vbw/runtime/approved-contract.json
  set_rules '[{"text": "A payment succeeds", "check": "C2"}, {"text": "Paying twice is refused", "check": "C1"}]'
  vbw_run show contract --changes
  [[ "$output" == *"changed rule R1.1: A payment succeeds -> C2 (was C1)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"added rule R1.2: Paying twice is refused -> C1"* ]] || { echo "$output"; false; }
  # A rule found by its words in another place has moved, not changed.
  set_rules '[{"text": "Paying twice is refused", "check": "C1"}, {"text": "A payment succeeds", "check": "C1"}]'
  vbw_run show contract --changes
  [[ "$output" == *"moved rule R1.2: A payment succeeds (was R1.1)"* ]] && [[ "$output" == *"added rule R1.1: Paying twice is refused -> C1"* ]] || { echo "$output"; false; }
  [[ "$output" != *"reworded"* ]] || { echo "$output"; false; }
  set_rules '[{"text": "A card payment succeeds", "check": "C1"}]'
  vbw_run show contract --changes
  [[ "$output" == *"reworded rule R1.1: A payment succeeds -> A card payment succeeds"* ]] && [[ "$output" != *"removed rule"* ]] || { echo "$output"; false; }
  set_rules '[{"text": "A payment succeeds", "check": "C1", "retired": "cards only"}]'
  vbw_run show contract --changes
  [[ "$output" == *"retired rule R1.1: A payment succeeds (cards only)"* ]] || { echo "$output"; false; }
  set_rules '[]'
  vbw_run show contract --changes
  [[ "$output" == *"removed rule R1.1: A payment succeeds"* ]]
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
  set_results() { jq "$1" .vbw/record.json > "$TEST_ROOT/r.json" && jq "$KEEP_PROTECTED" "$TEST_ROOT/r.json" > .vbw/record.json; }
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
  if printf '%s\n' "$output" | grep -q "^saved test results folders"; then echo "$output"; false; fi
  vbw_run show contract --changes
  [[ "$output" == *"saved test results folders: none (was results/, reports/)"* ]]
}
