#!/usr/bin/env bats
# R121 (decision D206; L1): the kernel's part of the triage. vbw triage gives
# the main conversation, in one call and with no agent, what it needs to sort a
# new idea: the active milestone, its requirements not yet proven or accepted,
# whether a run is open, and the open backlog with each item's sort and size.
# vbw todo add takes a sort (next or later) and a size (small, medium or
# large); vbw todo list shows them, next before later; items added before
# sorting existed still list, unchanged. A sorted item is a field VBW 2.0.27
# does not read, so it raises the record's schema to 3 (R46's rule).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [human] The receipt looks right\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '(.requirements[] | select(.id == "R1")).status = "proven"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" milestone rename "Checkout" > /dev/null
}

teardown() { vbw_teardown; }

triage_json() {
  run "$VBW" triage --json < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf '%s' "$output"
}

@test "R121: vbw triage --json names the active milestone, its open requirements, the run and the sorted backlog in one call" {
  "$VBW" todo add --sort later --size large "Gift cards" > /dev/null
  "$VBW" todo add --sort next --size small "Refunds" > /dev/null
  "$VBW" todo add "Dark mode" > /dev/null
  local out
  out=$(triage_json)
  printf '%s' "$out" | jq -e '.milestone.id == "M1" and .milestone.title == "Checkout"' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.open[].id] == ["R2", "R3"]' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.open[0].text == "A customer gets a receipt"' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.run == null' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.todos[] | [.id, .sort, .size]] == [["T2", "next", "small"], ["T1", "later", "large"], ["T3", null, null]]' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.todos[0].text == "Refunds"' || { echo "$out"; false; }
}

@test "R121: vbw triage shows an open run, and leaves out accepted requirements and closed backlog items" {
  jq '(.requirements[] | select(.id == "R3")).status = "accepted"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" todo add --sort next --size medium "Refunds" > /dev/null
  "$VBW" todo add --sort later --size small "Coupons" > /dev/null
  "$VBW" todo done T1 > /dev/null
  VBW_SESSION_ID=s-one "$VBW" run start plan > /dev/null
  local out
  out=$(triage_json)
  printf '%s' "$out" | jq -e '[.open[].id] == ["R2"]' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '.run.kind == "plan" and (.run.run | type == "string")' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.todos[].id] == ["T2"]' || { echo "$out"; false; }
}

@test "R121: after ship there is no active milestone and no open requirement" {
  jq '.requirements |= map(.status = (if .proof == "human" then "accepted" else "proven" end))
    | .milestone.status = "shipped" | .shipped = [{id: "M1", title: "Checkout", at: "2026-10-01T00:00:00Z"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  local out
  out=$(triage_json)
  printf '%s' "$out" | jq -e '.open == [] and (.milestone == null or .milestone.status == "shipped")' || { echo "$out"; false; }
}

@test "R121: vbw triage (text) prints the same facts and writes nothing" {
  "$VBW" todo add --sort next --size small "Refunds" > /dev/null
  local before
  before=$(cksum < .vbw/record.json)
  vbw_run triage
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"M1"*"Checkout"* ]] || { echo "$output"; false; }
  [[ "$output" == *"R2"*"A customer gets a receipt"* ]] || { echo "$output"; false; }
  [[ "$output" != *"R1 "* ]] || { echo "a proven requirement is listed: $output"; false; }
  [[ "$output" == *"T1"*"next"*"small"*"Refunds"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no run"* || "$output" == *"No run"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R121: vbw todo add keeps the sort and size, and vbw todo list shows them, next before later" {
  vbw_run todo add --sort later --size large "Gift cards"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"T1"* ]]
  "$VBW" todo add --sort next --size small "Refunds" > /dev/null
  "$VBW" todo add --sort next --size medium "Invoices" > /dev/null
  jq -e '.todos[0] | .sort == "later" and .size == "large" and .text == "Gift cards" and .status == "open"' .vbw/record.json
  vbw_run todo list
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 1p)" == "T2 "*"next"*"small"*"Refunds" ]] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == "T3 "*"next"*"medium"*"Invoices" ]] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 3p)" == "T1 "*"later"*"large"*"Gift cards" ]] || { echo "$output"; false; }
}

@test "R121: backlog items added before sorting existed still list as before, without a sort or size, and nothing about them changes" {
  "$VBW" todo add "Dark mode" > /dev/null
  "$VBW" todo add --sort later --size small "Coupons" > /dev/null
  "$VBW" todo add --sort next --size large "Refunds" > /dev/null
  jq -e '.todos[0] == {id: "T1", text: "Dark mode", status: "open"}' .vbw/record.json
  vbw_run todo list
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'T1 Dark mode' || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 1p)" == "T3 "* ]] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == "T2 "* ]] || { echo "$output"; false; }
}

@test "R121: a sort or size outside the allowed values, or one without the other, is refused and nothing is added" {
  local args
  for args in "--sort now --size small" "--sort soon --size small" "--sort next --size huge" "--sort next" "--size small"; do
    # shellcheck disable=SC2086 # the flags split on purpose
    run "$VBW" todo add $args "An idea" < /dev/null
    [ "$status" -ne 0 ] || { echo "accepted: $args"; false; }
  done
  jq -e '.todos == []' .vbw/record.json
}

@test "R121: the record validator accepts sorted items and refuses a bad sort or size" {
  "$VBW" todo add --sort next --size small "Refunds" > /dev/null
  vbw_run status
  [ "$status" -eq 0 ]
  jq '.todos[0].size = "huge"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  jq '.todos[0].size = "small" | .todos[0].sort = "now"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  jq '.todos[0].sort = "next" | del(.todos[0].size)' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
}

@test "R121: a sorted backlog item raises the schema to 3, so an older VBW asks for an update instead of calling the record corrupt" {
  "$VBW" todo add "Dark mode" > /dev/null
  jq -e '.schema == 1' .vbw/record.json
  "$VBW" todo add --sort later --size small "Coupons" > /dev/null
  jq -e '.schema == 3' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ]
  # An older VBW (one that reads up to schema 2, as 2.0.27 does) refuses it with its update message.
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/old-plugin"
  sed 's/^VBW_SCHEMA_MAX=.*/VBW_SCHEMA_MAX=2/' "$PLUGIN_ROOT/lib/record.sh" > "$TEST_ROOT/old-plugin/lib/record.sh"
  run "$TEST_ROOT/old-plugin/bin/vbw" status < /dev/null
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"needs a newer VBW"* ]]
  # A schema below what the fields need is damage, not age.
  jq '.schema = 2' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
}

@test "R121: a 'now' idea added while a run is open is recorded at once, and planning waits for the run to end" {
  VBW_SESSION_ID=s-one "$VBW" run start plan > /dev/null
  vbw_run spec add auto "A customer can download the receipt"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e 'any(.requirements[]; .text == "A customer can download the receipt")' .vbw/record.json
  run env VBW_SESSION_ID=s-one "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.action == "run"' || { echo "$output"; false; }
}

@test "R121: the kernel help lists vbw triage and the sort and size of vbw todo add" {
  vbw_run help
  [[ "$output" == *"triage"* ]] || { echo "$output"; false; }
  [[ "$output" == *"--sort"*"--size"* ]] || { echo "$output"; false; }
}
