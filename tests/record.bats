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
  "shipped": [],
  "requirements": [
    { "id": "R1", "text": "Pay by card", "proof": "auto", "status": "failing", "milestone": "M1" },
    { "id": "R2", "text": "Looks trustworthy", "proof": "human", "status": "open", "milestone": "M1" }
  ],
  "checks": [ { "id": "C1", "req": "R1", "run": ["npm", "test"], "files": ["tests/pay.test.ts"], "exit": 0, "output": "passed", "timeout": 60 } ],
  "phases": [ { "id": "P1", "title": "Payments", "reqs": ["R1", "R2"], "milestone": "M1" } ],
  "plans": [
    { "id": "P1.1", "phase": "P1", "title": "Card form", "reqs": ["R1"], "files": ["src/pay.ts"],
      "after": [], "status": "done" },
    { "id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R1"], "files": ["src/receipt.ts"],
      "after": ["P1.1"], "status": "planned" }
  ],
  "fixes": [ { "id": "F1", "req": "R1", "attempts": 1, "status": "open", "note": "C1 exit 1" } ],
  "todos": [ { "id": "T1", "text": "Dark mode", "status": "open" } ],
  "decisions": [ { "id": "D1", "text": "Stripe", "at": "2026-10-01T09:00:00Z" } ],
  "commands": { "test": ["npm", "test"] },
  "settings": { "profile": "balanced", "autonomy_cap": 25 },
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
  run bash -c 'jq -n --arg n "x" "{schema:1, project:{name:\$n}, milestone:{id:\"M1\",title:\"First milestone\",status:\"active\"}, shipped:[], requirements:[], checks:[], phases:[], plans:[], fixes:[], todos:[], decisions:[], commands:{}, settings:{profile:\"balanced\",autonomy_cap:25}, evidence:null, lease:null}" | jq -c -f "$1"' _ "$VALIDATOR"
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
  run violations_after '.checks[0].req = "R2"'
  [[ "$output" == *"C1 checks human-proved R2: only a person can judge it"* ]]
}

@test "rejects paths that escape the project" {
  run violations_after '.plans[0].files = ["../etc/passwd"]'
  [[ "$output" == *"P1.1 has an unsafe path: ../etc/passwd"* ]]
  run violations_after '.checks[0].files = ["/abs/pay.test.ts"]'
  [[ "$output" == *"C1 has an unsafe path: /abs/pay.test.ts"* ]]
}

@test "rejects plan dependency cycles" {
  run violations_after '.plans[0].after = ["P1.2"]'
  [[ "$output" == *"plan dependency cycle"* ]]
}

@test "checks run an argv, never a shell string, within sane limits" {
  run violations_after '.checks[0].run = "npm test"'
  [[ "$output" == *"C1 run must be a non-empty argv array"* ]]
  run violations_after '.checks[0].run = []'
  [[ "$output" == *"C1 run must be a non-empty argv array"* ]]
  run violations_after '.checks[0].timeout = 0'
  [[ "$output" == *"C1 timeout must be 1-3600 seconds"* ]]
  run violations_after '.checks[0].exit = 256'
  [[ "$output" == *"C1 exit must be an integer 0-255"* ]]
  run violations_after '.checks[0].output = "("'
  [[ "$output" == *"C1 output must be a valid regular expression"* ]]
}

@test "a fix targets exactly one requirement or project command" {
  run violations_after '.fixes[0] += {command: "test"}'
  [[ "$output" == *"F1 needs exactly one of req or command"* ]]
  run violations_after '.fixes[0] |= (del(.req) | .command = "test")'
  [ "$output" = "[]" ]
  run violations_after '.fixes[0] |= (del(.req) | .command = "deploy")'
  [[ "$output" == *"F1 references unknown command deploy"* ]]
}

@test "evidence has the documented shape" {
  local ok='{at:"2026-10-01T09:00:00Z", contract:("a"*64), tree:("c"*40), passed:false,
             checks:{C1:{status:"fail", exit:1, seconds:2, tail:"x"}},
             commands:{test:{status:"skipped", exit:null, seconds:0, tail:"not approved"}}, scope:[]}'
  run violations_after ".evidence = $ok"
  [ "$output" = "[]" ]
  run violations_after ".evidence = $ok | .evidence.checks.C1.status = \"flaky\""
  [[ "$output" == *"evidence needs at, contract, tree, passed"* ]]
  run violations_after '.evidence = {passed: true}'
  [[ "$output" == *"evidence needs at, contract, tree, passed"* ]]
}

@test "rejects the removed contract key and bad enums" {
  run violations_after '.contract = {hash: null, approved_at: null}'
  [[ "$output" == *"unknown key: contract"* ]]
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

@test "the example in docs/record.md is a valid record" {
  run bash -c 'awk "/^\`\`\`json\$/{f=1; next} /^\`\`\`\$/{if (f) exit} f" "$1/docs/record.md" | jq -c -f "$2"' _ "$REPO_ROOT" "$VALIDATOR"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "argv strings cannot hide a NUL (the kernel splits argv on NUL)" {
  run violations_after '.commands.test = ["npm", "te\u0000st"]'
  [[ "$output" == *"command test must be a non-empty argv array"* ]]
}
