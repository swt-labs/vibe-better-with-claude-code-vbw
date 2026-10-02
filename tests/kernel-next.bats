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
        {id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"},
        {id:"R2", text:"Trustworthy", proof:"human", status:"accepted", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone: "M1"}]
      | .plans = [
          {id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"done"},
          {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["b.js"], after:["P1.1"], status:"done"},
          {id:"P1.3", phase:"P1", title:"Email", reqs:["R1"], files:["c.js"], after:[], status:"done"}]' \
    .vbw/record.json > "$BASE"
}

teardown() { vbw_teardown; }

# next_after FILTER [unapproved]: apply FILTER to the base record, approve its
# contract (unless asked not to) with evidence of a passing proof of exactly
# that contract (unless FILTER set evidence), and print vbw next --json.
next_after() {
  jq "$1" "$BASE" > .vbw/record.json
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  # Phases count as verified by QA on that tree unless FILTER says otherwise.
  jq --arg h "$hash" --arg t "$tree" '(if .evidence == null then .evidence = {at: "2026-10-01T09:00:00Z", contract: $h, tree: $t,
      passed: true, checks: {}, commands: {}, scope: []} else . end)
    | .phases |= map(if has("qa") then . else .qa = {result: "pass", tier: "standard", tree: $t, at: "2026-10-01T09:00:00Z"} end)' .vbw/record.json > "$TEST_ROOT/n.json"
  cp "$TEST_ROOT/n.json" .vbw/record.json
  [ "${2:-}" = unapproved ] || vbw_consent_contract
  "$VBW" next --json < /dev/null
}

@test "row 1: a shipped milestone asks for the next milestone" {
  run next_after '.milestone.status = "shipped" | .shipped = [{id: "M1", title: "First milestone", at: "2026-10-01T09:00:00Z"}]'
  echo "$output" | jq -e '.action == "milestone" and .gate == true'
}

@test "row 2: no requirements asks for the spec" {
  run next_after '.requirements = [] | .checks = [] | .phases = [] | .plans = []' unapproved
  echo "$output" | jq -e '.action == "spec" and .gate == true'
}

@test "row 3: requirements without checks or phases need planning" {
  run next_after '.checks = []' unapproved
  echo "$output" | jq -e '.action == "plan" and .gate == false'
  run next_after '.phases = [] | .plans = []'
  echo "$output" | jq -e '.action == "plan"'
}

@test "row 4: an unapproved contract is a human gate" {
  run next_after '.' unapproved
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

@test "rows 7 and 9: escalated fixes gate, open fixes are worked" {
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:3, status:"escalated", note:"C1"}]'
  echo "$output" | jq -e '.action == "escalate" and .gate == true and .detail.fixes == ["F1"]'
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:1, status:"open", note:"C1"}]'
  echo "$output" | jq -e '.action == "fix" and .gate == false and .detail.fixes == ["F1"]'
}

@test "row 10: unproven auto requirements are proved (including after a fix)" {
  run next_after '.requirements[0].status = "open"'
  echo "$output" | jq -e '.action == "prove" and .gate == false'
  run next_after '.requirements[0].status = "failing" | .fixes = [{id:"F1", req:"R1", attempts:1, status:"fixed", note:"C1"}]'
  echo "$output" | jq -e '.action == "prove"'
}

@test "row 11: open human requirements go to acceptance" {
  run next_after '.requirements[1].status = "open"'
  echo "$output" | jq -e '.action == "accept" and .gate == true and .detail.requirements == ["R2"]'
}

@test "row 0: an open run lease comes first (wait for its workflow, or end it)" {
  run next_after '.lease = {run: "build-1", kind: "build", started_at: "2026-10-01T09:00:00Z", files: ["a.js"]}'
  echo "$output" | jq -e '.action == "run" and .gate == false and .detail.lease.run == "build-1"'
}

@test "row 12: everything proven and accepted is ready to ship" {
  run next_after '.'
  echo "$output" | jq -e '.action == "ship" and .gate == true'
}

@test "the human form prints one instruction line" {
  cp "$BASE" .vbw/record.json
  vbw_run next
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *"approve"* ]]
}

@test "row 10: evidence of another contract is stale and must be proved again" {
  run next_after '.evidence = {at: "2026-10-01T09:00:00Z", contract: ("b" * 64), tree: ("c" * 40), passed: true,
                               checks: {}, commands: {}, scope: []}'
  echo "$output" | jq -e '.action == "prove" and .detail.requirements == ["R1"]'
}

