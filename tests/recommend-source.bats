#!/usr/bin/env bats
# R133 (L1): the recommending workflow's reply schema refuses an empty string
# as the source of the top pick and of each runner-up (Claude Code checks the
# Architect's reply against it), so one empty source never reaches vbw
# recommend and makes it refuse the whole recommendation. A pick with no source
# at all is still allowed, and a reply whose sources are all valid T or R ids
# is recorded by vbw recommend exactly as before. The workflow runs under node
# with a stubbed runtime (tests/helpers/run-workflow.js: no model is called).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/recommending.js"
SUMMARY='{"milestone": {"id": "M1", "title": "Checkout", "status": "active"},
  "open": [{"id": "R1", "text": "A customer gets a receipt", "proof": "auto", "status": "open"}],
  "run": null,
  "todos": [{"id": "T1", "text": "Refunds", "sort": "next", "size": "small"}, {"id": "T2", "text": "Gift cards"}]}'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" todo add --sort next --size small "Refunds" > /dev/null
  "$VBW" todo add "Gift cards" > /dev/null
}

teardown() { vbw_teardown; }

# wf RESPONSE: the stubbed run of the recommending workflow, the Architect
# answering RESPONSE (null: no answer). Prints {calls, result, logs}.
wf() {
  command -v node > /dev/null || skip "node is not installed"
  local label out
  out=$(node "$RUN" "$WF" "$(jq -nc --argjson s "$SUMMARY" '{summary: $s, declined: []}')" '{}') || { echo "$out"; return 1; }
  label=$(printf '%s' "$out" | jq -r '.calls[0].opts.label')
  node "$RUN" "$WF" "$(jq -nc --argjson s "$SUMMARY" '{summary: $s, declined: []}')" "$(jq -nc --arg l "$label" --argjson r "$1" '{($l): $r}')"
}

# source_schemas: the schema of the top pick's source and of a runner-up's source, as a JSON array.
source_schemas() {
  wf null | jq -c '.calls[0].opts.schema | [.properties.top.properties.source, .properties.runners.items.properties.source]'
}

# accepts SCHEMA VALUE: true when a string schema (type, minLength, maxLength,
# pattern, enum) accepts VALUE, as a JSON Schema validator reads those keywords.
accepts() {
  node -e '
    const s = JSON.parse(process.argv[1]); const v = process.argv[2]
    let ok = s !== null && typeof s === "object" && (s.type === undefined || s.type === "string")
    if (ok && typeof s.minLength === "number") ok = v.length >= s.minLength
    if (ok && typeof s.maxLength === "number") ok = v.length <= s.maxLength
    if (ok && typeof s.pattern === "string") ok = new RegExp(s.pattern, "u").test(v)
    if (ok && Array.isArray(s.enum)) ok = s.enum.includes(v)
    process.exit(ok ? 0 : 1)' "$1" "$2"
}

@test "R133: the reply schema refuses an empty source for the top pick and for each runner-up" {
  local schemas
  schemas=$(source_schemas)
  printf '%s' "$schemas" | jq -e 'all(.[]; type == "object")' || { echo "no source in the schema: $schemas"; false; }
  ! accepts "$(printf '%s' "$schemas" | jq -c '.[0]')" "" || { echo "the top pick's source accepts an empty string: $schemas"; false; }
  ! accepts "$(printf '%s' "$schemas" | jq -c '.[1]')" "" || { echo "a runner-up's source accepts an empty string: $schemas"; false; }
}

@test "R133: the reply schema still accepts T and R ids as sources" {
  local schemas id
  schemas=$(source_schemas)
  for id in T1 T42 R1 R133; do
    accepts "$(printf '%s' "$schemas" | jq -c '.[0]')" "$id" || { echo "the top pick's source refuses $id: $schemas"; false; }
    accepts "$(printf '%s' "$schemas" | jq -c '.[1]')" "$id" || { echo "a runner-up's source refuses $id: $schemas"; false; }
  done
}

@test "R133: a pick with no source field is still allowed by the schema, kept by the workflow and recorded by vbw recommend" {
  local out rec
  out=$(wf null)
  printf '%s' "$out" | jq -e '.calls[0].opts.schema | ((.properties.top.required // []) | index("source") | not)
    and ((.properties.runners.items.required // []) | index("source") | not)' || { echo "$out"; false; }
  rec='{"top": {"text": "Refunds", "reason": "Customers ask for it most.", "size": "small"}, "runners": [{"text": "Gift cards", "size": "large"}]}'
  out=$(wf "$rec")
  printf '%s' "$out" | jq -e --argjson r "$rec" '.result.recommendation == $r' || { echo "$out"; false; }
  printf '%s' "$out" | jq -c '.result.recommendation' | "$VBW" recommend || false
  jq -e --argjson r "$rec" '.recommendation | del(.at) == $r' .vbw/record.json
}

@test "R133: a reply whose sources are valid T and R ids is recorded by vbw recommend exactly as before" {
  local out rec
  rec='{"top": {"text": "Refunds", "reason": "Customers ask for it most.", "size": "small", "source": "T1"}, "runners": [{"text": "Receipts", "size": "medium", "source": "R1"}, {"text": "Gift cards", "size": "large", "source": "T2"}]}'
  out=$(wf "$rec")
  printf '%s' "$out" | jq -e --argjson r "$rec" '.result.recommendation == $r' || { echo "$out"; false; }
  run sh -c 'printf "%s" "$1" | "$2" recommend' _ "$(printf '%s' "$out" | jq -c '.result.recommendation')" "$VBW"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "recommended: Refunds (small)" ]
  jq -e --argjson r "$rec" '.recommendation | del(.at) == $r and (.at | type == "string")' .vbw/record.json
}
