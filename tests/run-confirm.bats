#!/usr/bin/env bats
# R78 (docs/workflows.md): after the agents of a build, fix or QA run return,
# `vbw run confirm IDS...` says for each plan, fix or phase whether its state
# or verdict was recorded, and names plainly the ones that were not (exit 1).
# Also: ending a run that is already ended is a quiet no-op (R81: a workflow
# ends its own run, so the router's own end finds nothing open). L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"open", milestone:"M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}, {id:"P2", title:"More", reqs:["R1"], milestone:"M1"}]
      | .plans = [
          {id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:["a.js"], after:[], status:"planned"},
          {id:"P1.2", phase:"P1", title:"Receipt", reqs:["R1"], files:["b.js"], after:[], status:"planned"}]
      | .fixes = [{id:"F1", req:"R1", attempts:0, status:"open", note:"x"}, {id:"F2", req:"R1", attempts:0, status:"open", note:"y"}]' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
}

teardown() { vbw_teardown; }

# said ID TEXT: the output has a line that starts with ID and says TEXT.
said() { printf '%s\n' "$output" | grep -E "^$1[ :].*$2" > /dev/null; }

edit() { jq "$1" .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json; }

@test "R78: after a build, the plans whose Dev recorded done or blocked are confirmed and the others named" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  edit '(.plans[] | select(.id == "P1.1")).status = "done"'
  vbw_run run confirm P1.1 P1.2
  [ "$status" -eq 1 ]
  said P1.2 "not recorded"
  said P1.1 "recorded"
  ! said P1.1 "not recorded"
  edit '(.plans[] | select(.id == "P1.2")).status = "blocked" | (.plans[] | select(.id == "P1.2")).note = "needs a key"'
  vbw_run run confirm P1.1 P1.2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R78: after a fix run, a fix still open is named" {
  "$VBW" run start fix F1 F2 > /dev/null
  edit '(.fixes[] | select(.id == "F1")).status = "fixed"'
  vbw_run run confirm F1 F2
  [ "$status" -eq 1 ]
  said F2 "not recorded"
  ! said F1 "not recorded"
}

@test "R78: after a QA run, a phase with no verdict from this run is named" {
  "$VBW" run start qa > /dev/null
  edit '(.phases[] | select(.id == "P1")).qa = {result: "pass", tier: "standard", tree: ("a" * 40), at: (now | todate)}
    | (.phases[] | select(.id == "P2")).qa = {result: "pass", tier: "standard", tree: ("a" * 40), at: "2020-01-01T00:00:00Z"}'
  vbw_run run confirm P1 P2
  [ "$status" -eq 1 ]
  said P2 "not recorded"
  ! said P1 "not recorded"
}

@test "R78: every one recorded is said plainly, with exit 0" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  edit '.plans |= map(.status = "done")'
  vbw_run run confirm P1.1 P1.2
  [ "$status" -eq 0 ]
  [[ "$output" != *"not recorded"* ]]
  [[ "$output" == *"recorded"* ]]
}

@test "R78: confirm refuses without an open run, an unknown id, or no ids" {
  vbw_run run confirm P1.1
  [ "$status" -ne 0 ]
  "$VBW" run start build P1.1 > /dev/null
  vbw_run run confirm P9.9
  [ "$status" -ne 0 ]
  vbw_run run confirm
  [ "$status" -ne 0 ]
}

@test "R78: confirm changes nothing: the record and the history are as they were" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  local before commits
  before=$(cksum < .vbw/record.json)
  commits=$(git rev-list --count HEAD)
  vbw_run run confirm P1.1 P1.2
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  [ "$(git rev-list --count HEAD)" = "$commits" ]
}

@test "R81: ending a run that is not open is a quiet no-op: no commit, no record change" {
  local before commits
  before=$(cksum < .vbw/record.json)
  commits=$(git rev-list --count HEAD)
  vbw_run run end
  [ "$status" -eq 0 ]
  [[ "$output" == *"no run is open"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  [ "$(git rev-list --count HEAD)" = "$commits" ]
}
