#!/usr/bin/env bats
# R74 (docs/workflows.md): a plan whose files were already committed (for
# example by the approval commit, with no VBW-Plan trailer) and whose checks
# pass can be marked done; if its checks fail it cannot, and the failing check
# is named. A plan with no commit and no passing check still cannot be closed.
# Only the record's own history counts (docs/proof.md, "Whose commits VBW
# judges"): a commit older than the record whose VBW-Plan trailer names the
# same id (an old roadmap's) is not this plan's commit.
# L1: the kernel on a fixture project.

load helper
load fixture-helper

done_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

setup_file() { fixture_build done done_project; }
setup() { fixture_copy done; }

teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# approve_with CONTENT: commit src/pay.txt (a plain commit, no trailer) and the
# contract's files, then approve.
approve_with() {
  printf '%s\n' "$1" > src/pay.txt
  git add -A && git commit -q -m "feat(pay): pay"
  "$VBW" approve > /dev/null
}

status_of() { jq -r --arg p "$1" '.plans[] | select(.id == $p) | .status' .vbw/record.json; }

@test "R74: files committed with no VBW-Plan trailer and checks that pass: the plan can be marked done" {
  approve_with paid
  ! git log --format='%(trailers:key=VBW-Plan,valueonly)' | grep -q 'P1.1' || false
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(status_of P1.1)" = done ]
}

@test "R74: files committed but a check fails: it cannot be marked done and the failing check is named" {
  approve_with nope
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [[ "$output" == *C1* ]]
  [ "$(status_of P1.1)" != done ]
}

@test "R74: files with uncommitted changes still cannot be marked done" {
  approve_with paid
  printf 'paid\nmore\n' > src/pay.txt
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted"* ]]
  [ "$(status_of P1.1)" != done ]
}

@test "R74: a plan whose files are not committed anywhere has no commit and cannot be marked done" {
  printf 'paid\n' > src/pay.txt
  git add tests && git commit -q -m "test(pay): the check"
  "$VBW" approve > /dev/null
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [ "$(status_of P1.1)" != done ]
}

@test "R74: committed files with no check that could prove them are not enough" {
  approve_with paid
  jq '.checks = [] | .requirements |= map(.proof = "human") | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): no checks"
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [ "$(status_of P1.1)" != done ]
}

@test "R74: a plan committed by vbw commit is closed exactly as before" {
  printf 'paid\n' > src/pay.txt
  git add tests && git commit -q -m "test(pay): the check"
  "$VBW" approve > /dev/null
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(status_of P1.1)" = done ]
}

@test "R74: an old roadmap's commit with the same VBW-Plan id, older than the record, is not the plan's commit" {
  git commit -q --allow-empty -m "feat: old" -m "VBW-Plan: P1.1"
  git add tests && git commit -q -m "test(pay): the check"
  "$VBW" approve > /dev/null
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"no commit"* ]] || { echo "$output"; false; }
  [ "$(status_of P1.1)" != done ]
}

# sub_plan [OLD]: the plan's file and its check's subject move into a submodule
# at sub/ (OLD: its history already holds a commit whose VBW-Plan trailer names
# P1.1, an old roadmap's), added before the record is first committed, then the
# contract is approved.
sub_plan() {
  git init -q "$TEST_ROOT/subsrc"
  printf 'unpaid\n' > "$TEST_ROOT/subsrc/pay.txt"
  git -C "$TEST_ROOT/subsrc" add pay.txt
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  [ -z "${1:-}" ] || git -C "$TEST_ROOT/subsrc" commit -q --allow-empty -m "feat: old" -m "VBW-Plan: P1.1"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  printf 'grep -qx paid sub/pay.txt\n' > tests/pay.sh
  jq '(.plans[] | select(.id == "P1.1")).files = ["sub/pay.txt"]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore: sub"
  "$VBW" approve > /dev/null
}

@test "a plan whose file is in a submodule: its vbw commit there is found and the plan closes" {
  sub_plan
  printf 'paid\n' > sub/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(status_of P1.1)" = done ]
}

@test "a plan whose file is in a submodule: an uncommitted change there still stops done" {
  sub_plan
  printf 'paid\n' > sub/pay.txt
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted changes in: sub/pay.txt"* ]] || { echo "$output"; false; }
  [ "$(status_of P1.1)" != done ]
}

@test "a plan whose file is in a submodule: the submodule's commits older than the record are not the plan's" {
  sub_plan old
  vbw_run plan done P1.1
  [ "$status" -ne 0 ]
  # Judged as work committed without a trailer, not as the plan's commit.
  [[ "$output" == *"is committed but its checks do not pass"* ]] || { echo "$output"; false; }
  [ "$(status_of P1.1)" != done ]
}

@test "a check file in a submodule is committed there by the approval, and the plan built beside it closes" {
  git init -q "$TEST_ROOT/subsrc"
  printf 'unpaid\n' > "$TEST_ROOT/subsrc/pay.txt"
  git -C "$TEST_ROOT/subsrc" add pay.txt
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  printf 'grep -qx paid sub/pay.txt\n' > sub/pay.sh
  jq '(.plans[] | select(.id == "P1.1")).files = ["sub/pay.txt"]
    | .checks = [{id:"C1", req:"R1", run:["sh","sub/pay.sh"], files:["sub/pay.sh"]}] | .protected = ["sub/pay.sh"]' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add .gitmodules sub && git commit -q -m "chore: sub"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(git -C sub status --porcelain -- pay.sh)" ] || { git -C sub status --porcelain; false; }
  [ "$(git -C sub log -1 --format= --name-only)" = "pay.sh" ]
  printf 'paid\n' > sub/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R74: with an old roadmap's commit in the history, a commit after the record still counts" {
  git commit -q --allow-empty -m "feat: old" -m "VBW-Plan: P1.1"
  git add tests && git commit -q -m "test(pay): the check"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(status_of P1.1)" = done ]
}
