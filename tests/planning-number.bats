#!/usr/bin/env bats
# R106 (docs/workflows.md, docs/next.md; L1): the planning workflow tells the
# Architect the next free phase number (args.next_phase, from vbw next --json),
# the router passes it, the Architect numbers new phases from it, and a
# planning run has no renumbering step. The runtime is stubbed
# (tests/helpers/run-workflow.js): no model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows"
REQS='[{"id":"R1","proof":"auto","text":"x"}]'
SCOPE='{"phases":[{"id":"P70","title":"a","reqs":["R1"],"goal":"g","criteria":["c"]},{"id":"P71","title":"b","reqs":["R1"],"goal":"g","criteria":["c"]}],"notes":[]}'
LEAD='{"applied":true,"summary":"s","blockers":[]}'
NONE='{"decisions":[]}'
OK='{"ended":true,"recorded":true,"report":"all recorded; run ended"}'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# plan ARGS_EXTRA: the stubbed planning run with the requirements and ARGS_EXTRA merged into the args.
plan() {
  node "$RUN" "$WF/planning.js" "$(jq -nc --argjson r "$REQS" --argjson x "$1" '{requirements: $r, session: "s"} + $x')" \
    "$(jq -nc --argjson s "$SCOPE" --argjson l "$LEAD" --argjson n "$NONE" --argjson k "$OK" '{"architect (decide)": $n, "architect (scope)": $s, "lead": $l, "close run": $k}')"
}

@test "R106: the Architect's scoping task states the next free phase number" {
  run plan '{"next_phase": 70}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label == "architect (scope)")][0].prompt | contains("P70")' || { echo "$output"; false; }
}

@test "R106: the number follows the args, not a fixed text" {
  run plan '{"next_phase": 125}'
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label == "architect (scope)")][0].prompt | contains("P125") and (contains("P70") | not)' || { echo "$output"; false; }
}

@test "R106: a planning run has no renumbering step: the phases come back numbered and reach the Lead as given" {
  run plan '{"next_phase": 70}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.calls[].opts.label] == ["architect (decide)", "architect (scope)", "lead", "close run"]' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label == "lead")][0].prompt | contains("\"id\":\"P70\"") and contains("\"id\":\"P71\"")' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.status == "planned"' || { echo "$output"; false; }
}

@test "R106: planning again (decided) also states the number, and keeps started phases as they are" {
  run plan '{"next_phase": 70, "decided": true}'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '[.calls[].opts.label] == ["architect (scope)", "lead", "close run"]' || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.label == "architect (scope)")][0].prompt | contains("P70") and test("started"; "i")' || { echo "$output"; false; }
}

@test "R106: without a number in the args (an older router) planning still runs" {
  run plan '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.status == "planned"' || { echo "$output"; false; }
}

@test "R106: the router passes next_phase to the planning workflow, on the first run and on the run after the user's decisions" {
  local n
  n=$(grep -c '"next_phase": <next_phase>' "$PLUGIN_ROOT/skills/vibe/SKILL.md")
  [ "$n" -ge 2 ] || { echo "the router names next_phase $n times"; false; }
}

@test "R106: the Architect numbers new phases from the number its task gives" {
  grep -qi 'next free phase number' "$PLUGIN_ROOT/agents/architect.md"
  grep -q 'started' "$PLUGIN_ROOT/agents/architect.md"
}

@test "R106: the router and the prompts stay within their budgets" {
  run bats --filter "the router stays within its budget" "$BATS_TEST_DIRNAME/skills.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bats --filter "R39: prompts stay within" "$BATS_TEST_DIRNAME/profile-levels.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
