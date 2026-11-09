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
  run table 'schema_features | all(.[]; type == "object" and (.schema | type) == "number" and (.feature | type) == "string" and has("present")) and (map(.schema) == [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])'
  [ "$output" = "true" ] || { echo "rows: $(table 'schema_features | map({schema, feature})')"; false; }
  run table 'schema_features | map(.feature)'
  [ "$output" = '["settings.efforts","a decision that names its plans","settings.mcp","a recorded break that carries tree or contract","an amendment, an awaited check or a queued requirement","a list of test file forms","a proof that kept its clean copies","a break that names its rule by place or a requirement reworded with its rules kept","a recorded break that carries digests","a rule'"'"'s --none entry marked git (its check reads the project through git)","a break whose digests are a list, or a plan'"'"'s red-first runs"]' ] || { echo "$output"; false; }
  [ "$(table 'schema_floor')" = 4 ]
  [ "$(table 'schema_top')" = 15 ]
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

@test "R247: no second copy of the rule: record.sh and record.jq hold no literal schema 5 to 15 beside the word schema (VBW_SCHEMA_MAX aside), no per-schema chain, and their header comments name the module" {
  local f hits
  for f in "$PLUGIN_ROOT/lib/record.sh" "$PLUGIN_ROOT/lib/record.jq"; do
    hits=$(grep -iE 'schema' "$f" | grep -vE '^VBW_SCHEMA_MAX=' | grep -E '(^|[[:space:]"(,:=;])([56789]|1[0-5])([[:space:]",;:)]|$)' || true)
    [ -z "$hits" ] || { echo "a schema number is written in $f:"; echo "$hits"; false; }
  done
  ! grep -qE 'then [0-9]+ elif' "$PLUGIN_ROOT/lib/record.sh" || { echo "record_update still has an if/elif schema chain"; false; }
  ! grep -qE '\$r\.schema (==|!=) [0-9]' "$PLUGIN_ROOT/lib/record.jq" || { echo "record.jq still has a per-schema rule"; false; }
  head -n 10 "$PLUGIN_ROOT/lib/record.jq" | grep -q 'record-schema' || { echo "record.jq's header does not name record-schema.jq"; false; }
  grep -B 10 '^VBW_SCHEMA_MAX=' "$PLUGIN_ROOT/lib/record.sh" | grep -q 'record-schema' || { echo "record.sh's header does not name record-schema.jq"; false; }
}

@test "R247: vbw mutate on a fresh project writes a schema-15 record whose break carries tree, contract and digests (as a list) and names its rule by place; on every later write the highest feature present wins and 4 is the floor" {
  jq -e '.schema == 15 and (.plans[0].mutations | length == 1) and (.plans[0].mutations[0] | has("tree") and has("contract") and (.rule | has("req") and has("k")))' .vbw/record.json \
    || { jq -c '{schema, mutations: .plans[0].mutations}' .vbw/record.json; false; }
  [ "$(validate)" = "[]" ]
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" decide "still twelve" > /dev/null
  jq -e '.schema == 15' .vbw/record.json
  "$VBW" config set mcp github:read-only > /dev/null
  jq -e '.schema == 15 and .settings.mcp[0].server == "github"' .vbw/record.json
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

@test "R247: a schema above what the record holds is corrupt (exit 3) and the message names the feature that schema is only for: 15, 14, 13, 12, 11, 10, 8, 7, 6 and 5" {
  local n feature
  edit "$BARE | .schema = 4"
  "$VBW" decide "bare" > /dev/null
  jq -e '.schema == 4' .vbw/record.json
  for n in 15 14 13 12 11 10 8 7 6 5; do
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

@test "R247 (D582): a schema below what the record holds loads (status 0, doctor says valid) and its next write raises it: 6 with a break (VBW's own record's shape, its rule named by place, its files digested as a list) -> 15, 4 with settings.mcp -> 7, 5 with a decision's plans -> 6, 4 with settings.efforts -> 5, 9 with an awaited check and a list of test file forms -> 10" {
  local shape before after filter
  cp .vbw/record.json "$TEST_ROOT/built.json"
  # before @ the hand edit that makes the shape @ the schema the next write leaves
  for shape in \
    '6@.schema = 6@15' \
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

@test "R247: protected is stated once against the floor: a record of schema 4 to 15 without it, or one below 4 with it, is corrupt saying 'schema 4 or above'; a schema that is not a number stays corrupt" {
  local s
  for s in 4 5 6 7 8 9 10 11 12 13 14 15; do
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

@test "R247: this VBW reads up to schema 15: a schema-16 record exits 4 saying the project needs a newer VBW and that this VBW reads up to schema 15, never that it is corrupt" {
  [ "$(max_read)" = 15 ] || { echo "VBW_SCHEMA_MAX is $(max_read)"; false; }
  edit '.schema = 16'
  vbw_run status
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"needs a newer VBW"* && "$output" == *"reads up to schema 15"* ]] || { echo "$output"; false; }
  [[ "$output" != *"corrupt"* ]] || { echo "$output"; false; }
  vbw_run doctor
  [[ "$output" == *"update VBW with /vbw:update"* && "$output" != *"corrupt"* ]] || { echo "$output"; false; }
}

@test "R247 (T221): a kernel whose VBW_SCHEMA_MAX is 12 reading the schema-15 record this VBW's vbw mutate wrote says the project needs a newer VBW (exit 4), never that it is corrupt; the validator pins the break's shape" {
  jq -e '.schema == 15' .vbw/record.json
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
  # R286: this kernel writes the digests as a list (schema 15); an older one wrote the object.
  jq -e '.schema == 15 and (.plans[0].mutations[0].digests | type == "array")' .vbw/record.json || { jq -c '{schema, m: .plans[0].mutations[0]}' .vbw/record.json; false; }
}

@test "R264 schema 14: a rule's --none entry marked git is schema 14, a table row of its own; a none entry without the mark stays 12" {
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 2}, none: "reads git", git: true, at: "t", head: "h"}]}]}')" = 14 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 2}, none: "nothing", at: "t", head: "h"}]}]}')" = 12 ]
  table 'schema_features[] | select(.schema == 14) | .feature' | grep -qi 'git' || { echo "row 14 does not name git: $(table 'schema_features[] | select(.schema == 14)')"; false; }
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
  # 15: the fixture's own break, written by this kernel, carries its digests as a list (R286).
  jq -e '.schema == 15
    and .plans[0].mutations[0].rule == {req: "R1", k: 1}
    and .plans[0].mutations[1].rule == {req: "R1", text: "no such rule"}' .vbw/record.json || { jq '.schema, .plans[0].mutations[].rule' .vbw/record.json; false; }
  [ "$(validate)" = '[]' ] || { validate; false; }
}

