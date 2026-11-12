#!/usr/bin/env bats
# R203 (P164; docs/workflows.md, docs/proof.md, docs/record.md): a rule whose
# check reads nothing any plan of its requirement builds can be recorded
#
#   vbw mutate PLAN Rn.k --none REASON
#
# The kernel judges the check's last recorded run in the clone's run store
# ($(git common dir)/vbw/runs.json, where vbw prove keeps each unit's read
# list), using it only while it is current (the approved definition unchanged;
# between the tree it ran on and the committed code no file of its read list
# changed or was deleted and no listed folder's listing changed; its pass or
# fail does not matter). With no run, or a stale one, the command runs the
# check once in a clean copy of the committed code with read tracking on,
# records that run in the store as vbw prove would, says so, and judges that
# list. It accepts (exit 0, {rule: {req, k}, none, at, head} written under
# the plan) only a run with a read list, no git flag, and no read file or
# listed folder covered by a files entry of any plan of the requirement (done
# or not): an entry matches a read file when it is the same path, a folder
# entry (dir/) containing it, or "*"; it matches a listed folder when it covers
# that folder or is a file directly inside it. Otherwise it refuses, writes
# nothing, and names what could break the rule. The contract fingerprint never
# changes. A task --none keeps its shape. L1: the kernel on a fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Lab\n\n## Requirements\n\n- R1 [auto] The lab measures\n- R2 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src/other/deep notes tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo keep\n' > src/other/keep.sh
  printf 'echo deep\n' > src/other/deep/x.sh
  printf 'measured\n' > notes/measure.txt
  # C1 reads only the committed record (through jq); C2 reads a plan file; C3 lists a
  # folder; C4 reads the project through git; C5 reads a file no plan owns; C6 fails.
  printf "jq -e '.plans | length > 0' .vbw/record.json > /dev/null\n" > tests/record.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf 'ls src/other > /dev/null\n' > tests/list.sh
  printf 'git rev-parse HEAD > /dev/null\n' > tests/gitlog.sh
  # With R295_HOLD set, C5 first marks R295_HOLD/started, then waits (up to 30 s) for R295_HOLD/go.
  printf '[ -z "${R295_HOLD:-}" ] || { : > "$R295_HOLD/started"; i=0; while [ ! -f "$R295_HOLD/go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; }\ncat notes/measure.txt > /dev/null\n' > tests/notes.sh
  printf 'exit 1\n' > tests/never.sh
  jq -nc '{phases: [{id: "P1", title: "Lab", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Measure", reqs: ["R1", "R2"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["measure", "pay"]},
            {id: "P1.2", phase: "P1", title: "Other", reqs: ["R1"], files: ["src/other/new.sh", "src/other/deep/x.sh"], after: [], role: "dev", tasks: ["other"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/record.sh"], files: ["tests/record.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/list.sh"], files: ["tests/list.sh"]},
             {id: "C4", req: "R1", run: ["sh", "tests/gitlog.sh"], files: ["tests/gitlog.sh"]},
             {id: "C5", req: "R1", run: ["sh", "tests/notes.sh"], files: ["tests/notes.sh"]},
             {id: "C6", req: "R1", run: ["sh", "tests/never.sh"], files: ["tests/never.sh"]}],
    rules: [{req: "R1", text: "the measurement is a decision in the record", check: "C1"},
            {req: "R1", text: "the other folder is listed", check: "C3"},
            {req: "R1", text: "the commit is named", check: "C4"},
            {req: "R1", text: "the notes are read", check: "C5"},
            {req: "R1", text: "the never test", check: "C6"},
            {req: "R2", text: "paying prints paid", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(lab): start"
  "$VBW" approve > /dev/null
  STORE="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

record_sum() { cksum < .vbw/record.json; }
breaks() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]]' .vbw/record.json; }
# edit_record JQ: a hand edit of the record (the glance is dropped so readers take the record).
edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
# refused SUM: the last run failed and the record is byte-identical to SUM.
refused() {
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  [[ "$output" != *"unknown command"* ]] || { echo "no such command: $output"; return 1; }
  [ "$(record_sum)" = "$1" ] || { echo "the record changed: $output"; breaks P1.1; return 1; }
}
# says WORD...: the last run's output holds every WORD.
says() {
  local w
  for w in "$@"; do [[ "$output" == *"$w"* ]] || { echo "the output lacks '$w':"; echo "$output"; return 1; }; done
}
# run_of CHECK: the store's run of CHECK, compact JSON (null when none).
run_of() { jq -c --arg k "check:$1" '.runs[$k] // null' "$STORE" 2> /dev/null || echo null; }
# no_reads: a touch on PATH that silently skips every access-time change, so the
# file system records no reads (the start-of-run probe fails).
no_reads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

@test "R203: a rule whose check read no file of its requirement's plans is accepted: entry {rule, none, at, head} written, one line with the check and its counts, then the reason" {
  local hash
  hash=$(vbw_contract_hash)
  run "$VBW" mutate P1.1 R1.1 --none "the figures are a decision in the record, which only vbw writes" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq 'C1 read [0-9]+ files? and [0-9]+ folders?' || { echo "$output"; false; }
  says none "P1.1" "P1.2" "the figures are a decision in the record, which only vbw writes"
  # The limit, in the accepting line itself: a check that only tests a path is not seen.
  says "a check that only tests whether a plan file exists is not detected"
  breaks P1.1 | jq -e 'length == 1 and (.[0] | (keys | sort) == ["at", "head", "none", "rule"]
    and .rule == {req: "R1", k: 1}
    and .none == "the figures are a decision in the record, which only vbw writes"
    and (.head | test("^[0-9a-f]{40}$")) and .head == "'"$(git rev-parse HEAD)"'")' || { breaks P1.1; false; }
  # The store's run was judged: it names the record and no plan file.
  run_of C1 | jq -e '.reads | index(".vbw/record.json") != null and index("src/pay.sh") == null' || { run_of C1; false; }
  # The write never touches the contract.
  [ "$(vbw_contract_hash)" = "$hash" ] || { echo "the contract fingerprint changed"; false; }
  "$VBW" show contract < /dev/null | head -1 | grep -qv "NOT APPROVED" || { "$VBW" show contract | head -1; false; }
}

