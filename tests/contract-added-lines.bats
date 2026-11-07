#!/usr/bin/env bats
# R269: lines added to an approved check file do not stop the run. The approval
# snapshot (.vbw/runtime/approved-contract.json) records the approval's commit
# and each check file's git blob id; a check file whose approved lines are all
# still there, in their order, with new lines among them, is "added to": the
# run goes on, vbw next says prove and names the file with its count of added
# lines, the proof judges the check with the approved content (the evidence
# records the digest it judged, the reuse keys on it) and says so, and vbw show
# contract lists the file with its diff. A file with a line removed or changed,
# or a new file, still waits for approval before the proof, as before. L1.

load helper
load fixture-helper

SNAPSHOT='.vbw/runtime/approved-contract.json'
APPROVED_CHECK=$'#!/bin/sh\n# pays\ngrep -qx paid src/pay.txt\n'

# added_project: R1 with check C1 (sh tests/pay.sh, three lines), approved and built.
added_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf '%s' "$APPROVED_CHECK" > tests/pay.sh
  printf '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1"], "tier": "express"}],
   "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"], "after": [], "tasks": ["pay"]}],
   "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]}],
   "rules": [{"req": "R1", "text": "paid is written", "check": "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): paid" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
}

setup_file() { fixture_build added added_project; }
setup() { fixture_copy added; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# check_file TEXT: tests/pay.sh holds TEXT, committed (the proof runs on HEAD).
check_file() {
  printf '%s' "$1" > tests/pay.sh
  git add tests/pay.sh && git commit -q -m "test: edit the check file"
}

# classify: "waiting: <files on one line>" then "added: <file TAB lines, one per line>",
# as contract_waiting and contract_added report them. Both are captured with $(...), as
# every kernel caller captures them, so neither may hand its answer back in a variable (D654).
classify() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel 'r=$(cat "$VBW_RECORD"); w=$(contract_waiting "$r"); a=$(contract_added "$r"); printf "waiting: %s\nadded: %s\n" "$(printf "%s" "$w" | tr "\n" " ")" "$(printf "%s" "$a" | tr "\t\n" ",;")"'
}

@test "R269 classify: the approval snapshot records the approval's commit and each check file's git blob id" {
  jq -e --arg h "$(git rev-parse HEAD~1)" --arg b "$(git hash-object tests/pay.sh)" \
    '.commit == $h and .blobs["tests/pay.sh"] == $b' "$SNAPSHOT" || { cat "$SNAPSHOT"; false; }
}

@test "R269 classify: lines added at the end, in the middle or at the top of an approved check file are added-to, not waiting" {
  check_file "${APPROVED_CHECK}exit 1
"
  run classify
  [ "$output" = $'waiting: \nadded: tests/pay.sh,1;' ] || { echo "$output"; false; }
  check_file $'#!/bin/sh\necho one\n# pays\necho two\ngrep -qx paid src/pay.txt\n'
  run classify
  [ "$output" = $'waiting: \nadded: tests/pay.sh,2;' ] || { echo "$output"; false; }
  check_file $'# top\n#!/bin/sh\n# pays\ngrep -qx paid src/pay.txt\n'
  run classify
  [ "$output" = $'waiting: \nadded: tests/pay.sh,1;' ] || { echo "$output"; false; }
}

@test "R269 classify: a removed, changed or reordered line, a new file, and a snapshot without blob ids wait for approval as before" {
  check_file $'#!/bin/sh\ngrep -qx paid src/pay.txt\n'
  run classify
  [ "$output" = $'waiting: tests/pay.sh \nadded: ' ] || { echo "removed: $output"; false; }
  check_file $'#!/bin/sh\n# pays\ngrep -qx PAID src/pay.txt\n'
  run classify
  [ "$output" = $'waiting: tests/pay.sh \nadded: ' ] || { echo "changed: $output"; false; }
  check_file $'# pays\n#!/bin/sh\ngrep -qx paid src/pay.txt\n'
  run classify
  [ "$output" = $'waiting: tests/pay.sh \nadded: ' ] || { echo "reordered: $output"; false; }
  check_file "$APPROVED_CHECK"
  run classify
  [ "$output" = $'waiting: \nadded: ' ] || { echo "back to approved: $output"; false; }
  # A fix adds a check file the approval does not know.
  printf 'true\n' > tests/more.sh
  jq '.checks += [{id: "C2", req: "R1", run: ["sh", "tests/more.sh"], files: ["tests/more.sh"], fix: "F1"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  run classify
  [ "$output" = $'waiting: tests/more.sh \nadded: ' ] || { echo "new file: $output"; false; }
}

@test "R269 classify: a snapshot from before the blob ids (no commit, no blobs) leaves an added line waiting, as it did" {
  check_file "${APPROVED_CHECK}exit 1
"
  jq 'del(.commit, .blobs)' "$SNAPSHOT" > "$TEST_ROOT/old.json" && cp "$TEST_ROOT/old.json" "$SNAPSHOT"
  run classify
  [ "$output" = $'waiting: tests/pay.sh \nadded: ' ] || { echo "old snapshot: $output"; false; }
}

@test "R269 classify: a check file with a removed line still sends vbw next to approve first" {
  check_file $'#!/bin/sh\ngrep -qx paid src/pay.txt\n'
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "approve" and .detail.files == ["tests/pay.sh"]' > /dev/null || { echo "$output"; false; }
}

@test "R269 next: with lines added to a check file vbw next says prove and names the file with its count of added lines" {
  check_file "${APPROVED_CHECK}echo extra
exit 1
"
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "prove" and .added_to == [{file: "tests/pay.sh", lines: 2}]' > /dev/null || { echo "$output"; false; }
  run "$VBW" next < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n''check file tests/pay.sh: 2 lines added since the approval; the proof judges it with the approved content until they are approved at the next gate'* ]] || { echo "$output"; false; }
  check_file "${APPROVED_CHECK}exit 1
"
  run "$VBW" next < /dev/null
  [[ "$output" == *'check file tests/pay.sh: 1 line added since the approval; the proof judges it with the approved content until they are approved at the next gate'* ]] || { echo "$output"; false; }
}

@test "R269 proof: the proof judges an added-to check with the approved content, records the digest it judged, says so, and reuses it; the added lines count once approved" {
  check_file "${APPROVED_CHECK}echo extra
exit 1
"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e --arg d "$(printf '%s' "$APPROVED_CHECK" | shasum -a 256 | cut -d' ' -f1)" \
    '.evidence.checks.C1.status == "pass" and .evidence.checks.C1.judged == {"tests/pay.sh": $d}' .vbw/record.json \
    || { jq '.evidence.checks.C1' .vbw/record.json; false; }
  [[ "$output" == *'C1 pass'*'judged with the approved content (2 added lines pending approval)'* ]] || { echo "$output"; false; }
  # The working file as it is runs red: the pass came from the approved content.
  run sh tests/pay.sh
  [ "$status" -eq 1 ]
  # Nothing changed for the proof: the result is reused.
  run "$VBW" prove < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *'C1 pass'*'reused'* ]] || { echo "$output"; false; }
  # Approved, the added lines are the check: it runs and fails.
  "$VBW" approve > /dev/null
  run "$VBW" prove < /dev/null
  [ "$status" -ne 0 ]
  jq -e '.evidence.checks.C1.status == "fail" and (.evidence.checks.C1 | has("judged") | not)' .vbw/record.json || { jq '.evidence.checks.C1' .vbw/record.json; false; }
}

