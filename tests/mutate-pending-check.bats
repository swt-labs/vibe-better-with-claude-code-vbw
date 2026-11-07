#!/usr/bin/env bats
# R196 (T165; docs/proof.md): when a break survived the approved check and a
# strengthened check file waiting for approval catches it, vbw mutate says so in
# those words. When the check that went red has a file waiting for approval
# (changed since the approved contract, as checks_begin lists) and a survivor of
# the same target (rule or task) in this plan was recorded with that check at an
# earlier commit, the output line reads
# `TARGET survives the approved check; caught by the pending one: FILE...` and the
# command exits 0. With a pending file but no such survivor, the output says the
# break was caught by a check file waiting for approval and names the file,
# without claiming it survived the approved one. With no pending file the output
# is today's plain red line (`strengthened:` after a prior survivor, as before).
# The recorded break carries the pending files beside result red; vbw show plan
# shows the same words and --json carries them; such a red break counts for
# vbw plan done; recording it leaves the contract's fingerprint unchanged. L1:
# the kernel on a fixture project, in a build run.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  # C1 cannot fail on what is printed.
  printf 'sh src/pay.sh > /dev/null\n' > tests/pay.sh
  printf '[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1", plan: "P1.1"},
            {req: "R2", text: "a receipt is printed", check: "C2", plan: "P1.2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

PENDING='survives the approved check; caught by the pending one'

breaks() { jq -c '[.plans[] | select(.id == "P1.1") | .mutations // [] | .[]]' .vbw/record.json; }
last_break() { breaks | jq -c 'last'; }
# kept_break FILE: the working file still differs from its last commit (R265: the kernel never puts it back).
kept_break() { [ -n "$(git status --porcelain -- "$1")" ] || { echo "$1 was put back to its last commit by the kernel"; return 1; }; }
# break_pay TARGET: the break C1 cannot notice as approved, for TARGET (R1.1 or task1).
break_pay() {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 "$1" "prints unpaid instead of paid" src/pay.sh < /dev/null
}
# survivor TARGET: that break recorded as a survivor of TARGET.
survivor() {
  break_pay "$1"
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "no survivor: $output"; return 1; }
}
# strengthen: tests/pay.sh checks what is printed; committed as the plan's (a survivor opened it).
strengthen() {
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  "$VBW" commit P1.1 "test(pay): check what is printed" tests/pay.sh > /dev/null
}

@test "R196: after a survivor, a red check whose file waits for approval says the break survives the approved check and the pending one caught it; exit 0" {
  survivor R1.1
  strengthen
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF "R1.1 $PENDING: tests/pay.sh" || { echo "$output"; false; }
  last_break | jq -e '.rule == {req: "R1", k: 1} and .result == "red" and .checks == {C1: "red"} and .pending == ["tests/pay.sh"]' || { last_break; false; }
  kept_break src/pay.sh
}

@test "R196: the same words for a task break whose earlier survivor was recorded as a task" {
  survivor task1
  strengthen
  break_pay task1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF "task1 $PENDING: tests/pay.sh" || { echo "$output"; false; }
  last_break | jq -e '.task == 1 and .result == "red" and .pending == ["tests/pay.sh"]' || { last_break; false; }
}

@test "R196: a pending file with no earlier survivor of the target: caught by a check file waiting for approval, named, without claiming it survived the approved one" {
  # Another target's survivor opens strengthen_files; R1.1 itself has none.
  survivor task1
  strengthen
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -v '^vbw:' | grep 'waiting for approval' | grep -q 'tests/pay\.sh' || { echo "$output"; false; }
  [[ "$output" != *"survives"* ]] || { echo "claims it survived: $output"; false; }
  last_break | jq -e '.result == "red" and .pending == ["tests/pay.sh"]' || { last_break; false; }
}

@test "R196: with no file waiting for approval the output is today's plain red line, strengthened after a prior survivor as before" {
  survivor R1.1
  strengthen
  "$VBW" approve > /dev/null
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^R1\.1 red: prints unpaid instead of paid$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^strengthened: tests/pay\.sh$' || { echo "$output"; false; }
  [[ "$output" != *pending* && "$output" != *survives* ]] || { echo "$output"; false; }
  last_break | jq -e '.result == "red" and (has("pending") | not) and .strengthened == ["tests/pay.sh"]' || { last_break; false; }
}

@test "R196: a waiting check file of another check does not make the red check pending: the plain red line" {
  survivor R1.1
  strengthen
  "$VBW" approve > /dev/null
  printf '[ "$(sh src/receipt.sh)" = receipt ] && true\n' > tests/receipt.sh
  git add tests/receipt.sh && git commit -q -m "test(receipt): touched" -- tests/receipt.sh
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^R1\.1 red: prints unpaid instead of paid$' || { echo "$output"; false; }
  [[ "$output" != *"caught by"* && "$output" != *survives* ]] || { echo "$output"; false; }
  last_break | jq -e '.result == "red" and (has("pending") | not)' || { last_break; false; }
}

@test "R196: vbw show plan words a pending break with no earlier survivor as caught by a check file waiting for approval" {
  survivor task1
  strengthen
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" show plan P1.1 < /dev/null
  printf '%s\n' "$output" | grep -F 'caught by a check file waiting for approval' | grep -q 'tests/pay\.sh' || { echo "$output"; false; }
  [[ "$output" != *survives* ]] || { echo "$output"; false; }
}

@test "R196: vbw show plan shows the same words and --json carries the pending files; the red break counts for vbw plan done; the fingerprint is unchanged" {
  survivor R1.1
  strengthen
  local before
  before=$("$VBW" show contract < /dev/null | head -n 1)
  break_pay R1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$("$VBW" show contract < /dev/null | head -n 1)" = "$before" ]
  run "$VBW" show plan P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -F "$PENDING" | grep -q 'tests/pay\.sh' || { echo "$output"; false; }
  "$VBW" show plan P1.1 --json < /dev/null | jq -e '.plan.mutations | last | .pending == ["tests/pay.sh"] and .result == "red"'
  git checkout -q -- src/pay.sh
  # shellcheck disable=SC1010 # "done" is a vbw subcommand
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.plans[0].status == "done"' .vbw/record.json
}

@test "R196: the kernel code is bash 3.2 code that passes JSON only through jq" {
  local f
  for f in "$PLUGIN_ROOT"/lib/cmd-mutate.sh "$PLUGIN_ROOT"/lib/cmd-show.sh; do
    /bin/bash -n "$f"
    ! grep -nE '^[^#]*(\b(mapfile|readarray|eval)\b|(declare|local|typeset) -[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|,|\^)\})' "$f" || false
    ! grep -nE '^[^#]*\b(grep|sed|awk|cut)\b[^|;]*(record\.json|\.json\b)' "$f" || false
  done
}