@test "R203: a check that reads a plan file is refused, nothing written: each file with the plan covering it, then 'break the rule in that code instead'" {
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R2.1 --none "nothing to break" < /dev/null
  refused "$sum"
  says "a rule" "C2 reads src/pay.sh (P1.1)" "break the rule in that code instead"
  # The run was still made and kept for the next judgement.
  run_of C2 | jq -e '.status == "pass" and (.reads | index("src/pay.sh") != null)' || { run_of C2; false; }
}

@test "R203: a check that reads a plan file inside a submodule is refused the same way, naming the file by its project path" {
  git init -q "$TEST_ROOT/subsrc"
  printf 'measured\n' > "$TEST_ROOT/subsrc/measure.txt"
  git -C "$TEST_ROOT/subsrc" add measure.txt
  git -C "$TEST_ROOT/subsrc" commit -q -m "chore: seed"
  git -c protocol.file.allow=always submodule add -q "file://$TEST_ROOT/subsrc" sub
  printf 'cat sub/measure.txt > /dev/null\n' > tests/notes.sh
  edit_record '(.plans[] | select(.id == "P1.2")).files += ["sub/measure.txt"]'
  git add -A && git commit -q -m "chore: sub"
  "$VBW" approve > /dev/null
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.4 --none "nothing to break" < /dev/null
  refused "$sum"
  says "C5 reads sub/measure.txt (P1.2)" "break the rule in that code instead"
}

@test "R203: a plan whose files are * covers every file, and is named so" {
  local sum
  edit_record '(.plans[] | select(.id == "P1.2")).files = ["*"]'
  "$VBW" approve > /dev/null
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.1 --none "only the record" < /dev/null
  refused "$sum"
  says "P1.2 covers every file" "break the rule in that code instead"
}

@test "R203: a folder entry (dir/) covers a read file inside it" {
  local sum
  edit_record '(.plans[] | select(.id == "P1.1")).files = ["src/"]'
  "$VBW" approve > /dev/null
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R2.1 --none "nothing to break" < /dev/null
  refused "$sum"
  says "C2 reads src/pay.sh (P1.1)" "break the rule in that code instead"
}

@test "R203: a listed folder is covered by a plan file directly inside it or by a folder entry covering it, not by a file deeper down" {
  local sum
  sum=$(record_sum)
  # P1.2 lists src/other/new.sh: a file directly inside the listed folder src/other.
  run "$VBW" mutate P1.1 R1.2 --none "lists a folder" < /dev/null
  refused "$sum"
  says "src/other (P1.2)" "break the rule in that code instead"
  run_of C3 | jq -e '[.dirs[] | .path] | index("src/other") != null' || { run_of C3; false; }
  # A folder entry covering the listed folder.
  edit_record '(.plans[] | select(.id == "P1.2")).files = ["src/other/"]'
  "$VBW" approve > /dev/null
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.2 --none "lists a folder" < /dev/null
  refused "$sum"
  says "src/other (P1.2)"
  # Only a file deeper down: the listing of src/other cannot change from it.
  edit_record '(.plans[] | select(.id == "P1.2")).files = ["src/other/deep/x.sh"]'
  "$VBW" approve > /dev/null
  run "$VBW" mutate P1.1 R1.2 --none "lists a folder no plan adds to" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 1 and .[0].rule == {req: "R1", k: 2} and .[0].none == "lists a folder no plan adds to"' || { breaks P1.1; false; }
}