@test "R269 changes: vbw show contract and vbw show contract --changes list an added-to file with its count and the diff of the added lines" {
  check_file "${APPROVED_CHECK}echo extra
exit 1
"
  local cmd
  for cmd in "show contract" "show contract --changes"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    run "$VBW" $cmd < /dev/null
    [ "$status" -eq 0 ] || { echo "$cmd: $output"; false; }
    [[ "$output" == *'test file tests/pay.sh: 2 lines added since the approval'* ]] || { echo "$cmd: $output"; false; }
    [[ "$output" == *$'\n+echo extra\n+exit 1'* ]] || { echo "$cmd: $output"; false; }
    [[ "$output" != *'changed test file tests/pay.sh'* ]] || { echo "$cmd: $output"; false; }
  done
}

@test "R269 docs: docs/proof.md, docs/guards.md and docs/workflows.md tell the two cases apart" {
  grep -q 'added since the approval' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not describe lines added since the approval"; false; }
  grep -q 'judged with the approved content' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not name the summary line"; false; }
  grep -qi 'added-to\|lines added' "$REPO_ROOT/docs/guards.md" || { echo "docs/guards.md does not describe an added-to check file"; false; }
  grep -qi 'added-to\|lines added' "$REPO_ROOT/docs/workflows.md" || { echo "docs/workflows.md does not describe an added-to check file"; false; }
}
