#!/usr/bin/env bats
# R166 (docs/proof.md): while a check runs, vbw prove writes down every project
# file it opened and every folder it listed (its read list), from the run
# itself. A later proof reuses the check's pass only when its approved
# definition is unchanged, no file on its read list was changed, deleted or
# renamed, and no file was added to or removed from a folder it listed; in
# every other case the check runs again, and its summary line says why. A
# check whose last result failed, that never passed or that has no read list
# always runs. When the file system cannot record reads, nothing is reused.
# vbw prove --full reuses nothing and is a full proof; a proof that reused is
# not. Each check logs its name to $RANLOG when it really runs. The wiring
# cases at the end (fixture_copy wiring, from the former prove-reads.bats) pin
# how vbw prove and vbw fix done use the rule: read lists in the store, clean
# copies, the record's fingerprint (R175), and which fixes a failing check
# fails. Pinned once elsewhere: a file added to a listed folder
# (reads-listing.bats), no reads recorded and a clone with no recorded run
# (proof-causes.bats). L1.

load helper
load fixture-helper

setup_file() {
  fixture_build shop reads_project
  fixture_build wiring wiring_project
}
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# reads_project: the project most tests start from, built once per file.
reads_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer sees the price list\n- R3 [auto] A customer can refund\n- R4 [auto] A customer can log in\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src/prices tests
  printf 'app\n' > src/app.txt
  printf 'paid\n' > src/pay.txt
  printf 'unread\n' > src/other.txt
  printf '1\n' > src/prices/a.txt
  printf 'user\n' > src/login.txt
  # C1 reads src/pay.txt, which it does not declare (the case D181 missed).
  cat > tests/c1.sh << 'SH'
echo C1 >> "$RANLOG"
grep -qx paid src/pay.txt
SH
  # C2 lists a folder without opening the files in it.
  cat > tests/c2.sh << 'SH'
echo C2 >> "$RANLOG"
ls src/prices > /dev/null
SH
  # C3 fails while $TEST_ROOT/fail3 exists (outside the project).
  cat > tests/c3.sh << 'SH'
echo "C3$1" >> "$RANLOG"
[ ! -e "$TEST_ROOT/fail3" ]
SH
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  # C5 declares no files at all; it reads src/login.txt.
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R2", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C3", req:"R3", run:["sh","tests/c3.sh"], files:["tests/c3.sh"]},
      {id:"C5", req:"R4", run:["sh","-c","echo C5 >> \"$RANLOG\"; grep -qx user src/login.txt"]}]
    | .commands = {}
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2","R3","R4"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1","R2","R3","R4"], files:["src/app.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  FIRST=$(jq -r '.evidence.at' .vbw/record.json)
  : > "$RANLOG"
}

# wiring_project: the project of the wiring cases (fixture_copy wiring), where
# vbw prove and vbw fix done meet the rule: two requirements, two checks, the
# test command, and C1 noting the folder it ran in.
wiring_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n\n## Commands\n\n- test: sh tests/all.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  export RANLOG="$TEST_ROOT/ran.log"
  printf 'paid\n' > src/pay.txt
  printf 'sent\n' > src/receipt.txt
  printf 'unread\n' > src/other.txt
  # C1 notes the name of the folder it runs in (the name only: a fixture holds no path of its own).
  printf 'echo C1 >> "$RANLOG"\nbasename "$(pwd)" > "$TEST_ROOT/c1.pwd"\ngrep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'echo C2 >> "$RANLOG"\ngrep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf 'echo all >> "$RANLOG"\ngrep -qx paid src/pay.txt\n' > tests/all.sh
  git add -A && git commit -q -m "chore: files"
  printf '%s' '{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
              {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" plan "done" P1.1 > /dev/null 2>&1 || true
  "$VBW" plan "done" P1.2 > /dev/null 2>&1 || true
  git add -A && git commit -q -m "chore(vbw): plan" || true
  STORE="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"
  export STORE
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# ran: what really ran since the log was last emptied, sorted, one line.
ran() { sort "$RANLOG" | tr '\n' ' '; }

# change FILE: commit a change to one project file.
change() {
  printf 'more\n' >> "$1"
  git add "$1" && git commit -q -m "feat: change $1"
}

# line ID: the proof summary line of one check.
line() { printf '%s\n' "$output" | grep -E "^ +$1 " || true; }

# no_reads: a stand-in touch that cannot reset access times, as on a file
# system that records no reads (VBW resets access times with touch -a).
no_reads() {
  local real
  real=$(command -v touch)
  mkdir -p "$TEST_ROOT/noreads"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -*a*) exit 0 ;; esac; done\nexec %s "$@"\n' "$real" > "$TEST_ROOT/noreads/touch"
  chmod +x "$TEST_ROOT/noreads/touch"
}