# R264 (T246; docs/proof.md R203 section, docs/workflows.md): a rule whose check reads the
# project through git has no read list to vouch for it, so --none REASON is accepted on the
# reason alone: the entry gains git: true, the command prints one line of result (after
# R295's line naming the check it runs, when no current run is recorded), and the excuse is
# listed at the next gate (vbw show contract, --changes, vbw ship) until the next approval.
@test "R264: --none REASON on a check whose recorded run reads the project through git is accepted: entry {rule, none, git, at, head} written, one line printed naming the check, git and the reason" {
  run "$VBW" mutate P1.1 R1.3 --none "only git" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -v '^running C4 to record which files it reads' | grep -c .)" -eq 1 ] || { echo "$output"; false; }
  says "R1.3" "C4" "through git" "only git"
  breaks P1.1 | jq -e 'length == 1 and (.[0] | (keys | sort) == ["at", "git", "head", "none", "rule"] and .git == true and .rule == {req: "R1", k: 3} and .none == "only git" and (.head | test("^[0-9a-f]{40}$")))' || { breaks P1.1; false; }
  run_of C4 | jq -e '.git == true' || { run_of C4; false; }
  vbw_run show plan P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R264: an empty or missing reason is refused saying a reason is needed and why (no read list can vouch for the check); nothing runs, nothing is recorded" {
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.3 --none "" < /dev/null
  refused "$sum"
  says "--none needs a reason" "no read list"
  run "$VBW" mutate P1.1 R1.3 --none < /dev/null
  refused "$sum"
  says "--none needs a reason"
  [ "$(run_of C4)" = null ] || { echo "the check ran: $(run_of C4)"; false; }
}

@test "R264: vbw show plan and vbw show req print the excuse as 'no break possible: CHECK reads the project through git (REASON)', and vbw plan done counts it" {
  # What plan done asks, at the function that decides it: the fixture's C6 always fails and
  # plan done runs the checks first, and it asks breaks only of a building plan in a build run, and a requirement's rules of the plan that completes it.
  owed() { jq '.lease = {kind: "build"} | (.plans[] | select(.id == "P1.1")).status = "building" | (.plans[] | select(.id == "P1.2")).status = "done"' .vbw/record.json \
    | vbw_kernel '. "$VBW_LIB/cmd-plan.sh"; plan_missing_breaks P1.1'; }
  [[ "$(owed)" == *"R1.3"* ]] || { owed; false; }
  "$VBW" mutate P1.1 R1.3 --none "only git" < /dev/null > /dev/null
  vbw_run show plan P1.1
  printf '%s\n' "$output" | grep -qE '^  R1\.3: no break possible: C4 reads the project through git \(only git\)$' || { echo "$output"; false; }
  vbw_run show req R1
  [[ "$output" == *"no break possible: C4 reads the project through git (only git)"* ]] || { echo "$output"; false; }
  [[ "$(owed)" != *"R1.3"* ]] || { echo "plan done still asks for R1.3"; owed; false; }
}

@test "R264: vbw show contract and vbw show contract --changes list every git-read excuse since the last approval, one line each (plan, rule, check, reason), the block vbw ship shares; none listed after the next approval" {
  vbw_run show contract
  [[ "$output" != *"git-read excuses"* ]] || { echo "$output"; false; }
  "$VBW" mutate P1.1 R1.3 --none "only git" < /dev/null > /dev/null
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^git-read excuses since the last approval:$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^  P1\.1: R1\.3 C4 \(only git\)$' || { echo "$output"; false; }
  vbw_run show contract
  printf '%s\n' "$output" | grep -qE '^  P1\.1: R1\.3 C4 \(only git\)$' || { echo "$output"; false; }
  grep -q 'contract_amendments_block' "$PLUGIN_ROOT/lib/cmd-ship.sh" || { echo "vbw ship does not print the shared block"; false; }
  grep -q 'git-read excuses' "$PLUGIN_ROOT/lib/contract.sh" || { echo "the excuses are not part of the shared block in contract.sh"; false; }
  "$VBW" approve > /dev/null
  vbw_run show contract
  [[ "$output" != *"git-read excuses"* ]] || { echo "listed after the approval: $output"; false; }
}

