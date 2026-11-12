#!/usr/bin/env bats
# R156 (docs/workflows.md): every refusal of vbw apply names, in its text, the
# mode it came from: "full apply" (vbw apply with neither --add nor --patch),
# "--add" or "--patch". At least one refusal per mode is covered, among them
# input that is not valid JSON, an unknown field, an invalid tier, an open run,
# a changed started plan, a missing rule and a tier below its floor. An unknown
# option prints the usage line listing the three modes and exits 2. R211, R212,
# R215 and R216: the two-owner and mixed-owner refusals and their pinned Next
# lines. R220: a bats check whose case filter matches no case name in its file
# is refused before anything is written. L1.

load helper
load replan-helper
load fixture-helper

built_project() {
  vbw_setup
  replan_project
  # P1.1 has started. Checks and rules make the rule refusals reachable.
  printf 'true\n' > tests/c1.sh
  printf 'true\n' > tests/c2.sh
  printf 'true\n' > tests/c3.sh
  # Bats files with named cases for a check that filters by case name (R220); a case that
  # runs leaves tests/ran behind, so a kernel that ran the runner at apply shows itself.
  printf '@test "R1: paying works" { echo ran > "$BATS_TEST_DIRNAME/ran"; }\n@test "R1: a card is refused" { true; }\n' > tests/x.bats
  printf '@test "R2: a receipt is shown" { true; }\n' > tests/y.bats
  replan_accepted full "$(replan_doc '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]},
      {id: "C2", req: "R2", run: ["sh", "tests/c2.sh"], files: ["tests/c2.sh"]}]
    | .rules = [{req: "R1", text: "paying works", check: "C1"}, {req: "R2", text: "a receipt is shown", check: "C2"}]')"
  FULL=$(jq -c '.milestone.id as $m | {phases: [.phases[] | select(.milestone == $m) | {id, title, reqs, goal, criteria, tier}],
      plans: [.plans[] | {id, phase, title, reqs, files, after, tasks}], checks: .checks,
      rules: [.requirements[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]}' .vbw/record.json)
  ADD='{"phases": [{"id": "P3", "title": "Refund", "reqs": ["R3"], "goal": "Customers get refunds", "criteria": ["a refund is paid"], "tier": "standard"}],
    "plans": [{"id": "P3.1", "phase": "P3", "title": "Refund", "reqs": ["R3"], "files": ["src/r.txt"], "after": []}],
    "checks": [{"id": "C3", "req": "R3", "run": ["sh", "tests/c3.sh"], "files": ["tests/c3.sh"]}],
    "rules": [{"req": "R3", "text": "a refund is paid", "check": "C3"}]}'
  replan_start P1.1
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# refused_as MODE LABEL DOC: vbw apply in MODE refuses DOC, writes nothing, and
# its message names LABEL.
refused_as() {
  replan_refused "$1" "$3" || return 1
  [[ "$output" == *"$2"* ]] || { echo "the $1 refusal does not name '$2': $output"; return 1; }
}

full_with() { printf '%s' "$FULL" | jq -c "$1"; }
add_with() { printf '%s' "$ADD" | jq -c "$1"; }

@test "R156: full apply refusals name the full apply: not JSON, an unknown field, an invalid tier" {
  refused_as full "full apply" 'not json {'
  refused_as full "full apply" "$(full_with '.plans[0].file = "x"')"
  refused_as full "full apply" "$(full_with '.phases[0].tier = "fast"')"
}

@test "R156: full apply refusals name the full apply: an open run, a changed started plan, a missing rule, a tier below its floor" {
  refused_as full "full apply" "$(full_with '(.plans[] | select(.id == "P1.1")).files += ["src/extra.txt"]')"
  refused_as full "full apply" "$(full_with '.phases += [{id: "P3", title: "Refund", reqs: ["R3"], goal: "g", criteria: ["c"], tier: "standard"}]
    | .plans += [{id: "P3.1", phase: "P3", title: "Refund", reqs: ["R3"], files: ["src/r.txt"], after: []}]
    | .checks += [{id: "C3", req: "R3", run: ["sh", "tests/c3.sh"], files: ["tests/c3.sh"]}]')"
  refused_as full "full apply" "$(full_with '(.plans[] | select(.id == "P2.1")).files = ["src/payments/charge.js"]')"
  "$VBW" run start build P2.1 > /dev/null
  refused_as full "full apply" "$FULL"
}

