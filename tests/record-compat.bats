#!/usr/bin/env bats
# R46: a schema-1 record stays readable by VBW 2.0.16, the last release that reads
# only schema 1 (docs/record.md). A field 2.0.16 does not know makes it call the
# record corrupt, so a change that needs one raises the schema instead: then an
# older VBW says it needs a newer VBW (R33). The lists below are 2.0.16's, frozen.

load helper

TOP='["schema","project","milestone","requirements","checks","phases","plans","fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"]'
CHECK='["id","req","run","files","exit","output","timeout"]'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  PLAN='{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
              {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt", "src/pay.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}'
  printf '%s' "$PLAN" | "$VBW" apply > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt
  git add -A && git commit -q -m "feat: built"
  jq '.plans[].status = "done" | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "a"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

# fits: the record is schema 1 and holds only the fields 2.0.16 reads.
fits() {
  jq -e --argjson top "$TOP" --argjson check "$CHECK" '.schema == 1
    and all(keys[]; . as $k | $top | index($k))
    and all(.checks[]; all(keys[]; . as $k | $check | index($k)))' .vbw/record.json
}

@test "closing a fix, proving and keeping the interview answers in the project leave a record VBW 2.0.16 reads" {
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  fits
  vbw_run prove
  fits
  "$VBW" interview set level "senior engineer" > /dev/null
  "$VBW" interview set depth "technical and brief" > /dev/null
  "$VBW" interview set involvement "I make the calls" > /dev/null
  vbw_run interview keep project
  [ "$status" -eq 0 ]
  fits
}

@test "the fields 2.0.16 does not read raise the schema, never stay at schema 1" {
  printf '%s' "$PLAN" | jq '.checks[0].alone = true' | "$VBW" apply > /dev/null
  jq -e '.schema == 2' .vbw/record.json
  run fits
  [ "$status" -ne 0 ]
}

@test "a record carrying passes is refused as corrupt: passes belong to the clone, and no release wrote them" {
  jq '.passes = {}' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"unknown key: passes"* ]]
}
