#!/usr/bin/env bats
# R105 (docs/rigor.md): a phase's rigor tier is not raised by proven
# requirements it could affect when each of them is guarded by an approved
# check the proof re-runs; only proven requirements no check guards raise it
# (a [human] requirement a person accepted, or one whose check is not
# approved), and the tier's reasons still list what the phase could affect.
# Other reasons for a higher tier work as before. L1.

load helper
load rigor-helper

# M1 is shipped: R1 [auto] proven by P1.1 (src/old.js), guarded by the approved
# check C1; R3 [human] accepted, built by P1.2 (src/old3.js). M2 is current
# with R2 [auto]. The contract (with C1) is approved.
setup() {
  rigor_project 3 human
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Old behaviour\n- R2 [auto] New behaviour\n- R3 [human] Old behaviour feels right\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'true\n' > tests/old.sh
  edit_record '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | (.requirements[] | select(.id == "R1")) |= (.milestone = "M1" | .status = "proven")
    | (.requirements[] | select(.id == "R3")) |= (.milestone = "M1" | .status = "accepted")
    | (.requirements[] | select(.id == "R2")) |= (.milestone = "M2")
    | .phases = [{id: "P1", title: "Old", reqs: ["R1", "R3"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Old", reqs: ["R1"], files: ["src/old.js"], after: [], status: "done"},
                {id: "P1.2", phase: "P1", title: "Old human", reqs: ["R3"], files: ["src/old3.js"], after: [], status: "done"}]
    | .checks = [{id: "C1", req: "R1", run: ["sh", "tests/old.sh"], files: ["tests/old.sh"]}, {id: "C2", req: "R2", run: ["true"]}]
    | .commands.test = ["bash", "tools/test.sh"]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

tier_of() { jq -r '.phases[] | select(.id == "P2") | .tier' .vbw/record.json; }
plan_p2() { rigor_apply "$(PH=P2 R0=2 rigor_doc 1 "" "$@")" > /dev/null; }
reasons() { jq -r '.phases[] | select(.id == "P2") | .reasons[]' .vbw/record.json; }

@test "R105: a proven [auto] requirement guarded by an approved check does not raise the tier" {
  plan_p2 src/old.js
  [ "$(tier_of)" = express ] || { reasons; false; }
  reasons | grep -qx 'breaks: none'
}

@test "R105: the reasons still list the guarded requirement and its check" {
  plan_p2 src/old.js
  reasons | grep -E '^guarded: ' | grep -q 'R1'
  reasons | grep -E '^guarded: ' | grep -q 'C1'
}

@test "R105: a [human] requirement a person accepted raises the tier, and is named as what raised it" {
  plan_p2 src/old3.js
  [ "$(tier_of)" = standard ] || { reasons; false; }
  reasons | grep -qx 'breaks: R3'
}

@test "R105: with a guarded and an unguarded requirement the reasons mark each, and only the unguarded one raises the tier" {
  plan_p2 src/old.js src/old3.js
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: R3'
  reasons | grep -E '^guarded: ' | grep -q 'R1'
  ! reasons | grep -E '^guarded: ' | grep -q 'R3'
}

@test "R105: a requirement whose check changed since the approval is not guarded" {
  edit_record '(.checks[] | select(.id == "C1")).run = ["sh", "tests/old.sh", "again"]'
  plan_p2 src/old.js
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: R1'
}

@test "R105: a requirement whose check file changed since the approval is not guarded" {
  printf '# edited\n' >> tests/old.sh
  plan_p2 src/old.js
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: R1'
}

@test "R105: a requirement whose check was never approved is not guarded" {
  rm -f .vbw/runtime/approved-contract.json
  plan_p2 src/old.js
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: R1'
}

@test "R105: a requirement with no check at all is not guarded" {
  edit_record '.checks |= map(select(.id != "C1"))'
  plan_p2 src/old.js
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: R1'
}

@test "R105: a risk path still raises the tier of a phase whose proven requirement is guarded" {
  plan_p2 src/old.js src/auth/login.js
  [ "$(tier_of)" = deep ]
  reasons | grep -E '^risk: ' | grep -q 'src/auth/login.js'
  reasons | grep -qx 'breaks: none'
}

@test "R105: many files still raise the tier of a phase whose proven requirement is guarded" {
  plan_p2 src/old.js src/a.txt src/b.txt src/c.txt src/d.txt
  [ "$(tier_of)" = standard ]
  reasons | grep -qx 'breaks: none'
  reasons | grep -E '^guarded: ' | grep -q 'R1'
}

@test "R105: the approval line of the phase shows what it could affect and what raised it" {
  plan_p2 src/old.js src/old3.js
  vbw_run show contract
  [ "$status" -eq 0 ]
  line=$(printf '%s\n' "$output" | grep '^  P2 ')
  [[ "$line" == *"breaks: R3"* ]] || { echo "$line"; false; }
  [[ "$line" == *"guarded: R1"* ]] || { echo "$line"; false; }
}

@test "R105: docs/rigor.md explains guarded requirements and what raises the tier" {
  grep -qi 'guarded' "$REPO_ROOT/docs/rigor.md"
  grep -qi 'approved check' "$REPO_ROOT/docs/rigor.md"
  grep -q 'breaks:' "$REPO_ROOT/docs/rigor.md"
}
