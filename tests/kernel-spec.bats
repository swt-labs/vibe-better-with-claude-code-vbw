#!/usr/bin/env bats
# vbw spec check|sync|add: the user's spec.md is the source of the requirements
# (docs/proof.md).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

write_spec() {
  printf '# Shop\n\n## Goals\n\n- Sell things\n\n## Requirements\n\n%s\n## Notes\n\n- R99 [auto] not a requirement: outside the section\n' "$1" > .vbw/spec.md
}

@test "the scaffolded spec is valid and has no requirements (the examples are a comment)" {
  vbw_run spec check
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 requirements"* ]]
}

@test "check counts auto and human requirements; notes, prose and comments are ignored" {
  write_spec '- R1 [auto] A visitor can sign up
  They sign up with an email address.
- R2 [human] The landing page feels trustworthy
<!-- - R3 [auto] commented out -->
'
  vbw_run spec check
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 requirements (1 auto, 1 human)"* ]]
}

@test "malformed bullets and duplicate ids are errors with line numbers" {
  write_spec '- R1 [auto] Sign up
- R1 [human] Trust
- R2 auto Missing brackets
- Just a note
'
  vbw_run spec check
  [ "$status" -eq 1 ]
  [[ "$output" == *"line 10: R1 is defined twice"* ]]
  [[ "$output" == *"line 11: expected '- R<n> [auto|human] statement', got: - R2 auto Missing brackets"* ]]
  [[ "$output" == *"line 12: expected"* ]]
}

@test "a spec without a Requirements section is an error" {
  printf '# Shop\n\nJust prose.\n' > .vbw/spec.md
  vbw_run spec check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no '## Requirements' section"* ]]
}

@test "Windows line endings parse the same" {
  printf '# Shop\r\n\r\n## Requirements\r\n\r\n- R1 [auto] Sign up\r\n' > .vbw/spec.md
  vbw_run spec sync
  [ "$status" -eq 0 ]
  jq -e '.requirements == [{id:"R1", text:"Sign up", proof:"auto", status:"open", milestone:"M1"}]' .vbw/record.json
}

@test "sync adds, changes (resetting status) and removes requirements, in spec order" {
  write_spec '- R2 [auto] Pay by card
- R1 [human] Trustworthy
'
  vbw_run spec sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"added R2"* ]] && [[ "$output" == *"added R1"* ]]
  jq -e '[.requirements[].id] == ["R2","R1"]' .vbw/record.json
  jq '.requirements[0].status = "proven"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json

  write_spec '- R2 [auto] Pay by card or wallet
'
  vbw_run spec sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed R2 (status reset to open)"* ]]
  [[ "$output" == *"removed R1"* ]]
  jq -e '.requirements == [{id:"R2", text:"Pay by card or wallet", proof:"auto", status:"open", milestone:"M1"}]' .vbw/record.json
}

@test "sync keeps the status of unchanged requirements" {
  write_spec '- R1 [auto] Pay'
  "$VBW" spec sync > /dev/null
  jq '.requirements[0].status = "proven"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run spec sync
  [ "$status" -eq 0 ]
  jq -e '.requirements[0].status == "proven"' .vbw/record.json
}

@test "removing a requirement removes its checks and the unstarted plans that only served it" {
  write_spec '- R1 [auto] Pay
- R2 [auto] Refund
'
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["true"]}, {id:"C2", req:"R2", run:["true"]}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone:"M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["a"], after:[], status:"planned"},
                  {id:"P1.2", phase:"P1", title:"Refund", reqs:["R2"], files:["b"], after:["P1.1"], status:"planned"},
                  {id:"P1.3", phase:"P1", title:"Both", reqs:["R1","R2"], files:["c"], after:["P1.2"], status:"planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  write_spec '- R1 [auto] Pay'
  vbw_run spec sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed R2 and its checks C2"* ]]
  jq -e '[.checks[].id] == ["C1"] and [.plans[].id] == ["P1.1", "P1.3"]
         and .plans[1].reqs == ["R1"] and .plans[1].after == [] and .phases[0].reqs == ["R1"]' .vbw/record.json
}

@test "removing a requirement whose plan has started is refused, and changes nothing" {
  write_spec '- R1 [auto] Pay
- R2 [auto] Refund
'
  "$VBW" spec sync > /dev/null
  jq '.phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone:"M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Refund", reqs:["R2"], files:["b"], after:[], status:"done"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  cp .vbw/record.json "$TEST_ROOT/before.json"
  write_spec '- R1 [auto] Pay'
  vbw_run spec sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.1 (done) serves only R2"* ]]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "sync refuses an invalid spec and changes nothing" {
  write_spec '- R1 [maybe] Pay'
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run spec sync
  [ "$status" -eq 1 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "add inserts the next id at the end of the section and syncs" {
  write_spec '- R1 [auto] Pay
  a note that belongs to R1
'
  vbw_run spec add human "The receipt   looks right"
  [ "$status" -eq 0 ]
  [[ "$output" == *"- R2 [human] The receipt looks right"* ]]
  [ "$(sed -n 10,11p .vbw/spec.md)" = "  a note that belongs to R1
- R2 [human] The receipt looks right" ]
  grep -q '^## Notes$' .vbw/spec.md
  jq -e '[.requirements[].id] == ["R1","R2"]' .vbw/record.json
}

@test "add never reuses an id still in the record" {
  write_spec '- R1 [auto] Pay
- R5 [auto] Refund
'
  "$VBW" spec sync > /dev/null
  vbw_run spec add auto 'Cancel with a backslash \n and $HOME kept literally'
  [ "$status" -eq 0 ]
  grep -qF -- '- R6 [auto] Cancel with a backslash \n and $HOME kept literally' .vbw/spec.md
}

@test "add into the scaffolded spec keeps the example comment intact" {
  vbw_run spec add auto "A visitor can sign up"
  [ "$status" -eq 0 ]
  vbw_run spec check
  [[ "$output" == *"1 requirements (1 auto, 0 human)"* ]]
  grep -q '^- R2 \[human\] The landing page feels trustworthy$' .vbw/spec.md
}

@test "add rejects bad usage" {
  vbw_run spec add sometimes "x"
  [ "$status" -eq 2 ]
  vbw_run spec add auto "   "
  [ "$status" -eq 2 ]
}