@test "R264: the validator accepts git: true only on a rule --none entry, and refuses it on a task entry, a recorded break, or as any other value" {
  local good bad
  "$VBW" mutate P1.1 R1.3 --none "only git" < /dev/null > /dev/null
  "$VBW" mutate P1.1 task1 --none "only renames a variable" < /dev/null > /dev/null
  good=$(cat .vbw/record.json)
  for bad in '.[0].git = false' '.[0].git = "yes"' '.[1].git = true'; do
    printf '%s\n' "$good" > .vbw/record.json
    edit_record "(.plans[] | select(.id == \"P1.1\")).mutations |= ($bad)"
    vbw_run show plan P1.1
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; echo "$output"; false; }
    [[ "$output" == *corrupt* ]] || { echo "$bad: $output"; false; }
  done
}

@test "R203: a run with no read list is refused, saying the file system recorded none" {
  local sum
  sum=$(record_sum)
  no_reads
  PATH="$TEST_ROOT/noreads:$PATH" run "$VBW" mutate P1.1 R1.1 --none "only the record" < /dev/null
  refused "$sum"
  says "recorded none"
  run_of C1 | jq -e '. != null and .reads == null' || { run_of C1; false; }
}

@test "R203: with no run in the store the command runs the check once, says so, and the store gains the run as vbw prove would record it; a current run is judged again without running, whatever its pass or fail" {
  local before
  [ "$(run_of C1)" = null ]
  run "$VBW" mutate P1.1 R1.1 --none "only the record" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  says "ran C1 once"
  run_of C1 | jq -e '.status == "pass" and (.reads | type == "array") and (.dirs | type == "array") and .git == false
    and (.tree | test("^[0-9a-f]{40}$")) and (.at | test("^[0-9]{4}-")) and (.fp | length > 0) and (.seconds | type == "number")' || { run_of C1; false; }
  before=$(run_of C1)
  run "$VBW" mutate P1.1 R1.1 --none "only the record, again" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"ran C1 once"* ]] || { echo "ran again although the run was current: $output"; false; }
  [ "$(run_of C1)" = "$before" ] || { echo "the store's run changed: $(run_of C1)"; false; }
  # A failed run that is current is judged, not made again.
  run "$VBW" mutate P1.1 R1.5 --none "a test that cannot pass yet" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  says "ran C6 once"
  run_of C6 | jq -e '.status == "fail"' || { run_of C6; false; }
  before=$(run_of C6)
  run "$VBW" mutate P1.1 R1.5 --none "a test that cannot pass yet, again" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"ran C6 once"* ]] || { echo "ran again although the run was current: $output"; false; }
  [ "$(run_of C6)" = "$before" ]
  breaks P1.1 | jq -e 'length == 4' || { breaks P1.1; false; }
}

@test "R203: a stale run (a file on its read list changed since its tree) is not judged: the command runs the check again and judges the new list" {
  local tree
  run "$VBW" mutate P1.1 R1.4 --none "reads the notes only" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  says "ran C5 once"
  run_of C5 | jq -e '.reads | index("notes/measure.txt") != null' || { run_of C5; false; }
  tree=$(run_of C5 | jq -r .tree)
  printf 'measured twice\n' > notes/measure.txt
  git commit -q -am "docs(notes): measured twice"
  run "$VBW" mutate P1.1 R1.4 --none "reads the notes only" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  says "ran C5 once"
  [ "$(run_of C5 | jq -r .tree)" != "$tree" ] || { echo "the store still holds the old run: $(run_of C5)"; false; }
  breaks P1.1 | jq -e 'length == 2 and .[1].head == "'"$(git rev-parse HEAD)"'"' || { breaks P1.1; false; }
}

@test "R203: an empty reason, extra words, --check with a rule, an unknown plan, a rule the requirement lacks, or a plan not serving it are refused, nothing written and no run made" {
  local sum
  sum=$(record_sum)
  run "$VBW" mutate P1.1 R1.1 --none "" < /dev/null
  refused "$sum"
  says "needs a reason"
  run "$VBW" mutate P1.1 R1.1 --none "only the record" extra < /dev/null
  refused "$sum"
  run "$VBW" mutate P1.1 R1.1 --check C1 --none "only the record" < /dev/null
  refused "$sum"
  run "$VBW" mutate P9.9 R1.1 --none "only the record" < /dev/null
  refused "$sum"
  says "unknown plan P9.9"
  run "$VBW" mutate P1.1 R1.9 --none "only the record" < /dev/null
  refused "$sum"
  says "no rule 9"
  run "$VBW" mutate P1.2 R2.1 --none "only the record" < /dev/null
  refused "$sum"
  says "does not serve R2"
  [ "$(run_of C1)" = null ] && [ "$(run_of C2)" = null ] || { echo "a run was made: $(cat "$STORE")"; false; }
}

