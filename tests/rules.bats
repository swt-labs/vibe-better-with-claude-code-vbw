#!/usr/bin/env bats
# R31 (docs/proof.md): before approval every [auto] requirement lists the rules
# its text states (conditions, edge and error cases), each with the check that
# tests it. vbw apply refuses a listed rule no check tests, naming it; the
# approval screen (vbw show contract) shows the rules with their checks;
# requirements approved before rules existed keep their approval (D53).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay once\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'exit 1\n' > tests/pay.sh
  printf 'exit 1\n' > tests/twice.sh
  git add -A && git commit -q -m "chore: seed"
}

teardown() { vbw_teardown; }

# plan_doc RULES_JSON: the Lead's apply document with the given rules key
# (empty string: no rules key at all).
plan_doc() {
  local rules=""
  [ -z "$1" ] || rules=", \"rules\": $1"
  cat << JSON
{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1", "R2"], "goal": "Pay", "criteria": ["a payment succeeds"]}],
 "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"], "after": [],
            "tasks": ["write the payment", "record it", "show the receipt"]}],
 "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
            {"id": "C2", "req": "R1", "run": ["sh", "tests/twice.sh"], "files": ["tests/twice.sh"]}]$rules}
JSON
}

apply_rules() {
  plan_doc "$1" > "$TEST_ROOT/plan.json"
  run "$VBW" apply < "$TEST_ROOT/plan.json"
}

GOOD='[{"req": "R1", "text": "A payment succeeds", "check": "C1"}, {"req": "R1", "text": "Paying twice is refused", "check": "C2"}]'

@test "R31: apply refuses a rule that no check tests, naming it" {
  apply_rules '[{"req": "R1", "text": "A payment succeeds", "check": "C1"}, {"req": "R1", "text": "Paying twice is refused", "check": "C9"}]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Paying twice is refused"* ]]
  jq -e '.checks == [] and .plans == []' .vbw/record.json
}

@test "R31: apply refuses a rule whose check belongs to another requirement" {
  printf '\n- R3 [auto] A customer can refund\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  plan_doc "$GOOD" | jq -c '.checks += [{id: "C3", req: "R3", run: ["true"]}]
    | .rules[1].check = "C3"
    | .rules += [{req: "R3", text: "A refund is paid back", check: "C3"}]
    | .phases[0].reqs += ["R3"] | .plans[0].reqs += ["R3"]' > "$TEST_ROOT/plan.json"
  run "$VBW" apply < "$TEST_ROOT/plan.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Paying twice is refused"* ]]
}

@test "R31: apply refuses an [auto] requirement that lists no rules once the plan lists rules" {
  apply_rules '[]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"R1"* ]]
  [[ "$output" == *"rules"* ]]
  printf '\n- R3 [auto] A customer can refund\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  plan_doc "$GOOD" | jq -c '.checks += [{id: "C3", req: "R3", run: ["true"]}]
    | .phases[0].reqs += ["R3"] | .plans[0].reqs += ["R3"]' > "$TEST_ROOT/plan.json"
  run "$VBW" apply < "$TEST_ROOT/plan.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"R3"* ]]
  [[ "$output" == *"rules"* ]]
  jq -e '.checks == []' .vbw/record.json
}

@test "R31: a plan without any rules still applies, and the approval screen says the rules are not listed" {
  apply_rules ""
  [ "$status" -eq 0 ]
  vbw_run show contract
  [[ "$output" == *"R1 [auto] A customer can pay once"* ]]
  [[ "$output" == *"rules not listed"* ]]
}

@test "R31: apply refuses rules for a [human] requirement" {
  apply_rules '[{"req": "R1", "text": "A payment succeeds", "check": "C1"}, {"req": "R2", "text": "It looks calm", "check": "C1"}]'
  [ "$status" -ne 0 ]
  [[ "$output" == *"R2"* ]]
}

@test "R31: apply approves when every rule is covered, and the record keeps the rules" {
  apply_rules "$GOOD"
  [ "$status" -eq 0 ]
  jq -e '.requirements[0].rules == [{text: "A payment succeeds", check: "C1"}, {text: "Paying twice is refused", check: "C2"}]
    and (.requirements[1] | has("rules") | not)' .vbw/record.json
  vbw_run approve
  [ "$status" -eq 0 ]
}

@test "R31: re-planning without restating rules keeps them while their checks still exist" {
  apply_rules "$GOOD"
  [ "$status" -eq 0 ]
  apply_rules ""
  [ "$status" -eq 0 ]
  jq -e '.requirements[0].rules | length == 2' .vbw/record.json
}

@test "R31: approve refuses an [auto] requirement whose rules are not listed, and a changed requirement loses its rules" {
  apply_rules "$GOOD"
  vbw_run approve
  [ "$status" -eq 0 ]
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay once, by card\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -e '.requirements[0].rules == []' .vbw/record.json
  vbw_run approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1"* ]]
  [[ "$output" == *"rules"* ]]
}

@test "R31: the approval screen shows each requirement's rules with their checks" {
  apply_rules "$GOOD"
  vbw_run show contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"R1 [auto] A customer can pay once"* ]]
  [[ "$output" == *"rule: A payment succeeds -> C1"* ]]
  [[ "$output" == *"rule: Paying twice is refused -> C2"* ]]
  [[ "$output" != *"rules not listed"* ]]
}

@test "R31: a requirement approved before rules existed keeps its approval and shows 'rules not listed' (D53)" {
  mkdir -p .vbw
  cp "$BATS_TEST_DIRNAME/fixtures/records/v1.json" .vbw/record.json
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Pay by card\n- R2 [human] Looks trustworthy\n- R3 [auto] Refund a payment\n\n## Commands\n\n- test: npm test\n' > .vbw/spec.md
  vbw_run approve
  [ "$status" -eq 0 ]
  vbw_run show contract
  # The hash of this exact legacy record, computed before rules existed.
  [[ "$output" == "contract 9f2c89ff3f07 (approved)"* ]]
  [[ "$output" == *"R1 [auto] Pay by card"*"rules not listed"*"R2 [human]"*"R3 [auto] Refund a payment"*"rules not listed"* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'rules not listed')" -eq 2 ]
}
