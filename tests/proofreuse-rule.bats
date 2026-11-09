#!/usr/bin/env bats
# R166 (docs/proof.md): the one reuse rule and the clone's store of recorded
# runs ($(git common dir)/vbw/runs.json). A unit's pass is reused only when its
# last result passed, its definition is unchanged, it has a read list and did
# not read through git, and the diff between the code it ran on and the
# committed code touches no file it read, adds or removes no file in a folder
# it listed and, for a check, adds or removes no file of its requirement's plans
# (R168: a check may test whether a path exists without opening it, so the
# contract's ties count, read or not). Every other case returns its reason. L1.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  mkdir -p src/lib docs
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'l\n' > src/lib/l.txt
  printf 'd\n' > docs/d.txt
  git add -A && git commit -q -m "chore(test): files"
  "$VBW" init > /dev/null
  unset PROOFREUSE_STORE
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# pr SNIPPET: run SNIPPET with the kernel and the reuse library loaded.
pr() {
  bash -c 'VBW_LIB="$1/lib"; for l in core record consent contract checks proofreuse; do . "$VBW_LIB/$l.sh"; done
    VBW_COMMAND_TIMEOUT=3600; vbw_project; eval "$2"' _ "$PLUGIN_ROOT" "$1"
}

# store RUNJSON: write a one-run store whose run ran on the current commit.
# Fields: status, fp, reads, dirs, git (tree is filled in).
store() {
  local tree
  tree=$(pr 'vbw_head_tree')
  mkdir -p "$(git rev-parse --git-common-dir)/vbw"
  jq -n --argjson r "$1" --arg tree "$tree" \
    '{runs: {"check:C1": ({fp: "F", tree: $tree, status: "pass", at: "t", seconds: 1, tail: "", reads: ["src/a.txt"], dirs: ["src/lib"], git: false} + $r)}}' \
    > "$(git rev-parse --git-common-dir)/vbw/runs.json"
}

# reason [FP]: the rule's answer for check:C1 against the committed code.
reason() {
  pr 'PROOFREUSE_STORE=$(proofreuse_store_read); proofreuse_reason check:C1 "'"${1:-F}"'" "$(vbw_head_tree)"'
}

@test "a pass with a read list, an unchanged definition and nothing touched is reused" {
  store '{}'
  run reason
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a commit that touches nothing the unit read or listed keeps the reuse" {
  store '{}'
  printf 'x\n' > docs/d.txt; printf 'n\n' > src/new.txt
  git add -A && git commit -q -m "chore(test): elsewhere"
  run reason
  [ "$status" -eq 0 ]
}

@test "never passed: no run is stored for the unit" {
  mkdir -p "$(git rev-parse --git-common-dir)/vbw"
  printf '{"runs":{}}\n' > "$(git rev-parse --git-common-dir)/vbw/runs.json"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "never passed" ]
}

@test "last result failed" {
  store '{"status":"fail"}'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "last result failed" ]
}

@test "no read list" {
  store '{"reads":null}'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "no read list" ]
}

@test "definition changed" {
  store '{}'
  run reason OTHER
  [ "$status" -eq 1 ]
  [ "$output" = "definition changed" ]
}

@test "reads the project through git" {
  store '{"git":true}'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "reads the project through git" ]
}

@test "<path> changed: a file of the read list was edited" {
  store '{}'
  printf 'a2\n' > src/a.txt
  git commit -q -am "chore(test): edit"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "src/a.txt changed" ]
}

@test "<path> deleted: a file of the read list was removed" {
  store '{}'
  git rm -q src/a.txt && git commit -q -m "chore(test): delete"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "src/a.txt deleted" ]
}

@test "a renamed file of the read list counts as deleted" {
  store '{}'
  git mv src/a.txt src/z.txt && git commit -q -m "chore(test): rename"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "src/a.txt deleted" ]
}

@test "<folder> listing changed: a file was added to a listed folder" {
  store '{}'
  printf 'n\n' > src/lib/new.txt
  git add -A && git commit -q -m "chore(test): add"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "src/lib listing changed" ]
}

