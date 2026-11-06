#!/usr/bin/env bats
# R202 (docs/proof.md, docs/record.md): every proof and fix round says where its
# time went and why units ran again. vbw prove prints, just before its verdict
# line (proved / not proved), and vbw fix done just after its
# "test files: N ran, M reused" line, two lines:
#   VBW's own work: X of Y min
#   ran again: N of M units; top reasons: <reason> (count), ...
# Own work is everything that is not a unit's command running: planning (the
# reuse plan, the scope check and the other bookkeeping before the units),
# making the clean copies, read tracking (reset before and collection after each
# unit, summed over the units that run side by side), saving the run store and
# writing the record, each measured by the clock inside the proof; Y is the
# command's wall-clock time up to the end of the record step. Minutes
# carry one decimal. M counts every unit the proof covers (checks, approved
# commands, test files), N those that really ran. The reasons are the units'
# own (never passed, <file> changed, definition changed, ...) and, for a unit
# that ran for a whole-proof cause, that cause; at most three, most frequent
# first, ties in the order the units appear in the evidence. Both lines print
# when nothing ran: "ran again: 0 of M units; top reasons: none". The split
# stays in the evidence as evidence.own {planning, copies, tracking, saving,
# record, wall} (seconds) and the causes as evidence.causes; vbw show evidence
# prints the breakdown and each unit's reason, says "not recorded" on a record
# written before this change, and the validator refuses a malformed own. Before
# the first unit runs, vbw prove prints the same count in the future tense as its
# first line, "run again: N of M units; top reasons: ...", so a long proof says
# why before anyone waits for it. L1.

load helper
load fixture-helper

# The approved shop, and the same shop after its first proof, each built once per
# file and copied for every test.
setup_file() {
  fixture_build shop shop_project
  fixture_build proved proved_shop
}
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

proved_shop() {
  shop_project
  "$VBW" prove > /dev/null
}

