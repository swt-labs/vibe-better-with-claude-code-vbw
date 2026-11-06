#!/usr/bin/env bats
# R188 (P139; docs/proof.md, docs/rigor.md): vbw plan done asks for the
# mutation check's proof of a plan being built in an open build run (the build
# workflow's Devs). At standard it refuses until every approved rule of
# each requirement the plan completes (no other open plan serves it, the same
# rule plan done uses for checks) has a recorded break whose checks went red,
# whichever plan of the requirement recorded it; the refusal lists the rules
# still missing one (numbered as vbw show plan lists them) and names vbw mutate.
# Rules sharing one check each need their own break. A survivor alone covers
# nothing; a red break after its check file was strengthened does. At deep it
# asks the same one red break per rule and nothing per task (T174: a task break
# is the Dev's, for a task no rule's check covers). At express, for plans whose requirements are all [human],
# and for a phase with no recorded tier (a record from before tiers), plan done
# behaves as before; so it does outside a build run (a plan closed by hand). It
# refuses while the plan's files differ from their last commit, naming them.
# L1: the kernel on a fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] Paying feels safe\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'paid\n' > src/feel.txt
  # One check serves both rules of R1.
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "log the payment"]},
            {id: "P1.3", phase: "P1", title: "Feel", reqs: ["R2"], files: ["src/feel.txt"], after: [], role: "dev", tasks: ["calm words"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "nothing but paid is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.3 > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# edit_record JQ: a hand edit of the record (the glance is dropped so readers take the record).
edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
tier() { edit_record ".phases[0].tier = \"$1\""; }
status_of() { jq -r --arg p "$1" '.plans[] | select(.id == $p) | .status' .vbw/record.json; }
# red PLAN TARGET: a break of src/pay.sh its check notices, recorded for TARGET.
# red PLAN RULE: a break C1 notices, recorded for RULE; its bytes name the rule (the same bytes twice
# are refused, R265) and the Dev edits the break out after (the kernel leaves the file as given).
red() { printf 'echo unpaid %s\n' "$2" > src/pay.sh; "$VBW" mutate "$1" "$2" "prints unpaid" src/pay.sh < /dev/null > /dev/null; git checkout -q -- src/pay.sh; }
# refuses_naming PLAN WORD...: plan done refuses, names each WORD and vbw mutate.
refuses_naming() {
  local p=$1 w
  shift
  run "$VBW" plan done "$p" < /dev/null
  [ "$status" -ne 0 ] || { echo "plan done accepted: $output"; return 1; }
  [[ "$output" == *"vbw mutate"* ]] || { echo "the refusal does not name vbw mutate: $output"; return 1; }
  for w in "$@"; do [[ "$output" == *"$w"* ]] || { echo "the refusal does not name $w: $output"; return 1; }; done
  [ "$(status_of "$p")" != done ] || { echo "$p was marked done"; return 1; }
}
done_ok() {
  run "$VBW" plan done "$1" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(status_of "$1")" = done ]
}

@test "R188: at standard, plan done refuses with no breaks recorded and lists every rule still missing one" {
  refuses_naming P1.1 R1.1 R1.2
}

@test "R188: rules that share one check each need their own break" {
  red P1.1 R1.1
  refuses_naming P1.1 R1.2
  [[ "$output" != *R1.1* ]] || { echo "R1.1 has its red break: $output"; false; }
  red P1.1 R1.2
  done_ok P1.1
}

@test "R188: a survivor alone covers nothing; a red break of the same rule after its check was strengthened does" {
  red P1.1 R1.1
  # Printing to stderr as well: C1 reads standard output only, so the break survives.
  printf 'echo paid\necho oops >&2\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.2 "prints oops on stderr" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  refuses_naming P1.1 R1.2
  git checkout -q -- src/pay.sh
  printf '[ "$(sh src/pay.sh 2>&1)" = paid ]\n' > tests/pay.sh
  git commit -q -am "test(pay): nothing but paid, on either stream"
  printf 'echo paid\necho oops >&2\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 "prints oops on stderr" src/pay.sh < /dev/null > /dev/null
  done_ok P1.1
}

@test "R188: a requirement another open plan still serves asks nothing of this plan; the completing plan counts every plan's breaks" {
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  edit_record '.plans += [{id: "P1.4", phase: "P1", title: "Pay more", reqs: ["R1"], files: ["src/more.sh"], after: [], status: "planned", role: "dev", tasks: ["more"]}]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 P1.4 > /dev/null
  done_ok P1.1
  red P1.1 R1.1
  red P1.1 R1.2
  printf 'echo more\n' > src/more.sh
  "$VBW" commit P1.4 "feat(pay): more" > /dev/null
  done_ok P1.4
}

@test "T174: at deep, plan done asks one red break per rule, as at standard, and none per task" {
  tier deep
  refuses_naming P1.1 R1.1 R1.2
  [[ "$output" != *task1* && "$output" != *Tasks* ]] || { echo "the refusal asks for task breaks: $output"; false; }
  red P1.1 R1.1
  refuses_naming P1.1 R1.2
  red P1.1 R1.2
  done_ok P1.1
}

@test "R188: at express, plan done asks for no mutation check" {
  tier express
  done_ok P1.1
}

@test "R188: a plan whose requirements are all [human] asks for no mutation check, at standard or deep" {
  printf 'calm\n' > src/feel.txt
  "$VBW" commit P1.3 "feat(feel): calm words" > /dev/null
  done_ok P1.3
  edit_record '(.plans[] | select(.id == "P1.3")).status = "building"'
  tier deep
  done_ok P1.3
}

@test "R188: a phase with no recorded tier (a record from before tiers) asks for no mutation check" {
  edit_record 'del(.phases[0].tier, .phases[0].proposed, .phases[0].predicted, .phases[0].reasons)'
  done_ok P1.1
}

@test "R188: outside a build run (a plan closed by hand) plan done asks for no mutation check" {
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  done_ok P1.1
}

@test "R188 R265: plan done refuses while the plan's files differ from their last commit, naming them: a break vbw mutate left in the file included" {
  red P1.1 R1.1
  red P1.1 R1.2
  printf 'echo unpaid once more\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid once more" src/pay.sh < /dev/null > /dev/null
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"P1.1 has uncommitted changes in: src/pay.sh"* ]] || { echo "$output"; false; }
  [ "$(status_of P1.1)" != done ]
}