@test "row 8: scope violations in current evidence are a human gate" {
  cp "$BASE" .vbw/record.json
  jq --arg h "$(vbw_contract_hash)" --arg t "$(vbw_code_tree)" '.evidence = {at: "2026-10-01T09:00:00Z", contract: $h, tree: $t, passed: false,
      checks: {}, commands: {}, scope: ["abc (P1.1) changed x.js, which is not in the plan"]}' \
    "$BASE" > .vbw/record.json
  vbw_consent_contract
  run "$VBW" next --json
  echo "$output" | jq -e '.action == "scope" and .gate == true and (.detail.violations | length) == 1'
}

@test "approval is read from the clone's consent, never from the record" {
  run next_after '.' unapproved
  echo "$output" | jq -e '.action == "approve"'
  vbw_consent_contract
  run "$VBW" next --json
  echo "$output" | jq -e '.action == "ship"'
  # Any change to the contract withdraws the approval.
  jq '.checks[0].run = ["false"]' .vbw/record.json > "$TEST_ROOT/c.json" && cp "$TEST_ROOT/c.json" .vbw/record.json
  run "$VBW" next --json
  echo "$output" | jq -e '.action == "approve"'
}

@test "row 6: plans that share a file never build in the same wave" {
  run next_after '.plans |= map(.status = "planned") | .plans[2].files = ["a.js", "d.js"]'
  echo "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1"]'
}

@test "row 9: open fixes that share files form one group (one builder), others run alongside" {
  run next_after '.requirements += [{id:"R3", text:"Refund", proof:"auto", status:"failing", milestone:"M1"}]
    | .checks += [{id:"C2", req:"R3", run:["true"]}]
    | .phases[0].reqs += ["R3"]
    | .plans += [{id:"P1.4", phase:"P1", title:"Refund", reqs:["R3"], files:["r.js"], after:[], status:"done"}]
    | .requirements[0].status = "failing"
    | .fixes = [{id:"F1", req:"R1", attempts:0, status:"open", note:"C1"},
               {id:"F2", req:"R3", attempts:0, status:"open", note:"C2"},
               {id:"F3", req:"R1", attempts:0, status:"open", note:"again"}]'
  echo "$output" | jq -e '.action == "fix" and .detail.fixes == ["F1","F2","F3"]
    and (.detail.groups | sort) == [["F1","F3"],["F2"]]'
  # A project command may touch any file: it joins every group.
  run next_after '.commands = {test: ["true"]} | .requirements[0].status = "failing"
    | .fixes = [{id:"F1", req:"R1", attempts:0, status:"open", note:"C1"},
               {id:"F2", command:"test", attempts:0, status:"open", note:"exit 1"}]'
  echo "$output" | jq -e '.detail.groups == [["F1","F2"]]'
}

@test "row 2a: an unconverted VBW 1 plan is offered for conversion before the spec" {
  mkdir .vbw-planning && printf '# Project\n' > .vbw-planning/PROJECT.md
  run next_after '.requirements = [] | .checks = [] | .phases = [] | .plans = []' unapproved
  echo "$output" | jq -e '.action == "convert" and .gate == true'
  run next_after '.requirements = [] | .checks = [] | .phases = [] | .plans = [] | .converted = {from: ".vbw-planning", at: "2026-10-01T09:00:00Z"}' unapproved
  echo "$output" | jq -e '.action == "spec"'
  # Once work has started, an old folder no longer interrupts it.
  run next_after '.'
  echo "$output" | jq -e '.action == "ship"'
}

@test "row 10a: built phases not verified by QA on the proven code go to QA, at the profile's tier" {
  # A verdict on other code (the helper treats a phase without one as verified).
  run next_after '.phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}'
  echo "$output" | jq -e '.action == "qa" and .gate == false and .detail == {phases: ["P1"], tier: "standard"}'
  run next_after '.settings.profile = "quality" | .phases[0].qa = {result: "pass", tier: "deep", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}'
  echo "$output" | jq -e '.action == "qa" and .detail.tier == "deep"'
  # A phase still being built is not verified yet.
  run next_after '.phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"} | .plans[2].status = "blocked" | .plans[2].note = "x"'
  echo "$output" | jq -e '.action == "unblock"'
}

@test "row 10b: a phase QA failed on the proven code is verified again before shipping" {
  local tree
  tree=$(vbw_code_tree)
  # Its findings were closed without a code change: the failed verdict still stands.
  run next_after ".phases[0].qa = {result: \"fail\", tier: \"standard\", tree: \"$tree\", at: \"2026-10-01T09:00:00Z\"}"
  echo "$output" | jq -e '.action == "qa" and .detail.phases == ["P1"]'
}
