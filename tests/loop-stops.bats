#!/usr/bin/env bats
# R179 (P128; docs/loop.md, Where the loop stops): with the default ceiling the
# loop compares its spend with the ceiling before each step and stops before
# that step at or above it, or when the spend cannot be told; a workflow or
# proof already running is never killed (the loop stops once its result is
# recorded). --finish-item: once reached, the current item runs on to its ship
# and then the loop stops. --no-ceiling: no comparison. End of list: the loop
# stops after the last item's ship. vbw loop stop from any session stops the
# loop before its next step with the reason and the session. Anything the loop
# cannot do without the user (an action the loop does not know) stops it with
# the reason, the item and the step, recorded in the loop state. L1.

load helper
load loop-helper
load fixture-helper

setup_file() { fixture_build loop loop_project; }
setup() { fixture_copy loop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

step() { loop_next s1 > "$TEST_ROOT/step.json"; jq -r .action "$TEST_ROOT/step.json"; }
reason() { jq -r .reason "$TEST_ROOT/step.json"; }
untouched() { jq -e '.milestone.title == "Next" and ([.requirements[] | select(.milestone == "M2")] | length) == 0' .vbw/record.json; }

@test "R179: default ceiling: at or above it the loop stops before the next step with that reason; under it the step runs" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 > /dev/null
  figures s1 7 3000 300
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"ceiling"* ]] && [[ "$(reason)" == *'$5'* ]] || { reason; false; }
  untouched
  jq -e '.loop.ended.reason | test("ceiling")' .vbw/record.json
  jq -e '.loop.items | all(.[]; .status == "waiting")' .vbw/record.json
  [ "$(step)" = stopped ]
  run "$VBW" loop status
  [[ "$output" == *"ended"* ]] && [[ "$output" == *"ceiling"* ]] || { echo "$output"; false; }
}

@test "R179: under the ceiling the loop goes on" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 > /dev/null
  figures s1 6.9 3000 300
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.milestone.title == "Visitors can read a greeting"' .vbw/record.json
}

@test "R179: when the spend cannot be told the loop stops before the step" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  no_figures
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"cannot tell"* ]] || { reason; false; }
  untouched
}

@test "R179: --finish-item: once reached, the item runs on to its ship and then the loop stops" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --ceiling 5 --finish-item > /dev/null
  [ "$(step)" = plan ]
  figures s1 7 3000 300
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_build P2
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"ceiling"* ]] || { reason; false; }
  jq -e '.milestone.id == "M2" and .milestone.status == "shipped"' .vbw/record.json
  jq -e '.loop.items[0].status == "shipped" and .loop.items[1].status == "waiting"' .vbw/record.json
  jq -e '.todos[] | select(.id == "T2") | .status == "open"' .vbw/record.json
}

@test "R179: --no-ceiling: no comparison, even with no figure at all" {
  no_figures
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ] || { cat "$TEST_ROOT/step.json"; false; }
}

@test "R179: a stop asked from any session stops the loop before its next step, naming the user and the session" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" loop stop > /dev/null
  [ "$(step)" = stopped ]
  [[ "$(reason)" == *"stopped by the user"* ]] && [[ "$(reason)" == *"s9"* ]] || { reason; false; }
  untouched
  jq -e '.loop.ended.reason | test("s9")' .vbw/record.json
}

@test "R179: a workflow already running is never killed: the loop stops once the run has ended" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ]
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  figures s1 9 3000 300
  [ "$(step)" = run ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.lease != null and .loop.ended == null' .vbw/record.json
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  [ "$(step)" = stopped ]
  [[ "$(reason)" == *"ceiling"* ]] || { reason; false; }
}

@test "R179 (F207): a contract not ready yet is handed back to the session once, with the instruction; the same unsatisfied contract again ends the loop" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  rm -f tests/greet.sh
  [ "$(next_action)" = contract ]
  [ "$(step)" = contract ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.instruction | test("check file missing: tests/greet.sh")' "$TEST_ROOT/step.json"
  jq -e '.loop.item.id == "T1" and .loop.spend != null' "$TEST_ROOT/step.json" || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.loop.asked.item == "T1" and (.loop.asked.instruction | test("check file missing")) and .loop.ended == null' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  [ "$(git log -1 --format=%s)" = "chore(vbw): loop T1 contract" ]
  [ -z "$(git status --porcelain -- .vbw)" ]
  # Nothing changed: the same instruction again ends the loop, saying it asked once already.
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"contract needs you"* && "$(reason)" == *"T1"* && "$(reason)" == *"asked once already"* ]] || { reason; false; }
  jq -e '.loop.ended.reason | test("asked once already") and test("check file missing: tests/greet.sh")' .vbw/record.json
  jq -e '.loop.items[0].status == "in_progress"' .vbw/record.json
}

