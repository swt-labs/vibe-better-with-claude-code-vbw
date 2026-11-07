#!/usr/bin/env bats
# R188 (P140; D379, D380, D381; docs/workflows.md): the builders run the
# mutation check during the build. The building workflow passes each plan's
# rigor tier to its builder; a plan of a standard or deep phase gets the
# mutation instruction, a plan of an express phase none; the fixing workflow
# none. The Dev and Docs briefs name the step's commands (vbw mutate, vbw plan
# block) and levels, and keep its prohibitions (never weaken a check, never in
# a fix). A Dev block naming the rule raises the phase one tier. L1, with stubbed
# agents (tests/helpers/run-workflow.js) and the kernel on a fixture project: no
# model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows"
DEV="$PLUGIN_ROOT/agents/dev.md"
DOCS="$PLUGIN_ROOT/agents/docs.md"

teardown() { vbw_teardown; }

needs_node() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# build_prompts: the building workflow's agent calls for four plans, one per
# tier and a documentation plan at standard, as JSON {label: prompt}.
build_prompts() {
  node "$RUN" "$WF/building.js" '{"plans":["P1.1","P2.1","P3.1","P4.1"],"docs":["P4.1"],
    "rigor":{"P1":{"tier":"standard"},"P2":{"tier":"deep"},"P3":{"tier":"express"},"P4":{"tier":"standard"}}}' '{}' \
    | jq -c '[.calls[] | {key: .opts.label, value: .prompt}] | from_entries'
}
prompt_of() { build_prompts | jq -r --arg l "$1" '.[$l]'; }
# has_line FILE WORD...: one line of FILE holds every WORD (case-insensitive).
has_line() {
  local f=$1 w lines
  shift
  lines=$(cat "$f")
  for w in "$@"; do lines=$(printf '%s\n' "$lines" | grep -iF -- "$w") || { echo "no line of ${f##*/} holds all of: $*"; return 1; }; done
}

@test "R188: building passes each plan's tier; standard and deep plans get the mutation instruction, express none" {
  needs_node
  local p
  p=$(prompt_of "dev P1.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*standard' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
  p=$(prompt_of "dev P2.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*deep' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
  p=$(prompt_of "dev P3.1")
  ! printf '%s' "$p" | grep -qi mutat || { echo "$p"; false; }
  p=$(prompt_of "docs P4.1")
  printf '%s' "$p" | grep -Eiq 'tier[^a-z]*standard' && printf '%s' "$p" | grep -qi mutation || { echo "$p"; false; }
}

@test "R188: the fixing workflow gives no mutation instruction" {
  needs_node
  ! grep -qi mutat "$WF/fixing.js" || { grep -ni mutat "$WF/fixing.js"; false; }
  node "$RUN" "$WF/fixing.js" '{"groups":[["F1"]],"rigor":{"P1":{"tier":"deep"}}}' '{}' \
    | jq -e '[.calls[].prompt | test("mutat"; "i")] | any | not' > /dev/null
}

# names FILE WORD...: FILE holds every WORD (case-insensitive).
names() {
  local f=$1 w
  shift
  for w in "$@"; do grep -qiF -- "$w" "$f" || { echo "${f##*/} does not name: $w"; return 1; }; done
}

@test "R188: the Dev names the mutation step's commands and levels: vbw mutate, standard, deep, express, vbw plan block" {
  names "$DEV" "vbw mutate" standard deep express "vbw plan block"
}

@test "T174: the Dev breaks once per rule at standard and deep, a task only when no rule's check covers it, never per edge case" {
  local m
  m=$(grep -i '^ *- Standard' "$DEV")
  printf '%s' "$m" | grep -qi 'standard and deep' && printf '%s' "$m" | grep -qi 'once for each rule' || { echo "$m"; false; }
  printf '%s' "$m" | grep -qi "no rule's check covers" || { echo "$m"; false; }
  ! grep -qiE 'once per task|edge case its rules' "$DEV" || { grep -niE 'once per task|edge case its rules' "$DEV"; false; }
}

@test "R188: the Dev's prohibitions hold: a strengthened check is never weakened, and a fix never runs the mutation step" {
  has_line "$DEV" "never weaken"
  has_line "$DEV" mutation fix never
}

@test "R188: the Docs agent names vbw mutate, the levels, vbw plan block, and never weakens a check" {
  names "$DOCS" "vbw mutate" standard deep express "vbw plan block"
  has_line "$DOCS" "never weaken"
}

@test "R188: a Dev block naming the rule raises the phase one tier, as any Dev block does" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}]}' | "$VBW" apply > /dev/null
  run "$VBW" plan block P1.1 "R1.1 stays green after two strengthening attempts (checked stdout, then stderr)" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.phases[0].tier == "deep" and (.phases[0].escalations[-1].reason | contains("R1.1"))' .vbw/record.json || { jq '.phases[0]' .vbw/record.json; false; }
}