@test "R166: a check whose test reads a project file it does not declare runs again when a commit changes only that file (the case D181 missed)" {
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: .*src/pay\.txt' || { echo "$output"; false; }
}

@test "R166: a commit that changes only a file no check read reuses every check, each naming the proof it came from" {
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  local id
  for id in C1 C2 C3 C5; do
    line "$id" | grep -qF "reused (proof of $FIRST)" || { echo "$id: $(line "$id")"; echo "$output"; false; }
  done
}

@test "R166: a check that declares no files is reused when nothing it read changed, and runs when a file it read changed" {
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [[ "$(ran)" != *C5* ]] || { echo "ran: $(ran)"; false; }
  : > "$RANLOG"
  change src/login.txt
  vbw_run prove
  [ "$(ran)" = "C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: deleting a file a check read runs that check again" {
  git rm -q src/pay.txt && git commit -q -m "feat: drop pay"
  vbw_run prove
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: .*src/pay\.txt' || { echo "$output"; false; }
}

@test "R166: renaming a file a check read runs that check again" {
  git mv src/pay.txt src/paid.txt && git commit -q -m "feat: rename pay"
  vbw_run prove
  [[ " $(ran)" == *" C1 "* ]] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: removing a file from a folder a check listed runs that check again, and only it" {
  git rm -q src/prices/a.txt && git commit -q -m "feat: drop a price"
  vbw_run prove
  [ "$(ran)" = "C2 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a content change to a file in a listed folder that no check opened runs nothing" {
  change src/prices/a.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a changed approved definition runs that check again" {
  edit_record '(.checks[] | select(.id == "C3")).run = ["sh","tests/c3.sh","x"]'
  git commit -q -am "chore(vbw): C3 takes an argument"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C3x " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ "$(line C1)" == *reused* ]] || { echo "$output"; false; }
  [[ "$(line C3)" != *reused* ]] || { echo "$output"; false; }
}

@test "R166: a change to a check's own test file, approved again, runs that check again" {
  printf '# edited\n' >> tests/c1.sh
  git add tests/c1.sh && git commit -q -m "test: edit c1"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
}

@test "R166: a check whose last result failed runs again though nothing it read changed, and the summary says why" {
  : > "$TEST_ROOT/fail3"
  "$VBW" prove --full > /dev/null || true
  rm -f "$TEST_ROOT/fail3"
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C3 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C3 | grep -q 'ran: last result failed' || { echo "$output"; false; }
}

@test "R166: a check that never passed runs, and the summary says why" {
  printf 'echo C4 >> "$RANLOG"\n' > tests/c4.sh
  git add tests/c4.sh && git commit -q -m "test: c4"
  edit_record '.checks += [{id:"C4", req:"R3", run:["sh","tests/c4.sh"], files:["tests/c4.sh"]}]'
  git commit -q -am "chore(vbw): C4"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C4 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C4 | grep -q 'ran: never passed' || { echo "$output"; false; }
}

@test "R166: results saved without a read list always run again, and the summary says why" {
  no_reads
  PATH="$TEST_ROOT/noreads:$PATH" "$VBW" prove --full > /dev/null
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  local id
  for id in C1 C2 C3 C5; do
    line "$id" | grep -q 'ran: no read list' || { echo "$id: $(line "$id")"; echo "$output"; false; }
  done
}

@test "R166: vbw prove --full runs every check, reuses nothing and is recorded as full; a proof that reused results is not full" {
  change src/other.txt
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 C2 C3 C5 " ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.full == true and all(.evidence.checks[]; (.reused // false) == false)' .vbw/record.json
  : > "$RANLOG"
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ]
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; false; }
  jq -e '.evidence.full == false' .vbw/record.json
}

# The wiring of vbw prove and vbw fix done to the rule (moved from prove-reads.bats).

# open_fix: open fix F1 for R2 (its files: src/receipt.txt), committed.
open_fix() {
  jq '.fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "receipt"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git commit -q -am "chore(vbw): fix F1"
}

@test "R166: a proof saves the read list of every check and project command in the store, and none in the record" {
  fixture_copy wiring
  jq -e '.runs["check:C1"].reads | index("src/pay.txt") != null' "$STORE"
  jq -e '.runs["check:C2"].reads | index("src/receipt.txt") != null' "$STORE"
  jq -e '.runs["command:test"].reads | index("src/pay.txt") != null' "$STORE"
  [ "$(jq '[.evidence.checks[], .evidence.commands[] | select(has("reads") or has("dirs") or has("git"))] | length' .vbw/record.json)" -eq 0 ]
}

@test "R166: a check runs in a clean copy of the committed code, not in the working folder" {
  fixture_copy wiring
  [ "$(basename "$(cat "$TEST_ROOT/c1.pwd")")" = tree ]
}

@test "R175: a passing proof records the fingerprint of the record without its evidence or schema, so a later record change is no 'nothing committed'" {
  fixture_copy wiring
  [ "$(jq -r '.evidence.record' .vbw/record.json)" = "$(jq -c 'del(.evidence, .schema)' .vbw/record.json | vbw_kernel 'vbw_sha256')" ]
  "$VBW" decide "Pay by card" "the owner's choice" > /dev/null
  change src/other.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  [[ "$output" != *"nothing was committed"* ]] || { echo "$output"; false; }
}

@test "R166: a change to a file a check and the test command read runs both and nobody else, each saying why" {
  fixture_copy wiring
  change src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 all " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  line C1 | grep -qE 'ran: src/pay\.txt changed' || { echo "$output"; false; }
  line test | grep -qE 'ran: src/pay\.txt changed' || { echo "$output"; false; }
  line C2 | grep -q 'reused (proof of ' || { echo "$output"; false; }
  [[ "$output" == *"checks: 1 ran, 1 reused"* ]] || { echo "$output"; false; }
}

@test "R166: a reused line keeps the time of the proof that really ran it, across proofs" {
  fixture_copy wiring
  local first
  first=$(jq -r '.evidence.at' .vbw/record.json)
  change src/other.txt
  "$VBW" prove > /dev/null
  change src/other.txt
  vbw_run prove
  line C2 | grep -qF "reused (proof of $first)" || { echo "$first"; echo "$output"; false; }
}

@test "R166: vbw fix done takes the checks of every finished requirement as candidates, reuses the unchanged ones and saves read lists" {
  fixture_copy wiring
  open_fix
  change src/pay.txt
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "C1 " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C2 unchanged since its pass \(' || { echo "$output"; false; }
  jq -e '.runs["check:C1"].tree != null' "$STORE"
}

@test "R166: vbw fix done runs its checks in clean copies" {
  fixture_copy wiring
  open_fix
  change src/pay.txt
  "$VBW" fix "done" F1 > /dev/null
  [ "$(basename "$(cat "$TEST_ROOT/c1.pwd")")" = tree ]
}

@test "R166: a failing check that no named fix's files serve fails every named fix" {
  fixture_copy wiring
  open_fix
  printf 'wrong\n' > src/pay.txt
  git commit -q -am "fix: break pay"
  vbw_run fix "done" F1
  [ "$status" -ne 0 ]
  [[ "$output" == *"F1 broke finished work"* && "$output" == *"C1 fail"* ]] || { echo "$output"; false; }
  jq -e '[.fixes[] | select(.id == "F1")][0].status == "open"' .vbw/record.json
}

@test "R166: a failing check that a named fix's files serve fails that fix and not another" {
  fixture_copy wiring
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "pay"}, {id: "F2", req: "R2", attempts: 0, status: "open", note: "receipt"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git commit -q -am "chore(vbw): fixes"
  printf 'wrong\n' > src/pay.txt
  git commit -q -am "fix: break pay"
  vbw_run fix "done" F1 F2
  [ "$status" -ne 0 ]
  jq -e '([.fixes[] | select(.id == "F1")][0].status == "open") and ([.fixes[] | select(.id == "F2")][0].status == "fixed")' .vbw/record.json || { echo "$output"; false; }
}
