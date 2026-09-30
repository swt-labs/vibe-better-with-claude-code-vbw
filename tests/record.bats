#!/usr/bin/env bats
# plugin/lib/record.jq is the definition of .vbw/record.json (docs/record.md).
# It prints a JSON array of violations; [] means valid.

load helper

setup() {
  vbw_setup
  VALIDATOR="$PLUGIN_ROOT/lib/record.jq"
  VALID="$TEST_ROOT/valid.json"
  cat > "$VALID" <<'EOF'
{
  "schema": 1,
  "project": { "name": "Shop" },
  "milestone": { "id": "M1", "title": "Checkout", "status": "active" },
  "requirements": [
    { "id": "R1", "text": "Pay by card", "proof": "auto", "checks": ["C1"], "status": "failing" },
    { "id": "R2", "text": "Looks trustworthy", "proof": "human", "checks": [], "status": "open" }
  ],
  "checks": [ { "id": "C1", "req": "R1", "kind": "spec", "path": ".vbw/checks/C1.json" } ],
  "phases": [ { "id": "P1", "title": "Payments", "reqs": ["R1", "R2"], "status": "building" } ],
  "plans": [
    { "id": "P1.1", "phase": "P1", "title": "Card form", "reqs": ["R1"], "files": ["src/pay.ts"],
      "after": [], "status": "done" },
    { "id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R1"], "files": ["src/receipt.ts"],
      "after": ["P1.1"], "status": "planned" }
  ],
  "fixes": [ { "id": "F1", "req": "R1", "attempts": 1, "status": "open", "note": "C1 exit 1" } ],
  "todos": [ { "id": "T1", "text": "Dark mode", "status": "open" } ],
  "decisions": [ { "id": "D1", "text": "Stripe", "at": "2026-10-01T09:00:00Z" } ],
  "contract": { "hash": null, "approved_at": null },
  "evidence": null,
  "lease": null
}
EOF
}

teardown() { vbw_teardown; }

# Apply a jq edit to the valid record and print the violations.
violations_after() {
  jq "$1" "$VALID" | jq -c -f "$VALIDATOR"
}

@test "the documented example is valid" {
  run jq -c -f "$VALIDATOR" "$VALID"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "the minimal record written by vbw init is valid" {
  run bash -c 'jq -n --arg n "x" "{schema:1, project:{name:\$n}, milestone:{id:\"M1\",title:\"First milestone\",status:\"active\"}, requirements:[], checks:[], phases:[], plans:[], fixes:[], todos:[], decisions:[], contract:{hash:null,approved_at:null}, evidence:null, lease:null}" | jq -c -f "$1"' _ "$VALIDATOR"
  [ "$output" = "[]" ]
}

@test "rejects a newer or missing schema version" {
  run violations_after '.schema = 2'
  [[ "$output" == *"schema must be 1"* ]]
  run violations_after 'del(.schema)'
  [[ "$output" == *"schema must be 1"* ]]
}

@test "rejects unknown top-level keys" {
  run violations_after '.extra = true'
  [[ "$output" == *"unknown key: extra"* ]]
}

@test "rejects duplicate and malformed ids" {
  run violations_after '.requirements += [.requirements[0]]'
  [[ "$output" == *"duplicate id: R1"* ]]
  run violations_after '.requirements[0].id = "REQ1"'
  [[ "$output" == *"bad id: REQ1"* ]]
  run violations_after '.plans[0].id = "P2.1"'
  [[ "$output" == *"plan P2.1 is not in its phase P1"* ]]
}

@test "rejects dangling references" {
  run violations_after '.requirements[0].checks = ["C9"]'
  [[ "$output" == *"R1 references unknown check C9"* ]]
  run violations_after '.checks[0].req = "R9"'
  [[ "$output" == *"C1 references unknown requirement R9"* ]]
  run violations_after '.plans[1].after = ["P1.9"]'
  [[ "$output" == *"P1.2 references unknown plan P1.9"* ]]
  run violations_after '.fixes[0].req = "R9"'
  [[ "$output" == *"F1 references unknown requirement R9"* ]]
}

@test "rejects proof/status combinations that cannot happen" {
  run violations_after '.requirements[1].status = "proven"'
  [[ "$output" == *"R2 is human-proved and cannot be proven"* ]]
  run violations_after '.requirements[0].status = "accepted"'
  [[ "$output" == *"R1 is auto-proved and cannot be accepted"* ]]
  run violations_after '.requirements[1].checks = ["C1"]'
  [[ "$output" == *"R2 is human-proved and cannot have checks"* ]]
}

@test "rejects paths that escape the project" {
  run violations_after '.plans[0].files = ["../etc/passwd"]'
  [[ "$output" == *"P1.1 has an unsafe path: ../etc/passwd"* ]]
  run violations_after '.checks[0].path = "/abs/C1.json"'
  [[ "$output" == *"C1 has an unsafe path: /abs/C1.json"* ]]
}

@test "rejects plan dependency cycles" {
  run violations_after '.plans[0].after = ["P1.2"]'
  [[ "$output" == *"plan dependency cycle"* ]]
}

@test "rejects a half-set contract and bad enums" {
  run violations_after '.contract.hash = ("a" * 64)'
  [[ "$output" == *"contract hash and approved_at must both be set or both be null"* ]]
  run violations_after '.todos[0].status = "later"'
  [[ "$output" == *"T1 has an invalid status: later"* ]]
}

@test "violations are reported for non-object input instead of crashing" {
  run bash -c 'printf "[]" | jq -c -f "$1"' _ "$VALIDATOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"record must be a JSON object"* ]]
}

@test "rejects unknown fields inside items (typos and stale fields are loud)" {
  run violations_after '.plans[0].commits = ["3f2a9c1"]'
  [[ "$output" == *"P1.1 has an unknown field: commits"* ]]
  run violations_after '.requirements[0].stauts = "open"'
  [[ "$output" == *"R1 has an unknown field: stauts"* ]]
}