@test "R156: --add refusals name --add: not JSON, an unknown field, an invalid tier, a phase id in use" {
  refused_as add "--add" 'not json {'
  refused_as add "--add" "$(add_with '.phases[0].colour = "red"')"
  refused_as add "--add" "$(add_with '.phases[0].tier = "fast"')"
  refused_as add "--add" "$(add_with '.phases[0].id = "P2" | .plans[0].phase = "P2"')"
}

@test "R156: --add refusals name --add: a missing rule, a tier below its floor, an open run" {
  refused_as add "--add" "$(add_with '.rules = []')"
  refused_as add "--add" "$(add_with '.plans[0].files = ["src/payments/refund.js"]')"
  "$VBW" run start build P2.1 > /dev/null
  refused_as add "--add" "$ADD"
}

@test "R156: --patch refusals name --patch: not JSON, phases, an unknown field, a changed started plan, a rule naming no check, an open run" {
  refused_as patch "--patch" 'not json {'
  refused_as patch "--patch" '{"phases": []}'
  refused_as patch "--patch" '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt"], "after": [], "colour": "red"}]}'
  refused_as patch "--patch" '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Pay form", "reqs": ["R1"], "files": ["src/a.txt", "src/z.txt"], "after": []}]}'
  refused_as patch "--patch" '{"rules": [{"req": "R1", "text": "a second rule", "check": "C9"}]}'
  "$VBW" run start build P2.1 > /dev/null
  refused_as patch "--patch" '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R2"], "files": ["src/c.txt"], "after": []}]}'
}

