#!/usr/bin/env bats
# R203 (P164; docs/proof.md, docs/workflows.md): vbw plan done and vbw show
# plan with a rule recorded --none. At standard and deep a rule is covered when
# any plan of its requirement has a red break of it or an accepted --none entry
# for it; a rule with neither is still listed as missing, and the Next: line of
# that refusal names both ways (vbw mutate PLAN Rn.k "what you broke" FILE...,
# or --none REASON when the check reads nothing the plans build). A task --none
# keeps its meaning; at express plan done asks nothing. vbw show plan lists the
# entry as "Rn.k: no code could change its outcome: REASON" under mutations:,
# and --json carries it. L1: the kernel on a fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Lab\n\n## Requirements\n\n- R1 [auto] The lab measures and pays\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  # C1 reads only the committed record (through jq); C2 reads the plan's file.
  printf "jq -e '.plans | length > 0' .vbw/record.json > /dev/null\n" > tests/record.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Lab", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Measure", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["measure", "pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/record.sh"], files: ["tests/record.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "the measurement is a decision in the record", check: "C1"},
            {req: "R1", text: "paying prints paid", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(lab): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
tier() { edit_record ".phases[0].tier = \"$1\""; }
status_of() { jq -r --arg p "$1" '.plans[] | select(.id == $p) | .status' .vbw/record.json; }
breaks() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]]' .vbw/record.json; }
# none_ok RULE REASON: the rule is recorded --none from P1.1 (its check reads no plan file).
none_ok() {
  run "$VBW" mutate P1.1 "$1" --none "$2" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
# red RULE: a break of src/pay.sh that C2 notices, recorded for RULE.
red() { printf 'echo unpaid\n' > src/pay.sh; "$VBW" mutate P1.1 "$1" "prints unpaid" src/pay.sh < /dev/null > /dev/null; }
# refuses_naming WORD...: plan done refuses and names each WORD.
refuses_naming() {
  local w
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -ne 0 ] || { echo "plan done accepted: $output"; return 1; }
  for w in "$@"; do [[ "$output" == *"$w"* ]] || { echo "the refusal does not name '$w':"; echo "$output"; return 1; }; done
  [ "$(status_of P1.1)" != done ] || { echo "P1.1 was marked done"; return 1; }
}
done_ok() {
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(status_of P1.1)" = done ]
}
show() { "$VBW" show plan P1.1 < /dev/null; }
# line REGEX: show plan has a line matching REGEX (extended).
line() { show | grep -Eq -- "$1" || { echo "no line matches $1:"; show; return 1; }; }

@test "R203: at standard, a rule with an accepted --none entry counts as covered; one with neither a red break nor an entry is still missing" {
  refuses_naming R1.1 R1.2
  none_ok R1.1 "the figures are a decision in the record, which only vbw writes"
  refuses_naming R1.2
  [[ "$output" != *R1.1* ]] || { echo "R1.1 has its entry: $output"; false; }
  red R1.2
  done_ok
}

@test "R203: the refusal's Next: line names both ways: a break with files, or --none REASON when the check reads nothing the plans build" {
  refuses_naming R1.1 R1.2 'vbw mutate P1.1 Rn.k "what you broke" FILE...' "--none REASON"
  printf '%s\n' "$output" | grep -E '^Next:' | grep -q -- '--none REASON' || { echo "the Next: line lacks --none REASON:"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -E '^Next:' | grep -qiE 'reads nothing' || { echo "the Next: line does not say when --none applies:"; echo "$output"; false; }
}

@test "R203: at deep, a rule's --none entry covers the rule, and a task --none keeps its meaning" {
  tier deep
  none_ok R1.1 "only the record"
  # T174: deep asks one break per rule, as standard does; a task's reason is still recorded.
  "$VBW" mutate P1.1 task2 --none "only writes a log line nothing reads" < /dev/null > /dev/null
  jq -e '[.plans[0].mutations[] | select(.task == 2 and .none == "only writes a log line nothing reads")] | length == 1' .vbw/record.json
  refuses_naming R1.2
  red R1.2
  done_ok
}

@test "R203: a --none entry recorded by another plan of the requirement covers the rule for the completing plan" {
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  edit_record '.plans += [{id: "P1.2", phase: "P1", title: "More", reqs: ["R1"], files: ["src/more.sh"], after: [], status: "planned", role: "dev", tasks: ["more"]}]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.2 > /dev/null
  run "$VBW" mutate P1.2 R1.1 --none "only the record" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  red R1.2
  done_ok
  printf 'echo more\n' > src/more.sh
  "$VBW" commit P1.2 "feat(lab): more" > /dev/null
  run "$VBW" plan done P1.2 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R203: at express, plan done asks for no mutation check" {
  tier express
  done_ok
}

@test "R203: show plan lists the rule entry under mutations: as 'Rn.k: no code could change its outcome: REASON', and --json carries it" {
  none_ok R1.1 "the figures are a decision in the record"
  line '^mutations:'
  line '^  R1\.1: no code could change its outcome: the figures are a decision in the record$'
  "$VBW" mutate P1.1 task2 --none "only writes a log line nothing reads" < /dev/null > /dev/null
  line '^  task2: no testable behaviour: only writes a log line nothing reads$'
  show | grep -Eq 'no code could change its outcome' && show | grep -Eq 'no testable behaviour' || { show; false; }
  "$VBW" show plan P1.1 --json < /dev/null | jq -e '.plan.mutations | length == 2
    and (.[0] | .rule == {req: "R1", k: 1} and .none == "the figures are a decision in the record" and (.head | test("^[0-9a-f]{40}$")))
    and (.[1] | .task == 2 and (has("head") | not))' || { "$VBW" show plan P1.1 --json < /dev/null | jq '.plan.mutations'; false; }
}
