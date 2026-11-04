#!/usr/bin/env bats
# R252 (T226; docs/proof.md): a requirement added while a run is open queues. vbw
# spec add appends it to the spec as today and vbw spec sync writes it into the
# record marked queued: the approved contract leaves queued requirements out, so it
# stays approved, the run's agents are not stopped, and vbw check and vbw plan done
# keep working; vbw show contract lists it as queued, not as part of the approved
# contract, and vbw status names the queued count while the run is open. vbw run
# end clears the mark, so the requirement then counts as pending and vbw next names
# it. A hand-written new requirement synced during a run queues the same way; a
# hand edit to an existing requirement's text still un-approves. With no run open
# vbw spec add behaves as today. L1: the kernel on the shop fixture with a build run.

load helper
load fixture-helper

shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "receipt", criteria: ["sends"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt"], after: ["P1.1"], role: "dev", tasks: ["send"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R2", text: "sent is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  # The plan's file exists before its build only here: the floor is computed at apply.
  printf 'paid\n' > src/pay.txt
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

SESSION=0123456789abcdef-aaaa
as_main() { VBW_SESSION_ID="$SESSION" "$VBW" "$@"; }
approved() { "$VBW" show contract | head -n 1 | grep -qE '^contract [0-9a-f]{12} \(approved\)$'; }
queued() { jq -e --arg q "$1" '.requirements[] | select(.id == $q) | .queued == true' .vbw/record.json > /dev/null; }

@test "R252: vbw spec add during a build run appends the line to the spec and syncs the requirement as queued; the contract stays approved, the run stays open, vbw check and vbw plan done keep working, vbw show contract lists it as queued and vbw status names the count" {
  as_main run start build P1.1 > /dev/null
  vbw_run spec add auto "A customer gets a refund"
  [ "$status" -eq 0 ] && [[ "$output" == *"R3 [auto] A customer gets a refund"* ]] || { echo "$status: $output"; false; }
  grep -qx -- '- R3 \[auto\] A customer gets a refund' .vbw/spec.md
  queued R3
  jq -e '.lease.kind == "build" and .plans[0].status == "building" and .schema == 9' .vbw/record.json
  approved || { "$VBW" show contract | head -n 1; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r .action)" != approve ] || { echo "$output"; false; }
  vbw_run check C1
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  vbw_run show contract
  [[ "$output" == *$'\nqueued (not in the approved contract):\n  R3 [auto] A customer gets a refund'* ]] || { echo "$output"; false; }
  [[ "$output" != *$'\nrequirements:'*"R3"*$'\nplans:'* ]] || { echo "R3 is listed among the approved requirements: $output"; false; }
  vbw_run status
  [[ "$output" == *"queued: 1 requirement (R3)"* ]] || { echo "$output"; false; }
  as_main commit P1.1 "feat(pay): paid" > /dev/null
  run as_main plan "done" P1.1
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
}

@test "R252: vbw run end clears the queued mark, the requirement then counts as pending, vbw next names it and the contract reads changed; a second queued requirement is cleared with it" {
  as_main run start build P1.1 > /dev/null
  "$VBW" spec add auto "A customer gets a refund" > /dev/null
  "$VBW" spec add human "The refund page feels calm" > /dev/null
  queued R3 && queued R4
  as_main run end > /dev/null
  jq -e '[.requirements[] | select(has("queued"))] | length == 0' .vbw/record.json
  jq -e '.requirements | length == 4' .vbw/record.json
  vbw_run next --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R3"* && "$output" == *"R4"* ]] || { echo "vbw next does not name the queued requirements: $output"; false; }
  vbw_run show contract
  [[ "$output" != *"queued (not in the approved contract)"* ]] || { echo "$output"; false; }
  vbw_run status
  [[ "$output" != *"queued:"* ]] || { echo "$output"; false; }
}

@test "R252: with no run open vbw spec add is as today: the requirement enters the contract at once, which then reads not approved, and nothing is marked queued" {
  vbw_run spec add auto "A customer gets a refund"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '(.requirements | length == 3) and ([.requirements[] | select(has("queued"))] | length == 0)' .vbw/record.json
  ! approved || { echo "still approved"; false; }
  vbw_run show contract
  [[ "$output" == *"  R3 [auto] A customer gets a refund"* && "$output" != *"queued (not in the approved contract)"* ]] || { echo "$output"; false; }
}

@test "R252: vbw spec sync during a run queues a new requirement written by hand, while a hand edit to an existing requirement's text still un-approves the contract" {
  as_main run start build P1.1 > /dev/null
  printf -- '- R3 [auto] A customer gets a refund\n' >> .vbw/spec.md
  vbw_run spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  queued R3
  approved
  jq -e '.lease.kind == "build"' .vbw/record.json
  sed -i.bak 's/A customer can pay/A customer can pay by card/' .vbw/spec.md && rm -f .vbw/spec.md.bak
  vbw_run spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! approved || { echo "still approved"; false; }
  jq -e '.requirements[0].text == "A customer can pay by card" and .lease.kind == "build"' .vbw/record.json
  queued R3
}