@test "<folder> listing changed: a file was removed from a listed folder" {
  store '{}'
  git rm -q src/lib/l.txt && git commit -q -m "chore(test): remove"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "src/lib listing changed" ]
}

@test "editing a file inside a listed folder does not change the listing" {
  store '{}'
  printf 'l2\n' > src/lib/l.txt
  git commit -q -am "chore(test): edit in folder"
  run reason
  [ "$status" -eq 0 ]
}

@test "a file in a sub-folder of a listed folder is not in the listing" {
  store '{}'
  mkdir -p src/lib/deep && printf 'n\n' > src/lib/deep/x.txt
  git add -A && git commit -q -m "chore(test): deeper"
  run reason
  [ "$status" -eq 0 ]
}

@test "the root folder is named ." {
  store '{"dirs":["."]}'
  printf 'n\n' > root.txt
  git add -A && git commit -q -m "chore(test): root file"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = ". listing changed" ]
}

@test "a tree that is gone from the clone reuses nothing" {
  store '{"tree":"1111111111111111111111111111111111111111"}'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "the code it ran on is unknown" ]
}

@test "a clone with no runs reuses nothing, and its empty store holds runs and nothing else" {
  run pr 'PROOFREUSE_STORE=$(proofreuse_store_read); proofreuse_reason check:C1 F "$(vbw_head_tree)"; printf "%s\n" "$PROOFREUSE_STORE"'
  [[ "$output" == *"never passed"* ]]
  [[ "$output" == *'{"runs":{}}' ]]
}

@test "a store an older VBW left with a form is read as its runs alone" {
  mkdir -p "$(git rev-parse --git-common-dir)/vbw"
  printf '{"runs":{},"form":{"commands":{}}}\n' > "$(git rev-parse --git-common-dir)/vbw/runs.json"
  run pr 'proofreuse_store_read'
  [ "$output" = '{"runs":{}}' ]
}

@test "a damaged store reuses nothing" {
  mkdir -p "$(git rev-parse --git-common-dir)/vbw"
  printf 'not json {' > "$(git rev-parse --git-common-dir)/vbw/runs.json"
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "never passed" ]
  printf '[1,2]' > "$(git rev-parse --git-common-dir)/vbw/runs.json"
  run reason
  [ "$output" = "never passed" ]
}

@test "saving over a damaged store starts a good one" {
  mkdir -p "$(git rev-parse --git-common-dir)/vbw"
  printf 'garbage' > "$(git rev-parse --git-common-dir)/vbw/runs.json"
  run pr 'proofreuse_save "{\"checks\":[{\"id\":\"C1\",\"run\":[\"true\"]}],\"commands\":{}}" "{\"C1\":{\"status\":\"pass\",\"seconds\":2,\"tail\":\"ok\",\"reads\":[\"src/a.txt\"],\"dirs\":[],\"git\":false}}" "{}" TREE NOW'
  [ "$status" -eq 0 ]
  run jq -r '.runs["check:C1"] | "\(.status) \(.tree) \(.at) \(.seconds) \(.reads[0])"' "$(git rev-parse --git-common-dir)/vbw/runs.json"
  [ "$output" = "pass TREE NOW 2 src/a.txt" ]
  run jq -c 'keys' "$(git rev-parse --git-common-dir)/vbw/runs.json"
  [ "$output" = '["runs"]' ]
}

@test "a saved run keeps the others and a unit that did not run keeps its earlier run" {
  rec='{"checks":[{"id":"C1","run":["true"]},{"id":"C2","run":["true"]}],"commands":{"test":["make"]}}'
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[],\"dirs\":[]},\"C2\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[],\"dirs\":[]}}" "{\"test\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[],\"dirs\":[]}}" T1 N1'
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"fail\",\"seconds\":1,\"reads\":null},\"C2\":{\"status\":\"waiting\",\"seconds\":0}}" "{\"test\":{\"status\":\"skipped\",\"seconds\":0}}" T2 N2'
  run jq -r '[.runs["check:C1"].status, .runs["check:C1"].tree, .runs["check:C2"].tree, .runs["command:test"].tree] | join(" ")' "$(git rev-parse --git-common-dir)/vbw/runs.json"
  [ "$output" = "fail T2 T1 T1" ]
}

