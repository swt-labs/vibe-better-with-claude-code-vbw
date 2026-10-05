#!/usr/bin/env bats
# What each QA pass covered and what needs checking again (R47, R49): the digests
# of a phase's inputs (lib/qa-inputs.sh) and the reasons program (lib/qa.jq).

load helper
load qa-recheck-helper

teardown() { vbw_teardown; }

# rec N [CHAIN]: a record with built phases P1..PN of milestone M1, each with
# plan Pn.1 (done), every phase passed at digest "cN"; with CHAIN, Pn.1 comes after P(n-1).1.
rec() {
  jq -nc --argjson n "$1" --arg chain "${2:-}" '
    {milestone: {id: "M1"},
     phases: [range(1; $n + 1) | {id: "P\(.)", milestone: "M1", qa: {result: "pass", tier: "standard", tree: "c\(.)", at: "2026-10-05T00:00:00Z"}}],
     plans: [range(1; $n + 1) | {id: "P\(.).1", phase: "P\(.)", status: "done", after: (if $chain == "chain" and . > 1 then ["P\(. - 1).1"] else [] end)}]}'
}

# dig N [N=changed...]: the current digests of P1..PN; a listed number changes its files digest.
# The combined digest of Pn is "cN" unless changed (then "xN").
dig() {
  local n="$1" c
  shift
  c=$(printf '%s,' "$@")
  jq -nc --argjson n "$n" --arg c "${c%,}" '
    ($c | split(",") | map(select(. != ""))) as $ch
    | [range(1; $n + 1) | tostring | {key: "P\(.)", value: (if IN($ch[]) then {files: "f\(.)new", combined: "x\(.)"} else {files: "f\(.)", combined: "c\(.)"} end
        + {tests: "t\(.)", plan: "l\(.)"})}] | from_entries'
}

# cache N: what the clone cache holds after every phase passed (own digests and the digests of what it builds on).
cache() {
  jq -nc --argjson n "$1" '[range(1; $n + 1) | {key: "P\(.)", value: {files: "f\(.)", tests: "t\(.)", plan: "l\(.)",
    deps: ([range(1; .) | {key: "P\(.)", value: {files: "f\(.)", tests: "t\(.)", plan: "l\(.)"}}] | from_entries)}}] | from_entries'
}

qa() { jq -c --argjson inputs "$2" --argjson cache "$3" -f "$PLUGIN_ROOT/lib/qa.jq" <<< "$1"; }

@test "qa.jq: untouched phases keep their pass; the record's passes stand" {
  run qa "$(rec 2)" "$(dig 2)" "$(cache 2)"
  [ "$status" -eq 0 ]
  [ "$output" = '{"closure":{"P1":[],"P2":[]},"recheck":{},"standing":["P1","P2"],"problems":[]}' ]
}

@test "qa.jq: never checked, failed last time" {
  local r
  r=$(rec 2 | jq -c 'del(.phases[0].qa) | .phases[1].qa.result = "fail"')
  run qa "$r" "$(dig 2)" "$(cache 2)"
  echo "$output" | jq -e '.recheck == {"P1": ["not checked yet"], "P2": ["failed last time"]} and .standing == []'
}

@test "qa.jq: several reasons at once, each named: files, tests, goal or plan, and what it builds on" {
  local i
  i=$(dig 2 1 | jq -c '.P2.tests = "t2new" | .P2.plan = "l2new" | .P2.combined = "x2"')
  run qa "$(rec 2 chain)" "$i" "$(cache 2)"
  echo "$output" | jq -e '.recheck.P1 == ["its files changed"]
    and .recheck.P2 == ["its tests changed", "its goal or plan changed", "builds on P1, which changed"]'
}

@test "qa.jq: a phase that builds on a changed phase is checked again, transitively, and the one it builds on is not" {
  run qa "$(rec 3 chain)" "$(dig 3 1 | jq -c '.P2.combined = "x2" | .P3.combined = "x3"')" "$(cache 3)"
  echo "$output" | jq -e '.recheck | keys == ["P1","P2","P3"]'
  echo "$output" | jq -e '.recheck.P3 == ["builds on P1, which changed"]'
  run qa "$(rec 3 chain)" "$(dig 3 2 | jq -c '.P3.combined = "x3"')" "$(cache 3)"
  echo "$output" | jq -e '(.recheck | keys) == ["P2","P3"] and .standing == ["P1"]'
}

@test "qa.jq: a change that is checked again and passed leaves the dependent re-checked until it passes too" {
  local c
  c=$(cache 2 | jq -c '.P1.files = "f1new"')
  run qa "$(rec 2 chain | jq -c '.phases[0].qa.tree = "x1"')" "$(dig 2 1 | jq -c '.P1.combined = "x1" | .P2.combined = "x2"')" "$c"
  echo "$output" | jq -e '.recheck == {"P2": ["builds on P1, which changed"]} and .standing == ["P1"]'
}

@test "qa.jq: a cycle terminates and is named, with the phases in it" {
  local r
  r=$(rec 2 chain | jq -c '(.plans[] | select(.id == "P1.1")).after = ["P2.1"]')
  run qa "$r" "$(dig 2 1)" "$(cache 2)"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.problems | length == 1 and (.[0] | contains("P1") and contains("P2") and contains("cycle"))'
  echo "$output" | jq -e '.recheck.P1 | length > 0'
}

