#!/usr/bin/env bats
# R129 (L1): vbw plan block refuses a plan that is done, with a message that
# says the plan is already done, and the record is byte-for-byte unchanged. A
# planned or building plan is still marked blocked with its reason, and an
# unknown plan id is still refused with nothing changed.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "Pay", criteria: ["pay"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Form", reqs: ["R1"], files: ["src/a.js"], after: [], tasks: ["form"]},
            {id: "P1.2", phase: "P1", title: "Submit", reqs: ["R1"], files: ["src/b.js"], after: [], tasks: ["submit"]},
            {id: "P1.3", phase: "P1", title: "Receipt", reqs: ["R1"], files: ["src/c.js"], after: [], tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["true"], files: []}],
    rules: [{req: "R1", text: "pays", check: "C1"}]}' | "$VBW" apply > /dev/null
  jq '(.plans[] | select(.id == "P1.1")).status = "done" | (.plans[] | select(.id == "P1.2")).status = "building"' \
    .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
}

teardown() { vbw_teardown; }

@test "R129: blocking a plan that is done is refused with a message saying it is already done, and the record is unchanged" {
  local before
  before=$(cksum < .vbw/record.json)
  run "$VBW" plan block P1.1 "the API key is missing" < /dev/null
  [ "$status" -ne 0 ] || { echo "accepted: $output"; false; }
  printf '%s' "$output" | grep -qi 'already done' || { echo "$output"; false; }
  [[ "$output" == *P1.1* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "the record changed"; false; }
}

@test "R129: a planned or building plan is still marked blocked with its reason" {
  run "$VBW" plan block P1.3 "waiting for the design" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.plans[] | select(.id == "P1.3") | .status == "blocked" and .note == "waiting for the design"' .vbw/record.json
  run "$VBW" plan block P1.2 "the API key is missing" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.plans[] | select(.id == "P1.2") | .status == "blocked" and .note == "the API key is missing"' .vbw/record.json
  jq -e '.plans[] | select(.id == "P1.1") | .status == "done"' .vbw/record.json
}

@test "R129: blocking a plan id that does not exist is refused and nothing changes" {
  local before
  before=$(cksum < .vbw/record.json)
  run "$VBW" plan block P9.9 "nothing" < /dev/null
  [ "$status" -ne 0 ] || { echo "accepted: $output"; false; }
  [[ "$output" == *"P9.9"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}
