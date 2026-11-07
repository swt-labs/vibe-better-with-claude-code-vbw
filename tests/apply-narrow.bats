#!/usr/bin/env bats
# R80 (docs/workflows.md): one plan, check or rule can be changed without
# resubmitting the whole milestone: vbw apply --patch takes only the changed
# plans, checks and rules, and every untouched item stays byte-identical. Once
# work has started, a planning round cannot rename phases nobody asked for: an
# attempt is refused with the reason. (A new phase beside a started one, for
# the same requirement, is allowed since R157: tests/apply-beside-started.bats.)
# T168: a rule's address is Rn.k, its place among its requirement's rules. A
# patch rewords a rule ({rule, text?, check?, plan?}) or retires it ({rule,
# retire}) by address, in any milestone, a shipped one included; a retired rule
# stays in its place, marked with its reason, so no other rule's address moves;
# both change the contract, and vbw show contract --changes names them. L1.

load helper
load fixture-helper

narrow_project() {
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

setup_file() { fixture_build narrow narrow_project; }
setup() { fixture_copy narrow; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

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

# apply_patch DOC: vbw apply --patch with DOC; status and output (stdout and stderr) as bats' run sets them.
apply_patch() { status=0; output=$(printf '%s' "$1" | "$VBW" apply --patch 2>&1) || status=$?; }
# rules_of REQ: the requirement's rules, canonical.
rules_of() { part "[.requirements[] | select(.id == \"$1\")][0].rules"; }
three_rules() {
  apply_patch '{"rules": [{"req": "R1", "text": "paying twice is refused", "check": "C1"}, {"req": "R1", "text": "a refused card is named", "check": "C1"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "T168: a patch rewords a rule by its address; the other rules keep their place and words" {
  three_rules
  apply_patch '{"rules": [{"rule": "R1.2", "text": "paying twice is refused with a message"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(rules_of R1)" = '[{"check":"C1","text":"paying works"},{"check":"C1","text":"paying twice is refused with a message"},{"check":"C1","text":"a refused card is named"}]' ]
  # The check and the plan are reached by address too (the plan on every rule of R1: R212).
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules | map(.plan)')" = '[null,null,null]' ]
  apply_patch '{"checks": [{"id": "C4", "req": "R1", "run": ["sh", "tests/c1.sh"], "files": ["tests/c1.sh"]}], "rules": [{"rule": "R1.1", "plan": "P1.2"}, {"rule": "R1.2", "plan": "P1.2"}, {"rule": "R1.3", "check": "C4", "plan": "P1.2"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules[2]')" = '{"check":"C4","plan":"P1.2","text":"a refused card is named"}' ]
}

@test "T168: a patch retires a rule by its address: it stays in its place with its reason, no other rule moves, later patches keep it" {
  three_rules
  apply_patch '{"rules": [{"rule": "R1.2", "retire": "R1 now allows a second payment"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(rules_of R1)" = '[{"check":"C1","text":"paying works"},{"check":"C1","retired":"R1 now allows a second payment","text":"paying twice is refused"},{"check":"C1","text":"a refused card is named"}]' ]
  # A patch by words and a full apply leave the retired rule where it is.
  apply_patch '{"rules": [{"req": "R1", "text": "a refused card is named", "check": "C1"}, {"req": "R1", "text": "a receipt follows", "check": "C1"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules | map([.text, .retired])')" = '[["paying works",null],["paying twice is refused","R1 now allows a second payment"],["a refused card is named",null],["a receipt follows",null]]' ]
  run bash -c 'printf "%s" "$2" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '[.requirements[] | select(.id == "R1")][0].rules | map([.text, .retired])')" = '[["paying works",null],["paying twice is refused","R1 now allows a second payment"]]' ]
}

@test "T168: a rule of a shipped milestone is reworded or retired by its address" {
  edit_record '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | .requirements |= map(if .id == "R3" then .milestone = "M2" else .status = "proven" end)
    | .plans |= map(.status = "done")'
  apply_patch '{"rules": [{"rule": "R1.1", "retire": "R3 replaces it"}, {"rule": "R2.1", "text": "a receipt is shown at once"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(rules_of R1)" = '[{"check":"C1","retired":"R3 replaces it","text":"paying works"}]' ]
  [ "$(rules_of R2)" = '[{"check":"C2","text":"a receipt is shown at once"}]' ]
}

