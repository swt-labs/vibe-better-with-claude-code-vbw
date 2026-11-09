#!/usr/bin/env bats
# What each QA pass covered and what needs checking again (R47, R49): the digests
# of a phase's inputs (lib/qa-inputs.sh) and the reasons program (lib/qa.jq).

load helper
load qa-recheck-helper
load fixture-helper

# The built projects the digest tests start from, each built once per file.
setup_file() {
  fixture_build p2 qa_project 2
  fixture_build p2chain qa_project 2 chain
  fixture_build p3chain qa_project 3 chain
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

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

# As the kernel runs it: the shared definitions (lib/record.sh) first.
qa() { jq -c --argjson inputs "$2" --argjson cache "$3" "$(VBW_LIB="$PLUGIN_ROOT/lib" && . "$PLUGIN_ROOT/lib/record.sh" && printf '%s' "$VBW_JQ_DEFS")$(cat "$PLUGIN_ROOT/lib/qa.jq")" <<< "$1"; }

@test "qa.jq: untouched phases keep their pass; the record's passes stand" {
  run qa "$(rec 2)" "$(dig 2)" "$(cache 2)"
  [ "$status" -eq 0 ]
  [ "$output" = '{"closure":{"P1":[],"P2":[]},"recheck":{},"standing":["P1","P2"],"focus":{},"deviations":{},"interleaved":[],"problems":[]}' ]
}

@test "qa.jq: never checked, failed last time" {
  local r
  r=$(rec 2 | jq -c 'del(.phases[0].qa) | .phases[1].qa.result = "fail"')
  run qa "$r" "$(dig 2)" "$(cache 2)"
  echo "$output" | jq -e '.recheck == {"P1": ["not checked yet"], "P2": ["failed last time"]} and .standing == []'
}

@test "qa.jq: several reasons at once, each named: files, tests, goal or plan, and the tests of what it builds on" {
  local i
  i=$(dig 2 1 | jq -c '.P1.tests = "t1new" | .P2.tests = "t2new" | .P2.plan = "l2new" | .P2.combined = "x2"')
  run qa "$(rec 2 chain)" "$i" "$(cache 2)"
  echo "$output" | jq -e '.recheck.P1 == ["its files changed", "its tests changed"]
    and .recheck.P2 == ["its tests changed", "its goal or plan changed", "builds on P1, whose tests changed"]'
}

@test "qa.jq: a phase that builds on one whose tests changed is checked again, transitively, and the one it builds on is not" {
  run qa "$(rec 3 chain)" "$(dig 3 1 | jq -c '.P1.tests = "t1new" | .P2.combined = "x2" | .P3.combined = "x3"')" "$(cache 3)"
  echo "$output" | jq -e '.recheck | keys == ["P1","P2","P3"]'
  echo "$output" | jq -e '.recheck.P3 == ["builds on P1, whose tests changed"]'
  run qa "$(rec 3 chain)" "$(dig 3 2 | jq -c '.P2.tests = "t2new" | .P3.combined = "x3"')" "$(cache 3)"
  echo "$output" | jq -e '(.recheck | keys) == ["P2","P3"] and .standing == ["P1"]'
}

@test "qa.jq: a dependency whose files or plan changed but not its tests leaves the dependent standing" {
  run qa "$(rec 2 chain)" "$(dig 2 1 | jq -c '.P1.plan = "l1new"')" "$(cache 2)"
  echo "$output" | jq -e '(.recheck | keys) == ["P1"] and .standing == ["P2"]' || { echo "$output"; false; }
}

@test "qa.jq: a change that is checked again and passed leaves the dependent re-checked until it passes too" {
  local c
  c=$(cache 2 | jq -c '.P1.files = "f1new" | .P1.tests = "t1new"')
  run qa "$(rec 2 chain | jq -c '.phases[0].qa.tree = "x1"')" "$(dig 2 1 | jq -c '.P1.tests = "t1new" | .P1.combined = "x1" | .P2.combined = "x2"')" "$c"
  echo "$output" | jq -e '.recheck == {"P2": ["builds on P1, whose tests changed"]} and .standing == ["P1"]'
}

@test "qa.jq: a cycle among the plans terminates and is named, with the plans in it" {
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
  run qa "$(rec 2 chain)" null null
  echo "$output" | jq -e '.closure == {"P1": [], "P2": ["P1"]} and .recheck == {} and .standing == []'
}

@test "qa_digests: files, tests, plan and combined digests per phase, from the committed content" {
  fixture_copy p2chain
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'all(.[]; (.files, .tests, .plan, .combined) | test("^[0-9a-f]{64}$")) and .P2.deps == ["P1"] and .P1.deps == []'
  echo "$output" | jq -e '.P1.combined != .P2.combined and .P1.files != .P2.files'
}

@test "qa_digests: an uncommitted edit changes nothing; a code commit changes that phase only, a test commit what builds on it too" {
  fixture_copy p3chain
  local a b c
  a=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  printf 'dirty\n' >> src/p2.txt
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  [ "$a" = "$b" ]
  git add src/p2.txt && git commit -q -m "touch"
  c=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  jq -ne --argjson a "$a" --argjson c "$c" '$a.P1 == $c.P1 and $a.P2.files != $c.P2.files and $a.P2.tests == $c.P2.tests
    and $a.P2.combined != $c.P2.combined and $a.P3.files == $c.P3.files and $a.P3.combined == $c.P3.combined'
  printf '# stricter\n' >> tests/p2.sh
  git add tests/p2.sh && git commit -q -m "tests"
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"')
  jq -ne --argjson c "$c" --argjson b "$b" '$c.P1 == $b.P1 and $c.P2.tests != $b.P2.tests and $c.P3.combined != $b.P3.combined'
}

@test "qa_digests: a changed check file changes tests, a changed goal changes plan, other phases are untouched" {
  fixture_copy p2
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
  fixture_copy p2
  vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; d=$(qa_digests "$(cat "$VBW_RECORD")"); qa_cache_put P1 "$d"; qa_cache_put P2 "$d"'
  local f
  f="$(git rev-parse --git-common-dir)/vbw/qa.json"
  jq -e '[.P1, .P2] | all(.[]; (.files, .tests, .plan) | type == "string")' "$f"
  [ ! -e "$(git rev-parse --git-common-dir)/vbw/qa.lock" ]
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
  fixture_copy p2chain
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; d=$(qa_digests "$(cat "$VBW_RECORD")"); qa_cache_put P2 "$d"
    jq -c --argjson inputs "$d" --argjson cache "$(qa_cache_read)" "$VBW_JQ_DEFS$(cat "$VBW_LIB/qa.jq")" "$VBW_RECORD"'
  echo "$output" | jq -e '.recheck == {"P1": ["not checked yet"], "P2": ["not checked yet"]}'
  jq -e '.P2.deps | keys == ["P1"]' "$(git rev-parse --git-common-dir)/vbw/qa.json"
}

# ---- R268: vbw next fast on a big milestone ----

# linked N LINKS: a record with phases P1..PN of milestone M1, two done plans each
# (Pn.1, Pn.2) and the after-links LINKS, a JSON object {plan: [plans it comes after]}.
linked() {
  jq -nc --argjson n "$1" --argjson links "$2" '
    {milestone: {id: "M1"},
     phases: [range(1; $n + 1) | {id: "P\(.)", milestone: "M1"}],
     plans: [range(1; $n + 1) | "P\(.)" as $p | ("\($p).1", "\($p).2") | {id: ., phase: $p, status: "done", after: ($links[.] // [])}]}'
}

# shape N LINKS: the closure, the interleaved phases and the problems the program gives.
shape() { qa "$(linked "$1" "$2")" null null | jq -c '{closure, interleaved, problems}'; }

@test "R268 closure: qa.jq gives the same closure, interleaved phases and problems for a chain, a diamond, a ring, a self-link, a missing plan and the cycles" {
  run shape 3 '{"P2.1":["P1.1"],"P3.1":["P2.1"]}'
  [ "$output" = '{"closure":{"P1":[],"P2":["P1"],"P3":["P1","P2"]},"interleaved":[],"problems":[]}' ]
  run shape 4 '{"P2.1":["P1.1"],"P3.1":["P1.1"],"P4.1":["P2.1","P3.1"]}'
  [ "$output" = '{"closure":{"P1":[],"P2":["P1"],"P3":["P1"],"P4":["P1","P2","P3"]},"interleaved":[],"problems":[]}' ]
  run shape 2 '{"P2.1":["P1.1"],"P1.2":["P2.1"]}'
  [ "$output" = '{"closure":{"P1":["P2"],"P2":["P1"]},"interleaved":["P1","P2"],"problems":[]}' ]
  run shape 3 '{"P2.1":["P1.1"],"P3.1":["P2.1"],"P1.2":["P3.1"]}'
  [ "$output" = '{"closure":{"P1":["P2","P3"],"P2":["P1","P3"],"P3":["P1","P2"]},"interleaved":["P1","P2","P3"],"problems":[]}' ]
  run shape 2 '{"P1.2":["P1.1"]}'
  [ "$output" = '{"closure":{"P1":[],"P2":[]},"interleaved":[],"problems":[]}' ]
  run shape 2 '{"P2.1":["P9.9"]}'
  [ "$output" = '{"closure":{"P1":[],"P2":[]},"interleaved":[],"problems":["plan P2.1 comes after P9.9, which does not exist"]}' ]
  run shape 2 '{"P1.1":["P2.1"],"P2.1":["P1.1"]}'
  [ "$output" = '{"closure":{"P1":["P2"],"P2":["P1"]},"interleaved":["P1","P2"],"problems":["plans P1.1, P2.1 come after each other (a cycle)"]}' ]
  run shape 3 '{"P1.1":["P2.1"],"P2.1":["P3.2"],"P3.2":["P1.1"],"P3.1":["P1.2"]}'
  [ "$output" = '{"closure":{"P1":["P2","P3"],"P2":["P1","P3"],"P3":["P1","P2"]},"interleaved":["P1","P2","P3"],"problems":["plans P1.1, P2.1, P3.2 come after each other (a cycle)"]}' ]
}

@test "R268 closure: qa.jq walks the graph once: no expansion round per phase or per plan" {
  # The closure of 79 phases took one full round per phase (79 passes over the whole map);
  # one walk from each node (depth-first, visited set) gives the same answer in one pass.
  run grep -c 'range(0; \$ids | length)\|range(0; \$pids | length)' "$PLUGIN_ROOT/lib/qa.jq"
  [ "$output" = 0 ]
}

@test "R268 digests: qa_digests gives the digests it always gave" {
  fixture_copy p3chain
  run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"'
  [ "$status" -eq 0 ]
  [ "$output" = '{"P1":{"files":"83566488d0ca6f98525ecbe83f8151fee5eedfa41222cb90b21417ddd2b527d9","tests":"036fd329c840e4854ecac49af06bd8dd6a5236d2312717f72b064fd3918bd51c","plan":"b305be2c4509500e5a6ba9d873478647aafcce6009e0a2c91757874760a52b75","reqs":"a0d5d58e525744595c480a84e188f0658d57810c2835ee1b48a0ce70f4f56c2f","combined":"257e05dd68ad4ee787aa77f44cd7c2f1900f4227ee228290c2502df98e3f0d33","deps":[]},"P2":{"files":"40426796e4bb781736811b845c475b0a95afce7f58246edf47f1334334e6c0d2","tests":"f9baffd2748396e10a424d4c2bad206d84423c758cf54b6774fb264b113c6c67","plan":"b51b36ec3663ba204251dc4567f280edca41c863d2364b4173e8a3bc753c53b2","reqs":"ad5ebab88bd9111aa6c6aabe2729c98d75b4f5ee198e63ba1051f5dacc595505","combined":"e5942760f577b170ac07c38116b78f845db686ac1a79114064c3e191bade2bbc","deps":["P1"]},"P3":{"files":"c31d0a9056d4d3099a1187fe559e7e4926f69430266c5d54e84583605189ae85","tests":"6cb34afb5a433f049010b81d6a54066009c918eeabe35c32003c9e55830b7218","plan":"e41d9f36dd0235bdea51b6a3362af39d3252cea28dc8e8968278fe441dff8baa","reqs":"1f83d438158e3b8a341cde389f1a9e764e541e02b18f8fa6452f2e66179ab1fb","combined":"0d7abfe19a9bea9b72eb4136783d7d65272ee60f1a49fecbe06bc34c6947bc62","deps":["P1","P2"]}}' ]
}

@test "R268 digests: qa_digests reads each repository's tree once, however many phases, and a submodule once too" {
  fixture_copy p3chain
  mkdir -p "$TEST_ROOT/shim"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GIT_LOG"\nexec "%s" "$@"\n' "$(command -v git)" > "$TEST_ROOT/shim/git"
  chmod +x "$TEST_ROOT/shim/git"
  export GIT_LOG="$TEST_ROOT/git.log"
  : > "$GIT_LOG"
  PATH="$TEST_ROOT/shim:$PATH" run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")" > /dev/null'
  [ "$status" -eq 0 ]
  run grep -c ' ls-tree ' "$GIT_LOG"
  [ "$output" = 1 ]
  # A submodule tracked by a plan's file: its own tree once.
  git -C "$TEST_ROOT" init -q sub && printf 'x\n' > "$TEST_ROOT/sub/s.txt" && git -C "$TEST_ROOT/sub" add s.txt && git -C "$TEST_ROOT/sub" commit -q -m sub
  git -c protocol.file.allow=always submodule add -q "$TEST_ROOT/sub" vendor/sub 2> /dev/null
  git commit -q -m "chore: submodule"
  edit_record '.plans |= map(if .id == "P1.1" then .files += ["vendor/sub/s.txt"] else . end)'
  : > "$GIT_LOG"
  PATH="$TEST_ROOT/shim:$PATH" run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")" > /dev/null'
  [ "$status" -eq 0 ]
  run grep -c ' ls-tree ' "$GIT_LOG"
  [ "$output" = 2 ]
}

@test "R268 digests: qa_digests hands its answer out through vbw_out, not a builtin write" {
  # A loop fed by a process substitution ends with a live child: macOS bash 3.2 does
  # not restart a printf it interrupts (CLAUDE.md, "No builtin write while the shell
  # has a live child"), so the digests reach the caller through vbw_out.
  body=$(sed -n '/^qa_digests() {/,/^}/p' "$PLUGIN_ROOT/lib/qa-inputs.sh")
  [ -n "$body" ]
  ! grep -q "printf '%s\\\\n' \"\$out\"" <<< "$body" || { echo "qa_digests still writes with a builtin printf"; false; }
  grep -q 'vbw_out' <<< "$body" || { echo "qa_digests does not write through vbw_out"; false; }
}
