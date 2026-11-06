#!/usr/bin/env bats
# R247 (T221, D582; docs/record.md Versioning): the record's schema is one table,
# plugin/lib/record-schema.jq, shared by the writer (record.sh record_update) and
# the validator (record.jq): settings.efforts 5, a decision that names its plans 6,
# settings.mcp 7, a recorded break (plans[].mutations[]) that carries tree or
# contract 8, an amendment, an awaited check or a queued requirement (R250) 9,
# test_files as a list of forms (#735: named forms or a dir) 10, a proof's
# own.copy_slots (#738: kept copies) 11, a break that names its rule by place or a
# requirement reworded with its rules kept (R258) 12; the
# highest feature present wins and 4 is the floor. A schema above
# the table's answer is corrupt, named by the feature that schema is only for; a
# schema below it loads and is raised on its next write, as a schema 1 to 3 record
# already does. VBW_SCHEMA_MAX is 12, so a VBW up to 2.1.25 asks to be updated for
# a record that carries an amendment, and an older one for a list of test file
# forms or a proof that kept copies, instead of calling it corrupt. L1: the kernel on a
# fixture project with one mutation break.

load helper
load fixture-helper

LIB_JQ='include "record-schema";'

# built_project: a project with one approved rule and its check, committed, after
# one vbw mutate: the plan's break carries tree and contract, the shape every
# record this VBW writes after a mutation check has (VBW's own holds ten).
built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh > /dev/null < /dev/null
}

setup_file() { fixture_build built built_project; }
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# edit FILTER: change the record by hand, as a restored or older project would hold it.
edit() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cat "$TEST_ROOT/edit.json" > .vbw/record.json
}
# validate [FILE]: the validator's violations of FILE (the record), as the kernel runs it.
validate() {
  jq -c --slurpfile interview "$PLUGIN_ROOT/lib/interview.json" -f "$PLUGIN_ROOT/lib/record.jq" "${1:-.vbw/record.json}"
}
# table FILTER: FILTER run with the schema table's definitions, no input.
table() { jq -c -n -L "$PLUGIN_ROOT/lib" "$LIB_JQ $1"; }
# schema_of RECORD: the table's answer for RECORD, a jq object literal.
schema_of() { table "$1 | schema_of"; }
# Removes every feature of the table from the record: the floor's content.
BARE='del(.plans[].mutations, .test_files) | .settings |= del(.mcp, .efforts) | .decisions |= map(del(.plans)) | if (.evidence | type) == "object" and (.evidence.own | type) == "object" then .evidence.own |= del(.copy_slots) else . end'
max_read() { sed -n 's/^VBW_SCHEMA_MAX=//p' "$PLUGIN_ROOT/lib/record.sh"; }