@test "R156: an unknown option prints the usage line listing the three modes and exits 2" {
  local out code=0 before
  before=$(cksum < .vbw/record.json)
  out=$(printf '%s' "$FULL" | "$VBW" apply --foo 2>&1) || code=$?
  [ "$code" -eq 2 ] || { echo "exit $code: $out"; false; }
  [[ "$out" == *"usage: vbw apply"* ]] || { echo "$out"; false; }
  [[ "$out" == *"full"* && "$out" == *"--add"* && "$out" == *"--patch"* ]] || { echo "$out"; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

# R211 and R212 (T187, T191): two refusals that stop a red mutation baseline and an
# undefined rule owner, judged on the record as the document would leave it, in every mode.

# r211_named CHECK A B: the refusal names the check and both plans, says why, and ends with its next step.
r211_named() {
  [[ "$output" == *"$1"* && "$output" == *"$2"* && "$output" == *"$3"* ]] || { echo "does not name $1, $2 and $3: $output"; return 1; }
  [[ "$output" == *"unbroken code"* ]] || { echo "does not say why (red on unbroken code): $output"; return 1; }
  last_line_is "$TWO_OWNER_NEXT"
}
# last_line_is TEXT: the refusal's last line is its next step, word for word (R216).
last_line_is() {
  local last
  last=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)
  [ "$last" = "$1" ] || { echo "the last line is not '$1': $output"; return 1; }
}
TWO_OWNER_NEXT="Next: give each plan's rules a check of their own (a separate test file, or the same file with a case filter as a distinct check), or move the rules to one plan"
MIXED_NEXT='Next: name a plan on every rule of the requirement, or on none (vbw apply --patch rewords a rule: {"rule": "Rn.k", "plan": "P1.1"})'
# beside_named CHECK A B: the refusal says the two plans build beside each other, and ends with the two-owner next step.
beside_named() {
  [[ "$output" == *"$1 is owned by two plans that build beside each other (a shared wave): $2 and $3; the first Dev's mutation step would run $1 before the other Dev committed, a race that fails only sometimes"* ]] || { echo "not the beside words for $1, $2, $3: $output"; return 1; }
  last_line_is "$TWO_OWNER_NEXT"
}
# r2_two_plans AFTER FILES: FULL with P2.2 (after AFTER, files FILES) and C2's rules naming P2.1 and P2.2.
r2_two_plans() {
  full_with ".plans += [{id: \"P2.2\", phase: \"P2\", title: \"Receipt mail\", reqs: [\"R2\"], files: $2, after: $1, tasks: [\"mail\"]}]
    | .rules = [.rules[] | if .req == \"R2\" then . + {plan: \"P2.1\"} else . end] + [{req: \"R2\", text: \"a receipt is mailed\", check: \"C2\", plan: \"P2.2\"}]"
}

@test "R211 R216: full apply refuses a check whose rules name two plans that build one after the other, through after, a chain or a shared file, naming the check and both plans, why, and the next step; the record is unchanged" {
  refused_as full "full apply" "$(r2_two_plans '["P2.1"]' '["src/d.txt"]')"
  r211_named C2 P2.1 P2.2
  # The same through a shared file, with no after.
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/c.txt"]')"
  r211_named C2 P2.1 P2.2
  # Through a chain: P2.3 after P2.2 after P2.1, the rules naming P2.1 and P2.3.
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]},
      {id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: ["P2.2"], tasks: ["print"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is printed", check: "C2", plan: "P2.3"}]')"
  r211_named C2 P2.1 P2.3
}

@test "R211 R216: --add and --patch refuse the same, naming their mode" {
  refused_as add "--add" "$(add_with '.plans += [{id: "P3.2", phase: "P3", title: "Refund mail", reqs: ["R3"], files: ["src/r2.txt"], after: ["P3.1"]}]
    | .rules = [{req: "R3", text: "a refund is paid", check: "C3", plan: "P3.1"}, {req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.2"}]')"
  r211_named C3 P3.1 P3.2
  refused_as patch "--patch" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": ["P2.1"]}],
    "rules": [{"req": "R2", "text": "a receipt is shown", "check": "C2", "plan": "P2.1"}, {"req": "R2", "text": "a receipt is mailed", "check": "C2", "plan": "P2.2"}]}'
  r211_named C2 P2.1 P2.2
}

@test "R211 R215: no refusal when the check's rules name one plan or none, when one of the two plans is done, or when the check belongs to a requirement of another milestone; a retired rule counts for nothing" {
  # Both rules name P2.1: one owner.
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.1"}]')"
  # No rule names a plan.
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules += [{req: "R2", text: "a receipt is mailed", check: "C2"}]')"
  # P1.1 is done, P1.2 builds after it: C1's rules may name both.
  replan_accepted full "$(full_with '.rules = [.rules[] | if .req == "R1" then . + {plan: "P1.1"} else . end] + [{req: "R1", text: "a card is refused", check: "C1", plan: "P1.2"}]')"
  # A retired rule naming the later plan is nothing.
  replan_edit '(.requirements[] | select(.id == "R2")).rules += [{text: "a receipt is faxed", check: "C2", plan: "P2.2", retired: "fax dropped"}]'
  replan_accepted full "$(full_with '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.1"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end]')"
  [ "$(replan_part '[.requirements[] | select(.id == "R2")][0].rules | map([.plan, .retired])')" = '[["P2.1",null],["P2.2","fax dropped"]]' ]
  # A check of another milestone's requirement: R2 moves to M0, its rules name P2.1 and P2.2 beside each other.
  replan_edit '.shipped = [{id: "M0", title: "Old", at: "2026-01-01T00:00:00Z"}] | (.requirements[] | select(.id == "R2")) |= (.milestone = "M0" | .rules = [{text: "a receipt is shown", check: "C2", plan: "P2.1"}, {text: "a receipt is mailed", check: "C2", plan: "P2.2"}])
    | (.plans[] | select(.id == "P2.2")).after = []'
  replan_accepted patch '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": []}]}'
}

@test "R212 R216: every mode refuses a requirement whose live rules name a plan on only some, naming the requirement and the counts, with its next step; the record is unchanged" {
  refused_as full "full apply" "$(full_with '.rules += [{req: "R1", text: "a card is refused", check: "C1", plan: "P1.1"}]')"
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
  refused_as add "--add" "$(add_with '.rules += [{req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.1"}]')"
  [[ "$output" == *"R3: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
  refused_as patch "--patch" '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1", "plan": "P1.1"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  last_line_is "$MIXED_NEXT"
}

@test "R212: a patch reword that names a plan on one rule and leaves the requirement mixed is refused; every rule naming a plan, or none, is accepted; retired rules are not counted" {
  replan_accepted patch '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1"}]}'
  refused_as patch "--patch" '{"rules": [{"rule": "R1.1", "plan": "P1.1"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  replan_accepted patch '{"rules": [{"rule": "R1.1", "plan": "P1.1"}, {"rule": "R1.2", "plan": "P1.1"}]}'
  [ "$(replan_part '[.requirements[] | select(.id == "R1")][0].rules | map(.plan)')" = '["P1.1","P1.1"]' ]
  # Taking the plan off one rule by a reword leaves the requirement mixed.
  replan_edit '(.requirements[] | select(.id == "R1")).rules[1] |= del(.plan)'
  refused_as patch "--patch" '{"rules": [{"rule": "R1.2", "text": "a card is refused by name"}]}'
  [[ "$output" == *"R1: 1 of 2 rules name a plan"* ]] || { echo "$output"; false; }
  # A retired rule without a plan beside live rules with one.
  replan_edit '(.requirements[] | select(.id == "R1")).rules |= [.[0], {text: "an old rule", check: "C1", retired: "gone"}]'
  replan_accepted patch '{"rules": [{"req": "R1", "text": "a card is refused", "check": "C1", "plan": "P1.1"}]}'
  [ "$(replan_part '[.requirements[] | select(.id == "R1")][0].rules | map([.plan, .retired])')" = '[["P1.1",null],[null,"gone"],["P1.1",null]]' ]
}

@test "R215 R216: every mode refuses a check whose rules name two plans that build beside each other (a shared wave), naming the check and both plans, the race, and the next step; the record is unchanged" {
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/d.txt"]')"
  beside_named C2 P2.1 P2.2
  refused_as add "--add" "$(add_with '.plans += [{id: "P3.2", phase: "P3", title: "Refund mail", reqs: ["R3"], files: ["src/r2.txt"], after: []}]
    | .rules = [{req: "R3", text: "a refund is paid", check: "C3", plan: "P3.1"}, {req: "R3", text: "a refund is mailed", check: "C3", plan: "P3.2"}]')"
  beside_named C3 P3.1 P3.2
  refused_as patch "--patch" '{"plans": [{"id": "P2.2", "phase": "P2", "title": "Receipt mail", "reqs": ["R2"], "files": ["src/d.txt"], "after": []}],
    "rules": [{"req": "R2", "text": "a receipt is shown", "check": "C2", "plan": "P2.1"}, {"req": "R2", "text": "a receipt is mailed", "check": "C2", "plan": "P2.2"}]}'
  beside_named C2 P2.1 P2.2
}

@test "R215 R216: a pair in an earlier and a later wave with no tie between them is refused with the ordered words and the wave reason" {
  # P2.3 shares nothing with P2.1; P2.2 builds after P2.3, so P2.1 is in wave 1 and P2.2 in wave 2.
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], tasks: ["print"]},
      {id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.3"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.2"}]')"
  [[ "$output" == *"C2 is owned by two plans that build one after the other (P2.1 builds in an earlier wave than P2.2): P2.1 and P2.2; the earlier plan's mutation step would find C2 red on unbroken code"* ]] || { echo "$output"; false; }
  last_line_is "$TWO_OWNER_NEXT"
}

