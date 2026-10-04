#!/usr/bin/env bats
# vbw approve and vbw prove (docs/proof.md). The M2 exit gate: a hostile
# repository never gets code executed, tampering is caught, vacuous checks are
# flagged before building, and fix attempts are capped.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  # C1 passes once src/pay.txt says "paid".
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1","R2"], milestone: "M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"planned"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

build_pay() {
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  edit_record '.plans[0].status = "done"'
}

# --- approve ---------------------------------------------------------------

@test "approve records consent in the git directory and logs a decision" {
  vbw_run approve
  [ "$status" -eq 0 ]
  [[ "$output" == *"approved contract"* ]]
  jq -e '.granted | map(select(.kind == "contract")) | length == 1' .git/vbw/consent.json
  jq -e '.decisions[-1].text | startswith("Contract approved: 2 requirements, 1 checks, 1 plans")' .vbw/record.json
  [ ! -e .vbw/consent.json ]
  vbw_run next --json
  echo "$output" | jq -e '.action == "build"'
}

@test "approving twice is a no-op" {
  "$VBW" approve > /dev/null
  vbw_run approve
  [ "$status" -eq 0 ]
  [[ "$output" == *"already approved"* ]]
  jq -e '[.decisions[] | select(.text | startswith("Contract approved"))] | length == 1' .vbw/record.json
}

@test "approve refuses an incomplete contract and says why" {
  edit_record '.checks = []'
  rm tests/pay.sh
  printf '\n- R3 [auto] Refunds\n' >> .vbw/spec.md
  vbw_run approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec.md and the record differ (vbw spec sync)"* ]]
  [[ "$output" == *"R1 has no check"* ]]
  [ ! -e .git/vbw/consent.json ]
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["true"], files:["tests/pay.sh"]}, {id:"C2", req:"R3", run:["true"]}]'
  vbw_run approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"check file missing: tests/pay.sh"* ]]
}

@test "approve consents to the project commands by exact argv" {
  edit_record '.commands = {test: ["sh", "-c", "exit 0"]}'
  vbw_run approve
  [ "$status" -eq 0 ]
  [[ "$output" == *"approved command test: sh -c exit 0"* ]]
  jq -e '.granted | map(select(.kind == "command" and .detail.name == "test")) | length == 1' .git/vbw/consent.json
}

# --- the M2 exit gate --------------------------------------------------------

@test "hostile repository: a fresh clone runs nothing until its user approves" {
  # The attacker's repository ships checks and commands that leave a marker,
  # plus a consent file inside the working tree.
  edit_record '.checks[0].run = ["sh", "-c", "touch \"$HOME/pwned-check\""]
    | .commands = {test: ["sh", "-c", "touch \"$HOME/pwned-command\""]}'
  mkdir -p .vbw && printf '{"granted":[{"kind":"contract","hash":"x"}]}' > .vbw/consent.json
  git add -A && git commit -q -m "chore(vbw): hostile"
  git clone -q "$PROJECT" "$TEST_ROOT/victim"
  cd "$TEST_ROOT/victim"

  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
  vbw_run check --expect-red
  [ "$status" -eq 1 ]
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve" and .gate == true'
  [ ! -e "$HOME/pwned-check" ]
  [ ! -e "$HOME/pwned-command" ]
}

@test "hostile update: a command added after approval never runs" {
  "$VBW" approve > /dev/null
  build_pay
  edit_record '.commands = {test: ["sh", "-c", "touch \"$HOME/pwned\""]}'
  vbw_run prove
  [[ "$output" == *"test skipped: not approved"* ]]
  [ ! -e "$HOME/pwned" ]
  jq -e '.evidence.commands.test.status == "skipped"' .vbw/record.json
}

@test "argv is executed directly, never through a shell" {
  edit_record '.checks[0].run = ["echo", "$(touch pwned); touch pwned2"] | .checks[0].output = "touch pwned2"'
  "$VBW" approve > /dev/null
  vbw_run prove
  [[ "$output" == *"C1 pass"* ]]
  [ ! -e pwned ] && [ ! -e pwned2 ]
}

