#!/usr/bin/env bats
# R251 (T225; docs/proof.md): an approval an operator can judge. When a check or a
# requirement changed since the last approval, vbw show contract --changes says for
# each changed item what it promised before and what it promises now, one plain
# line each: a changed check's command, exit, output, timeout and files as
# "before -> after", a changed plan's files (and order) the same way; a check
# amended since approval (vbw apply --amend) is listed among the amendments, not as
# a change. The approval question stays exactly "Approve contract <12 hex>?" (the
# approve hooks' regexes are unchanged: tests/approve-choice-guard.bats) and the
# counts follow it: "N changes, M amendments since the last approval", both from the
# same diff; a first approval names the items instead. L1: the kernel on the
# two-phase shop fixture, approved once.

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
  printf 'data\n' > tests/pay-data.txt
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "receipt", criteria: ["sends"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt"], after: ["P1.1"], role: "dev", tasks: ["send"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R2", text: "sent is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  [ "$1" = fresh ] || "$VBW" approve > /dev/null
}

setup_file() {
  fixture_build approved shop approved
  fixture_build fresh shop fresh
}
setup() { fixture_copy approved; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

patch() { printf '%s' "$1" | "$VBW" apply --patch > /dev/null; }
question() { printf '%s\n' "$1" | sed -n 's/^approval question: //p'; }

@test "R251: vbw show contract --changes states before -> after for a changed check's command, exit, output, timeout and files, and for a changed plan's files and order, one line each" {
  patch '{"checks": [{"id": "C1", "req": "R1", "run": ["bash", "tests/pay.sh", "--strict"], "files": ["tests/pay.sh", "tests/pay-data.txt"], "exit": 1, "output": "paid", "timeout": 30}]}'
  patch '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt", "src/mail.txt"], "after": []}]}'
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local line
  line=$(printf '%s\n' "$output" | grep -E '^  changed check C1 \(R1\): ')
  [ -n "$line" ] || { echo "no changed check C1 line: $output"; false; }
  [[ "$line" == *"run sh tests/pay.sh -> bash tests/pay.sh --strict"* ]] || { echo "$line"; false; }
  [[ "$line" == *"exit 0 -> 1"* ]] || { echo "$line"; false; }
  [[ "$line" == *"output none -> paid"* ]] || { echo "$line"; false; }
  [[ "$line" == *"timeout none -> 30 s"* ]] || { echo "$line"; false; }
  [[ "$line" == *"files tests/pay.sh -> tests/pay.sh, tests/pay-data.txt"* ]] || { echo "$line"; false; }
  line=$(printf '%s\n' "$output" | grep -E '^  changed plan P2.1 Receipt: ')
  [ -n "$line" ] || { echo "no changed plan P2.1 line: $output"; false; }
  [[ "$line" == *"files src/receipt.txt -> src/receipt.txt, src/mail.txt"* ]] || { echo "$line"; false; }
  [[ "$line" == *"after P1.1 -> none"* ]] || { echo "$line"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^  changed ')" -eq 2 ]
}

@test "R251: a check amended since approval (a file added with vbw apply --amend) is listed under the amendments, never as a changed check; the question counts the changes and the amendments from the same diff" {
  VBW_SESSION_ID=0123456789abcdef-aaaa "$VBW" run start build P1.1 > /dev/null
  printf '%s' '{"checks": [{"id": "C1", "files": ["tests/pay.sh", "tests/pay-data.txt"]}]}' | VBW_SESSION_ID=0123456789abcdef-aaaa "$VBW" apply --amend > /dev/null
  VBW_SESSION_ID=0123456789abcdef-aaaa "$VBW" run end > /dev/null
  vbw_run show contract --changes
  [[ "$output" == *"no changes since the last approval"* && "$output" == *"amendments since the last approval:"* && "$output" == *"C1"*"tests/pay-data.txt"* ]] || { echo "$output"; false; }
  [[ "$output" != *"changed check C1"* ]] || { echo "$output"; false; }
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay by card\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  vbw_run show contract --changes
  [[ "$output" == *"changed requirement R1: [auto] A customer can pay -> [auto] A customer can pay by card"* ]] || { echo "$output"; false; }
  [[ "$output" != *"changed check C1"* && "$output" == *"amendments since the last approval:"* ]] || { echo "$output"; false; }
  vbw_run show contract
  [ "$(question "$output")" = "Approve contract $("$VBW" show contract | head -n 1 | cut -d' ' -f2)? 1 change, 1 amendment since the last approval" ] || { question "$output"; false; }
}

@test "R251: the approval question stays 'Approve contract <12 hex>?' and the counts come after it: '2 changes since the last approval' with no amendment, the options exactly Approve and Not yet" {
  patch '{"checks": [{"id": "C1", "req": "R1", "run": ["bash", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}'
  patch '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt", "src/mail.txt"], "after": ["P1.1"]}]}'
  vbw_run show contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local q hash
  hash=$(printf '%s\n' "$output" | head -n 1 | cut -d' ' -f2)
  q=$(question "$output")
  [ "$q" = "Approve contract $hash? 2 changes since the last approval" ] || { echo "$q"; false; }
  [[ "$hash" =~ ^[0-9a-f]{12}$ ]]
  [[ "$output" == *$'\napproval options: Approve, Not yet'* ]] || { echo "$output"; false; }
  # The hooks read the fingerprint from that exact question, with the counts after it.
  [ "$(printf '%s' "$q" | jq -R '{tool_name: "AskUserQuestion", tool_input: {questions: [{question: ., options: [{label: "Approve"}, {label: "Not yet"}]}]}}' \
    | jq -r --arg fp "$hash" 'select(.tool_input.questions[0].question | test("^Approve contract [^\\s?]+\\?")) | .tool_input.questions[0].question | capture("^Approve contract (?<f>[^\\s?]+)\\?").f')" = "$hash" ]
  # vbw approve answers that question and leaves nothing changed.
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run show contract --changes
  [[ "$output" == *"no changes since the last approval"* ]]
}

@test "R251: a first approval names the items, not changes or amendments: 'Approve contract <12 hex>? first approval: 2 requirements, 2 checks, 2 plans'" {
  fixture_copy fresh
  vbw_run show contract
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local hash
  hash=$(printf '%s\n' "$output" | head -n 1 | cut -d' ' -f2)
  [ "$(question "$output")" = "Approve contract $hash? first approval: 2 requirements, 2 checks, 2 plans" ] || { question "$output"; false; }
  [[ "$output" != *"amendment"* ]]
}
