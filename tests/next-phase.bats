#!/usr/bin/env bats
# R106 (docs/next.md): vbw next --json states the next free phase number, one
# after the highest phase number the record knows (shipped, started and removed
# phases included; a sub-phase like P65.1 counts as its whole number), so the
# Architect is given it and planning never needs a renumbering round. L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors can read notes\n- R2 [auto] Visitors can add notes\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

next_phase() { "$VBW" next --json < /dev/null | jq -c '.next_phase'; }

@test "R106: a project with no phase starts at 1" {
  [ "$(next_phase)" = 1 ]
}

@test "R106: the next free number is one after the highest phase" {
  edit_record '.phases = [{id: "P1", title: "A", reqs: ["R1"], milestone: "M1"}, {id: "P3", title: "B", reqs: ["R2"], milestone: "M1"}]'
  [ "$(next_phase)" = 4 ]
}

@test "R106: numbers compare as numbers, not as text (P10 is higher than P9)" {
  edit_record '.phases = [{id: "P9", title: "A", reqs: ["R1"], milestone: "M1"}, {id: "P10", title: "B", reqs: ["R2"], milestone: "M1"}]'
  [ "$(next_phase)" = 11 ]
}

@test "R106: a sub-phase named in a plan or a decision counts as its whole number" {
  edit_record '.phases = [{id: "P2", title: "A", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P2.1", phase: "P2", title: "A", reqs: ["R1", "R2"], files: ["src/a.txt"], after: [], status: "planned"}]
    | .decisions += [{id: "D1", at: "2026-10-01T09:00:00Z", text: "F49: keep commits 9a4287b0 and dc143c6a (P65.1: an alone check is at the gate)"}]'
  [ "$(next_phase)" = 66 ]
}

@test "R106: phases of a shipped milestone count" {
  edit_record '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | (.requirements[]) |= (.milestone = "M2")
    | .phases = [{id: "P7", title: "Old", reqs: ["R1"], milestone: "M1"}]'
  [ "$(next_phase)" = 8 ]
}

@test "R106: a phase that was started counts, whatever else the record holds" {
  edit_record '.phases = [{id: "P20", title: "A", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P20.1", phase: "P20", title: "A", reqs: ["R1", "R2"], files: ["src/a.txt"], after: [], status: "building"}]'
  [ "$(next_phase)" = 21 ]
}

@test "R106: a removed phase that a recorded decision names still counts" {
  edit_record '.phases = [{id: "P2", title: "A", reqs: ["R1", "R2"], milestone: "M1"}]
    | .decisions += [{id: "D1", at: "2026-10-01T09:00:00Z", text: "Contract approved: 2 requirements, 1 checks, 1 plans (abcdef123456); express: P12 (R1)"}]'
  [ "$(next_phase)" = 13 ]
}

@test "R106: letters that merely end in P and digits are not phase numbers" {
  edit_record '.phases = [{id: "P2", title: "A", reqs: ["R1", "R2"], milestone: "M1"}]
    | .decisions += [{id: "D1", at: "2026-10-01T09:00:00Z", text: "SHIP99, ABP77 and XP5 are not phases"}]'
  [ "$(next_phase)" = 3 ]
}

@test "R106: planning again numbers after the highest, including phases already started" {
  edit_record '.phases = [{id: "P1", title: "A", reqs: ["R1"], milestone: "M1"}, {id: "P2", title: "B", reqs: ["R2"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["src/a.txt"], after: [], status: "done"},
                {id: "P2.1", phase: "P2", title: "B", reqs: ["R2"], files: ["src/b.txt"], after: [], status: "planned"}]'
  [ "$(next_phase)" = 3 ]
}

@test "R106: the number is part of every answer of vbw next, not only the plan step" {
  edit_record '.phases = [{id: "P4", title: "A", reqs: ["R1", "R2"], milestone: "M1"}]
    | .plans = [{id: "P4.1", phase: "P4", title: "A", reqs: ["R1", "R2"], files: ["src/a.txt"], after: [], status: "planned"}]
    | .checks = [{id: "C1", req: "R1", run: ["true"]}, {id: "C2", req: "R2", run: ["true"]}]'
  local action
  action=$("$VBW" next --json < /dev/null | jq -r '.action')
  [ "$action" != plan ] || { "$VBW" next --json < /dev/null; false; }
  [ "$(next_phase)" = 5 ]
}

@test "R106: docs/next.md names next_phase and how the number is found" {
  grep -q 'next_phase' "$REPO_ROOT/docs/next.md"
  grep -qi 'sub-phase' "$REPO_ROOT/docs/next.md"
}