@test "T168: a rule address is refused when it names no rule, a retired rule or one rule twice, or the entry is malformed, or it comes outside --patch; the record is unchanged" {
  three_rules
  apply_patch '{"rules": [{"rule": "R1.2", "retire": "superseded"}]}'
  local before
  before=$(cksum < .vbw/record.json)
  apply_patch '{"rules": [{"rule": "R1.4", "text": "x"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"--patch refused: R1 has no rule R1.4 (it has 3)"* ]] && [[ "$output" == *"Next: "* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R9.1", "retire": "x"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"R9 has no rule R9.1"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.2", "text": "x"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.2 is retired (superseded)"* ]] || { echo "$output"; false; }
  # R2 is not proven and its only rule would go.
  apply_patch '{"rules": [{"rule": "R2.1", "retire": "superseded"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"R2 lists no rules"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.1", "text": "x"}, {"rule": "R1.1", "retire": "y"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.1 is named twice"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.1", "retire": "y", "text": "x"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"a rule address takes"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.1"}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"a rule address takes"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.1", "retire": ""}]}'
  [ "$status" -ne 0 ] && [[ "$output" == *"a rule address takes"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"req": "R1", "text": "x", "check": "C1", "retired": "y"}]}'
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  run bash -c 'printf "%s" "$2" | jq -c ".rules += [{rule: \"R1.1\", retire: \"y\"}]" | "$1" apply' _ "$VBW" "$DOC"
  [ "$status" -ne 0 ] && [[ "$output" == *"full apply refused: a rule address (R1.1) is for vbw apply --patch"* ]] || { echo "$output"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "T168: a reworded or a retired rule changes the contract, and vbw show contract --changes names each by its address" {
  three_rules
  # R3 is never planned here: without it the contract can be approved.
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: checks"
  "$VBW" approve > /dev/null
  run "$VBW" show contract
  [[ "${lines[0]}" == *"(approved)"* ]] || { echo "$output"; false; }
  apply_patch '{"rules": [{"rule": "R1.2", "text": "paying twice shows the first receipt"}, {"rule": "R1.3", "retire": "cards are no longer refused"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" show contract
  [[ "${lines[0]}" == *"(NOT APPROVED)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"rule R1.2: paying twice shows the first receipt -> C1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"rule R1.3 retired: a refused card is named (cards are no longer refused)"* ]] || { echo "$output"; false; }
  run "$VBW" show contract --changes
  [[ "$output" == *"reworded rule R1.2: paying twice is refused -> paying twice shows the first receipt"* ]] || { echo "$output"; false; }
  [[ "$output" == *"retired rule R1.3: a refused card is named (cards are no longer refused)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"added rule"* ]] && [[ "$output" != *"removed rule"* ]] || { echo "$output"; false; }
}

# R266 (T248; docs/workflows.md): a patch row that names an existing plan or check and leaves
# fields out keeps that row's other fields; an explicit null removes an optional field; null
# on a required field, or a new row lacking one, is refused in one line naming the row and
# the field, before anything is merged or the rigor tiers computed, so no jq error and no
# internal error ever reaches the caller.
# clean_refusal: the last run failed, printed no raw error, and the record is as SUM.
clean_refusal() {
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  [[ "$output" != *"jq: "* && "$output" != *"Cannot iterate"* && "$output" != *"internal error"* && "$output" != *"rigor tiers"* ]] || { echo "a raw error reached the caller: $output"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$1" ] || { echo "the record changed: $output"; return 1; }
}

@test "R266: a plan row with only some fields keeps the row's other fields (the T248 shapes: id and files only; no reqs; no files)" {
  local before
  before=$(part '[.plans[] | select(.id == "P1.2")][0]')
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.2", "files": ["src/b.txt", "src/b2.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(part '[.plans[] | select(.id == "P1.2")][0] | del(.files)')" = "$(printf '%s' "$before" | jq -cS 'del(.files)')" ] || { part '[.plans[] | select(.id == "P1.2")][0]'; false; }
  [ "$(part '[.plans[] | select(.id == "P1.2")][0].files')" = '["src/b.txt","src/b2.txt"]' ]
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.2", "title": "Pay with one click"}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  part '[.plans[] | select(.id == "P1.2")][0]' | jq -e '.title == "Pay with one click" and .phase == "P1" and .reqs == ["R1"] and .files == ["src/b.txt", "src/b2.txt"] and .after == ["P1.1"] and .tasks == ["button"]' || { part '[.plans[] | select(.id == "P1.2")][0]'; false; }
}

@test "R266: a check row with only some fields keeps the row's other fields" {
  run "$VBW" apply --patch <<< '{"checks": [{"id": "C2", "run": ["sh", "tests/c2.sh", "--strict"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  part '[.checks[] | select(.id == "C2")][0]' | jq -e '.req == "R2" and .run == ["sh", "tests/c2.sh", "--strict"] and .files == ["tests/c2.sh"]' || { part '[.checks[] | select(.id == "C2")][0]'; false; }
}

@test "R266: an explicit null removes an optional field of a plan (after, tasks, role) or a check (exit, output, timeout, alone, files)" {
  edit_record '(.plans[] | select(.id == "P1.2")).role = "dev" | (.checks[] | select(.id == "C2")) += {exit: 0, output: "ok", timeout: 60, alone: true}'
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.2", "after": null, "tasks": null, "role": null}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  part '[.plans[] | select(.id == "P1.2")][0]' | jq -e '(.after // []) == [] and (has("tasks") | not) and (has("role") | not) and .title == "Pay button" and .files == ["src/b.txt"]' || { part '[.plans[] | select(.id == "P1.2")][0]'; false; }
  run "$VBW" apply --patch <<< '{"checks": [{"id": "C2", "exit": null, "output": null, "timeout": null, "alone": null, "files": null}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  part '[.checks[] | select(.id == "C2")][0]' | jq -e '(has("exit") | not) and (has("output") | not) and (has("timeout") | not) and (has("alone") | not) and (has("files") | not) and .req == "R2" and .run == ["sh", "tests/c2.sh"]' || { part '[.checks[] | select(.id == "C2")][0]'; false; }
}

@test "R266: null on a required field (plan: phase, title, reqs, files; check: req, run) is refused in one line naming the row and the field, with its next step; the record is unchanged" {
  local sum f
  sum=$(cksum < .vbw/record.json)
  for f in phase title reqs files; do
    run "$VBW" apply --patch <<< "{\"plans\": [{\"id\": \"P1.2\", \"$f\": null}]}"
    clean_refusal "$sum"
    # One line naming the row and the field, then its next step (R162: every refusal carries one).
    [ "$(printf '%s\n' "$output" | grep . | grep -vc '^Next:')" -eq 1 ] || { echo "$f: $output"; false; }
    [[ "$output" == *"P1.2"* && "$output" == *"$f"* ]] || { echo "$f: $output"; false; }
  done
  for f in req run; do
    run "$VBW" apply --patch <<< "{\"checks\": [{\"id\": \"C2\", \"$f\": null}]}"
    clean_refusal "$sum"
    # One line naming the row and the field, then its next step (R162: every refusal carries one).
    [ "$(printf '%s\n' "$output" | grep . | grep -vc '^Next:')" -eq 1 ] || { echo "$f: $output"; false; }
    [[ "$output" == *"C2"* && "$output" == *"$f"* ]] || { echo "$f: $output"; false; }
  done
}

@test "R266: a new row lacking a required field is refused as '--patch refused: ...' naming the row and the field, with a Next: line; nothing is written and no jq or internal error shows" {
  local sum
  sum=$(cksum < .vbw/record.json)
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.3", "phase": "P1", "title": "Pay later", "files": ["src/d.txt"]}]}'
  clean_refusal "$sum"
  printf '%s\n' "$output" | head -n 1 | grep -qE '^(vbw: )?--patch refused: .*P1\.3.*reqs' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^Next: ' || { echo "no Next: line: $output"; false; }
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.3", "files": ["src/d.txt"]}]}'
  clean_refusal "$sum"
  printf '%s\n' "$output" | head -n 1 | grep -qE '^(vbw: )?--patch refused: .*P1\.3' || { echo "$output"; false; }
  run "$VBW" apply --patch <<< '{"checks": [{"id": "C3", "req": "R1"}]}'
  clean_refusal "$sum"
  printf '%s\n' "$output" | head -n 1 | grep -qE '^(vbw: )?--patch refused: .*C3.*run' || { echo "$output"; false; }
}

@test "R266: while a build run is open, a plan or rule patch is still refused and a check-only partial row merges" {
  # R3 is not planned in this fixture: drop it so the contract can be approved and a build started.
  sed -i.bak '/^- R3 /d' .vbw/spec.md && rm -f .vbw/spec.md.bak
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  local sum
  sum=$(cksum < .vbw/record.json)
  run "$VBW" apply --patch <<< '{"plans": [{"id": "P1.2", "title": "Pay with one click"}]}'
  clean_refusal "$sum"
  [[ "$output" == *"build run is open"* ]] || { echo "$output"; false; }
  run "$VBW" apply --patch <<< '{"checks": [{"id": "C2", "run": ["sh", "tests/c2.sh", "--strict"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  part '[.checks[] | select(.id == "C2")][0]' | jq -e '.req == "R2" and .run == ["sh", "tests/c2.sh", "--strict"] and .files == ["tests/c2.sh"]' || { part '[.checks[] | select(.id == "C2")][0]'; false; }
  jq -e '.lease.kind == "build"' .vbw/record.json
}

@test "R266 docs: docs/workflows.md's --patch row and merge list say a row with an existing id is merged field by field, that an explicit null removes an optional field, and that a missing required field is refused naming it" {
  local doc="$REPO_ROOT/docs/workflows.md"
  grep -E '^\| *`vbw apply --patch' "$doc" | grep -qiE 'field by field|other fields' || { echo "the --patch row does not say a row keeps its other fields"; false; }
  tr '\n' ' ' < "$doc" | grep -qiE 'existing `id`[^.;]*(merged|keeps)[^.;]*field' || { echo "the merge list does not say an existing id is merged field by field"; false; }
  tr '\n' ' ' < "$doc" | grep -qiE 'null[^.;]*removes[^.;]*optional' || { echo "the docs do not say an explicit null removes an optional field"; false; }
  tr '\n' ' ' < "$doc" | grep -qiE 'required field[^.;]*refused|refused[^.;]*required field' || { echo "the docs do not say a missing required field is refused"; false; }
}