@test "R203: the validator accepts the rule entry and refuses one carrying checks, result, files or what, or lacking head or the rule's req and text; a task --none keeps its shape" {
  local good bad
  "$VBW" mutate P1.1 R1.1 --none "only the record" < /dev/null > /dev/null
  "$VBW" mutate P1.1 task1 --none "only renames a variable" < /dev/null > /dev/null
  breaks P1.1 | jq -e 'length == 2 and (.[1] | (keys | sort) == ["at", "none", "task"] and .task == 1)' || { breaks P1.1; false; }
  vbw_run show plan P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  good=$(cat .vbw/record.json)
  for bad in '.checks = {C1: "red"}' '.result = "red"' '.files = ["src/pay.sh"]' '.what = "x"' 'del(.head)' '.head = "abc"' 'del(.rule.k)' '.rule = "R1.1"'; do
    printf '%s\n' "$good" > .vbw/record.json
    edit_record "(.plans[] | select(.id == \"P1.1\")).mutations[0] |= ($bad)"
    vbw_run show plan P1.1
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; echo "$output"; false; }
    [[ "$output" == *corrupt* ]] || { echo "$bad: $output"; false; }
  done
}

@test "R203: the command's code is bash 3.2 code that passes JSON only through jq" {
  local f="$PLUGIN_ROOT/lib/cmd-mutate.sh"
  /bin/bash -n "$f"
  ! grep -nE '^[^#]*(\b(mapfile|readarray|eval)\b|(declare|local|typeset) -[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|,|\^)\})' "$f" || false
  ! grep -nE '^[^#]*\b(grep|sed|awk|cut)\b[^|;]*(record\.json|runs\.json|\.json\b)' "$f" || false
}

# R295 (field report 2026-11-11): --none never runs a check silently. With no current run of
# the rule's check recorded, it says, before the check's command starts, which check it runs
# and why: to record which files it reads, so later proofs know which changes can reach it.
# With a current run it runs nothing and says no such line. C5 holds (R295_HOLD) while it runs.

# hold_wait FILE: wait (up to 30 s) until FILE exists.
hold_wait() {
  local i
  for ((i = 0; i < 300; i++)); do [ -f "$1" ] && return 0; sleep 0.1; done
  echo "never appeared: $1"
  return 1
}

@test "R295: with no current run, --none names the check it runs and why before the check's command starts, and still says it ran it" {
  export R295_HOLD="$TEST_ROOT/hold"
  mkdir -p "$R295_HOLD"
  "$VBW" mutate P1.1 R1.4 --none "reads the notes only" > "$TEST_ROOT/none.out" 2>&1 < /dev/null 3>&- &
  local pid=$! code=0 said
  hold_wait "$R295_HOLD/started" || { touch "$R295_HOLD/go"; wait "$pid" || true; cat "$TEST_ROOT/none.out"; false; }
  # The check's command is running now: the line is already out.
  said=$(grep -F C5 "$TEST_ROOT/none.out" | grep -iF 'files it reads' || true)
  touch "$R295_HOLD/go"
  wait "$pid" || code=$?
  [ -n "$said" ] || { echo "no line named C5 and why before it ran:"; cat "$TEST_ROOT/none.out"; false; }
  [ "$code" -eq 0 ] || { cat "$TEST_ROOT/none.out"; false; }
  grep -qF 'C5' "$TEST_ROOT/none.out" && grep -qiE 'ran C5|C5 ran' "$TEST_ROOT/none.out" || { cat "$TEST_ROOT/none.out"; false; }
}

@test "R295: with a current run of the check recorded, --none runs no check and says no such line" {
  export R295_HOLD="$TEST_ROOT/hold"
  mkdir -p "$R295_HOLD"
  touch "$R295_HOLD/go"
  run "$VBW" mutate P1.1 R1.4 --none "reads the notes only" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$R295_HOLD/started" ] || { echo "the first --none ran no check"; false; }
  rm -f "$R295_HOLD/started"
  run "$VBW" mutate P1.1 R1.4 --none "reads the notes only, again" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -f "$R295_HOLD/started" ] || { echo "the check ran although its run was current: $output"; false; }
  [[ "$output" != *"files it reads"* ]] || { echo "$output"; false; }
}
