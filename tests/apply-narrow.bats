#!/usr/bin/env bats
# R80 (docs/workflows.md): one plan, check or rule can be changed without
# resubmitting the whole milestone: vbw apply --patch takes only the changed
# plans, checks and rules, and every untouched item stays byte-identical. Once
# work has started, a planning round cannot add phases or rename phases nobody
# asked for: an attempt is refused with the reason. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  # R3 starts in the milestone but is planned only by the tests that add it.
  mkdir -p src tests
  for n in 1 2 3; do printf 'true\n' > "tests/c$n.sh"; done
  DOC='{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"], "goal": "pay works", "criteria": ["pays"], "tier": "standard"},
                   {"id": "P2", "title": "Receipt", "reqs": ["R2"], "goal": "receipt works", "criteria": ["receipt"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/a.txt"], "after": [], "tasks": ["form"]},
              {"id": "P1.2", "phase": "P1", "title": "Pay button", "reqs": ["R1"], "files": ["src/b.txt"], "after": ["P1.1"], "tasks": ["button"]},
              {"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt"], "after": [], "tasks": ["page"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/c1.sh"], "files": ["tests/c1.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "tests/c2.sh"], "files": ["tests/c2.sh"]}],
    "rules": [{"req": "R1", "text": "paying works", "check": "C1"}, {"req": "R2", "text": "a receipt is shown", "check": "C2"}]}'
  # R3 is not part of this milestone's plan yet: drop it from the first apply.
  printf '%s' "$DOC" | "$VBW" apply > /dev/null
}

teardown() { vbw_teardown; }

edit_record() { jq "$1" .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json; }

# part EXPR: a part of the record in canonical form.
part() { jq -cS "$1" .vbw/record.json; }

@test "R80: a patch changes one plan; every other plan, phase, check and rule is byte-identical" {
  local phases plans checks reqs
  phases=$(part '.phases'); checks=$(part '.checks'); reqs=$(part '.requirements')
  plans=$(part '[.plans[] | select(.id != "P1.2")]')
  printf '{"plans": [{"id": "P1.2", "phase": "P1", "title": "Pay with one click", "reqs": ["R1"], "files": ["src/b.txt"], "after": ["P1.1"], "tasks": ["button", "one click"]}]}' \
    | "$VBW" apply --patch
  [ "$(part '[.plans[] | select(.id == "P1.2")][0].title')" = '"Pay with one click"' ]
  [ "$(part '[.plans[] | select(.id != "P1.2")]')" = "$plans" ]
  [ "$(part '.phases')" = "$phases" ]
  [ "$(part '.checks')" = "$checks" ]
  [ "$(part '.requirements')" = "$reqs" ]
}

@test "R80: a patch changes one check; the others are byte-identical" {
  local others plans
  others=$(part '[.checks[] | select(.id != "C2")]'); plans=$(part '.plans')
  printf '{"checks": [{"id": "C2", "req": "R2", "run": ["sh", "tests/c2.sh", "--strict"], "files": ["tests/c2.sh"]}]}' | "$VBW" apply --patch
  [ "$(part '[.checks[] | select(.id == "C2")][0].run')" = '["sh","tests/c2.sh","--strict"]' ]
  [ "$(part '[.checks[] | select(.id != "C2")]')" = "$others" ]
  [ "$(part '.plans')" = "$plans" ]
}

@test "R80: a patch adds one rule; the requirement's other rules and every other requirement are untouched" {
  local r2
  r2=$(part '[.requirements[] | select(.id == "R2")]')
  printf '{"rules": [{"req": "R1", "text": "paying twice is refused", "check": "C1"}]}' | "$VBW" apply --patch
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules | map(.text)')" = '["paying works","paying twice is refused"]' ]
  [ "$(part '[.requirements[] | select(.id == "R2")]')" = "$r2" ]
}

@test "R80: a patch changes one rule's check by its text" {
  printf '{"checks": [{"id": "C4", "req": "R1", "run": ["sh", "tests/c1.sh"], "files": ["tests/c1.sh"]}], "rules": [{"req": "R1", "text": "paying works", "check": "C4"}]}' | "$VBW" apply --patch
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules')" = '[{"check":"C4","text":"paying works"}]' ]
}

@test "R80: a patch can add a plan to an existing phase" {
  printf '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": [], "tasks": ["mail"]}]}' | "$VBW" apply --patch
  [ "$(part '[.plans[] | select(.phase == "P2")] | length')" = 2 ]
}

@test "R80: a patch never carries phases, and is refused with the reason" {
  local before
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf '"'"'{"phases": [{"id": "P3", "title": "Refund", "reqs": ["R3"]}]}'"'"' | "$1" apply --patch' _ "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *phase* ]]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R80: a patch is held to the same rules as a full apply" {
  local before
  before=$(cksum < .vbw/record.json)
  # A plan that has started cannot change.
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done"'
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf '"'"'{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/z.txt"], "after": []}]}'"'"' | "$1" apply --patch' _ "$VBW"
  [ "$status" -ne 0 ]
  [[ "$output" == *"started"* ]]
  # An unknown phase, and a rule for a check that does not exist.
  run bash -c 'printf '"'"'{"plans": [{"id": "P9.1", "phase": "P9", "title": "x", "reqs": ["R1"], "files": ["src/q.txt"], "after": []}]}'"'"' | "$1" apply --patch' _ "$VBW"
  [ "$status" -ne 0 ]
  run bash -c 'printf '"'"'{"rules": [{"req": "R1", "text": "x", "check": "C99"}]}'"'"' | "$1" apply --patch' _ "$VBW"
  [ "$status" -ne 0 ]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R80: once work has started, a planning round cannot rename a phase" {
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done"'
  local before
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf "%s" "$2" | jq -c ".phases[0].title = \"Checkout flow\"" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"P1"* ]]
  [[ "$output" == *"title"* ]]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R80: once work has started, a planning round cannot add a phase for requirements that already have one" {
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done"'
  local before
  before=$(cksum < .vbw/record.json)
  run bash -c 'printf "%s" "$2" | jq -c ".phases += [{id: \"P3\", title: \"Pay again\", reqs: [\"R1\"], goal: \"g\", criteria: [\"c\"], tier: \"standard\"}] | .plans += [{id: \"P3.1\", phase: \"P3\", title: \"x\", reqs: [\"R1\"], files: [\"src/p3.txt\"], after: []}]" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -ne 0 ]
  [[ "$output" == *"P3"* ]]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R80: a new phase for a requirement nobody planned yet is still welcome mid-way" {
  edit_record '(.plans[] | select(.id == "P1.1")).status = "done"'
  run bash -c 'printf "%s" "$2" | jq -c ".phases += [{id: \"P3\", title: \"Refund\", reqs: [\"R3\"], goal: \"g\", criteria: [\"c\"], tier: \"standard\"}] | .plans += [{id: \"P3.1\", phase: \"P3\", title: \"Refund\", reqs: [\"R3\"], files: [\"src/p3.txt\"], after: []}] | .checks += [{id: \"C3\", req: \"R3\", run: [\"sh\", \"tests/c3.sh\"], files: [\"tests/c3.sh\"]}] | .rules += [{req: \"R3\", text: \"refund works\", check: \"C3\"}]" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '[.phases[].id]')" = '["P1","P2","P3"]' ]
}

@test "R80: before any work has started, planning may still rename and reshape phases" {
  run bash -c 'printf "%s" "$2" | jq -c ".phases[0].title = \"Checkout flow\"" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '.phases[0].title')" = '"Checkout flow"' ]
}