@test "R215 R216: a pair with one plan blocked is refused like an open pair, with and without a blocked plan the later one waits for" {
  # P2.1 blocked, P2.2 beside it.
  replan_edit '(.plans[] | select(.id == "P2.1")) |= (.status = "blocked" | .note = "waiting")'
  refused_as full "full apply" "$(r2_two_plans '[]' '["src/d.txt"]')"
  beside_named C2 P2.1 P2.2
  # P2.3 blocked too, and P2.2 waits for it: P2.1 is in an earlier wave.
  replan_edit '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], status: "blocked", note: "waiting", tasks: ["print"]}]'
  refused_as full "full apply" "$(full_with '.plans += [{id: "P2.3", phase: "P2", title: "Receipt print", reqs: ["R2"], files: ["src/e.txt"], after: [], tasks: ["print"]},
      {id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: ["P2.3"], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is mailed", check: "C2", plan: "P2.2"}]')"
  [[ "$output" == *"P2.1 builds in an earlier wave than P2.2"* ]] || { echo "$output"; false; }
  last_line_is "$TWO_OWNER_NEXT"
}

# R220 (M45): a check running bats with a case filter that matches no case name in the file,
# as the file stands in the project folder at apply time, is refused in every mode before
# anything is written; the kernel reads the file, it never runs the runner.

# with_check RUN_JSON: FULL with a check C9 of R2 running RUN_JSON (its .bats words as files) and a rule naming it.
with_check() {
  full_with ".checks += [{id: \"C9\", req: \"R2\", run: $1, files: ($1 | map(select(endswith(\".bats\"))))}]
    | .rules += [{req: \"R2\", text: \"a receipt is filed\", check: \"C9\"}]"
}
EMPTY_FILTER_NEXT="Next: write the cases the filter names into tests/x.bats (each @test name matching the pattern), see them fail with the runner, then send the document again; or correct the pattern"

@test "R220: every mode refuses a check whose bats case filter matches no case name in the file, naming the check and the file with the mode's name and the pinned words, and ends with its own Next line; the record is unchanged and the runner never ran" {
  local words
  words="runs tests/x.bats with a case filter (--filter 'R220') that matches no case name in the file: the Lead writes the failing cases at planning, so a new check is red because its cases fail, never because none exist"
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R220", "tests/x.bats"]')"
  [[ "$output" == *"C9 $words"* ]] || { echo "not the pinned words: $output"; false; }
  last_line_is "$EMPTY_FILTER_NEXT"
  refused_as add "--add" "$(add_with '.checks[0].run = ["bats", "--filter", "R220", "tests/x.bats"] | .checks[0].files = ["tests/x.bats"]')"
  [[ "$output" == *"C3 $words"* ]] || { echo "not the pinned words: $output"; false; }
  last_line_is "$EMPTY_FILTER_NEXT"
  refused_as patch "--patch" '{"checks": [{"id": "C9", "req": "R2", "run": ["bats", "--filter", "R220", "tests/x.bats"], "files": ["tests/x.bats"]}],
    "rules": [{"req": "R2", "text": "a receipt is filed", "check": "C9"}]}'
  [[ "$output" == *"C9 $words"* ]] || { echo "not the pinned words: $output"; false; }
  last_line_is "$EMPTY_FILTER_NEXT"
  [ ! -e tests/ran ] || { echo "the kernel ran the test file at apply"; false; }
}

@test "R220: a missing test file counts as one with no case names and is named (missing); a pattern grep -E cannot parse matches nothing and is named; with several files or a directory word a match in any one passes; a pattern matching a case passes" {
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R1", "tests/none.bats"]')"
  [[ "$output" == *"runs tests/none.bats (missing) with a case filter (--filter 'R1') that matches no case name"* ]] || { echo "$output"; false; }
  refused_as full "full apply" "$(with_check '["bats", "--filter", "(", "tests/x.bats"]')"
  [[ "$output" == *"with a case filter (--filter '(') that matches no case name"* ]] || { echo "$output"; false; }
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R2", "tests/x.bats"]')"
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R9", "tests"]')"
  [[ "$output" == *"runs tests/x.bats, tests/y.bats with a case filter (--filter 'R9')"* ]] || { echo "the files under the directory word are not named: $output"; false; }
  replan_accepted full "$(with_check '["bats", "--filter", "R2", "tests/x.bats", "tests/y.bats"]')"
  replan_accepted full "$(with_check '["bats", "--filter", "R2", "tests"]')"
  replan_accepted full "$(with_check '["bats", "--filter", "paying", "tests/x.bats"]')"
  replan_accepted full "$(with_check '["bats", "--print-output-on-failure", "--filter", "card is", "tests/x.bats"]')"
  [ ! -e tests/ran ] || { echo "the kernel ran the test file at apply"; false; }
}

@test "R220: a check without a filter, a runner that is not bats, --filter-tags and --filter-status are not judged; -f and --filter= are judged like --filter, behind env and timeout wrappers too; a check resent unchanged is judged on the file as it stands; the two-owner and mixed-owner refusals come first" {
  local run
  for run in '["bats", "tests/x.bats"]' '["pytest", "-k", "R220", "tests/x.bats"]' '["go", "test", "-run", "R220", "./..."]' \
             '["bats", "--filter-tags", "R220", "tests/x.bats"]' '["bats", "--filter-status", "failed", "tests/x.bats"]'; do
    replan_accepted full "$(with_check "$run")"
  done
  for run in '["bats", "-f", "R220", "tests/x.bats"]' '["bats", "--filter=R220", "tests/x.bats"]' \
             '["env", "X=1", "bats", "--filter", "R220", "tests/x.bats"]' '["timeout", "60", "bats", "--filter", "R220", "tests/x.bats"]'; do
    refused_as full "full apply" "$(with_check "$run")"
    [[ "$output" == *"R220') that matches no case name in the file"* ]] || { echo "$output"; false; }
  done
  # The record holds C9 with a filter its file matched; the file changes under it and the same document is refused.
  replan_accepted full "$(with_check '["bats", "--filter", "paying", "tests/x.bats"]')"
  printf '@test "R1: a card is refused" { true; }\n' > tests/x.bats
  refused_as full "full apply" "$(with_check '["bats", "--filter", "paying", "tests/x.bats"]')"
  [[ "$output" == *"--filter 'paying') that matches no case name"* ]] || { echo "$output"; false; }
  # C9's rules name two open plans beside each other: the two-owner refusal, not the empty filter's.
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R220", "tests/x.bats"]' | jq -c '.plans += [{id: "P2.2", phase: "P2", title: "Receipt mail", reqs: ["R2"], files: ["src/d.txt"], after: [], tasks: ["mail"]}]
    | .rules = [.rules[] | if .req == "R2" then . + {plan: "P2.1"} else . end] + [{req: "R2", text: "a receipt is archived", check: "C9", plan: "P2.2"}]')"
  beside_named C9 P2.1 P2.2
  # R2's rules name a plan on only one: the mixed-owner refusal first.
  refused_as full "full apply" "$(with_check '["bats", "--filter", "R220", "tests/x.bats"]' | jq -c '(.rules[] | select(.check == "C9")).plan = "P2.1"')"
  last_line_is "$MIXED_NEXT"
}

# R296 (field report 2026-11-11): a plan whose files include a protected check file is
# refused in every mode, as --amend already refuses it, before anything is written: a
# build would never be let to edit it. The refusal names its mode and the file, says a
# build never edits it, and gives the same way on as the guard (common.jq's
# protected_reason): the main session changes the check with vbw apply --patch, then the
# user approves it. A patch that carries the check's own row (the approved way to change
# a check) is still accepted; only a plan listing the file is refused.

# guard_way FILE: the way on the guard gives for FILE, after its "leave FILE as it is; ".
guard_way() {
  jq -nr -L "$PLUGIN_ROOT/hooks" --arg f "$1" 'include "common"; $f | protected_reason' | sed -n 's/^Next: leave .* as it is; //p'
}
# protected_refused MODE LABEL FILE DOC: the apply is refused, the record unchanged, and the
# message names LABEL, FILE as a protected check file, a build, and the guard's way on.
protected_refused() {
  local way first second
  way=$(guard_way "$3")
  [ -n "$way" ] || { echo "the guard gives no way on for $3"; return 1; }
  refused_as "$1" "$2" "$4" || return 1
  [[ "$output" == *"$3"*"protected check file"* ]] || { echo "the $1 refusal does not name $3 as a protected check file: $output"; return 1; }
  [[ "$output" == *"build"* ]] || { echo "the $1 refusal does not say a build never edits it: $output"; return 1; }
  [[ "$output" == *"$way"* ]] || { echo "the $1 refusal does not give the guard's way on ($way): $output"; return 1; }
  first=$(printf "%s\n" "$output" | sed -n 1p); second=$(printf "%s\n" "$output" | sed -n 2p)
  [[ "$first" == *"$way"* ]] || { echo "the first line of the $1 refusal does not give the guard's way on ($way): $first"; return 1; }
  [ "$second" = "Next: $way" ] || { echo "$1: $second"; return 1; }
}

@test "R296: a full apply, --add and --patch each refuse a plan whose files include a protected check file, naming the mode, the file and the guard's way on; the record is unchanged" {
  protected_refused full "full apply" tests/c2.sh "$(full_with '(.plans[] | select(.id == "P2.1")).files += ["tests/c2.sh"]')"
  protected_refused add "--add" tests/c1.sh "$(add_with '.plans[0].files += ["tests/c1.sh"]')"
  # A file the same document makes a check file is protected too.
  protected_refused add "--add" tests/c3.sh "$(add_with '.plans[0].files += ["tests/c3.sh"]')"
  protected_refused patch "--patch" tests/c2.sh '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt", "tests/c2.sh"], "after": []}]}'
  protected_refused patch "--patch" tests/c1.sh '{"plans": [{"id": "P2.1", "files": ["src/c.txt", "tests/c1.sh"]}]}'
}

@test "R296: a patch carrying a check's own row, with the check file's new content, is accepted; a plan listing no check file beside it is accepted too" {
  printf 'true # stronger\n' > tests/c2.sh
  replan_accepted patch '{"checks": [{"id": "C2", "req": "R2", "run": ["sh", "tests/c2.sh"], "files": ["tests/c2.sh"]}],
    "plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt page", "reqs": ["R2"], "files": ["src/c.txt", "src/d.txt"], "after": []}]}'
  replan_part '[.plans[] | select(.id == "P2.1") | .files]' | jq -e '. == [["src/c.txt", "src/d.txt"]]' > /dev/null || { replan_part .plans; false; }
}