shop_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  printf 'other\n' > src/other.txt
  # C1 and C2 read src/a.txt, C3 and C6 read src/c.txt, C4 reads src/b.txt; C5 is added later.
  printf 'grep -q . src/a.txt\n' > tests/c1.sh
  printf 'grep -q . src/a.txt\n' > tests/c2.sh
  printf 'grep -q . src/c.txt\n' > tests/c3.sh
  printf 'grep -q . src/b.txt\n' > tests/c4.sh
  printf 'grep -q . src/c.txt\n' > tests/c5.sh
  printf 'grep -q . src/c.txt\n' > tests/c6.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R1", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C3", req:"R1", run:["sh","tests/c3.sh"], files:["tests/c3.sh"]},
      {id:"C4", req:"R1", run:["sh","tests/c4.sh"], files:["tests/c4.sh"]},
      {id:"C6", req:"R1", run:["sh","tests/c6.sh"], files:["tests/c6.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1","R2"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/a.txt","src/b.txt","src/c.txt"], after:[], status:"done"},
                {id:"P1.2", phase:"P1", title:"Look", reqs:["R2"], files:["src/other.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

OWN_RE="^VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$"

# first: the first line of $output; the opening line is the first line.
first() { printf '%s\n' "$output" | head -n 1; }

# nth K: line K of $output counted from its end (1 is the last line).
nth() { printf '%s\n' "$output" | tail -n "$1" | head -n 1; }

# after_counts: the two lines that follow the "test files: ..." count line, in L1 and L2.
after_counts() {
  local n
  n=$(printf '%s\n' "$output" | grep -n '^test files: [0-9]* ran, [0-9]* reused$' | head -n 1 | cut -d: -f1)
  [ -n "$n" ] || { echo "no test files count line in:"; echo "$output"; return 1; }
  L1=$(printf '%s\n' "$output" | sed -n "$((n + 1))p")
  L2=$(printf '%s\n' "$output" | sed -n "$((n + 2))p")
}

# mixed_change: src/a.txt and src/b.txt change, C3's definition changes, C5 is
# new, C6 is untouched; approved and committed.
mixed_change() {
  printf 'more\n' >> src/a.txt
  printf 'more\n' >> src/b.txt
  edit_record '.checks |= map(if .id == "C3" then . + {timeout: 100} else . end)
    | .checks += [{id:"C5", req:"R1", run:["sh","tests/c5.sh"], files:["tests/c5.sh"]}]
    | .checks |= sort_by(.id)'
  git add -A && git commit -q -m "feat: mixed change"
  "$VBW" approve > /dev/null
}

@test "R202: the first proof prints both lines just before its verdict, every unit ran for the one cause, and the evidence keeps the split and the cause" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nth 1)" = proved ] || { echo "$output"; false; }
  [[ "$(nth 3)" =~ $OWN_RE ]] || { echo "line 3 from the end: $(nth 3)"; echo "$output"; false; }
  [ "$(nth 2)" = "ran again: 5 of 5 units; top reasons: this clone has no earlier recorded run (5)" ] || { echo "$output"; false; }
  [ "$(first)" = "run again: 5 of 5 units; top reasons: this clone has no earlier recorded run (5)" ] || { echo "$output"; false; }
  jq -e '.evidence.own | type == "object" and (keys == ["copies","copy_slots","planning","record","saving","tracking","wall"])
    and (del(.copy_slots) | all(.[]; type == "number" and . >= 0)) and .wall >= .planning
    and (.copy_slots | .claimed == 0 and .refreshed == 0 and .made >= 1 and .refresh == 0)' .vbw/record.json || { jq .evidence.own .vbw/record.json; false; }
  jq -e '.evidence.causes == ["this clone has no earlier recorded run"]' .vbw/record.json || { jq .evidence.causes .vbw/record.json; false; }
}

@test "R202: a change that affects no unit prints zeros: ran again 0 of 5, top reasons none; the own-work line still prints" {
  fixture_copy proved
  printf 'changed\n' >> src/other.txt
  git add -A && git commit -q -m "chore: unread file"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nth 1)" = proved ] || { echo "$output"; false; }
  [[ "$(nth 3)" =~ $OWN_RE ]] || { echo "$output"; false; }
  [ "$(nth 2)" = "ran again: 0 of 5 units; top reasons: none" ] || { echo "$output"; false; }
  [ "$(first)" = "run again: 0 of 5 units; top reasons: none" ] || { echo "$output"; false; }
  jq -e '.evidence.causes == [] and (.evidence.own | type == "object")' .vbw/record.json || { jq .evidence .vbw/record.json; false; }
}

@test "R202: mixed reasons: at most three, most frequent first, ties in the units' order" {
  fixture_copy proved
  mixed_change
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nth 2)" = "ran again: 5 of 6 units; top reasons: src/a.txt changed (2), definition changed (1), src/b.txt changed (1)" ] || { echo "$output"; false; }
  [ "$(first)" = "run again: 5 of 6 units; top reasons: src/a.txt changed (2), definition changed (1), src/b.txt changed (1)" ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.why == "src/a.txt changed" and .evidence.checks.C5.why == "never passed" and .evidence.checks.C6.reused == true
    and .evidence.causes == []' .vbw/record.json || { jq .evidence.checks .vbw/record.json; false; }
}

@test "R202: vbw show evidence prints the step breakdown and each unit's reason or reuse" {
  fixture_copy proved
  mixed_change
  "$VBW" prove > /dev/null
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^  own work: [0-9]+\.[0-9]+ of [0-9]+\.[0-9]+ s: planning [0-9]+\.[0-9]+, copies [0-9]+\.[0-9]+, read tracking [0-9]+\.[0-9]+, saving [0-9]+\.[0-9]+, record [0-9]+\.[0-9]+$' \
    || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^  C1 pass .* ran: src/a.txt changed$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^  C6 pass .* reused \(proof of ' || { echo "$output"; false; }
}

@test "R202: a record written before this change still reads, and vbw show evidence says not recorded" {
  fixture_copy proved
  # A record written before own is at the floor: without own.copy_slots it is schema 4.
  edit_record 'del(.evidence.own, .evidence.causes) | .evidence.checks |= map_values(del(.why)) | .schema = 4'
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^  own work: not recorded$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -Eq '^  C1 pass .* not recorded$' || { echo "$output"; false; }
}

@test "R202: the validator refuses a malformed own split" {
  fixture_copy proved
  local bad good
  good=$(cat .vbw/record.json)
  edit_record '.evidence.own = {planning: "x"}'
  vbw_run show evidence
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *corrupt* ]] || { echo "$output"; false; }
  for bad in '.evidence.own |= del(.record)' '.evidence.own.extra = 1' '.evidence.own.wall = -1' '.evidence.own = []' \
             '.evidence.causes = "x"' '.evidence.causes = [1]'; do
    printf '%s\n' "$good" > .vbw/record.json
    edit_record "$bad"
    vbw_run show evidence
    [ "$status" -ne 0 ] || { echo "accepted: $bad"; echo "$output"; false; }
    [[ "$output" == *corrupt* ]] || { echo "$bad: $output"; false; }
  done
}

@test "R202: vbw fix done prints both lines right after its count lines" {
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  after_counts
  [[ "$L1" =~ $OWN_RE ]] || { echo "after the counts: $L1"; echo "$output"; false; }
  [ "$L2" = "ran again: 5 of 5 units; top reasons: this clone has no earlier recorded run (5)" ] || { echo "$output"; false; }
  [ "$(nth 1)" = "F1 fixed: vbw prove decides" ] || { echo "$output"; false; }
}