# R286 (field report 2026-11-09, D685): no line of the record pairs a file path with a
# SHA-256 digest, so a secret scanner's keyword rule never refuses a record commit. A
# break's digests are a list of {file, sha256}, each on lines of its own in the record's
# pretty-printing, the path never on the digest's line; the values are unchanged. The
# list is the next row of the table, schema 15, which a plan's red-first runs (R292)
# share, so 2.1.29 costs one schema step. An older record's object is converted on its
# first write. Gitleaks' generic-api-key rule, copied from Gitleaks v8.24.3
# (config/gitleaks.toml, id generic-api-key; Gitleaks is not installed, no dependency is
# added; a newer Gitleaks pattern is copied here by hand), is matched with jq per line and
# over the whole text, as Gitleaks scans a file.
GENERIC_API_KEY=$(cat << 'RE'
(?i)[\w.-]{0,50}?(?:access|auth|(?-i:[Aa]pi|API)|credential|creds|key|passw(?:or)?d|secret|token)(?:[ \t\w.-]{0,20})[\s'"]{0,3}(?:=|>|:{1,3}=|\|\||:|=>|\?=|,)[\x60'"\s=]{0,5}([\w.=-]{10,150}|[a-z0-9][a-z0-9+/]{11,}={0,3})(?:[\x60'"\s;]|\\[nr]|$)
RE
)
SECRET_PATHS='["src/api.rs","lib/auth_token.py","config/secret_keys.ts","tests/password.bats"]'

# keyword_record: the fixture's record as VBW 2.1.28 wrote it (schema 13, digests an object)
# with the four paths in the break, the test-file evidence and a QA fingerprint.
keyword_record() {
  jq --argjson p "$SECRET_PATHS" '.schema = 13
    | .plans[0].files += $p
    | .plans[0].mutations[0] |= (.files += $p | .digests = ([$p | to_entries[] | {key: .value, value: ("\(.key + 1)" * 64)}] | from_entries))
    | .phases[0].qa = {result: "pass", tier: "quick", tree: ("e" * 64), at: "2026-01-01T00:00:00Z"}
    | .evidence = {at: "2026-01-01T00:00:00Z", contract: ("c" * 64), tree: ("d" * 40), head: ("d" * 40), passed: true, scope: [],
        checks: {C1: {status: "pass", exit: 0, seconds: 1, tail: "", at: "2026-01-01T00:00:00Z", fp: ("f" * 64)}}, commands: {},
        test_files: ([$p[] | {key: ., value: {status: "pass", exit: 0, seconds: 1, tail: "", at: "2026-01-01T00:00:00Z", fp: ("a" * 64)}}] | from_entries)}' .vbw/record.json > "$TEST_ROOT/edit.json" && cat "$TEST_ROOT/edit.json" > .vbw/record.json
}
# keyword_lines FILE: the lines of FILE that hold a 64-hex value and one of the words a secret scanner's keyword rule looks for.
keyword_lines() { grep -E '[0-9a-fA-F]{64}' "$1" | grep -iE 'api|key|token|auth|secret|credential|password' || true; }
# leaks FILE: the lines of FILE the generic-api-key pattern matches, then "whole" when it matches the whole text.
leaks() {
  jq -Rr --arg re "$GENERIC_API_KEY" 'select(test($re))' "$1"
  jq -Rse --arg re "$GENERIC_API_KEY" 'test($re)' "$1" > /dev/null && echo whole
  return 0
}