@test "tamper: editing a protected check file after approval fails prove" {
  "$VBW" approve > /dev/null
  build_pay
  printf 'exit 0\n' > tests/pay.sh
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed since it was approved"* ]]
  jq -e '.evidence == null' .vbw/record.json
}

@test "tamper: editing a check or widening a plan in the record withdraws approval" {
  "$VBW" approve > /dev/null
  edit_record '.checks[0].run = ["true"]'
  vbw_run prove
  [ "$status" -eq 1 ]
  git checkout -q .vbw/record.json
  edit_record '.plans[0].files += ["tests/pay.sh"]'
  vbw_run prove
  [ "$status" -eq 1 ]
  git checkout -q .vbw/record.json
  vbw_run check --expect-red
  [ "$status" -eq 0 ]
}

@test "red-first: checks fail before building; a vacuous check is flagged" {
  edit_record '.checks += [{id:"C2", req:"R1", run:["true"]}]'
  "$VBW" approve > /dev/null
  vbw_run check --expect-red C1
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 red (fail), as expected"* ]]
  vbw_run check --expect-red
  [ "$status" -eq 1 ]
  [[ "$output" == *"C2 passed before building: it proves nothing"* ]]
  vbw_run check --expect-red C9
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown check C9"* ]]
  jq -e '.evidence == null' .vbw/record.json
}

@test "fix cap: three failed attempts escalate to a person" {
  "$VBW" approve > /dev/null
  edit_record '.plans[0].status = "done"'
  printf 'unpaid\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat(pay): unpaid" -- src/pay.txt
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.requirements[0].status == "failing" and .fixes == [{id:"F1", req:"R1", attempts:0, status:"open", note:"C1 fail (exit 1)"}]' .vbw/record.json
  vbw_run prove
  jq -e '.fixes | length == 1 and .[0].attempts == 0' .vbw/record.json
  local n
  for n in 1 2; do
    edit_record '.fixes[0].status = "fixed"'
    "$VBW" prove > /dev/null || true
    jq -e --argjson n "$n" '.fixes[0].attempts == $n and .fixes[0].status == "open"' .vbw/record.json
  done
  edit_record '.fixes[0].status = "fixed"'
  vbw_run prove
  [[ "$output" == *"F1 escalated (R1, attempts 3)"* ]]
  jq -e '.fixes[0].status == "escalated"' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "escalate" and .gate == true'
  # A person fixes it: the next passing proof closes the fix.
  printf 'paid\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "fix(pay): paid" -- src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e '.fixes[0].status == "closed" and .requirements[0].status == "proven"' .vbw/record.json
}

@test "a passing proof proves the requirement and records the evidence" {
  "$VBW" approve > /dev/null
  build_pay
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 pass"* ]]
  [[ "$output" == *"scope ok"* ]]
  [[ "$output" == *"R1 proven"* ]]
  [[ "$output" == *"proved"* ]]
  jq -e --arg h "$(vbw_contract_hash)" '.evidence.passed and .evidence.contract == $h and .requirements[0].status == "proven"' .vbw/record.json
  jq -e '.requirements[1].status == "open"' .vbw/record.json
  vbw_run show evidence
  [[ "$output" == *"passed"* ]]
}

@test "expected exit status and output are both enforced" {
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","-c","echo 3 passed; exit 4"], exit: 4, output: "[0-9]+ passed"},
                          {id:"C2", req:"R1", run:["sh","-c","echo 0 failed"], output: "[0-9]+ passed"}]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.checks.C1.status == "pass" and .evidence.checks.C2.status == "fail"' .vbw/record.json
  jq -e '.evidence.checks.C2.tail == "0 failed"' .vbw/record.json
}

@test "a check that hangs is stopped at its timeout" {
  edit_record '.checks[0] = {id:"C1", req:"R1", run:["sleep","30"], timeout: 1} | .plans[0].status = "done"'
  "$VBW" approve > /dev/null
  SECONDS=0
  vbw_run prove
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 10 ]
  jq -e '.evidence.checks.C1.status == "timeout" and .fixes[0].note == "C1 timeout"' .vbw/record.json
}

