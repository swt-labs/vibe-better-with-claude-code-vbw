#!/usr/bin/env bats
# R167: the `## Test files` section of .vbw/spec.md (docs/proof.md): parsing,
# refusals, the record's test_files field, and its approval like a command
# (part of the contract hash; shown by vbw show contract). L1.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# spec FORM: the spec with one requirement, a test command and, when FORM is
# not empty, a Test files section holding FORM's lines.
spec() {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  [ -z "$1" ] || printf '\n## Test files\n\n%s\n' "$1" >> .vbw/spec.md
}

FORM='- run: sh {file}
- files: tests/t_*.sh'

@test "spec check accepts a run line with {file} once and files lines, several lines and several patterns" {
  spec '- run: ["sh", "{file}"]
- files: tests/t_*.sh src/*.t
- files: more/*.t'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.test_files' .vbw/record.json)" = '{"run":["sh","{file}"],"files":["tests/t_*.sh","src/*.t","more/*.t"]}' ]
}

@test "the spec parser returns the form as run argv and files" {
  spec "$FORM"
  jq -Rs -f "$PLUGIN_ROOT/lib/spec.jq" < .vbw/spec.md | jq -e '.test_files == {run: ["sh","{file}"], files: ["tests/t_*.sh"]} and .errors == []'
}

@test "a spec without the section has no form" {
  spec ""
  jq -Rs -f "$PLUGIN_ROOT/lib/spec.jq" < .vbw/spec.md | jq -e '.test_files == null'
}

@test "a run line without {file}, or with it twice, is refused naming its line" {
  spec '- run: sh tests/t_a.sh
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 13"* && "$output" == *"{file}"* ]] || { echo "$output"; false; }
  spec '- run: sh {file} {file}
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 13"* ]] || { echo "$output"; false; }
}

@test "a section without files, or without a run line, is refused naming the section's line" {
  spec '- run: sh {file}'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 11"* && "$output" == *"files"* ]] || { echo "$output"; false; }
  spec '- files: tests/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 11"* && "$output" == *"run"* ]] || { echo "$output"; false; }
}

@test "a second run line and an unknown line are refused" {
  spec '- run: sh {file}
- run: bash {file}
- files: a'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"two run lines"* ]] || { echo "$output"; false; }
  spec '- run: sh {file}
- files: a
- other: b'
  run "$VBW" spec sync
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 15"* ]] || { echo "$output"; false; }
}

@test "sync removes the field when the section goes, and an older record without it opens as before" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  jq -e 'has("test_files")' .vbw/record.json > /dev/null
  spec ""
  "$VBW" spec sync > /dev/null
  jq -e 'has("test_files") | not' .vbw/record.json > /dev/null
  run "$VBW" status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "sync says when the form is added, changed or removed" {
  spec "$FORM"
  run "$VBW" spec sync
  [[ "$output" == *"added test file form"* ]] || { echo "$output"; false; }
  spec '- run: sh {file} x
- files: tests/t_*.sh'
  run "$VBW" spec sync
  [[ "$output" == *"changed test file form"* ]] || { echo "$output"; false; }
  spec ""
  run "$VBW" spec sync
  [[ "$output" == *"removed test file form"* ]] || { echo "$output"; false; }
}

@test "the form is part of the contract: editing it changes the hash and needs a new approval" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: spec"
  vbw_run show contract
  h1=$(printf '%s\n' "$output" | grep -oE '[0-9a-f]{12}' | head -1)
  spec '- run: sh {file} again
- files: tests/t_*.sh'
  "$VBW" spec sync > /dev/null
  vbw_run show contract
  h2=$(printf '%s\n' "$output" | grep -oE '[0-9a-f]{12}' | head -1)
  [ -n "$h1" ] && [ "$h1" != "$h2" ] || { echo "$h1 $h2"; false; }
}

@test "vbw approve grants the form like a command, and vbw show contract lists it among the commands that will run" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","c.sh"], files:["c.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["a.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules) | .protected = ["c.sh"] | .schema = 4' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  : > c.sh
  git add -A && git commit -q -m "chore: project"
  vbw_run show contract
  [[ "$output" == *"test file form"* && "$output" == *"sh {file}"* && "$output" == *"tests/t_*.sh"* ]] || { echo "$output"; false; }
  run "$VBW" approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"approved test file form"* ]] || { echo "$output"; false; }
  jq -e 'any(.granted[]; .kind == "test_files")' "$(git rev-parse --git-common-dir)/vbw/consent.json" > /dev/null
}

# #735: several named forms, each with its own run, files and optional dir.
FORMS='- webapp:
  - dir: apps/webapp
  - run: sh run.sh {file}
  - files: apps/webapp/src/*.t
- mobile:
  - run: ["sh", "apps/mobile/run.sh", "{file}"]
  - files: apps/mobile/*.t
  - files: apps/mobile/more/*.t'

@test "#735: named forms parse into an array of {name, dir, run, files}, dir null when absent" {
  spec "$FORMS"
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.test_files == [
    {name: "webapp", dir: "apps/webapp", run: ["sh","run.sh","{file}"], files: ["apps/webapp/src/*.t"]},
    {name: "mobile", dir: null, run: ["sh","apps/mobile/run.sh","{file}"], files: ["apps/mobile/*.t","apps/mobile/more/*.t"]}]' .vbw/record.json \
    || { jq .test_files .vbw/record.json; false; }
}

@test "#735: the unnamed shape stays {run, files}; with a top-level dir it is one form with a null name" {
  spec "$FORM"
  "$VBW" spec sync > /dev/null
  [ "$(jq -c '.test_files' .vbw/record.json)" = '{"run":["sh","{file}"],"files":["tests/t_*.sh"]}' ]
  spec '- dir: apps/a/
- run: sh {file}
- files: apps/a/t_*.sh'
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.test_files' .vbw/record.json)" = '[{"name":null,"dir":"apps/a","run":["sh","{file}"],"files":["apps/a/t_*.sh"]}]' ] \
    || { jq -c .test_files .vbw/record.json; false; }
}

# refused SPEC_LINES TEXT...: spec check refuses the section, naming every TEXT.
refused() {
  local t
  spec "$1"
  shift
  run "$VBW" spec check
  [ "$status" -ne 0 ] || { echo "accepted: $output"; return 1; }
  for t in "$@"; do [[ "$output" == *"$t"* ]] || { echo "missing '$t' in: $output"; return 1; }; done
}

@test "#735: a form without run or files, a form named twice and a run naming {file} twice are refused with the line" {
  refused '- a:
  - files: x/*.t' "line 13" "form a needs a '- run:"
  refused '- a:
  - run: sh {file}' "line 13" "form a needs a '- files:"
  refused '- a:
  - run: sh {file}
  - files: x/*.t
- a:
  - run: sh {file}
  - files: y/*.t' "line 16" "form a is named twice"
  refused '- a:
  - run: sh {file} {file}
  - files: x/*.t' "line 14" "{file} exactly once"
  refused '- a:
  - run: sh {file}
  - run: sh {file}
  - files: x/*.t' "line 15" "form a has two run lines"
}

@test "#735: a dir that is absolute, has . or .. parts, or lies under .vbw/ or .git/ is refused with its line" {
  local d
  for d in /abs a/../b ./a .vbw/x .git; do
    refused "- a:
  - dir: $d
  - run: sh {file}
  - files: $d/x.t" "line 14" "the dir of form a"
  done
}

@test "#735: a files pathspec of a form with dir outside that dir is refused" {
  refused '- webapp:
  - dir: apps/webapp
  - run: sh {file}
  - files: apps/other/*.t' "line 16" "the files of form webapp must lie under its dir apps/webapp/"
  refused '- dir: apps/a
- run: sh {file}
- files: elsewhere/*.t' "line 15" "must lie under its dir apps/a/"
}

@test "#735: top-level run, files or dir lines beside a named form, and a nested line outside one, are refused with the line" {
  refused '- run: sh {file}
- a:
  - run: sh {file}
  - files: x/*.t' "line 14" "mixes"
  refused '- a:
  - run: sh {file}
  - files: x/*.t
- files: y/*.t' "line 16" "mixes"
  refused '  - run: sh {file}' "line 13" "named form"
}

@test "#735: a committed file matched by two forms is refused at check and sync, naming it and both forms" {
  mkdir -p apps/a
  printf 'true\n' > apps/a/x.t
  git add apps/a/x.t && git commit -q -m "test: x"
  refused '- one:
  - run: sh {file}
  - files: apps/a/*.t
- two:
  - run: sh {file}
  - files: apps/*/x.t' "line 16" "apps/a/x.t is matched by forms one and two"
  run "$VBW" spec sync
  [ "$status" -ne 0 ] && [[ "$output" == *"matched by forms one and two"* ]] || { echo "$output"; false; }
  jq -e 'has("test_files") | not' .vbw/record.json > /dev/null
}
