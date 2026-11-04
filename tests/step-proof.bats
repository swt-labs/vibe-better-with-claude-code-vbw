#!/usr/bin/env bats
# R190, phase P146 (L1): a proof counts its finished units in the step note
# (.vbw/runtime/step.json). A proof with no run of this session open is its own
# step: kind proof, its pid, parts {done, total} over the units it runs, an end
# time from the proof history (median time per unit). Inside this session's
# build or fix it is what that step is doing now ('proving 12 of 40 checks',
# .proof {done, total}) and the end time stays the step's. A proof of another
# session never replaces this session's step. A proof killed outright is never
# shown as running, and the next proof removes its note. The Stop hook still
# waits while a background proof runs. The core count comes from stand-ins for
# getconf, nproc and sysctl first on PATH (8 cores: room for 4 lanes).

load helper
load step-helper

setup() {
  vbw_setup
  local bin="$TEST_ROOT/bin" tool
  mkdir -p "$bin"
  for tool in getconf nproc sysctl; do
    printf '#!/bin/sh\necho 8\n' > "$bin/$tool"
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  CONC="$TEST_ROOT/conc"
  SNAPS="$TEST_ROOT/snaps"
  mkdir -p "$CONC"
  export PATH CONC SNAPS
  step_project
  mkdir -p tests
  # unit.sh: one of many units; records how many units run at this moment.
  cat > tests/unit.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/peak"
sleep 0.2
rm -f "$CONC/run.$$"
SH
  # snap.sh: a copy of the note as this unit starts.
  cat > tests/snap.sh << 'SH'
jq -c . "$NOTE" >> "$SNAPS" 2> /dev/null || echo '{"missing": true}' >> "$SNAPS"
SH
  # barrier.sh: waits until the units that have started number a multiple of 4,
  # so that four units finish at the same moment (at most about 5 s).
  cat > tests/barrier.sh << 'SH'
touch "$CONC/arrive.$$"
i=0
while [ "$i" -lt 100 ]; do
  [ $(($(ls "$CONC" | grep -c '^arrive\.') % 4)) -eq 0 ] && break
  sleep 0.05
  i=$((i + 1))
done
SH
  # slow.sh: runs until the test says go (at most about 30 s).
  cat > tests/slow.sh << 'SH'
i=0
while [ ! -e "$CONC/go" ] && [ "$i" -lt 300 ]; do
  sleep 0.1
  i=$((i + 1))
done
SH
}

teardown() {
  touch "$CONC/go" "$CONC/stop" 2> /dev/null || true
  wait 2> /dev/null || true
  vbw_teardown
}

# checks N SCRIPT: N checks C1..CN, each running tests/SCRIPT.sh; every plan
# done; committed and approved.
checks() {
  step_edit ".plans[].status = \"done\" | .checks = [range(1; $1 + 1) | {id: \"C\(.)\", req: \"R1\", run: [\"sh\", \"tests/$2.sh\"], files: [\"tests/$2.sh\"]}]"
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
}

# until_note FILTER: wait for the note to hold FILTER (at most about 10 s).
until_note() {
  local _
  for _ in $(seq 1 100); do
    jq -e "$1" "$NOTE" > /dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "the note never held: $1"
  cat "$NOTE" 2> /dev/null
  return 1
}

@test "R190: with 4 lanes, 40 finished units read exactly 40 of 40, never fewer or more" {
  checks 40 unit
  "$VBW" config set check_jobs 4 > /dev/null
  # A watcher reads the note while the proof runs.
  (
    while [ ! -e "$CONC/stop" ]; do
      jq -c '{kind, parts}' "$NOTE" >> "$TEST_ROOT/seen" 2> /dev/null || true
      sleep 0.02
    done
  ) &
  local watcher=$!
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || { cat "$TEST_ROOT/prove.out"; false; }
  touch "$CONC/stop"
  wait "$watcher" || true
  # The units really ran side by side.
  [ "$(sort -n "$CONC/peak" | tail -1)" -gt 1 ] || { echo "the units never ran in parallel"; false; }
  [ -s "$TEST_ROOT/seen" ] || { echo "the watcher never saw a note"; false; }
  jq -s -e 'all(.[]; .kind == "proof" and .parts.total == 40 and .parts.done >= 0 and .parts.done <= 40)' "$TEST_ROOT/seen" \
    || { sort -u "$TEST_ROOT/seen"; false; }
  jq -s -e '[.[].parts.done] | max == 40' "$TEST_ROOT/seen" || { sort -u "$TEST_ROOT/seen"; false; }
  jq -s -e '[.[].parts.done] as $d | all(range(1; $d | length); $d[.] >= $d[. - 1])' "$TEST_ROOT/seen" || { cat "$TEST_ROOT/seen"; false; }
  jq -e '[.steps[] | select(.kind == "proof")] | last | .parts == 40' "$STEPS" || { cat "$STEPS"; false; }
  [ ! -e "$NOTE" ] || { echo "the proof's note outlived it"; cat "$NOTE"; false; }
}