@test "R286 schema: a break whose digests are a list, or a plan's red-first runs, is schema 15, the table's top, which VBW_SCHEMA_MAX follows; the older object stays 13" {
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 1}, tree: "t", digests: [{file: "src/pay.sh", sha256: "absent"}]}]}]}')" = 15 ]
  [ "$(schema_of '{plans: [{id: "P1.1", red_runs: []}]}')" = 15 ]
  [ "$(schema_of '{plans: [{mutations: [{rule: {req: "R1", k: 1}, tree: "t", digests: {"src/pay.sh": "absent"}}]}]}')" = 13 ]
  [ "$(table 'schema_top')" = 15 ]
  [ "$(max_read)" = 15 ] || { echo "VBW_SCHEMA_MAX is $(max_read)"; false; }
}

@test "R286 schema: the validator refuses a break whose digests name a file twice, add a key, or name a file the break did not, and accepts the list and the older object" {
  [ "$(validate)" = '[]' ] || { validate; false; }
  edit '.plans[0].mutations[0].digests += [.plans[0].mutations[0].digests[0]]'
  [ "$(validate)" != '[]' ] || { echo "accepted a file twice in the digests"; false; }
  edit '.plans[0].mutations[0].digests |= unique | .plans[0].mutations[0].digests[0].extra = 1'
  [ "$(validate)" != '[]' ] || { echo "accepted an extra key in a digest"; false; }
  edit '.plans[0].mutations[0].digests[0] |= del(.extra) | .plans[0].mutations[0].digests[0].file = "src/other.sh"'
  [ "$(validate)" != '[]' ] || { echo "accepted a file the break did not name"; false; }
  edit '.plans[0].mutations[0].digests = {"src/pay.sh": "absent"}'
  [ "$(validate)" = '[]' ] || { validate; false; }
}

@test "R286 schema: a VBW that reads up to schema 14 refuses this VBW's schema-15 record with the R272 line, never calling it corrupt, and leaves it unchanged" {
  jq -e '.schema == 15' .vbw/record.json || { jq .schema .vbw/record.json; false; }
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
  sed -i.bak 's/^VBW_SCHEMA_MAX=.*$/VBW_SCHEMA_MAX=14/' "$TEST_ROOT/plugin/lib/record.sh"
  cp .vbw/record.json "$TEST_ROOT/kept.json"
  run "$TEST_ROOT/plugin/bin/vbw" status < /dev/null
  [ "$status" -eq 4 ] || { echo "exit $status: $output"; false; }
  [[ "$output" == *"this project needs a newer VBW"* && "$output" != *"corrupt"* ]] || { echo "$output"; false; }
  cmp -s .vbw/record.json "$TEST_ROOT/kept.json" || { echo "the older kernel changed the record"; false; }
}

@test "R286 layout: Gitleaks' generic-api-key pattern finds the old layout's path-and-digest lines, and nothing in the record this VBW writes from the same data" {
  keyword_record
  [ "$(validate)" = "[]" ] || { echo "the 2.1.28 shape does not validate: $(validate)"; false; }
  # The test can fail: the old layout holds the field report's lines.
  [ -n "$(leaks .vbw/record.json)" ] || { echo "the pattern finds nothing in the old layout"; false; }
  [ -n "$(keyword_lines .vbw/record.json)" ] || { echo "no old-layout line pairs a keyword with a digest"; false; }
  "$VBW" decide "digests on lines of their own" > /dev/null
  jq -e '.schema == 15 and (.plans[0].mutations[0].digests | type == "array")' .vbw/record.json || { jq -c '{schema, d: .plans[0].mutations[0].digests}' .vbw/record.json; false; }
  local found
  found=$(leaks .vbw/record.json)
  [ -z "$found" ] || { echo "the pattern matches the record VBW wrote:"; echo "$found"; false; }
  found=$(keyword_lines .vbw/record.json)
  [ -z "$found" ] || { echo "lines pair a keyword with a digest:"; echo "$found"; false; }
  # Each digest on a line whose field name is neutral, its file on another line.
  [ "$(grep -cE '^ +"sha256": "[0-9a-f]{64}",?$' .vbw/record.json)" -ge 4 ] || { grep -nE '[0-9a-f]{64}' .vbw/record.json; false; }
}