@test "R202: vbw fix done with nothing to judge prints zeros" {
  edit_record '.plans |= map(.status = "planned") | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  vbw_run fix done F1
  after_counts
  [[ "$L1" =~ $OWN_RE ]] || { echo "after the counts: $L1"; echo "$output"; false; }
  [ "$L2" = "ran again: 0 of 0 units; top reasons: none" ] || { echo "$output"; false; }
}

@test "R202: the own-work line says the five steps over the command's wall time, in minutes with one decimal" {
  # A unit that takes a while: the wall time is a tenth of a minute or more, the VBW's own steps stay small.
  printf 'sleep 13\ngrep -q . src/a.txt\n' > tests/c1.sh
  git add -A && git commit -q -m "test: a slow unit"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  want=$(jq -r '.evidence.own | def min: (. / 6 | round) as $t | "\($t / 10 | floor).\($t % 10)";
    "VBW'"'"'s own work: \((.planning + .copies + .tracking + .saving + .record) | min) of \(.wall | min) min"' .vbw/record.json)
  [ "$(nth 3)" = "$want" ] || { echo "wanted: $want"; echo "$output"; false; }
  [ "$(jq '.evidence.own.wall >= 13' .vbw/record.json)" = true ] || { jq .evidence.own .vbw/record.json; false; }
  [[ "$(nth 3)" != *" of 0.0 min" ]] || { echo "$output"; false; }
  [ "$(jq '.evidence.own.record > 0 and .evidence.own.planning > 0 and .evidence.own.copies > 0 and .evidence.own.saving > 0 and .evidence.own.tracking > 0' .vbw/record.json)" = true ] || { jq .evidence.own .vbw/record.json; false; }
}

@test "R202: the scope check counts as planning, and the wall time is read after the record step it covers" {
  # A scope listing that takes 3 s and a record write that takes 3 s: both land in their steps, and the
  # wall covers every step but the units' own tracking (the serial steps tile it up to the record step).
  mkdir -p "$TEST_ROOT/slowbin"
  printf '#!/bin/sh\ncase " $* " in *"trailers:key=VBW-Plan"*) sleep 3 ;; esac\nexec %s "$@"\n' "$(command -v git)" > "$TEST_ROOT/slowbin/git"
  printf '#!/bin/sh\n%s "$@" || exit $?\ncase " $* " in *" -A -01 "*|*" -1 second "*) sleep 3 ;; esac\n' "$(command -v touch)" > "$TEST_ROOT/slowbin/touch"
  chmod +x "$TEST_ROOT/slowbin/git" "$TEST_ROOT/slowbin/touch"
  PATH="$TEST_ROOT/slowbin:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.own | .planning >= 3 and .record >= 3 and .wall + 0.01 >= (.planning + .copies + .saving + .record)' .vbw/record.json \
    || { jq .evidence.own .vbw/record.json; false; }
}

@test "R202: the read tracking step counts the collection after a unit as well as the reset before it" {
  # find is what the collection runs several times and the reset never runs: a find that takes a second
  # puts at least twelve seconds into the step over the five units (four finds each), which the five resets alone (each at most one wait for the next whole second) cannot.
  mkdir -p "$TEST_ROOT/slowbin"
  printf '#!/bin/sh\nsleep 1\nexec %s "$@"\n' "$(command -v find)" > "$TEST_ROOT/slowbin/find"
  chmod +x "$TEST_ROOT/slowbin/find"
  PATH="$TEST_ROOT/slowbin:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq '.evidence.own.tracking >= 12' .vbw/record.json)" = true ] || { jq .evidence.own .vbw/record.json; false; }
}

@test "R202: vbw fix done counts the time its clean copies take as VBW's own work" {
  # One slot, so one copy: a git whose worktree add takes 4 s puts them into the own-work line (0.1 min);
  # without them the round's own steps stay under 3 s, which prints 0.0.
  "$VBW" config set check_jobs 1 > /dev/null
  mkdir -p "$TEST_ROOT/slowbin"
  real=$(command -v git)
  printf '#!/bin/sh\ncase " $* " in *" worktree add "*) sleep 4 ;; esac\nexec %s "$@"\n' "$real" > "$TEST_ROOT/slowbin/git"
  chmod +x "$TEST_ROOT/slowbin/git"
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  PATH="$TEST_ROOT/slowbin:$PATH" vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  after_counts
  [[ "$L1" =~ ^"VBW's own work: 0."[1-9]" of " ]] || { echo "after the counts: $L1"; echo "$output"; false; }
}
