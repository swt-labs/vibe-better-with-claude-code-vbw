#!/usr/bin/env bats
# R190, phase P148: the steptime scenario of tools/l3-suite.sh, run in the real
# Claude Code window (L3) on a realistic project with a seeded step history,
# shows the same end time in VBW's chat message, the status line and Comms for
# a build; a background proof's 'N of M checks' counting up in the status line;
# and, on a project with no history, 'no end time yet'. As in
# tests/l3-panel-comms.bats these tests do not run Claude Code (L1): they hold
# the scenario's structure and the result it wrote under tools/l3-results/. The
# result is written by the run, not by a person.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULT="$REPO_ROOT/tools/l3-results/steptime.json"

body() { sed -n '/^scenario_steptime()/,/^}/p' "$SUITE"; }

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R190: the suite has a steptime scenario that seeds a step history and records each fact" {
  [ -n "$(body)" ] || { echo "tools/l3-suite.sh has no scenario_steptime"; false; }
  body | grep -q 'steps.json' || { echo "scenario_steptime does not seed the step history"; false; }
  for fact in chat_end statusline_end comms_end same_end proof_counts proof_counted_up no_history_no_end_time; do
    body | grep -q "$fact" || { echo "scenario_steptime does not record $fact"; false; }
  done
}

@test "R190: a committed result of the steptime scenario shows one end time in chat, status line and Comms, at L3" {
  [ -f "$RESULT" ] || { echo "the steptime scenario has not been run: no result is committed"; false; }
  jq -e '.scenario == "steptime" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-10-16")
    and (.fixture | type == "string" and length > 0)
    and (.facts.chat_end | test("^[0-9]{2}:[0-9]{2}$"))
    and .facts.statusline_end == .facts.chat_end and .facts.comms_end == .facts.chat_end
    and .facts.same_end == true
    and (.not_tested | type == "array" and length > 0)' "$RESULT" || { cat "$RESULT"; false; }
}

@test "R190: the committed result shows a background proof counting up and 'no end time yet' without history" {
  [ -f "$RESULT" ] || { echo "the steptime scenario has not been run: no result is committed"; false; }
  jq -e '.facts.proof_counted_up == true
    and (.facts.proof_counts | type == "array" and length >= 2)
    and (.facts.proof_counts as $c | all(range(1; $c | length); $c[.] >= $c[. - 1]) and ($c[-1] > $c[0]))
    and .facts.no_history_no_end_time == true' "$RESULT" || { cat "$RESULT"; false; }
}

# R240 (T211, D558): the status line's end time reaches the steptime scenario. The
# scenario's sampler kept the status line pattern 'until HH:MM' after commit d7f73771
# (2026-10-24) changed the status line to 'until around HH:MM', so it recorded nothing
# there in about 120 samples on 2026-10-31 while the chat and Comms had the time. The
# suite now reads the status line with one top-level pattern, L3_STATUS_UNTIL, which
# tests/statusline-step.bats runs over a real render; both scenarios that read the status
# line use it, and the comment describes the wording the status line prints.

road_body() { sed -n '/^scenario_road()/,/^}/p' "$SUITE"; }

@test "R240: the suite defines L3_STATUS_UNTIL once at top level, accepting 'until around HH:MM' with an optional day word" {
  [ "$(grep -c '^L3_STATUS_UNTIL=' "$SUITE")" -eq 1 ] || { echo "L3_STATUS_UNTIL is not defined exactly once at top level"; false; }
  grep -m1 '^L3_STATUS_UNTIL=' "$SUITE" > "$TEST_ROOT/pattern.sh"
  # shellcheck disable=SC1091
  . "$TEST_ROOT/pattern.sh"
  local s
  for s in 'until around 14:20' 'until around tomorrow 00:20' '● working: building P1.1 · 0 of 1 · until around 14:20'; do
    printf '%s\n' "$s" | grep -qE "$L3_STATUS_UNTIL" || { echo "'$L3_STATUS_UNTIL' does not read: $s"; false; }
  done
  # The old wording is not what the status line prints, so the pattern must not read it as a time.
  ! printf '%s\n' 'until 14:20' | grep -qE "$L3_STATUS_UNTIL" || { echo "'$L3_STATUS_UNTIL' still reads the old 'until HH:MM'"; false; }
}

@test "R240: the steptime sampler and the road scenario read the status line column with L3_STATUS_UNTIL, and no stale 'until HH:MM' pattern remains" {
  body | grep -E '^\s*sl=' | grep -q 'L3_STATUS_UNTIL' || { echo "steptime's status line column is not read with L3_STATUS_UNTIL:"; body | grep -E '^\s*sl='; false; }
  road_body | grep -E '^\s*sl=' | grep -q 'L3_STATUS_UNTIL' || { echo "the road scenario's status line column is not read with L3_STATUS_UNTIL:"; road_body | grep -E '^\s*sl='; false; }
  ! grep -q "st_time 'until'" "$SUITE" || { echo "the stale st_time 'until' call remains"; false; }
  ! grep -qE "'until \(tomorrow \)\?\[0-9\]" "$SUITE" || { echo "a stale inline 'until (tomorrow )?HH:MM' pattern remains"; false; }
  # The comment above the scenario describes the status line's wording as it prints today.
  sed -n '/^# steptime (R190/,/^steptime_seed()/p' "$SUITE" | grep -q 'status line.*until around' || { echo "the scenario's comment does not say the status line prints 'until around HH:MM'"; false; }
  ! sed -n '/^# steptime (R190/,/^steptime_seed()/p' "$SUITE" | grep -qE '\("until HH:MM"\)' || { echo "the scenario's comment still says the status line prints 'until HH:MM'"; false; }
}

@test "R240: the committed result is from a run on the fixed suite (2026-11-01 or later) with the status line's end time equal to the chat's and Comms'" {
  [ -f "$RESULT" ] || { echo "no steptime result is committed"; false; }
  jq -e '.scenario == "steptime" and .evidence_level == "L3" and .passed == true
    and (.at | type == "string" and . >= "2026-11-01")
    and (.facts.statusline_end | test("^[0-9]{2}:[0-9]{2}$"))
    and .facts.statusline_end == .facts.chat_end and .facts.statusline_end == .facts.comms_end
    and .facts.same_end == true and (.facts.screen_samples > 0)' "$RESULT" || { cat "$RESULT"; false; }
}
