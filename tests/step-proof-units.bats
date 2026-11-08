#!/usr/bin/env bats
# R191, phase P149 (L1): a proof (vbw prove, and the proof inside vbw fix done)
# records every unit it ran (a check, a test file, a project command) with that
# unit's own seconds, as units [{name, seconds}] beside its parts in the step
# history. A proof's expected time is the sum of its units' costs times the
# learned ratio, rounded. A unit's cost is the fastest it ran in the latest 10
# proofs that recorded units or in its last recorded run (runs.json, the
# per-check store in the clone's git folder): a busy day's slow run never sets
# the promise, and a proof that runs late moves its end as it goes. The ratio is
# those proofs' total wall time over their total unit time, so one proof of two
# units cannot skew it: parallel lanes and this machine's load are learned, not
# assumed. A unit never run before counts as the median of the known ones.
# Without that basis the proofs that recorded only parts still give today's
# time per unit; with fewer than 3 finished proofs there is no time. The
# proof's sentence ends with the reason most of its units run again, so a long
# proof says why before anyone waits for it (R202): "; top reason: <reason> (N units)".

load helper
load step-helper
load road-helper
load fixture-helper

built_project() {
  vbw_setup
  step_project
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["true"]}, {id: "C2", req: "R1", run: ["true"]},
    {id: "C3", req: "R1", run: ["true"]}, {id: "C4", req: "R1", run: ["true"]}]'
  git add -A && git commit -q -m "chore(vbw): checks"
  "$VBW" approve > /dev/null
}
setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

last() { jq -c --arg k "$1" '[.steps[] | select(.kind == $k)] | last' "$STEPS"; }
step_of() { "$VBW" next --json | jq -c '.step'; }

@test "R191: a proof records every unit it ran with its own seconds" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last proof | jq -e '.parts == 4 and (.units | length == 4)
    and ([.units[].name] | sort == ["check:C1", "check:C2", "check:C3", "check:C4"])
    and all(.units[]; .seconds | type == "number" and . >= 0)' || { cat "$STEPS"; false; }
}

@test "R191: the proof inside vbw fix done records its units too" {
  step_edit '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last proof | jq -e '.parts == 4 and (.units | length == 4) and ([.units[].name] | sort == ["check:C1", "check:C2", "check:C3", "check:C4"])' || { cat "$STEPS"; false; }
}

@test "R191: each unit records its own seconds, not a shared or zero value" {
  step_edit '.checks = [{id: "C1", req: "R1", run: ["sleep", "2"]}, {id: "C2", req: "R1", run: ["true"]}]'
  git add -A && git commit -q -m "chore(vbw): a slow check"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  last proof | jq -e '([.units[] | select(.name == "check:C1")][0].seconds) as $slow
    | ([.units[] | select(.name == "check:C2")][0].seconds) as $fast
    | $slow >= 2 and $fast < $slow and .seconds >= $slow' || { cat "$STEPS"; false; }
}

@test "R191: a proof's expected time is its units' costs times the learned ratio, rounded" {
  # The store's last runs: 10, 20, 30, 40 s; three proofs timed C1 at 40 and C2 at 60 for 150 s of wall:
  # the ratio is 450 / 300 = 1.5, the costs stay the fastest (10, 20, 30, 40): 100 s times 1.5.
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 150 5
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.kind == "proof" and .parts == 4 and .seconds == 150 and (.say | startswith("Proving 4 checks: about 3 min"))' || { echo "$s"; false; }
}

@test "R202: a proof's sentence ends with the reason most of its units run again, and the answer carries it" {
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 150 3
  local s
  s=$(step_of)
  printf '%s' "$s" | jq -e '.why.count == 4 and (.why.reason | type == "string" and length > 0)
    and (.why.reason as $r | .say | endswith("; top reason: \($r) (4 units)"))' || { echo "$s"; false; }
  # Cached or not, the same answer. The sentence's clock time is the moment's own ("until around
  # 12:58"): two calls a second apart can straddle a minute, so it is left out of the comparison.
  local same='[(.say | sub("until around [0-9]{2}:[0-9]{2}"; "until around HH:MM")), .why]'
  [ "$(step_of | jq -c "$same")" = "$(printf '%s' "$s" | jq -c "$same")" ] || { step_of; false; }
}

