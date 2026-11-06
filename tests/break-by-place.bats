#!/usr/bin/env bats
# R258 (T234; docs/proof.md, The mutation check; docs/record.md): a recorded break
# belongs to its rule by the rule's place in the requirement (the Rn.k address of
# T168), never by its text. So rewording a rule with vbw apply --patch keeps the
# breaks already recorded against it: vbw plan done still counts them, vbw show plan
# numbers them, vbw show req lists them, and vbw mutate's judgement of an earlier
# survivor of the same rule finds it. A retired rule keeps its place and its breaks,
# and the rules after it keep their k and their breaks. The field case: a parenthesis
# added to two rules made the record list their breaks unnumbered and vbw plan done
# refuse the next plan until the breaks were made again. L1: the kernel on a project
# with one check serving two rules, in a build run.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "nothing but paid is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

as_dev() { VBW_SESSION_ID=s1 "$VBW" "$@" < /dev/null; }
# red TARGET: a break of src/pay.sh that C1 notices, recorded for TARGET (R1.1 or R1.2).
red() { printf 'echo unpaid\n' > src/pay.sh; as_dev mutate P1.1 "$1" "prints unpaid" src/pay.sh > /dev/null; }
# patch DOC: with the run closed, change the rules by address, approve again and reopen the build run.
patch() {
  as_dev run end > /dev/null
  printf '%s' "$1" | "$VBW" apply --patch > /dev/null
  "$VBW" approve > /dev/null
  as_dev run start build P1.1 > /dev/null
}
show() { "$VBW" show plan P1.1 < /dev/null; }
breaks() { jq -c '[.plans[] | select(.id == "P1.1") | .mutations[]]' .vbw/record.json; }

@test "R258: a recorded break names its rule by place: rule is {req, k}, not {req, text}" {
  red R1.2
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[]] | length == 1 and .[0].rule == {req: "R1", k: 2} and .[0].result == "red"' .vbw/record.json \
    || { breaks; false; }
}

@test "R258 field case: a parenthesis added to two rules keeps their breaks, so vbw plan done accepts the plan and vbw show plan numbers the breaks" {
  red R1.1
  red R1.2
  patch '{"rules": [{"rule": "R1.1", "text": "paying prints paid (always)"}, {"rule": "R1.2", "text": "nothing but paid is printed (ever)"}]}'
  jq -e '.requirements[0].rules | map(.text) == ["paying prints paid (always)", "nothing but paid is printed (ever)"]' .vbw/record.json
  show | grep -qE '^  R1\.1: prints unpaid: red' || { echo "the first break is not numbered R1.1:"; show; false; }
  show | grep -qE '^  R1\.2: prints unpaid: red' || { echo "the second break is not numbered R1.2:"; show; false; }
  ! show | grep -qE '^  R1: ' || { echo "a break is listed unnumbered:"; show; false; }
  run as_dev plan done P1.1
  [ "$status" -eq 0 ] || { echo "plan done refused after the rewording: $output"; false; }
  [[ "$output" != *"Rules no recorded break has made a check fail"* ]] || { echo "$output"; false; }
  [ "$(jq -r '.plans[0].status' .vbw/record.json)" = done ]
}

@test "R258: a break of one rule never counts for another: plan done still names the rule without a break" {
  red R1.1
  run as_dev plan done P1.1
  [ "$status" -ne 0 ] || { echo "plan done accepted with R1.2 unbroken: $output"; false; }
  [[ "$output" == *"R1.2 nothing but paid is printed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"R1.1 paying prints paid"* ]] || { echo "R1.1 has a break and is still asked: $output"; false; }
}

@test "R258: a retired rule keeps its place and its breaks, the rule after it keeps its k and its break; vbw show req lists each rule's breaks" {
  red R1.1
  red R1.2
  patch '{"rules": [{"rule": "R1.1", "retire": "folded into R1.2"}]}'
  jq -e '.requirements[0].rules[0].retired == "folded into R1.2" and (.requirements[0].rules | length == 2)' .vbw/record.json
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[].rule] == [{req: "R1", k: 1}, {req: "R1", k: 2}]' .vbw/record.json || { breaks; false; }
  show | grep -qE '^  R1\.2: prints unpaid: red' || { echo "R1.2's break moved or lost its number:"; show; false; }
  run as_dev plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" show req R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -E 'rule R1\.2:' | grep -qiE 'break' || { echo "show req does not list R1.2's recorded break:"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -E 'rule R1\.1 retired:' | grep -qiE 'break' || { echo "show req does not list the retired rule's recorded break:"; echo "$output"; false; }
}

@test "R258: vbw mutate finds an earlier survivor of a reworded rule by its place: a red break after the check was strengthened is marked strengthened" {
  # A survivor: C1 does not notice a comment added to the code.
  printf 'echo paid # x\n' > src/pay.sh
  run as_dev mutate P1.1 R1.1 "adds a comment" src/pay.sh
  [ "$status" -eq 1 ] && [[ "$output" == *"survivor"* ]] || { echo "$status: $output"; false; }
  patch '{"rules": [{"rule": "R1.1", "text": "paying prints paid (no comments)"}]}'
  # The Dev strengthens the check (a survivor opens the file), commits it, and breaks the code the same way.
  printf '[ "$(sh src/pay.sh)" = paid ] && ! grep -q "#" src/pay.sh\n' > tests/pay.sh
  git add tests/pay.sh && git commit -q -m "test(shop): no comments"
  printf 'echo paid # x\n' > src/pay.sh
  run as_dev mutate P1.1 R1.1 "adds a comment" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[] | select(.result == "red")] | length == 1
    and (.[0].rule == {req: "R1", k: 1}) and ((.[0].strengthened // []) | index("tests/pay.sh"))' .vbw/record.json \
    || { echo "the red break does not name the strengthened check file:"; breaks; false; }
}