@test "R190: four units that finish at the same moment all count: 40 of 40, never fewer" {
  checks 40 barrier
  "$VBW" config set check_jobs 4 > /dev/null
  (
    while [ ! -e "$CONC/stop" ]; do
      jq -c '{kind, parts}' "$NOTE" >> "$TEST_ROOT/seen" 2> /dev/null || true
      sleep 0.02
    done
  ) &
  local watcher=$!
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || { cat "$TEST_ROOT/prove.out"; false; }
  touch "$CONC/stop"
  wait "$watcher" || true
  jq -s -e 'all(.[]; .parts.total == 40 and .parts.done <= 40) and ([.[].parts.done] | max == 40)' "$TEST_ROOT/seen" || { sort -u "$TEST_ROOT/seen"; false; }
  jq -e '[.steps[] | select(.kind == "proof")] | last | .parts == 40' "$STEPS" || { cat "$STEPS"; false; }
}

@test "R190: each finished unit counts before the next one starts; a proof's end time is its median time per unit times its units" {
  checks 3 snap
  "$VBW" config set check_jobs 1 > /dev/null
  step_seed proof 30 3 3
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || { cat "$TEST_ROOT/prove.out"; false; }
  jq -s -e '[.[] | .parts.done] == [0, 1, 2] and all(.[]; .kind == "proof" and .parts.total == 3 and .run == null
    and .session == "s1" and (.pid | type == "number") and (.doing | test("proving [0-9]+ of 3 checks"))
    and ((.first_end | fromdateiso8601) - (.started_at | fromdateiso8601)) == 30)' "$SNAPS" || { cat "$SNAPS"; false; }
}

@test "R190: a proof inside this session's build is what the build is doing now; the end time stays the build's" {
  checks 3 snap
  step_edit '.plans[0].status = "planned"'
  "$VBW" config set check_jobs 1 > /dev/null
  step_seed build 300 1 3
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  cp "$NOTE" "$TEST_ROOT/before.json"
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || true
  jq -s -e --slurpfile b "$TEST_ROOT/before.json" 'length == 3 and ([.[] | .proof.done] == [0, 1, 2]) and all(.[];
    .kind == "build" and .run == $b[0].run and .end == $b[0].end and .first_end == $b[0].first_end
    and .parts == $b[0].parts and .proof.total == 3 and (.doing | test("^proving [0-9]+ of 3 checks$")))' "$SNAPS" \
    || { cat "$TEST_ROOT/before.json" "$SNAPS"; false; }
  # Once the proof ends, the build is what runs again, with the same end time.
  jq -e --slurpfile b "$TEST_ROOT/before.json" '.kind == "build" and .end == $b[0].end and .proof == null and .doing == $b[0].doing' "$NOTE" \
    || { cat "$NOTE"; false; }
}

@test "R190: a proof of another session never replaces this session's step" {
  checks 3 snap
  step_edit '.plans[0].status = "planned"'
  "$VBW" config set check_jobs 1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  cp "$NOTE" "$TEST_ROOT/before.json"
  VBW_SESSION_ID=s2 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || true
  [ -s "$SNAPS" ] || { cat "$TEST_ROOT/prove.out"; false; }
  jq -s -e --slurpfile b "$TEST_ROOT/before.json" 'all(.[]; .kind == "build" and .session == "s1" and .run == $b[0].run
    and .proof == null and .doing == $b[0].doing)' "$SNAPS" || { cat "$SNAPS"; false; }
  jq -e --slurpfile b "$TEST_ROOT/before.json" '.kind == "build" and .session == "s1" and .doing == $b[0].doing' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: a proof killed outright is never shown as running, and the next proof removes its note" {
  checks 1 slow
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 &
  until_note '.kind == "proof" and (.pid | type == "number")'
  local pid
  pid=$(jq -r '.pid' "$NOTE")
  kill -0 "$pid"
  "$VBW" status --json | jq -e '.step.kind == "proof"' > /dev/null || { "$VBW" status --json; false; }
  kill -9 "$pid"
  sleep 0.2
  ! kill -0 "$pid" 2> /dev/null || false
  [ -e "$NOTE" ]
  "$VBW" status --json | jq -e 'has("step") and .step == null' > /dev/null || { "$VBW" status --json; false; }
  touch "$CONC/go"
  VBW_SESSION_ID=s1 "$VBW" prove > /dev/null 2>&1 || true
  [ ! -e "$NOTE" ] || { cat "$NOTE"; false; }
}

@test "R190: the Stop hook still waits while a background proof runs" {
  checks 1 slow
  "$VBW" auto on s1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 &
  until_note '.kind == "proof"'
  local out
  out=$(printf '{"session_id": "s1"}' | vbw_hook Stop)
  [ -z "$out" ] || { echo "the Stop hook answered while the proof ran: $out"; false; }
  touch "$CONC/go"
}

