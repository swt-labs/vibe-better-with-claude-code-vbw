#!/usr/bin/env bats
# R74 (docs/next.md): a blocked or stuck plan never stops unrelated plans from
# being scheduled by vbw next. The blocked plan is reported by name with its
# reason; plans that depend on it stay unscheduled; independent ones are still
# offered. When nothing else can run, the blocked plan is the human gate.
# L1: the decision table on fixture records.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  BASE="$TEST_ROOT/base.json"
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"open", milestone:"M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
      | .plans = [
          {id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"blocked", note:"needs the payment provider key"},
          {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["b.js"], after:[], status:"planned"},
          {id:"P1.3", phase:"P1", title:"Email", reqs:["R1"], files:["c.js"], after:["P1.1"], status:"planned"},
          {id:"P1.4", phase:"P1", title:"Report", reqs:["R1"], files:["d.js"], after:["P1.2"], status:"planned"}]' \
    .vbw/record.json > "$BASE"
}

teardown() { vbw_teardown; }

# next_after FILTER: apply FILTER to the base record, approve its contract and
# print vbw next --json.
next_after() {
  jq "$1" "$BASE" > .vbw/record.json
  vbw_consent_contract
  "$VBW" next --json < /dev/null
}

@test "R74: a blocked plan does not stop an independent plan from being offered" {
  run next_after '.'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.action == "build" and .gate == false and .detail.plans == ["P1.2"]' || { echo "$output"; false; }
}

@test "R74: the blocked plan is reported by name with its reason" {
  run next_after '.'
  echo "$output" | jq -e '.detail.blocked == [{id: "P1.1", note: "needs the payment provider key"}]' || { echo "$output"; false; }
  echo "$output" | jq -e '.instruction | contains("P1.1") and contains("needs the payment provider key")' || { echo "$output"; false; }
}

@test "R74: plans that depend on the blocked plan stay unscheduled, and later waves still wait for their own dependencies" {
  run next_after '.'
  echo "$output" | jq -e '(.detail.plans | index("P1.3")) == null and (.detail.plans | index("P1.4")) == null' || { echo "$output"; false; }
}

@test "R74: once the independent work is done, the blocked plan is the gate and dependents are not offered" {
  run next_after '.plans[1].status = "done" | .plans[3].status = "done"'
  echo "$output" | jq -e '.action == "unblock" and .gate == true and .detail.plans == ["P1.1"]' || { echo "$output"; false; }
}

@test "R74: with no blocked plan the build step names no blocked plans" {
  run next_after '.plans[0].status = "planned" | .plans[0] |= del(.note)'
  echo "$output" | jq -e '.action == "build" and ((.detail.blocked // []) | length) == 0' || { echo "$output"; false; }
}

@test "R74: several blocked plans are all named, each with its reason" {
  run next_after '.plans[1].status = "blocked" | .plans[1].note = "waits for design"'
  echo "$output" | jq -e '.action == "unblock" and .gate == true' || { echo "$output"; false; }
  run next_after '.plans[1].status = "blocked" | .plans[1].note = "waits for design" | .plans += [{id:"P1.5", phase:"P1", title:"Other", reqs:["R1"], files:["e.js"], after:[], status:"planned"}]'
  echo "$output" | jq -e '.action == "build" and .detail.plans == ["P1.5"] and (.detail.blocked | map(.id) | sort) == ["P1.1", "P1.2"]' || { echo "$output"; false; }
}
