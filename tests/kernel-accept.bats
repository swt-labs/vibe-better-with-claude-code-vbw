#!/usr/bin/env bats
# R11: accepting a [human] requirement closes only the fixes opened by the
# user's own rejections; a fix QA opened stays open until QA passes the phase.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1", "R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1", "R2"], "files": ["src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null
}

teardown() { vbw_teardown; }

@test "R11: a user rejection opens a fix and a later accept of that requirement closes it" {
  "$VBW" req reject R2 "too plain" > /dev/null
  jq -e '[.fixes[] | select(.req == "R2")] | length == 1 and .[0].status == "open"' .vbw/record.json
  vbw_run req accept R2
  [ "$status" -eq 0 ]
  jq -e '.requirements[] | select(.id == "R2") | .status == "accepted"' .vbw/record.json
  jq -e '[.fixes[] | select(.req == "R2")] | all(.status == "closed")' .vbw/record.json
}

@test "R11: a fix opened by QA stays open after the user accepts the requirement" {
  "$VBW" qa finding R2 "the plan promised a trust badge; none exists" > /dev/null
  "$VBW" req reject R2 "too plain" > /dev/null
  vbw_run req accept R2
  [ "$status" -eq 0 ]
  jq -e '[.fixes[] | select(.source == "qa")] | length == 1 and .[0].status == "open"' .vbw/record.json
  jq -e '[.fixes[] | select(.source != "qa")] | length == 1 and .[0].status == "closed"' .vbw/record.json
}

@test "R11: the QA-opened fix closes only when QA records a passing verdict for the phase" {
  "$VBW" qa finding R2 "the plan promised a trust badge; none exists" > /dev/null
  "$VBW" req accept R2 > /dev/null
  jq -e '.fixes[0].status == "open"' .vbw/record.json
  "$VBW" qa record P1 fail standard > /dev/null
  jq -e '.fixes[0].status == "open"' .vbw/record.json
  vbw_run qa record P1 pass standard
  [ "$status" -eq 0 ]
  jq -e '.fixes[0].status == "closed"' .vbw/record.json
}
