#!/usr/bin/env bats
# T152 (R188; docs/proof.md): a rule may name the plan that builds its code
# ("plan" in vbw apply's rules). vbw plan done of that plan, at standard and
# deep in a build run, then asks for the rule's red break even while another
# plan of the requirement is still open, so an early plan can no longer finish
# without breaking its own rules and leave them to a later plan that may not own
# the code (M33: P139.2 finished with 1 of 10 rules broken; the docs plan that
# finished R188 could not break kernel code). A rule's plan must serve the
# rule's requirement. A rule without a plan keeps today's rule: the plan that
# completes the requirement asks for it. A retired rule (T168) is owed no
# break: vbw plan done does not ask for it, vbw mutate refuses its address and
# vbw show plan leaves it out, the other rules keeping their addresses. L1: the
# kernel on a fixture project.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo more\n' > src/more.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf '[ "$(sh src/more.sh)" = more ]\n' > tests/more.sh
}

teardown() { vbw_teardown; }

# plan_doc RULE1_PLAN RULE2_PLAN: two plans of R1, each rule owned by the named plan ("" for none)
# and served by a check of its own (R215: one check may not serve two open plans).
plan_doc() {
  jq -nc --arg a "$1" --arg b "$2" '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P1.2", phase: "P1", title: "More", reqs: ["R1"], files: ["src/more.sh"], after: [], role: "dev", tasks: ["more"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/more.sh"], files: ["tests/more.sh"]}],
    rules: [({req: "R1", text: "paying prints paid", check: "C1"} + (if $a == "" then {} else {plan: $a} end)),
            ({req: "R1", text: "more prints more", check: "C2"} + (if $b == "" then {} else {plan: $b} end))]}'
}
start() {
  plan_doc "$1" "$2" | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
}
status_of() { jq -r --arg p "$1" '.plans[] | select(.id == $p) | .status' .vbw/record.json; }

@test "T152: the rule's plan is kept in the record" {
  start P1.1 P1.2
  jq -e '[.requirements[] | select(.id == "R1") | .rules[] | .plan] == ["P1.1", "P1.2"]' .vbw/record.json
}

@test "T152: a plan cannot finish without a red break of the rules it owns, while another plan of the requirement is open" {
  start P1.1 P1.2
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -ne 0 ] || { echo "plan done accepted: $output"; false; }
  [[ "$output" == *"R1.1"* ]] && [[ "$output" != *"R1.2"* ]] || { echo "$output"; false; }
  [ "$(status_of P1.1)" != done ]
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null > /dev/null
  git checkout -q -- src/pay.sh
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "T152: a rule without a plan keeps today's rule: an early plan finishes, the completing plan asks" {
  start "" ""
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" plan done P1.2 < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.1"* ]] || { echo "$output"; false; }
}

@test "T168: a retired rule is owed no break and is left out of the plan's rules; R1.2 keeps its address" {
  plan_doc "" "" | "$VBW" apply > /dev/null
  printf '{"rules": [{"rule": "R1.1", "retire": "paying is another requirement now"}]}' | "$VBW" apply --patch > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
  run "$VBW" show plan P1.2
  [[ "$output" == *"R1.2 more prints more -> C2"* ]] && [[ "$output" != *"R1.1"* ]] || { echo "$output"; false; }
  [ "$("$VBW" show plan P1.2 --json | jq -c '[.rules[].n]')" = '["R1.2"]' ]
  run "$VBW" mutate P1.2 R1.1 --none "nothing" < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.1 is retired (paying is another requirement now)"* ]] || { echo "$output"; false; }
  "$VBW" plan done P1.1 < /dev/null > /dev/null
  run "$VBW" plan done P1.2 < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.2"* ]] && [[ "$output" != *"R1.1"* ]] || { echo "$output"; false; }
}

@test "T152: a rule's plan must serve the rule's requirement" {
  run bash -c 'jq ".rules[].plan = \"P9.9\"" | "$1" apply' _ "$VBW" <<< "$(plan_doc "" "")"
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"P9.9"* ]] || { echo "$output"; false; }
}