@test "a run that read through git is saved without read lists, an older store's lists go at the next save, and it still runs again" {
  # An older VBW kept C1's whole read list though it read through git.
  store '{"git":true,"reads":["src/a.txt","src/b.txt","src/lib/l.txt"],"dirs":[{"path":"src","fp":"x"}]}'
  rec='{"checks":[{"id":"C1","run":["true"]},{"id":"C2","run":["true"]},{"id":"C3","run":["true"]}],"commands":{}}'
  pr 'proofreuse_save '"'$rec'"' "{\"C2\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[\"src/a.txt\"],\"dirs\":[{\"path\":\"src\",\"fp\":\"y\"}],\"git\":true},\"C3\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[\"src/a.txt\"],\"dirs\":[{\"path\":\"src\",\"fp\":\"y\"}],\"git\":false}}" "{}" T N'
  run jq -c '.runs | map_values({reads, dirs, git})' "$(git rev-parse --git-common-dir)/vbw/runs.json"
  [ "$output" = '{"check:C1":{"reads":[],"dirs":[],"git":true},"check:C2":{"reads":[],"dirs":[],"git":true},"check:C3":{"reads":["src/a.txt"],"dirs":[{"path":"src","fp":"y"}],"git":false}}' ]
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "reads the project through git" ]
}

@test "every save writes the runs' seconds beside the store, and a unit that leaves the store leaves them" {
  rec='{"checks":[{"id":"C1","run":["true"]},{"id":"C2","run":["true"]}],"commands":{"test":["make"]}}'
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":2,\"reads\":[],\"dirs\":[]},\"C2\":{\"status\":\"fail\",\"seconds\":5,\"reads\":[],\"dirs\":[]}}" "{\"test\":{\"status\":\"pass\",\"seconds\":7,\"reads\":[],\"dirs\":[]}}" T N'
  run jq -c . "$(git rev-parse --git-common-dir)/vbw/run-times.json"
  [ "$output" = '{"runs":{"check:C1":{"seconds":2},"check:C2":{"seconds":5},"command:test":{"seconds":7}}}' ]
  pr 'proofreuse_save '"'$rec'"' "{\"C2\":{\"status\":\"pass\",\"seconds\":3,\"reads\":[],\"dirs\":[]}}" "{}" T N "[\"check:C1\"]"'
  run jq -c . "$(git rev-parse --git-common-dir)/vbw/run-times.json"
  [ "$output" = '{"runs":{"check:C2":{"seconds":3},"command:test":{"seconds":7}}}' ]
}

@test "the store is never written into the record" {
  rec='{"checks":[{"id":"C1","run":["true"]}],"commands":{}}'
  before=$(cat .vbw/record.json)
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[],\"dirs\":[]}}" "{}" T N'
  [ "$(cat .vbw/record.json)" = "$before" ]
  [ -f "$(git rev-parse --git-common-dir)/vbw/runs.json" ]
}