@test "R247: record-schema.jq is the one definition: definitions only, rows {schema, feature, present}, schema_of the highest feature present with 4 the floor, schema_top equal to VBW_SCHEMA_MAX" {
  [ -f "$PLUGIN_ROOT/lib/record-schema.jq" ] || { echo "no plugin/lib/record-schema.jq"; false; }
  # A module with a main expression cannot be included.
  run table '1'
  [ "$status" -eq 0 ] && [ "$output" = "1" ] || { echo "$output"; false; }
  run table 'schema_features | all(.[]; type == "object" and (.schema | type) == "number" and (.feature | type) == "string" and has("present")) and (map(.schema) == [5, 6, 7, 8, 9, 10, 11, 12, 13, 14])'
  [ "$output" = "true" ] || { echo "rows: $(table 'schema_features | map({schema, feature})')"; false; }
  run table 'schema_features | map(.feature)'
  [ "$output" = '["settings.efforts","a decision that names its plans","settings.mcp","a recorded break that carries tree or contract","an amendment, an awaited check or a queued requirement","a list of test file forms","a proof that kept its clean copies","a break that names its rule by place or a requirement reworded with its rules kept"]' ] || { echo "$output"; false; }
  [ "$(table 'schema_floor')" = 4 ]
  [ "$(table 'schema_top')" = 14 ]
  [ "$(max_read)" = "$(table 'schema_top')" ] || { echo "VBW_SCHEMA_MAX $(max_read) is not the table's top $(table 'schema_top')"; false; }
  # Single-quoted jq literals only: bash 3.2 unescapes \" inside "$( "..." )" and splits the text.
  [ "$(schema_of 'null')" = 4 ]
  [ "$(schema_of '{}')" = 4 ]
  [ "$(schema_of '{settings: {efforts: {dev: "high"}}}')" = 5 ]
  [ "$(schema_of '{decisions: [{id: "D1", plans: []}]}')" = 6 ]
  [ "$(schema_of '{decisions: [{id: "D1", plans: ["P1.1"]}], settings: {efforts: {dev: "high"}}}')" = 6 ]
  [ "$(schema_of '{settings: {mcp: [{server: "github", read_only: true}]}}')" = 7 ]
  [ "$(schema_of '{settings: {mcp: [{server: "github", read_only: true}], efforts: {dev: "high"}}, decisions: [{plans: []}]}')" = 7 ]
  [ "$(schema_of '{plans: [{mutations: [{tree: "t"}]}]}')" = 8 ]
  [ "$(schema_of '{plans: [{mutations: [{contract: "c"}]}]}')" = 8 ]
  [ "$(schema_of '{plans: [{mutations: [{task: 1, none: "nothing"}]}]}')" = 4 ]
  [ "$(schema_of '{settings: {mcp: [{server: "github", read_only: true}]}, plans: [{mutations: [{tree: "t", contract: "c"}]}]}')" = 8 ]
  [ "$(schema_of '{plans: [{amendments: [{what: "w", at: "t", session: null}]}]}')" = 9 ]
  [ "$(schema_of '{plans: [{awaits: ["C1"]}]}')" = 9 ]
  [ "$(schema_of '{checks: [{amendments: []}]}')" = 9 ]
  [ "$(schema_of '{requirements: [{queued: true}]}')" = 9 ]
  [ "$(schema_of '{plans: [{mutations: [{tree: "t"}]}], checks: [{id: "C1"}], requirements: [{id: "R1"}]}')" = 8 ]
  [ "$(schema_of '{test_files: {run: ["sh", "{file}"], files: ["t/*.sh"]}}')" = 4 ]
  [ "$(schema_of '{test_files: [{name: null, dir: "app", run: ["sh", "{file}"], files: ["app/t/*.sh"]}]}')" = 10 ]
  [ "$(schema_of '{test_files: [{name: "web", dir: null, run: ["sh", "{file}"], files: ["t/*.sh"]}], plans: [{mutations: [{tree: "t"}]}]}')" = 10 ]
  [ "$(schema_of '{evidence: {own: {copies: 1}}}')" = 4 ]
  [ "$(schema_of '{evidence: {own: {copies: 1, copy_slots: {claimed: 1, refreshed: 0, made: 0, refresh: 0.2}}}}')" = 11 ]
  [ "$(schema_of '{evidence: {own: {copy_slots: {}}}, plans: [{mutations: [{tree: "t"}]}]}')" = 11 ]
  [ "$(schema_of '{evidence: {own: {copy_slots: {}}}, test_files: [{name: "web", dir: null, run: ["sh", "{file}"], files: ["t/*.sh"]}]}')" = 11 ]
  # The validator and the writer read the table, not a copy of it.
  grep -q 'include "record-schema" {search: "./"}' "$PLUGIN_ROOT/lib/record.jq" || { echo "record.jq does not include record-schema"; false; }
  grep -q 'schema_of' "$PLUGIN_ROOT/lib/record.sh" || { echo "record.sh does not use schema_of"; false; }
  grep -q -- '-L "\$VBW_LIB"' "$PLUGIN_ROOT/lib/record.sh" || { echo "record.sh's writer does not load the module with -L"; false; }
}

@test "R247: no second copy of the rule: record.sh and record.jq hold no literal schema 5 to 14 beside the word schema (VBW_SCHEMA_MAX aside), no per-schema chain, and their header comments name the module" {
  local f hits
  for f in "$PLUGIN_ROOT/lib/record.sh" "$PLUGIN_ROOT/lib/record.jq"; do
    hits=$(grep -iE 'schema' "$f" | grep -vE '^VBW_SCHEMA_MAX=' | grep -E '(^|[[:space:]"(,:=;])([56789]|1[0-4])([[:space:]",;:)]|$)' || true)
    [ -z "$hits" ] || { echo "a schema number is written in $f:"; echo "$hits"; false; }
  done
  ! grep -qE 'then [0-9]+ elif' "$PLUGIN_ROOT/lib/record.sh" || { echo "record_update still has an if/elif schema chain"; false; }
  ! grep -qE '\$r\.schema (==|!=) [0-9]' "$PLUGIN_ROOT/lib/record.jq" || { echo "record.jq still has a per-schema rule"; false; }
  head -n 10 "$PLUGIN_ROOT/lib/record.jq" | grep -q 'record-schema' || { echo "record.jq's header does not name record-schema.jq"; false; }
  grep -B 10 '^VBW_SCHEMA_MAX=' "$PLUGIN_ROOT/lib/record.sh" | grep -q 'record-schema' || { echo "record.sh's header does not name record-schema.jq"; false; }
}

@test "R247: vbw mutate on a fresh project writes a schema-13 record whose break carries tree, contract and digests and names its rule by place; on every later write the highest feature present wins and 4 is the floor" {
  jq -e '.schema == 13 and (.plans[0].mutations | length == 1) and (.plans[0].mutations[0] | has("tree") and has("contract") and (.rule | has("req") and has("k")))' .vbw/record.json \
    || { jq -c '{schema, mutations: .plans[0].mutations}' .vbw/record.json; false; }
  [ "$(validate)" = "[]" ]
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" decide "still twelve" > /dev/null
  jq -e '.schema == 13' .vbw/record.json
  "$VBW" config set mcp github:read-only > /dev/null
  jq -e '.schema == 13 and .settings.mcp[0].server == "github"' .vbw/record.json
  # Without the break, settings.mcp decides; then nothing; then each lower feature in turn.
  edit 'del(.plans[].mutations) | .schema = 4'
  "$VBW" decide "seven now" > /dev/null
  jq -e '.schema == 7' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 7"; false; }
  "$VBW" config set mcp default > /dev/null
  jq -e '.schema == 4' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 4"; false; }
  "$VBW" config set effort.dev high > /dev/null
  jq -e '.schema == 5' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 5"; false; }
  edit '.decisions += [{id: "D90", text: "an approval", at: "2026-01-01T00:00:00Z", plans: ["P1.1"]}]'
  "$VBW" decide "six now" > /dev/null
  jq -e '.schema == 6' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 6"; false; }
  "$VBW" config set mcp github:read-only > /dev/null
  jq -e '.schema == 7' .vbw/record.json || { echo "schema $(jq .schema .vbw/record.json), not 7"; false; }
}

@test "R247: a schema above what the record holds is corrupt (exit 3) and the message names the feature that schema is only for: 14, 13, 12, 11, 10, 8, 7, 6 and 5" {
  local n feature
  edit "$BARE | .schema = 4"
  "$VBW" decide "bare" > /dev/null
  jq -e '.schema == 4' .vbw/record.json
  for n in 14 13 12 11 10 8 7 6 5; do
    edit ".schema = $n"
    feature=$(table "schema_features[] | select(.schema == $n) | .feature")
    vbw_run status
    [ "$status" -eq 3 ] || { echo "schema $n: exit $status: $output"; false; }
    [[ "$output" == *"record is corrupt"* ]] || { echo "$output"; false; }
    [[ "$output" == *"schema $n is only for a record with ${feature//\"/}"* ]] || { echo "schema $n: $output"; false; }
    vbw_run doctor
    [[ "$output" == *"corrupt"* && "$output" == *"restore .vbw/record.json from git"* ]] || { echo "doctor on schema $n: $output"; false; }
    [[ "$output" != *"needs a newer VBW"* ]] || { echo "doctor calls schema $n newer: $output"; false; }
  done
  # The feature present is not the one the schema is for.
  edit '.schema = 7 | .settings.efforts = {dev: "high"}'
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"schema 7 is only for a record with settings.mcp"* ]] || { echo "$output"; false; }
  edit '.schema = 8 | .settings.efforts = {dev: "high"} | .settings.mcp = [{server: "github", read_only: true}]'
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"schema 8 is only for a record with a recorded break that carries tree or contract"* ]] || { echo "$output"; false; }
}

@test "R247 (D582): a schema below what the record holds loads (status 0, doctor says valid) and its next write raises it: 6 with a break (VBW's own record's shape, its rule named by place, its files digested) -> 13, 4 with settings.mcp -> 7, 5 with a decision's plans -> 6, 4 with settings.efforts -> 5, 9 with an awaited check and a list of test file forms -> 10" {
  local shape before after filter
  cp .vbw/record.json "$TEST_ROOT/built.json"
  # before @ the hand edit that makes the shape @ the schema the next write leaves
  for shape in \
    '6@.schema = 6@13' \
    "4@$BARE | .schema = 4 | .settings.mcp = [{server: \"github\", read_only: true}]@7" \
    "5@$BARE | .schema = 5 | .decisions += [{id: \"D90\", text: \"an approval\", at: \"2026-01-01T00:00:00Z\", plans: [\"P1.1\"]}]@6" \
    "4@$BARE | .schema = 4 | .settings.efforts = {dev: \"high\"}@5" \
    "9@.schema = 9 | del(.plans[].mutations) | .plans[0].awaits = [\"C1\"] | .test_files = [{name: \"web\", dir: null, run: [\"sh\", \"{file}\"], files: [\"tests/*.sh\"]}]@10"; do
    cp "$TEST_ROOT/built.json" .vbw/record.json
    before=${shape%%@*}; after=${shape##*@}; filter=${shape#*@}; filter=${filter%@*}
    edit "$filter"
    jq -e --argjson s "$before" '.schema == $s' .vbw/record.json || { echo "setup: schema is $(jq .schema .vbw/record.json), not $before"; false; }
    [ "$(validate)" = "[]" ] || { echo "schema $before -> $after: $(validate)"; false; }
    vbw_run status
    [ "$status" -eq 0 ] || { echo "schema $before -> $after: $output"; false; }
    vbw_run doctor
    [[ "$output" == *"the plan of record is valid"* ]] || { echo "doctor, schema $before -> $after: $output"; false; }
    [[ "$output" != *"corrupt"* && "$output" != *"needs a newer VBW"* ]] || { echo "doctor, schema $before -> $after: $output"; false; }
    jq -e --argjson s "$before" '.schema == $s' .vbw/record.json
    cp .vbw/record.json "$TEST_ROOT/before.json"
    vbw_run decide "raise it"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    jq -e --argjson s "$after" '.schema == $s' .vbw/record.json || { echo "schema $before -> $(jq .schema .vbw/record.json), not $after"; false; }
    [ "$(jq -cS 'del(.schema, .decisions)' .vbw/record.json)" = "$(jq -cS 'del(.schema, .decisions)' "$TEST_ROOT/before.json")" ] || { echo "the raise changed more than the schema"; false; }
    vbw_run status
    [ "$status" -eq 0 ] || { echo "$output"; false; }
  done
}

@test "R247: protected is stated once against the floor: a record of schema 4 to 14 without it, or one below 4 with it, is corrupt saying 'schema 4 or above'; a schema that is not a number stays corrupt" {
  local s
  for s in 4 5 6 7 8 9 10 11 12 13 14; do
    run validate <(jq "del(.protected) | .schema = $s" .vbw/record.json)
    [[ "$output" == *"protected is missing: a record of schema 4 or above must carry the protected field"* ]] || { echo "schema $s without protected: $output"; false; }
  done
  run validate <(jq '.schema = 3' .vbw/record.json)
  [[ "$output" == *"protected is only for a record of schema 4 or above"* ]] || { echo "$output"; false; }
  run validate <(jq '.schema = "eight"' .vbw/record.json)
  [ "$output" != "[]" ] || { echo "a schema that is not a number passed"; false; }
  run validate <(jq 'del(.schema)' .vbw/record.json)
  [ "$output" != "[]" ] || { echo "a record without a schema passed"; false; }
  edit '.schema = "eight"'
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"corrupt"* ]] || { echo "$output"; false; }
}

@test "R247: this VBW reads up to schema 14: a schema-15 record exits 4 saying the project needs a newer VBW and that this VBW reads up to schema 14, never that it is corrupt" {
  [ "$(max_read)" = 14 ] || { echo "VBW_SCHEMA_MAX is $(max_read)"; false; }
  edit '.schema = 15'
  vbw_run status
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"needs a newer VBW"* && "$output" == *"reads up to schema 14"* ]] || { echo "$output"; false; }
  [[ "$output" != *"corrupt"* ]] || { echo "$output"; false; }
  vbw_run doctor
  [[ "$output" == *"update VBW with /vbw:update"* && "$output" != *"corrupt"* ]] || { echo "$output"; false; }
}

@test "R247 (T221): a kernel whose VBW_SCHEMA_MAX is 12 reading the schema-13 record this VBW's vbw mutate wrote says the project needs a newer VBW (exit 4), never that it is corrupt; the validator pins the break's shape" {
  jq -e '.schema == 13' .vbw/record.json
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  sed -i.bak 's/^VBW_SCHEMA_MAX=.*$/VBW_SCHEMA_MAX=12/' "$TEST_ROOT/plugin/lib/record.sh"
  grep -qx 'VBW_SCHEMA_MAX=12' "$TEST_ROOT/plugin/lib/record.sh"
  run "$TEST_ROOT/plugin/bin/vbw" status < /dev/null
  [ "$status" -eq 4 ] || { echo "exit $status: $output"; false; }
  [[ "$output" == *"needs a newer VBW"* && "$output" == *"reads up to schema 12"* ]] || { echo "$output"; false; }
  [[ "$output" != *"corrupt"* ]] || { echo "$output"; false; }
  run "$TEST_ROOT/plugin/bin/vbw" doctor < /dev/null
  [[ "$output" == *"update VBW with /vbw:update"* && "$output" != *"corrupt"* ]] || { echo "$output"; false; }
  cmp -s .vbw/record.json "$(fixture_root)/project with space/.vbw/record.json" || { echo "the older kernel changed the record"; false; }
  # The shape the schema is for, through the validator: tree a tree id, contract a hash.
  [ "$(validate)" = "[]" ]
  run validate <(jq '.plans[0].mutations[0].tree = "short"' .vbw/record.json)
  [[ "$output" == *"P1.1 mutations must be recorded breaks (vbw mutate)"* ]] || { echo "$output"; false; }
  run validate <(jq '.plans[0].mutations[0].contract = "not-a-hash"' .vbw/record.json)
  [[ "$output" == *"P1.1 mutations must be recorded breaks (vbw mutate)"* ]] || { echo "$output"; false; }
  run validate <(jq '.schema = 8 | .plans[0].mutations[0] |= (del(.tree, .contract, .digests) | .rule = {req: "R1", text: "paying prints paid"})' .vbw/record.json)
  [[ "$output" == *"schema 8 is only for a record with a recorded break that carries tree or contract"* ]] || { echo "$output"; false; }
}

# R258 (T234; docs/record.md Versioning, docs/proof.md): a recorded break names its rule by
# place, {req, k}, so rewording a rule keeps its breaks. A new record key, so schema 12: the
# table's top row, VBW_SCHEMA_MAX moves with it, and a requirement reworded with its rules
# kept (R259, requirements[].reworded) is the row's other feature. A record whose breaks
# carry the old {req, text} shape stays readable; its first write converts each break to the
# place of the rule whose text it carries, and a break whose text matches no rule is kept as
# it is (it counts for no rule, as before).

@test "R258 schema 12: a break naming its rule by place and a reworded requirement are schema 12, the table's top, which VBW_SCHEMA_MAX follows" {
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 1}, tree: "t"}]}]}')" = 12 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 2}, none: "nothing", at: "t", head: "h"}]}]}')" = 12 ]
  [ "$(schema_of '{requirements: [{id: "R1", reworded: true}]}')" = 12 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", text: "t"}, tree: "t"}]}]}')" = 8 ]
}

# R265 (T247): a recorded break carries digests, one per broken file: a new key, so
# schema 13, one row (D614). R264 (T246): a rule's --none entry on a check that reads the
# project through git carries git: true: schema 14, the next row, the table's top.
@test "R265 schema 13: a break that carries digests is schema 13, a table row of its own naming the digests" {
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 1}, tree: "t", digests: {"src/pay.sh": "absent"}}]}]}')" = 13 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 1}, tree: "t"}]}]}')" = 12 ]
  table 'schema_features[] | select(.schema == 13) | .feature' | grep -qi 'digest' || { echo "row 13 does not name the digests: $(table 'schema_features[] | select(.schema == 13)')"; false; }
  jq -e '.schema == 13 and (.plans[0].mutations[0].digests | type == "object")' .vbw/record.json || { jq -c '{schema, m: .plans[0].mutations[0]}' .vbw/record.json; false; }
}

@test "R264 schema 14: a rule's --none entry marked git is schema 14, the table's top, which VBW_SCHEMA_MAX follows; a none entry without the mark stays 12" {
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 2}, none: "reads git", git: true, at: "t", head: "h"}]}]}')" = 14 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 2}, none: "nothing", at: "t", head: "h"}]}]}')" = 12 ]
  table 'schema_features[] | select(.schema == 14) | .feature' | grep -qi 'git' || { echo "row 14 does not name git: $(table 'schema_features[] | select(.schema == 14)')"; false; }
  [ "$(table 'schema_top')" = 14 ]
  [ "$(max_read)" = 14 ] || { echo "VBW_SCHEMA_MAX is $(max_read)"; false; }
}

@test "R258 schema 12: the validator accepts a break's rule as {req, k} (k 1 to 9999) and as the older {req, text}, and refuses every other shape; reworded can only be true" {
  edit '.schema = 12 | .plans[0].mutations[0].rule = {req: "R1", k: 1}'
  [ "$(validate)" = '[]' ] || { validate; false; }
  edit '.plans[0].mutations[0].rule = {req: "R1", text: "paying prints paid"}'
  [ "$(validate)" = '[]' ] || { validate; false; }
  local bad
  for bad in '{req: "R1", k: 0}' '{req: "R1", k: "1"}' '{req: "R1"}' '{req: "R1", k: 1, text: "paying prints paid"}' '{k: 1}'; do
    edit ".plans[0].mutations[0].rule = $bad"
    [ "$(validate)" != '[]' ] || { echo "accepted a break whose rule is $bad"; false; }
  done
  edit '.plans[0].mutations[0].rule = {req: "R1", k: 1} | .requirements[0].reworded = true'
  [ "$(validate)" = '[]' ] || { validate; false; }
  edit '.requirements[0].reworded = false'
  [ "$(validate)" != '[]' ] || { echo "accepted reworded: false"; false; }
}

@test "R258 schema 12: a record whose breaks name their rules by text stays readable, and its first write converts each to the place of the rule with that text; a break matching no rule is kept as it is" {
  # The fixture's break was written by this kernel; a second one, by hand, names no rule of R1.
  edit '.plans[0].mutations[0].rule = {req: "R1", text: "paying prints paid"}
    | .plans[0].mutations += [.plans[0].mutations[0] | .rule = {req: "R1", text: "no such rule"} | .what = "stray"]
    | .schema = 8'
  [ "$(validate)" = '[]' ] || { validate; false; }
  vbw_run show plan P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" decide "Use blue buttons" "the owner prefers them" > /dev/null
  jq -e '.schema == 12
    and .plans[0].mutations[0].rule == {req: "R1", k: 1}
    and .plans[0].mutations[1].rule == {req: "R1", text: "no such rule"}' .vbw/record.json || { jq '.schema, .plans[0].mutations[].rule' .vbw/record.json; false; }
  [ "$(validate)" = '[]' ] || { validate; false; }
}