@test "R179 (F207): the check file written after the hand-back lets the next step approve by delegation and go on" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  rm -f tests/greet.sh
  [ "$(step)" = contract ] || { cat "$TEST_ROOT/step.json"; false; }
  printf 'grep -qx hello src/greet.txt\n' > tests/greet.sh
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '(.loop | has("asked") | not) and .loop.ended == null and .loop.items[0].status == "in_progress"' .vbw/record.json || { jq .loop .vbw/record.json; false; }
  jq -e '.decisions[-1].text | test("approved by the loop")' .vbw/record.json
  [ -z "$(git status --porcelain -- .vbw)" ]
}

@test "R179: a run open in another session stops the loop with the reason" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
  VBW_SESSION_ID=s9 "$VBW" run start qa > /dev/null
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  [[ "$(reason)" == *"s9"* ]] || { reason; false; }
}

@test "R179 (F179): a kernel step the loop runs itself that refuses (a ship with the plan's file uncommitted) ends the loop with the reason, the item and the step, and the report" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 T2 --no-ceiling > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" "$(jq -r .next_phase "$TEST_ROOT/step.json" | sed 's/^/P/')"
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.decisions[-1].text | test("approved by the loop")' .vbw/record.json
  jq -e '.detail.plans == ["P2.1"] and .loop.item.id == "T1"' "$TEST_ROOT/step.json"
  # A run the loop's session opens carries the same lease as any run and ends through vbw run end.
  VBW_SESSION_ID=s1 "$VBW" run start build P2.1 > /dev/null
  jq -e '.lease | .kind == "build" and .session == "s1" and .files == ["src/greet.txt"] and (.run | startswith("build-")) and (.started_at | type == "string")' .vbw/record.json
  [ "$(step)" = run ]
  printf 'hello\n' > src/greet.txt
  "$VBW" commit P2.1 "feat(greet): hello" > /dev/null
  "$VBW" plan done P2.1 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  jq -e '.lease == null and (.costs.runs | length) == 1 and .costs.runs[0].kind == "build"' .vbw/record.json
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  # An uncommitted edit to the plan's own file makes vbw ship refuse (R244: a stray
  # file of the user's never does): the loop must say so, not go quiet.
  printf 'hello\nagain\n' > src/greet.txt
  # The working tree changed, so the kernel asks for a proof first; the proof passes (greet.txt still says hello), then the ship refuses.
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  [ "$(step)" = stopped ] || { cat "$TEST_ROOT/step.json"; false; }
  jq -e '.loop.ended != null and (.loop.ended.reason | test("the ship was refused") and test("T1") and test("step ship") and test("Next: run /vbw:vibe"))' .vbw/record.json \
    || { jq .loop.ended .vbw/record.json; false; }
  [ -f .vbw/loop-report.md ]
  grep -q 'ship was refused' .vbw/loop-report.md
  # The loop committed nothing on its own: the edit is still on disk, uncommitted.
  [ "$(git status --porcelain -- src/greet.txt)" = " M src/greet.txt" ]
  # The cut-off item's cost line shows its spend so far, never "not counted yet" once the loop has ended (F184).
  ! grep -q 'not counted yet' .vbw/loop-report.md || { cat .vbw/loop-report.md; false; }
  grep -qE '^- T1 \(in_progress\): .* so far \(cut off when the loop ended\)' .vbw/loop-report.md || { cat .vbw/loop-report.md; false; }
}

@test "R179 (F205): a step resumed after the last item's ship ends the loop on the end of the list, not the ceiling, whatever the spend" {
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --ceiling 5 > /dev/null
  [ "$(step)" = plan ]
  loop_plan "$(item_req "Visitors can read a greeting")" P2
  [ "$(step)" = build ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_build P2
  [ "$(step)" = prove ] || { cat "$TEST_ROOT/step.json"; false; }
  loop_prove
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  # A step cut off right after the last ship (its record committed, the loop not yet ended), resumed once the
  # spend is above the ceiling: nothing was cut off, so the loop ends on the end of its list (F205).
  edit_record 'del(.loop.ended)'
  figures s1 9 5000 500
  [ "$(step)" = done ] || { cat "$TEST_ROOT/step.json"; false; }
  [ "$(reason)" = "end of the list: 1 shipped, 0 parked" ] || { reason; false; }
  jq -e '.loop.ended.reason == "end of the list: 1 shipped, 0 parked" and .loop.items[0].status == "shipped"' .vbw/record.json
  grep -q 'end of the list' .vbw/loop-report.md
  ! grep -q 'ceiling reached' .vbw/loop-report.md
}
