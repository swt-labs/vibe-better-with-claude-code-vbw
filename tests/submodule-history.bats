#!/usr/bin/env bats
# #732 (docs/workflows.md, "Submodules"; docs/proof.md, "Whose commits VBW
# judges"): a plan file inside a submodule is committed in the submodule, so
# every reader of VBW's provenance reads each submodule's own history as well
# as the project's, and names a file by its project path: the delivered-files
# check, the scope check, vbw show req, the loop's report, vbw show contract
# --changes (the approved content of a test file in a submodule), and QA's
# fingerprint of a phase's files and tests. L1: the kernel on a fixture
# project whose plan and check files are all in a submodule.

load helper

# Built for each case: git writes the submodule's source path into its config, so
# a fixture copy would point back at the fixture (fixture-helper.bash refuses it).
setup() { sub_project; }
teardown() { vbw_teardown; }

# sub_project: a submodule at sub/; R1's check C1 (sub/t.sh, committed in the
# submodule by the approval) and P1.1's file sub/a.js, which vbw commit
# committed in the submodule. P1.1 is done.
sub_project() {
  vbw_setup
  vbw_git_project
  vbw_submodule sub
  git commit -q -m "chore: add sub"
  "$VBW" init > /dev/null
  printf '# Sub\n\n## Requirements\n\n- R1 [auto] sub/a.js says a2\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf '[ "$(cat sub/a.js)" = a2 ]\n' > sub/t.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Sub", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "A", "reqs": ["R1"], "files": ["sub/a.js"], "tasks": ["sub/a.js says a2"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "sub/t.sh"], "files": ["sub/t.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'a2\n' > sub/a.js
  "$VBW" commit P1.1 "feat(sub): a2" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
}

deviations() {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/delivered.sh"; delivered_deviations "$(cat "$VBW_RECORD")"'
}

@test "the fixture: the approval and vbw commit committed in the submodule, and the project's pointer did not move" {
  [ "$(git -C sub log -1 --format=%s)" = "feat(sub): a2" ]
  git -C sub log --format=%H -- t.sh | grep -q .
  # The project's commits hold the submodule as it was added: no commit moved its pointer.
  [ "$(git log --format=%H -- sub | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(git ls-tree HEAD sub | cut -d' ' -f3 | cut -f1)" != "$(git -C sub rev-parse HEAD)" ]
}

@test "delivered files: a hand change to a plan's file in the submodule is a deviation, named by its project path" {
  [ "$(deviations)" = '[]' ] || { deviations; false; }
  printf 'by hand\n' > sub/a.js
  git -C sub commit -q -am "chore: by hand"
  deviations | jq -e --arg h "$(git -C sub rev-parse HEAD)" 'length == 1 and .[0].file == "sub/a.js" and .[0].plan == "P1.1" and .[0].change == "changed" and .[0].by == [$h]' \
    || { deviations; false; }
}

@test "scope: a commit in the submodule naming the plan that changes a file outside it is a violation, named by its project path" {
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-prove.sh"; prove_scope "$(cat "$VBW_RECORD")"' | jq -e '.scope == []' || false
  printf 'x\n' > sub/out.js
  git -C sub add out.js
  git -C sub commit -q -m "feat(sub): out" -m "VBW-Plan: P1.1"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/cmd-prove.sh"; prove_scope "$(cat "$VBW_RECORD")"' > "$TEST_ROOT/scope.json"
  jq -e --arg h "$(git -C sub rev-parse HEAD | cut -c1-12)" '.scope == ["\($h) (P1.1) changed sub/out.js, which is not in the plan"]' "$TEST_ROOT/scope.json" \
    || { cat "$TEST_ROOT/scope.json"; false; }
}

@test "vbw show req lists the requirement's commits in the submodule" {
  vbw_run show req R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"$(git -C sub rev-parse --short HEAD) feat(sub): a2 (in sub)"* ]] || { echo "$output"; false; }
}

@test "the loop's report lists a shipped item's commits in the submodule" {
  jq '.loop = {started_at: "2026-10-30T00:00:00Z", ended: {at: "2026-10-30T01:00:00Z", reason: "end of the backlog"},
      items: [{id: "T1", text: "sub/a.js says a2", status: "shipped", milestone: .milestone.id, req: "R1"}]}' .vbw/record.json > "$TEST_ROOT/l.json" \
    && cp "$TEST_ROOT/l.json" .vbw/record.json
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel 'for l in loop cmd-loop loop-report; do . "$VBW_LIB/$l.sh"; done; loop_report_write "$VBW_RECORD"'
  grep -qF "$(git -C sub rev-parse --short HEAD) feat(sub): a2 (in sub)" .vbw/loop-report.md || { cat .vbw/loop-report.md; false; }
}

@test "vbw show contract --changes shows the diff of a changed test file in the submodule from its approved content" {
  printf '[ "$(cat sub/a.js)" = a2 ] && [ -n "$(cat sub/a.js)" ]\n' > sub/t.sh
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"changed test file sub/t.sh"* ]] || { echo "$output"; false; }
  [[ "$output" != *"not in the project's git history"* ]] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF -- '+[ "$(cat sub/a.js)" = a2 ] && [ -n "$(cat sub/a.js)" ]' || { echo "$output"; false; }
}

@test "QA's fingerprint of a phase moves with a commit of its file, or of its test file, in the submodule" {
  local before after
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  before=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -c '.P1 | {files, tests}')
  printf 'by hand\n' > sub/a.js
  git -C sub commit -q -am "chore: by hand"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  after=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -c '.P1 | {files, tests}')
  [ "$(printf '%s' "$before" | jq -r .files)" != "$(printf '%s' "$after" | jq -r .files)" ] || { echo "files: $before / $after"; false; }
  [ "$(printf '%s' "$before" | jq -r .tests)" = "$(printf '%s' "$after" | jq -r .tests)" ] || { echo "tests: $before / $after"; false; }
  printf 'true\n' > sub/t.sh
  git -C sub commit -q -am "test: by hand"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  before=$after
  after=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -c '.P1 | {files, tests}')
  [ "$(printf '%s' "$before" | jq -r .tests)" != "$(printf '%s' "$after" | jq -r .tests)" ] || { echo "tests: $before / $after"; false; }
}