@test "a missing program is a failure, not a crash" {
  edit_record '.checks[0].run = ["vbw-no-such-program"]'
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.checks.C1.status == "fail" and .evidence.checks.C1.exit == 127' .vbw/record.json
}

@test "approved project commands run; a failing one becomes a fix" {
  edit_record '.commands = {lint: ["sh","-c","echo lint ok"], test: ["sh","-c","echo 2 failing; exit 1"]}'
  "$VBW" approve > /dev/null
  build_pay
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.evidence.commands.lint.status == "pass" and .evidence.commands.test.status == "fail"' .vbw/record.json
  jq -e '.requirements[0].status == "proven" and .fixes == [{id:"F1", command:"test", attempts:0, status:"open", note:"test fail"}]' .vbw/record.json
}

@test "scope: a VBW commit that touches files outside its plan fails proof" {
  "$VBW" approve > /dev/null
  build_pay
  printf 'sneaky\n' > src/other.txt
  git add src/other.txt
  git commit -q -m "feat(pay): more" -m "VBW-Plan: P1.1"
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"(P1.1) changed src/other.txt, which is not in the plan"* ]]
  jq -e '.evidence.passed == false and (.evidence.scope | length) == 1' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "scope"'
}

@test "show contract renders what is approved, and whether it is" {
  vbw_run show contract
  [[ "$output" == *"(NOT APPROVED)"* ]]
  [[ "$output" == *"R1 [auto] A customer can pay"* ]]
  [[ "$output" == *"C1 sh tests/pay.sh [protects tests/pay.sh]"* ]]
  [[ "$output" == *"P1.1 Pay: src/pay.txt"* ]]
  "$VBW" approve > /dev/null
  vbw_run show contract
  [[ "$output" == *"(approved)"* ]]
}

@test "a requirement still being built fails without opening a fix" {
  "$VBW" approve > /dev/null
  printf 'unpaid\n' > src/pay.txt
  vbw_run prove
  [ "$status" -eq 1 ]
  jq -e '.requirements[0].status == "failing" and .fixes == []' .vbw/record.json
  edit_record '.plans[0].status = "done"'
  vbw_run prove
  jq -e '.fixes | length == 1 and .[0].req == "R1"' .vbw/record.json
}

@test "a hanging check is stopped even when the environment ignores the stop signals" {
  edit_record '.checks[0] = {id:"C1", req:"R1", run:["sleep","30"], timeout: 1} | .plans[0].status = "done"'
  "$VBW" approve > /dev/null
  SECONDS=0
  # CI runners can start processes with SIGALRM/SIGTERM ignored; that is inherited.
  run bash -c 'trap "" ALRM TERM; exec "$1" prove' _ "$VBW"
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 15 ]
  jq -e '.evidence.checks.C1.status == "timeout"' .vbw/record.json
}

@test "a proof commits its evidence: VBW's own files are never left modified" {
  "$VBW" approve > /dev/null
  build_pay
  printf 'mine\n' > staged.txt && git add staged.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$(git log -1 --format=%s)" == "chore(vbw): proof passed" ]]
  [ -z "$(git status --porcelain -- .vbw/record.json)" ]
  git diff --cached --name-only | grep -qx staged.txt
}

# --- prove proves the committed code (R32), and freshness knows it -------

@test "an edit proved while uncommitted, then committed, needs a new proof" {
  "$VBW" approve > /dev/null
  build_pay
  "$VBW" prove > /dev/null
  printf 'paid\n# later edit\n' > src/pay.txt
  "$VBW" prove > /dev/null
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" != prove ]
  git add src/pay.txt && git commit -q -m "feat(pay): later edit"
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" = prove ] || { echo "$output"; false; }
}

@test "committing VBW's own record after a proof keeps the proof fresh" {
  "$VBW" approve > /dev/null
  build_pay
  "$VBW" prove > /dev/null
  "$VBW" decide "keep it" > /dev/null
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r '.action')" != prove ]
}