@test "qa.jq: a plan after a plan or a phase that does not exist is a problem, by name" {
  run qa "$(rec 2 chain | jq -c '(.plans[] | select(.id == "P2.1")).after = ["P9.9"]')" "$(dig 2)" "$(cache 2)"
  echo "$output" | jq -e '.problems | length == 1 and (.[0] | contains("P2.1") and contains("P9.9"))'
  run qa "$(rec 2 chain | jq -c '(.plans[] | select(.id == "P2.1")).phase = "P9"')" "$(dig 2)" "$(cache 2)"
  echo "$output" | jq -e '.problems | any(.[]; contains("P2.1") and contains("P9"))'
}

@test "qa.jq: without the clone cache the only change reason is the plain one" {
  local c
  for c in null '{}' '"junk"' '{"P1": 5}'; do
    run qa "$(rec 2 chain)" "$(dig 2 1 | jq -c '.P2.combined = "x2"')" "$c"
    echo "$output" | jq -e '.recheck == {"P1": ["its files, tests or plan changed"], "P2": ["its files, tests or plan changed"]}'
  done
}

@test "qa.jq: only the built phases of the active milestone are judged" {
  local r
  r=$(rec 3 | jq -c '(.plans[] | select(.id == "P2.1")).status = "todo" | .phases[2].milestone = "M0"')
  run qa "$r" "$(dig 3 1 2 3)" "$(cache 3)"
  echo "$output" | jq -e '(.recheck | keys) == ["P1"] and .standing == []'
}

@test "qa.jq: without digests it still reports the closure and the problems" {
  run jq -c --argjson inputs null --argjson cache null -f "$PLUGIN_ROOT/lib/qa.jq" <<< "$(rec 2 chain)"
  echo "$output" | jq -e '.closure == {"P1": [], "P2": ["P1"]} and .recheck == {} and .standing == []'
}

@test "qa_digests: files, tests, plan and combined digests per phase, from the committed content" {
  qa_project 2 chain
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; (.files, .tests, .plan, .combined) | test("^[0-9a-f]{64}$")) and .P2.deps == ["P1"] and .P1.deps == []'
  echo "$output" | jq -e '.P1.combined != .P2.combined and .P1.files != .P2.files'
}

@test "qa_digests: an uncommitted edit changes nothing; a commit changes that phase and what builds on it only" {
  qa_project 3 chain
  local a b c
  a=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  printf 'dirty\n' >> src/p2.txt
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  [ "$a" = "$b" ]
  git add src/p2.txt && git commit -q -m "touch"
  c=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  jq -ne --argjson a "$a" --argjson c "$c" '$a.P1 == $c.P1 and $a.P2.files != $c.P2.files and $a.P2.tests == $c.P2.tests
    and $a.P2.combined != $c.P2.combined and $a.P3.files == $c.P3.files and $a.P3.combined != $c.P3.combined'
}

@test "qa_digests: a changed check file changes tests, a changed goal changes plan, other phases are untouched" {
  qa_project 2
  local a b c
  a=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  printf '# stricter\n' >> tests/p1.sh
  git add tests/p1.sh && git commit -q -m "tests"
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  edit_record '(.phases[] | select(.id == "P2")).goal = "Part 2 works for everyone"'
  c=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  jq -ne --argjson a "$a" --argjson b "$b" --argjson c "$c" '
    $a.P1.tests != $b.P1.tests and $a.P1.files == $b.P1.files and $a.P2 == $b.P2
    and $b.P2.plan != $c.P2.plan and $b.P2.files == $c.P2.files and $b.P1 == $c.P1'
}

@test "qa cache: written for a phase, read back, and a damaged or missing file reads as no cache" {
  qa_project 2
  vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; d=$(qa_digests "$(cat "$VBW_RECORD")"); qa_cache_put P1 "$d"; qa_cache_put P2 "$d"'
  local f
  f="$(git rev-parse --git-common-dir)/vbw/qa.json"
  jq -e '[.P1, .P2] | all(.[]; (.files, .tests, .plan) | type == "string")' "$f"
  [ ! -d "$(git rev-parse --git-common-dir)/vbw/qa.lock" ]
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_cache_read | jq -c "keys"'
  [ "$output" = '["P1","P2"]' ]
  printf 'not json' > "$f"
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_cache_read'
  [ "$output" = "null" ]
  rm -f "$f"
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_cache_read'
  [ "$output" = "null" ]
  # a pass after damage rebuilds the file
  vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_cache_put P1 "$(qa_digests "$(cat "$VBW_RECORD")")"'
  jq -e 'keys == ["P1"]' "$f"
}

@test "the digests, the cache and the record give the reasons; a pass recorded in the cache stands" {
  qa_project 2 chain
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; d=$(qa_digests "$(cat "$VBW_RECORD")"); qa_cache_put P2 "$d"
    jq -c --argjson inputs "$d" --argjson cache "$(qa_cache_read)" -f "$VBW_LIB/qa.jq" "$VBW_RECORD"'
  echo "$output" | jq -e '.recheck == {"P1": ["not checked yet"], "P2": ["not checked yet"]}'
  jq -e '.P2.deps | keys == ["P1"]' "$(git rev-parse --git-common-dir)/vbw/qa.json"
}
