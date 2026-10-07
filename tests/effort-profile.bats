#!/usr/bin/env bats
# R107 (docs/workflows.md, docs/rigor.md; L1): the profile sets an effort level
# for every role and step the workflows use (plugin/lib/efforts.json: profile,
# then role, then step), lower for closing a run and for documentation, higher
# for planning and QA; vbw config effort and vbw next --json give the current
# profile's table to the workflows; a table with a value Claude Code does not
# accept, or a missing role or step, is refused by VBW naming the role and the
# step, before any run starts.

load helper

EFFORTS="$PLUGIN_ROOT/lib/efforts.json"
# The roles and steps the workflows use (docs/workflows.md).
STEPS='{"architect":["decide","scope"],"lead":["plan","close"],"dev":["build","fix"],"docs":["build"],"qa":["verify"],"scout":["survey","merge"],"debugger":["investigate","diagnose","fix"]}'
RANK='def rank: {low: 0, medium: 1, high: 2, xhigh: 3, max: 4}[.];'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# plugin_copy: a copy of the plugin in $TEST_ROOT/plugin, for the tests that damage the table.
plugin_copy() {
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/plugin"
}

@test "R107: the profile file has a table for each profile, and every role and step the workflows use has a value Claude Code accepts" {
  [ -f "$EFFORTS" ]
  jq -e --argjson steps "$STEPS" '
    (keys | sort) == ["balanced", "budget", "quality"]
    and all(.[]; . as $t | $steps | to_entries | all(.[]; . as $r | $r.value | all(.[]; . as $s
        | ($t[$r.key][$s] // null) | IN("low", "medium", "high", "xhigh", "max"))))' "$EFFORTS"
}

@test "R107: closing a run and documentation get a lower effort than building, planning and QA a higher one, in every profile" {
  jq -e "$RANK"'
    all(.[]; (.lead.close | rank) < (.dev.build | rank)
      and (.docs.build | rank) < (.dev.build | rank)
      and (.architect.scope | rank) > (.dev.build | rank)
      and (.architect.decide | rank) > (.dev.build | rank)
      and (.lead.plan | rank) > (.dev.build | rank)
      and (.qa.verify | rank) > (.dev.build | rank))' "$EFFORTS"
}

@test "R107: vbw config effort prints the table of the current profile, and follows a profile change" {
  vbw_run config effort
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --slurpfile e "$EFFORTS" '. == $e[0].balanced' || { echo "$output"; false; }
  "$VBW" config set profile quality > /dev/null
  vbw_run config effort
  printf '%s' "$output" | jq -e --slurpfile e "$EFFORTS" '. == $e[0].quality' || { echo "$output"; false; }
  "$VBW" config set profile budget > /dev/null
  vbw_run config effort
  printf '%s' "$output" | jq -e --slurpfile e "$EFFORTS" '. == $e[0].budget' || { echo "$output"; false; }
}

@test "R107: vbw next --json carries the same table, so the router can pass it to every workflow" {
  "$VBW" config set profile quality > /dev/null
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --slurpfile e "$EFFORTS" '.effort == $e[0].quality' || { echo "$output"; false; }
}

@test "R107: a value Claude Code does not accept is refused with the role and the step, by vbw config effort and by vbw next" {
  plugin_copy
  jq '.balanced.architect.scope = "turbo"' "$EFFORTS" > "$TEST_ROOT/plugin/lib/efforts.json"
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *architect* ]] || { echo "$output"; false; }
  [[ "$output" == *scope* ]] || { echo "$output"; false; }
  [[ "$output" == *turbo* ]] || { echo "$output"; false; }
  run "$TEST_ROOT/plugin/bin/vbw" next --json < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *architect* && "$output" == *scope* ]] || { echo "$output"; false; }
}

@test "R107: a value that is not text is refused the same way" {
  plugin_copy
  jq '.balanced.qa.verify = 3' "$EFFORTS" > "$TEST_ROOT/plugin/lib/efforts.json"
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *qa* && "$output" == *verify* ]] || { echo "$output"; false; }
}

@test "R107: a missing role or step is refused with its name, so no workflow starts with a gap" {
  plugin_copy
  jq 'del(.balanced.lead.close)' "$EFFORTS" > "$TEST_ROOT/plugin/lib/efforts.json"
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *lead* && "$output" == *close* ]] || { echo "$output"; false; }
  jq 'del(.balanced.debugger)' "$EFFORTS" > "$TEST_ROOT/plugin/lib/efforts.json"
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *debugger* ]] || { echo "$output"; false; }
}

@test "R107: only the profile in use is judged: a bad value in another profile does not stop this one" {
  plugin_copy
  jq '.quality.dev.build = "turbo"' "$EFFORTS" > "$TEST_ROOT/plugin/lib/efforts.json"
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$TEST_ROOT/plugin/bin/vbw" config set profile quality > /dev/null
  run "$TEST_ROOT/plugin/bin/vbw" config effort < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *dev* && "$output" == *build* ]] || { echo "$output"; false; }
}

@test "R107: the router and every skill that starts a workflow pass the effort table in the workflow's args" {
  local f
  grep -q '`effort`' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
  for f in debug map research skills; do
    grep -q 'config effort' "$PLUGIN_ROOT/skills/$f/SKILL.md" || { echo "skill $f does not read vbw config effort"; false; }
    grep -q '"effort"' "$PLUGIN_ROOT/skills/$f/SKILL.md" || { echo "skill $f does not pass effort in the args"; false; }
  done
}

@test "R107: the effort table is described for people: the effort levels, the steps and where the table lives" {
  grep -q 'efforts.json' "$REPO_ROOT/docs/workflows.md"
  grep -qi 'xhigh' "$REPO_ROOT/docs/workflows.md"
  grep -q 'config effort' "$REPO_ROOT/docs/workflows.md"
}

@test "R107: the router and the prompts stay within their budgets" {
  run bats --filter "the router stays within its budget" "$BATS_TEST_DIRNAME/skills.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bats --filter "R39: prompts stay within" "$BATS_TEST_DIRNAME/profile-levels.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
