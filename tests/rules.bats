#!/usr/bin/env bats
# R31 (docs/proof.md): before approval every [auto] requirement lists the rules
# its text states (conditions, edge and error cases), each with the check that
# tests it. vbw apply refuses a listed rule no check tests, naming it; the
# approval screen (vbw show contract) shows the rules with their checks;
# requirements approved before rules existed keep their approval (D53). A
# requirement whose every rule is retired (T168) has none listed.

load helper
load fixture-helper

built_project() {
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

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

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

@test "R31: approve refuses an [auto] requirement whose rules are not listed (one added after the plan has none yet)" {
  apply_rules "$GOOD"
  vbw_run approve
  [ "$status" -eq 0 ]
  printf -- '- R3 [auto] A customer can refund\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -e '.requirements[2].rules == []' .vbw/record.json
  vbw_run approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"R3"* ]]
}

@test "R31, T168: approve refuses an [auto] requirement whose every rule is retired" {
  apply_rules "$GOOD"
  [ "$status" -eq 0 ]
  printf '{"rules": [{"rule": "R1.1", "retire": "superseded"}]}' | "$VBW" apply --patch > /dev/null
  jq '.requirements[0].rules[1].retired = "superseded too"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run approve
  [ "$status" -eq 1 ] && [[ "$output" == *"R1 has no rules listed"* ]] || { echo "$output"; false; }
}

@test "R31: the approval screen shows each requirement's rules with their checks" {
  apply_rules "$GOOD"
  vbw_run show contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"R1 [auto] A customer can pay once"* ]]
  [[ "$output" == *"rule R1.1: A payment succeeds -> C1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"rule R1.2: Paying twice is refused -> C2"* ]] || { echo "$output"; false; }
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

# R259 (T235; docs/proof.md Rules, docs/record.md): rewording a requirement keeps its rules.
# vbw spec sync with a changed [auto] text keeps the requirement's rules in their places (so
# their recorded breaks, matched by place under R258, follow), resets its status, marks it
# reworded and says so; a requirement whose proof changes from auto to human loses its rules
# as today, and the message says so; the reworded requirement reads changed in vbw show
# contract --changes and the contract needs approval again; at the next plan step vbw next
# names the reworded requirements for the Lead to review, and the Lead's full apply clears
# the mark. Removing a rule stays an explicit vbw apply --patch retire, never a sync.

# reword: one clause added to R1's text in the spec.
reword() { sed -i.bak 's/A customer can pay once$/A customer can pay once, by card/' .vbw/spec.md && rm -f .vbw/spec.md.bak; }
approved() { "$VBW" show contract < /dev/null | head -n 1 | grep -qE '^contract [0-9a-f]{12} \(approved\)$'; }

@test "R259: vbw spec sync with a changed [auto] text keeps the requirement's rules, their places and words, resets its status, marks it reworded and says how many rules it kept" {
  apply_rules "$GOOD"
  [ "$status" -eq 0 ]
  vbw_run approve
  [ "$status" -eq 0 ]
  jq '.requirements[0].status = "proven"' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  local before
  before=$(jq -c '.requirements[0].rules' .vbw/record.json)
  reword
  vbw_run spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"changed R1 (status reset to open, 2 rules kept)"* ]] || { echo "$output"; false; }
  [ "$(jq -c '.requirements[0].rules' .vbw/record.json)" = "$before" ] || { jq '.requirements[0]' .vbw/record.json; false; }
  jq -e '.requirements[0] | .text == "A customer can pay once, by card" and .status == "open" and .reworded == true' .vbw/record.json || { jq '.requirements[0]' .vbw/record.json; false; }
  vbw_run show req R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"rule R1.1: A payment succeeds -> C1"* && "$output" == *"rule R1.2: Paying twice is refused -> C2"* ]] || { echo "$output"; false; }
}

@test "R259: a requirement whose proof changes from auto to human loses its rules and its checks (neither can belong to a human requirement), and the sync message names them" {
  apply_rules "$GOOD"
  [ "$status" -eq 0 ]
  sed -i.bak 's/- R1 \[auto\]/- R1 [human]/' .vbw/spec.md && rm -f .vbw/spec.md.bak
  vbw_run spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # Today the sync dies on the record's own rule (C1 checks human-proved R1), so the requirement cannot become human at all.
  [[ "$output" == *"changed R1"* && "$output" == *"rules"* && "$output" == *"C1"* && "$output" == *"C2"* ]] || { echo "the message does not name the dropped rules and checks: $output"; false; }
  jq -e '.requirements[0] | .proof == "human" and (has("rules") | not) and (has("reworded") | not)' .vbw/record.json || { jq '.requirements[0]' .vbw/record.json; false; }
  jq -e '[.checks[] | select(.req == "R1")] == [] and ((.protected // []) | index("tests/pay.sh") | not)' .vbw/record.json || { jq '{checks, protected}' .vbw/record.json; false; }
}

@test "R259: the reworded requirement reads changed in vbw show contract --changes and the contract needs approval again" {
  apply_rules "$GOOD"
  vbw_run approve
  [ "$status" -eq 0 ]
  reword
  "$VBW" spec sync > /dev/null
  ! approved || { echo "still approved after the rewording"; false; }
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1"* ]] && printf '%s\n' "$output" | grep -qiE 'changed|reworded' || { echo "$output"; false; }
  jq -e '.requirements[0].rules | length == 2' .vbw/record.json
}

@test "R259: at the next plan step vbw next names the reworded requirements with their kept rules, and the Lead's full apply clears the mark while keeping the rules" {
  apply_rules "$GOOD"
  vbw_run approve
  [ "$status" -eq 0 ]
  reword
  printf -- '- R3 [auto] A customer can refund\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  vbw_run next --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.action == "plan" and .detail.reworded == ["R1"]' > /dev/null || { echo "$output"; false; }
  [[ "$(printf '%s' "$output" | jq -r .instruction)" == *"R1"* ]] || { echo "the plan instruction does not name R1: $(printf '%s' "$output" | jq -r .instruction)"; false; }
  printf '%s' "$output" | jq -r .instruction | grep -qiE 'reworded|rules kept|kept its rules|kept their rules' || { echo "$(printf '%s' "$output" | jq -r .instruction)"; false; }
  plan_doc "$GOOD" | jq -c '.checks += [{id: "C3", req: "R3", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}]
    | .rules += [{req: "R3", text: "A refund is paid back", check: "C3"}]
    | .phases[0].reqs += ["R3"] | .plans[0].reqs += ["R3"]' > "$TEST_ROOT/plan.json"
  run "$VBW" apply < "$TEST_ROOT/plan.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.requirements[0] | (has("reworded") | not) and (.rules | length == 2)' .vbw/record.json || { jq '.requirements[0]' .vbw/record.json; false; }
  vbw_run next --json
  printf '%s' "$output" | jq -e '(.detail.reworded // []) == []' > /dev/null || { echo "$output"; false; }
}