@test "the plan reuses what the rule allows and says why the rest runs" {
  rec='{"checks":[{"id":"C1","run":["true"]},{"id":"C2","run":["true"]},{"id":"C3","run":["true"]}],"commands":{"test":["make"]}}'
  tree=$(pr 'vbw_head_tree')
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[\"src/a.txt\"],\"dirs\":[]},\"C2\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[\"src/b.txt\"],\"dirs\":[]}}" "{\"test\":{\"status\":\"pass\",\"seconds\":1,\"reads\":null}}" '"$tree"' N'
  printf 'b2\n' > src/b.txt
  git commit -q -am "chore(test): edit b"
  run pr 'proofreuse_plan '"'$rec'"' 1; jq -nc --argjson r "$REUSE_CHECKS" --argjson w "$WHY_CHECKS" --argjson c "$WHY_COMMANDS" "{reused: (\$r | keys), why: \$w, commands: \$c, todo: \"${TODO_CHECKS[*]}\"}"'
  [ "$status" -eq 0 ]
  [ "$output" = '{"reused":["C1"],"why":{"C2":"src/b.txt changed","C3":"never passed"},"commands":{"test":"no read list"},"todo":"C2 C3"}' ]
}

# plan_verdict REC: proofreuse_plan under the record REC: the reused checks and why the others run.
plan_verdict() {
  pr 'proofreuse_plan '"'$1'"'; jq -nc --argjson r "$REUSE_CHECKS" --argjson w "$WHY_CHECKS" "{reused: (\$r | keys), why: \$w}"'
}

# tied REC: C1 ran on the current commit and read src/a.txt only; REC's plans say what its requirement delivers.
tied() {
  pr 'proofreuse_save '"'$1'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[\"src/a.txt\"],\"dirs\":[]}}" "{}" "$(vbw_head_tree)" N'
}

@test "R168: a deleted file of its requirement's plans runs a check again though it never read it: a check may test whether a path exists" {
  rec='{"checks":[{"id":"C1","req":"R1","run":["true"]}],"plans":[{"id":"P1.1","reqs":["R1"],"files":["src/b.txt"]}],"commands":{}}'
  tied "$rec"
  git rm -q src/b.txt && git commit -q -m "chore(test): drop b"
  run plan_verdict "$rec"
  [ "$output" = '{"reused":[],"why":{"C1":"src/b.txt deleted"}}' ] || { echo "$output"; false; }
  # The one-unit front gives the same answer when it is given the record.
  run pr 'PROOFREUSE_STORE=$(proofreuse_store_read); proofreuse_current check:C1 "$(proofreuse_check_fp '"'$rec'"' C1)" "$(vbw_head_tree)" '"'$rec'"
  [ "$status" -eq 1 ] && [ "$output" = "src/b.txt deleted" ] || { echo "$status: $output"; false; }
}

@test "R168: an added file of its requirement's plans runs the check again, through a folder entry or *; an exact entry elsewhere ties nothing" {
  rec='{"checks":[{"id":"C1","req":"R1","run":["true"]}],"plans":[{"id":"P1.1","reqs":["R1"],"files":["src/lib/"]}],"commands":{}}'
  tied "$rec"
  printf 'n\n' > src/lib/new.txt
  git add src/lib/new.txt && git commit -q -m "chore(test): add"
  run plan_verdict "$rec"
  [ "$output" = '{"reused":[],"why":{"C1":"src/lib/new.txt added"}}' ] || { echo "$output"; false; }
  run plan_verdict "$(printf '%s' "$rec" | jq -c '.plans[0].files = ["*"]')"
  [ "$output" = '{"reused":[],"why":{"C1":"src/lib/new.txt added"}}' ] || { echo "$output"; false; }
  run plan_verdict "$(printf '%s' "$rec" | jq -c '.plans[0].files = ["src/lib/l.txt"]')"
  [ "$output" = '{"reused":["C1"],"why":{}}' ] || { echo "$output"; false; }
}

@test "R168: a content change to a file of its requirement's plans the check did not read, or a file deleted from another requirement's plans, keeps the reuse" {
  rec='{"checks":[{"id":"C1","req":"R1","run":["true"]}],"plans":[{"id":"P1.1","reqs":["R1"],"files":["src/b.txt"]},{"id":"P2.1","reqs":["R2"],"files":["docs/d.txt"]}],"commands":{}}'
  tied "$rec"
  printf 'b2\n' > src/b.txt
  git commit -q -am "chore(test): edit b"
  run plan_verdict "$rec"
  [ "$output" = '{"reused":["C1"],"why":{}}' ] || { echo "$output"; false; }
  git rm -q docs/d.txt && git commit -q -m "chore(test): drop d"
  run plan_verdict "$rec"
  [ "$output" = '{"reused":["C1"],"why":{}}' ] || { echo "$output"; false; }
}

@test "proving again with nothing committed reuses nothing" {
  rec='{"checks":[{"id":"C1","run":["true"]}],"commands":{}}'
  tree=$(pr 'vbw_head_tree')
  pr 'proofreuse_save '"'$rec'"' "{\"C1\":{\"status\":\"pass\",\"seconds\":1,\"reads\":[],\"dirs\":[]}}" "{}" '"$tree"' N'
  run pr 'proofreuse_plan '"'$rec'"'; printf "%s\n" "$REUSE_CHECKS"'
  [[ "$output" == *'"reused":true'* ]]
  git add -A .vbw && git commit -q -m "chore(vbw): state"
  code=$(pr 'vbw_code_tree')
  rec='{"requirements":[],"plans":[],"checks":[{"id":"C1","run":["true"]}],"commands":{},"evidence":{"passed":true,"tree":"'"$code"'","head":"'"$tree"'"}}'
  rec=$(printf '%s' "$rec" | jq -c --arg c "$(pr 'contract_hash '"'$rec'")" '.evidence.contract = $c')
  rec=$(printf '%s' "$rec" | jq -c --arg f "$(printf '%s' "$rec" | jq -c 'del(.evidence, .schema)' | pr 'vbw_sha256')" '.evidence.record = $f')
  run pr 'proofreuse_plan '"'$rec'"'; printf "%s\n" "$WHY_CHECKS"'
  [ "$output" = '{"C1":"proving again with nothing committed"}' ]
  # The record changed since that proof (R175): the rule reuses again.
  rec=$(printf '%s' "$rec" | jq -c '.plans = [{id: "P1.1"}]')
  run pr 'proofreuse_plan '"'$rec'"'; printf "%s\n" "$REUSE_CHECKS"'
  [[ "$output" == *'"reused":true'* ]] || { echo "$output"; false; }
}

@test "the served-files rule, the documentation rule and the evidence reuse are gone" {
  run grep -En 'proofreuse_docs|proofreuse_test_run|proofreuse_stamp|checks_fingerprint|test_run|served' "$PLUGIN_ROOT/lib/proofreuse.sh"
  [ "$status" -eq 1 ]
}

# R279 (measured at 2.1.28, D686): a version bump reruns only the units whose outcome can
# depend on the version. A unit's run keeps, beside its read list, the files the VBW kernel
# it ran read for its own bookkeeping (kernel_reads: the version for the writer file of
# R272, logged by the kernel when the proof names a file for it, the read itself leaving
# the file's access time as it was). When the only change to such a file is its version
# value, a unit that read it only through the kernel is reused; a unit that read it
# itself (printing or comparing the version) runs again, the reason 'reads the version:
# FILE'; any other change to the file reruns every unit that read it either way.

# version_file: a VBW-shaped plugin.json, committed.
version_file() {
  mkdir -p plugin/.claude-plugin
  jq -n '{name: "vbw", version: "1.0.0", description: "a plugin"}' > plugin/.claude-plugin/plugin.json
  git add plugin && git commit -q -m "chore(test): plugin"
}
# bump FILTER: change plugin.json with FILTER and commit.
bump() {
  jq "$1" plugin/.claude-plugin/plugin.json > "$TEST_ROOT/p.json" && cp "$TEST_ROOT/p.json" plugin/.claude-plugin/plugin.json
  git commit -q -am "chore(test): bump"
}
PJ='plugin/.claude-plugin/plugin.json'

@test "R279 rule: a unit that read plugin.json only through the kernel's version read is reused after a change of only the version" {
  version_file
  store '{"reads": ["src/a.txt"], "kernel_reads": ["plugin/.claude-plugin/plugin.json"]}'
  bump '.version = "1.0.1"'
  run reason
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ]
}

@test "R279 rule: a unit that read plugin.json itself runs again after a version bump, the reason naming the version" {
  version_file
  store '{"reads": ["src/a.txt", "plugin/.claude-plugin/plugin.json"], "kernel_reads": ["plugin/.claude-plugin/plugin.json"]}'
  bump '.version = "1.0.1"'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "reads the version: $PJ" ] || { echo "$output"; false; }
}

@test "R279 rule: any other change to plugin.json reruns a unit that read it, through the kernel or itself, as before" {
  version_file
  store '{"reads": ["src/a.txt"], "kernel_reads": ["plugin/.claude-plugin/plugin.json"]}'
  bump '.description = "another plugin"'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "$PJ changed" ] || { echo "$output"; false; }
  bump '.version = "1.0.2" | .description = "a third plugin"'
  run reason
  [ "$status" -eq 1 ]
  [ "$output" = "$PJ changed" ] || { echo "$output"; false; }
}
