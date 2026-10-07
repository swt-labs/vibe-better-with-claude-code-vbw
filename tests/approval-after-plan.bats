#!/usr/bin/env bats
# R100 (L1): after the plan changes (a new plan, a changed plan or a re-plan),
# VBW asks for approval only with the approval menu. No kernel output, and no
# step of the router, tells the user to type /vbw:approve (typing it still works).

load helper
load approve-choice-helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

setup() {
  vbw_setup
  approve_choice_project
}
teardown() { vbw_teardown; }

@test "R100: vbw doctor on a planned, unapproved contract does not tell the user to type /vbw:approve and says VBW asks with the approval menu" {
  run "$VBW" doctor < /dev/null
  [[ "$output" == *"not approved"* ]] || { echo "$output"; false; }
  [[ "$output" != *"/vbw:approve"* ]] || { echo "$output"; false; }
  [[ "$output" == *"approval menu"* ]] || { echo "$output"; false; }
}

@test "R100: after a changed plan the contract view ends with the approval question and names no typed command" {
  printf '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay now", "reqs": ["R1"], "files": ["src/pay.txt"]}]}' | "$VBW" apply --patch > /dev/null
  run "$VBW" show contract < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"approval question: Approve contract $(fingerprint)?"* ]]
  [[ "$output" != *"/vbw:approve"* ]]
}

@test "R100: no output of apply, spec sync or a plan reset tells the user to type /vbw:approve" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] It feels fast\n' > .vbw/spec.md
  run "$VBW" spec sync < /dev/null
  [[ "$output" != *"/vbw:approve"* ]]
  run bash -c 'printf "{\"phases\": [{\"id\": \"P1\", \"title\": \"Checkout\", \"reqs\": [\"R1\", \"R2\"]}], \"plans\": [{\"id\": \"P1.1\", \"phase\": \"P1\", \"title\": \"Pay\", \"reqs\": [\"R1\"], \"files\": [\"src/pay.txt\"]}], \"checks\": [{\"id\": \"C1\", \"req\": \"R1\", \"run\": [\"sh\", \"tests/pay.sh\"], \"files\": [\"tests/pay.sh\"]}], \"rules\": [{\"req\": \"R1\", \"text\": \"paid is written\", \"check\": \"C1\"}]}" | "$1" apply' _ "$VBW"
  [[ "$output" != *"/vbw:approve"* ]]
}

@test "R100: the router's step for a changed plan asks for approval only with the approval menu" {
  local para
  para=$(sed -n '/^\*\*Changing the plan\*\*/,/^## Rules/p' "$ROUTER")
  [ -n "$para" ]
  printf '%s' "$para" | tr '\n' ' ' | grep -qiE 'approval menu|AskUserQuestion'
}

@test "R100: the router's planned step hands the user to the approval menu and never relays a typed command" {
  local para
  para=$(sed -n '/^\*\*plan\*\*: `VBW_SESSION_ID/,/^\*\*approve\*\*/p' "$ROUTER")
  [ -n "$para" ]
  printf '%s' "$para" | tr '\n' ' ' | grep -qiE 'approval menu|never (relay|pass on|tell)'
}