@test "T173: a proof that stayed open for hours is left out of the learned ratio: 8 times the median of its kind and size" {
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 150 3
  # One proof left open overnight (11 h for the same two units): pooled in, the ratio would be 101.
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 40000 1
  step_of | jq -e '.kind == "proof" and .seconds == 150' || { step_of; false; }
}

@test "R191: a unit's cost is the fastest it ran in the latest 10 proofs or in its last recorded run, never a slower one" {
  # C1's last run took 100 s on a busy machine, its proofs 10 s; C2 ran 20 s last, 50 s in its proofs:
  # costs 10 + 20 + 30 + 40 = 100 s, ratio 180 / 180 = 1. Summing the last runs would promise 190 s.
  runs_seed '{"check:C1": 100, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  hist_proof '[{"name": "check:C1", "seconds": 10}, {"name": "check:C2", "seconds": 50}]' 60 3
  step_of | jq -e '.kind == "proof" and .seconds == 100' || { step_of; false; }
}

@test "R191: a proof of its own sizes its note by its units' costs, the learned ratio and the median for an unknown unit" {
  # C1..C3 are known (10, 20, 30 s), C4 never ran: it counts as 20, so 80 s times the ratio 1.5.
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30}'
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 150 3
  SNAP="$TEST_ROOT/snap"
  export SNAP
  step_edit '.checks[0].run = ["sh", "-c", "cp \"$NOTE\" \"$SNAP\""]'
  git add -A && git commit -q -m "chore(vbw): a check that reads the note"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.kind == "proof" and .run == null and ((.first_end | fromdateiso8601) - (.started_at | fromdateiso8601)) == 120' "$SNAP" || { cat "$SNAP"; false; }
}

@test "R191 (D429): the proof inside vbw fix done leaves the fix step's parts to the fixes closed" {
  step_edit '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}, {id: "F2", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fixes"
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start fix F1 F2 > /dev/null
  jq -e '.kind == "fix" and .parts == {done: 0, total: 2}' "$NOTE" || { cat "$NOTE"; false; }
  VBW_SESSION_ID=s1 "$VBW" fix done F1 > /dev/null
  jq -e '.kind == "fix" and .parts == {done: 1, total: 2} and .proof == null and (.doing | startswith("fixing"))' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R191: the ratio is the latest 10 proofs' total wall time over their total unit time, so a small proof cannot skew it" {
  # Three proofs of one 100 s unit took 100, 200 and 500 s: 800 / 300. Costs 10 + 20 + 30 + 40 = 100 s: 267 s
  # (the median ratio, 2, would say 200). Then a proof of one 1 s unit took 50 s (a ratio of 50 on its own):
  # the ratio moves to 850 / 301, and C1's cost to its fastest, 1 s: 91 s times 2.824 = 257 s.
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  hist_proof '[{"name": "check:C1", "seconds": 100}]' 100 1
  hist_proof '[{"name": "check:C1", "seconds": 100}]' 200 1
  hist_proof '[{"name": "check:C1", "seconds": 100}]' 500 1
  step_of | jq -e '.kind == "proof" and .seconds == 267' || { step_of; false; }
  hist_proof '[{"name": "check:C1", "seconds": 1}]' 50 1
  step_of | jq -e '.kind == "proof" and .seconds == 257' || { step_of; false; }
}

@test "R191: a unit never run before counts as the median of this proof's known units" {
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30}'
  hist_proof '[{"name": "check:C1", "seconds": 40}, {"name": "check:C2", "seconds": 60}]' 150 3
  step_of | jq -e '.kind == "proof" and .parts == 4 and .seconds == 120' || { step_of; false; }
}

@test "R191: without proofs that recorded units, proofs with only parts give today's time per unit; with no proof in all there is none" {
  step_seed proof 30 3 3
  step_of | jq -e '.kind == "proof" and .parts == 4 and .seconds == 40' || { step_of; false; }
  jq 'del(.steps[] | select(.kind == "proof"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  runs_seed '{"check:C1": 10, "check:C2": 20, "check:C3": 30, "check:C4": 40}'
  step_of | jq -e '.kind == "proof" and .seconds == null and .end == null
    and .say == "Proving 4 checks: no end time yet (VBW has timed fewer than 3 steps like this here); top reason: no read list (4 units)"' || { step_of; false; }
}
