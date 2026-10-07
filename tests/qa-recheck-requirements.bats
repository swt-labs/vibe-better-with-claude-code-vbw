#!/usr/bin/env bats
# R104 (docs/proof.md): a phase whose [auto] requirements changed (one added,
# reworded or removed) is checked by QA again, and the reason is shown in plain
# words; a goal or code change still lists it whatever else happened. L1.

load helper
load qa-recheck-helper
load qa-skip-helper

setup() { qa_skip_project; }
teardown() { vbw_teardown; }

@test "R104: a reworded [auto] requirement of the phase lists it again, naming the requirement as the reason" {
  spec_reword 'Part three works' 'Part three works for every customer'
  [ "$(rechecked)" = '["P1"]' ] || { next_json | jq -c '.qa'; false; }
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("requirement"; "i"))'
  if next_json | jq -r '.qa.recheck.P1[]' | grep -Eiq 'fingerprint|hash|sha|digest|checksum|tree|blob|inputs'; then
    echo "jargon in the reason"
    false
  fi
}

@test "R104: the reason for a reworded [auto] requirement reaches the QA instruction" {
  spec_reword 'Part three works' 'Part three works for every customer'
  vbw_run next
  [ "$status" -eq 0 ]
  [[ "$output" == *"P1 ("* ]] || { echo "$output"; false; }
  [[ "$output" == *"requirement"* ]] || { echo "$output"; false; }
  vbw_run show qa
  [[ "$output" == *"requirement"* ]] || { echo "$output"; false; }
}

@test "R104: an [auto] requirement added to the phase lists it again, naming the requirement" {
  edit_record '.requirements += [{id: "R4", text: "Part four works", proof: "auto", status: "proven", milestone: "M1"}]
    | (.phases[] | select(.id == "P1")).reqs += ["R4"]'
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("requirement"; "i"))'
}

@test "R104: an [auto] requirement removed from the phase lists it again" {
  spec_drop 'R3 [auto]'
  jq -e '.phases[0].reqs == ["R1", "R2"]' .vbw/record.json
  [ "$(rechecked)" = '["P1"]' ]
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("requirement"; "i"))'
}

@test "R104: a decision recorded together with a reworded [auto] requirement still lists the phase" {
  "$VBW" decide "Use blue buttons" > /dev/null
  spec_reword 'Part three works' 'Part three works for every customer'
  [ "$(rechecked)" = '["P1"]' ]
}

@test "R104: rewording a [human] requirement alone is not an [auto] change: the phase stands" {
  spec_reword 'Part two feels right' 'Part two feels right to the owner'
  jq -e '(.requirements[] | select(.id == "R2")).status == "open"' .vbw/record.json
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c '.qa.recheck'; false; }
}

@test "R104: docs/proof.md says which changes do not list a passed phase again and which do" {
  grep -qi 'decision' "$REPO_ROOT/docs/proof.md"
  grep -qiE '\[human\] requirement.*(removed|removing)|(removed|removing).*\[human\] requirement' "$REPO_ROOT/docs/proof.md"
  grep -qiE 'requirement.*(reworded|changed)' "$REPO_ROOT/docs/proof.md"
}