@test "R190: vbw fix done counts each fix it closes as one part done of the fix step" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"},
    {id: "F2", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fixes"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 F2 > /dev/null
  jq -e '.kind == "fix" and .parts == {done: 0, total: 2}' "$NOTE" || { cat "$NOTE"; false; }
  VBW_SESSION_ID=s1 "$VBW" fix done F1 F2 > "$TEST_ROOT/done.out" 2>&1 || { cat "$TEST_ROOT/done.out"; false; }
  jq -e '.kind == "fix" and .parts == {done: 2, total: 2} and .proof == null' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R190: the note is rewritten under a lock: a proof waits while another writer holds it, and takes over a dead owner's" {
  checks 2 snap
  local lock="$PROJECT/.vbw/runtime/step.lock"
  mkdir -p "$lock"
  sleep 30 &
  local holder=$!
  printf '%s\n' "$holder" > "$lock/pid"
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 &
  local prove=$!
  sleep 1.5
  kill -0 "$prove" || { echo "the proof did not wait for the lock"; cat "$TEST_ROOT/prove.out"; false; }
  [ ! -e "$NOTE" ] || { echo "the note was written while another writer held the lock"; cat "$NOTE"; false; }
  [ ! -s "$SNAPS" ] || { echo "a unit ran while the lock was held"; false; }
  rm -rf "$lock"
  kill "$holder" 2> /dev/null || true
  wait "$prove" || { cat "$TEST_ROOT/prove.out"; false; }
  jq -e '[.steps[] | select(.kind == "proof")] | last | .parts == 2' "$STEPS" || { cat "$STEPS"; false; }
  # A lock whose owner is gone is taken over at once.
  sleep 0.1 &
  local gone=$!
  wait "$gone"
  mkdir -p "$lock"
  printf '%s\n' "$gone" > "$lock/pid"
  printf 'x\n' >> src/a.txt
  git add src/a.txt && git commit -q -m "feat(pay): change a"
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove2.out" 2>&1 || { cat "$TEST_ROOT/prove2.out"; false; }
  [ ! -e "$lock" ] || { echo "the dead owner's lock stayed"; false; }
}

@test "R190 (D429): a late fix moves its end to its own pace, marked later than usual, never earlier than the first end" {
  step_seed fix 300 1 3
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"},
    {id: "F2", req: "R1", attempts: 0, status: "open", note: "C1 fail"}, {id: "F3", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fixes"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 F2 F3 > /dev/null
  # R191.15: the first end is the median wall time of a whole fix round (three seeded 300 s rounds).
  [ "$(step_secs first_end)" -eq 300 ]
  step_back 1000
  VBW_SESSION_ID=s1 "$VBW" fix done F1 > /dev/null
  # Three parts at the pace of the first: three times the time so far, whatever a busy machine adds to it.
  local so_far
  so_far=$(($(date +%s) - $(jq -r '.started_at | fromdateiso8601' "$NOTE")))
  [ "$(step_secs end)" -ge 2990 ] && [ "$(step_secs end)" -le "$((so_far * 3 + 30))" ] || { cat "$NOTE"; false; }
  jq -e '.late == true and .end != .first_end' "$NOTE" || { cat "$NOTE"; false; }
  step_back 500
  VBW_SESSION_ID=s1 "$VBW" fix done F2 > /dev/null
  [ "$(step_secs end)" -ge 2240 ] && [ "$(step_secs end)" -le 2270 ] || { cat "$NOTE"; false; }
}

@test "R190 (D429): a late proof of its own moves its end at its own pace as units finish, never before the first end" {
  # lateunit.sh: the first unit back-dates the note by 1000 s; every unit copies the note as it starts.
  cat > tests/lateunit.sh << 'SH'
if [ ! -e "$CONC/back" ]; then
  touch "$CONC/back"
  jq -c 'def back: fromdateiso8601 - 1000 | todateiso8601; .started_at |= back | .first_end |= back | .end |= back' "$NOTE" > "$CONC/n.json" && cp "$CONC/n.json" "$NOTE"
fi
jq -c . "$NOTE" >> "$SNAPS"
SH
  checks 3 lateunit
  "$VBW" config set check_jobs 1 > /dev/null
  step_seed proof 30 3 3
  VBW_SESSION_ID=s1 "$VBW" prove > "$TEST_ROOT/prove.out" 2>&1 || { cat "$TEST_ROOT/prove.out"; false; }
  jq -s -e '.[0].late == false
    and (.[1].parts.done == 1 and .[1].late == true and .[1].end > .[1].first_end)
    and (.[2].parts.done == 2 and .[2].late == true and .[2].end > .[2].first_end and .[2].end != .[1].end)' "$SNAPS" || { cat "$SNAPS"; false; }
}
