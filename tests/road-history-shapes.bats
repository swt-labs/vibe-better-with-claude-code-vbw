#!/usr/bin/env bats
# T174 (L1): the milestone's end (vbw next --json's road) reads the step history
# in every shape VBW has written: steps with parts only (P146), build units
# without tasks and with tasks (P149), units with breaks (T174), fix tiers,
# planning counts, QA phases and proof units. An entry of a shape VBW never
# wrote (a step that is not an object, units or phases that are not lists, a
# unit that is not an object) is skipped, never the road: the road stays an
# object, and a wave the history cannot time leaves it with no end and the
# reason, as any piece without a basis does.

load helper
load step-helper
load road-helper

setup() {
  vbw_setup
  road_project
}
teardown() { vbw_teardown; }

road_of() { "$VBW" next --json | jq -c '.road'; }

# hist_unit TIER TASKS BREAKS SECONDS: one finished build of one plan with breaks recorded (T174).
hist_unit() {
  hist_add "$(jq -nc --arg t "$1" --argjson k "$2" --argjson b "$3" --argjson s "$4" '{kind: "build", seconds: $s, parts: 1,
    units: [{id: "P7.1", tier: $t, tasks: $k, breaks: $b, seconds: $s}]}')"
}

# junk: entries of shapes VBW never wrote, none of them with parts.
junk() {
  jq '.steps += ["a step that is text", 42, null,
      {kind: "build", run: "j1", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, units: "P1.1"},
      {kind: "build", run: "j2", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, units: ["P1.1", 7, {tier: "deep", tasks: "two", breaks: "x", seconds: "slow"}]},
      {kind: "build", run: "j3", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, units: {id: "P1.1"}},
      {kind: "qa", run: "j4", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, phases: ["P1", 3]},
      {kind: "qa", run: "j5", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, phases: "P1"},
      {kind: "proof", run: "j6", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: 100, units: "check:C1"},
      {kind: "fix", run: "j7", started_at: "2026-01-01T00:00:00Z", ended_at: "2026-01-01T00:01:40Z", seconds: "long", tier: ["deep"]}]' \
    "$STEPS" > "$TEST_ROOT/junk.json" && cp "$TEST_ROOT/junk.json" "$STEPS"
}

@test "T174: the road times every wave from a history holding every shape VBW has written" {
  step_seed build 300 1 2
  hist_build deep - 100 1
  road_hist
  hist_unit deep 1 0 100
  hist_unit standard 1 0 100
  hist_plan 2 100 3
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e 'type == "object" and (.seconds | type) == "number" and .seconds > 0 and (.say | startswith("Milestone end: "))' || { echo "$r"; false; }
  "$VBW" next --json | jq -e '.step.kind == "build" and (.step.seconds | type) == "number"' || "$VBW" next --json | jq '.step'
}

@test "T174: entries of a shape VBW never wrote are skipped, never the road" {
  road_hist
  local before after
  before=$(road_of | jq '.seconds')
  [ "$before" != null ] || { road_of; false; }
  junk
  after=$(road_of | jq '.seconds')
  [ "$after" = "$before" ] || { echo "before $before, after $after"; road_of; false; }
  "$VBW" next --json | jq -e '(.step.seconds | type) == "number"' || "$VBW" next --json | jq '.step'
}

@test "T174: a wave the history cannot time leaves the road with no end and the reason, never no road" {
  # No readable run at all, only junk: no wave has a basis (one or two readable runs give a rough range, R270).
  mkdir -p "$(dirname "$STEPS")" && printf '{"steps": []}\n' > "$STEPS"
  junk
  local r
  r=$(road_of)
  printf '%s' "$r" | jq -e 'type == "object" and .seconds == null and .end == null
    and .say == "no milestone end time yet (VBW has timed fewer than 3 plans here)"' || { echo "$r"; false; }
}
