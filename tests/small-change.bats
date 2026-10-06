#!/usr/bin/env bats
# R72 (docs/rigor.md): a small change (one or two files, low risk) goes from
# the user's request to done through /vbw:vibe without a planning workflow:
# vbw next marks the plan step as small (detail.small) whatever the size of the
# repository, the router plans it itself as one express phase with one plan
# and its check, the user approves once, it is built, checked and closed. A
# change touching more than two files, or a risk path, is not treated as small
# and follows normal planning: in a large repository vbw apply refuses an
# express phase of more than two files. L1: the kernel on fixtures; the router's
# own behaviour is a real-app (L3) matter.

load helper
load rigor-helper

teardown() { vbw_teardown; }

# big_repo: one requirement, existing code, a project test command, 40 more files.
big_repo() {
  rigor_project "${1:-1}"
  mkdir -p many
  local i
  for ((i = 1; i <= 40; i++)); do printf '%s\n' "$i" > "many/f$i.txt"; done
  printf 'x\n' > src/app.js
  git add many src && git commit -q -m "chore(test): a real-sized repository"
  edit_record '.commands.test = ["true"]'
}

plan_step() {
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "plan"' > /dev/null
}

@test "R72: in a large repository a one-requirement, low-risk request is marked small, and its early tier is unchanged" {
  big_repo 1
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == true and .detail.tier == "standard"' || { echo "$output"; false; }
}

@test "R72: two [auto] requirements with no risk word are still small" {
  big_repo 2
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == true' || { echo "$output"; false; }
}

@test "R72: three requirements are not small" {
  big_repo 3
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == false' || { echo "$output"; false; }
}

@test "R72: a [human] requirement is not small" {
  big_repo 1
  edit_record '(.requirements[0]).proof = "human"'
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == false' || { echo "$output"; false; }
}

@test "R72: a request that names a risk path (sign-in, payments, migrations, secrets, deletion, CI) is not small" {
  big_repo 1
  printf '%s\n' '# Notes' '' '## Requirements' '' '- R1 [auto] Visitors can log in with a password' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == false' || { echo "$output"; false; }
}

@test "R72: a forced standard or deep rigor is never small" {
  big_repo 1
  edit_record '.settings.rigor = "deep"'
  plan_step
  printf '%s' "$output" | jq -e '.detail.small == false' || { echo "$output"; false; }
}

@test "R72: in a large repository an express phase of two files is accepted" {
  big_repo 1
  rigor_apply "$(rigor_doc 1 "" src/a.js src/b.js)" > /dev/null
  phase_json '.phases[0].tier == "express"'
}

@test "R72: in a large repository a change over more than two files is not small: express is refused, the tier is standard when left to the kernel" {
  big_repo 1
  run rigor_apply "$(rigor_doc 1 express src/a.js src/b.js src/c.js)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"floor at standard"* ]] || { echo "$output"; false; }
  rigor_apply "$(rigor_doc 1 "" src/a.js src/b.js src/c.js)" > /dev/null
  phase_json '.phases[0].tier == "standard"'
}

@test "R72: a small change goes from plan to done with one approval: build, check, close, ship" {
  big_repo 1
  printf 'grep -qx done src/note.txt\n' > tests/note.sh
  printf 'start\n' > src/note.txt
  git add tests src && git commit -q -m "chore(test): note"
  local doc
  doc=$(rigor_doc 1 express src/note.txt | jq -c '.checks = [{id: "C1", req: "R1", run: ["sh", "tests/note.sh"], files: ["tests/note.sh"]}] | .rules = [{req: "R1", text: "the note says done", check: "C1"}]')
  rigor_apply "$doc" > /dev/null
  phase_json '.phases[0].tier == "express"'
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "approve"'
  "$VBW" approve > /dev/null
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1"]'
  printf 'done\n' > src/note.txt
  "$VBW" commit P1.1 "feat(note): done" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" next --json
  printf '%s' "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
}

@test "R72: the router and docs tell the small path: plan it itself, no planning workflow, more than two files or a risk path plans normally" {
  local r="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -q 'detail.small' "$r"
  grep -qi 'two files' "$r"
  grep -q 'detail.small' "$BATS_TEST_DIRNAME/../docs/rigor.md"
}