# R265 (T247; D634): the kernel never touches the working copy, so the Dev commits every
# finished task before a break, edits the break out right after each vbw mutate (and before
# the next --queue), and is no longer told that VBW undoes it or to check the file.
@test "R265: the Dev's mutation step says to commit every finished task before a break, that the kernel leaves the file as given, and to edit the break out right after each mutate and before the next --queue; the undo sentences are gone" {
  has_line "$DEV" "commit" "before" "break"
  has_line "$DEV" "leaves the file as" "mutate"
  has_line "$DEV" "edit the break out" "right after each"
  has_line "$DEV" "edit the break out before the next --queue"
  has_line "$DEV" "same broken bytes twice"
  has_line "$DEV" "--queue" "edit"
  ! grep -qi 'it undoes the break' "$DEV" || { echo "dev.md still says VBW undoes the break"; false; }
  ! grep -qi 'check the file is unchanged' "$DEV" || { echo "dev.md still says to check the file is unchanged"; false; }
}

@test "R265: the Docs agent's mutation step says to commit every finished task before a break and to edit the break out right after each mutate; the undo sentences are gone" {
  has_line "$DOCS" "commit" "before" "break"
  has_line "$DOCS" "leaves the file as" "mutate"
  has_line "$DOCS" "edit the break out" "right after each"
  has_line "$DOCS" "same broken bytes twice"
  ! grep -qi 'it undoes the break' "$DOCS" || { echo "docs.md still says VBW undoes the break"; false; }
  ! grep -qi 'check the file is unchanged' "$DOCS" || { echo "docs.md still says to check the file is unchanged"; false; }
}

@test "R265: docs/workflows.md's mutate row and its paragraph say the break stays in the working copy and the Dev edits it out; 'VBW undoes the break' is gone" {
  local doc="$REPO_ROOT/docs/workflows.md"
  ! grep -q 'VBW undoes the break' "$doc" || { echo "docs/workflows.md still says VBW undoes the break"; false; }
  grep -E '^\| *`vbw mutate' "$doc" | grep -qiE 'leaves (the|each|every) (named )?file|stays in the working copy|never touches' || { echo "the mutate row does not say the file is left as given"; false; }
  grep -E '^\| *`vbw mutate' "$doc" | grep -qi 'stays in the working copy' && grep -E '^\| *`vbw mutate' "$doc" | grep -qi 'edits it out' || { echo "the mutate row does not say the break stays and the Dev edits it out"; false; }
  tr '\n' ' ' < "$doc" | grep -qiE 'edit(s)? the break out' || { echo "docs/workflows.md does not tell the Dev to edit the break out"; false; }
  tr '\n' ' ' < "$doc" | grep -qiE 'same (broken )?bytes[^.]*(twice|again)[^.]*refused|refus[^.]*same (broken )?bytes' || { echo "docs/workflows.md does not document the refusal of the same bytes twice"; false; }
}