@test "R286 convert: a schema 13 or 14 record's object digests become the list on its first write, every digest keeping its value and its file, nothing else changed" {
  local s
  keyword_record
  cp .vbw/record.json "$TEST_ROOT/old.json"
  for s in 13 14; do
    # 14: the same record with a rule's --none entry marked git (R264), as 2.1.28 wrote it.
    jq --argjson s "$s" '.schema = $s | if $s == 14 then .plans[0].mutations += [{rule: {req: "R1", k: 1}, none: "reads git", git: true, at: "2026-01-01T00:00:00Z", head: ("b" * 40)}] else . end' "$TEST_ROOT/old.json" > .vbw/record.json
    cp .vbw/record.json "$TEST_ROOT/old$s.json"
    [ "$(validate)" = "[]" ] || { echo "schema $s: $(validate)"; false; }
    "$VBW" decide "convert $s" > /dev/null
    jq -e '.schema == 15 and all(.plans[].mutations[]?; (.digests // []) | type == "array")' .vbw/record.json || { jq -c '{schema, d: [.plans[].mutations[]?.digests]}' .vbw/record.json; false; }
    [ "$(jq -cS '.plans[0].mutations[0].digests | sort_by(.file)' .vbw/record.json)" = "$(jq -cS '.plans[0].mutations[0].digests | to_entries | map({file: .key, sha256: .value}) | sort_by(.file)' "$TEST_ROOT/old$s.json")" ] \
      || { echo "schema $s: the digests changed"; jq -c '.plans[0].mutations[0].digests' .vbw/record.json "$TEST_ROOT/old$s.json"; false; }
    [ "$(jq -cS 'del(.schema, .decisions, .plans[].mutations[]?.digests)' .vbw/record.json)" = "$(jq -cS 'del(.schema, .decisions, .plans[].mutations[]?.digests)' "$TEST_ROOT/old$s.json")" ] \
      || { echo "schema $s: the conversion changed more than the digests and the schema"; false; }
    [ "$(validate)" = "[]" ] || { echo "schema $s after: $(validate)"; false; }
  done
}

@test "R286 readers: vbw mutate, vbw show, vbw next and vbw status answer an old record and its converted one the same" {
  # The fixture's working file still holds its break (D634): a second identical break is refused by its digests.
  edit '.schema = 13 | .plans[0].mutations[0].digests |= (if type == "array" then map({key: .file, value: .sha256}) | from_entries else . end)'
  jq -e '.plans[0].mutations[0].digests | type == "object" and length == 1' .vbw/record.json || { jq -c '.plans[0].mutations[0].digests' .vbw/record.json; false; }
  local m1 s1 n1 st1 m2 s2 n2 st2
  m1=$("$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh 2>&1 < /dev/null) && { echo "the same bytes were not refused: $m1"; false; }
  s1=$("$VBW" show plan P1.1 2>&1 < /dev/null)
  n1=$("$VBW" next 2>&1 < /dev/null)
  st1=$("$VBW" status 2>&1 < /dev/null | grep -v "^what's next")
  [[ "$m1" == *"holds the same bytes of src/pay.sh"* ]] || { echo "$m1"; false; }
  "$VBW" decide "convert" > /dev/null
  jq -e '.schema == 15 and (.plans[0].mutations[0].digests | type == "array")' .vbw/record.json || { jq -c '{schema, d: .plans[0].mutations[0].digests}' .vbw/record.json; false; }
  m2=$("$VBW" mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh 2>&1 < /dev/null) && { echo "the same bytes were not refused after the conversion: $m2"; false; }
  s2=$("$VBW" show plan P1.1 2>&1 < /dev/null)
  n2=$("$VBW" next 2>&1 < /dev/null)
  st2=$("$VBW" status 2>&1 < /dev/null | grep -v "^what's next")
  [ "$m1" = "$m2" ] || { echo "vbw mutate: $m1 / $m2"; false; }
  [ "$s1" = "$s2" ] || { diff <(echo "$s1") <(echo "$s2"); false; }
  [ "$n1" = "$n2" ] || { echo "vbw next: $n1 / $n2"; false; }
  [ "$st1" = "$st2" ] || { diff <(echo "$st1") <(echo "$st2"); false; }
}
