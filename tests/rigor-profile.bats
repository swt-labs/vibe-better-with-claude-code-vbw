#!/usr/bin/env bats
# R26: which agents run, how many, the QA tier and the models follow each
# phase's tier through the profile (lib/tiers.json: profile -> tier -> cell
# {agents, qa, models}); vbw next --json exposes exactly the cell, per phase,
# under the top-level "rigor" key.

load helper
load rigor-helper

teardown() { vbw_teardown; }

TIERS="$BATS_TEST_DIRNAME/../plugin/lib/tiers.json"
PROFILES="$BATS_TEST_DIRNAME/../plugin/lib/profiles.json"

@test "the profile defines, for each tier, the agents with their count, the QA tier and the models" {
  [ -f "$TIERS" ]
  jq -e --slurpfile p "$PROFILES" 'keys == ($p[0] | keys)
    and all(.[]; keys == ["deep", "express", "standard"]
      and all(.[]; (.agents | type == "object" and length > 0 and all(.[]; type == "number" or . == "plans"))
        and (.qa | IN("quick", "standard", "deep"))
        and (.models | (.dev | IN("opus", "sonnet", "haiku")) and (.qa | IN("opus", "sonnet", "haiku")))))' "$TIERS"
}

@test "express is one Dev; standard and deep keep the profile's models and QA tiers as before" {
  jq -e --slurpfile p "$PROFILES" 'all(.[]; .express.agents.dev == 1 and .express.qa == "quick" and .deep.qa == "deep")
    and (to_entries | all(.[]; .key as $k | .value.standard.models == {dev: $p[0][$k].dev, qa: $p[0][$k].qa}))
    and .quality.standard.qa == "deep" and .balanced.standard.qa == "standard" and .budget.standard.qa == "quick"
    and all(to_entries[]; .value.express.models.dev != "opus")' "$TIERS"
}

@test "vbw next --json gives each phase exactly its profile cell, for every profile and tier" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  local p t
  for p in quality balanced budget; do
    for t in express standard deep; do
      edit_record ".settings.profile = \"$p\" | .phases[0].tier = \"$t\""
      vbw_run next --json
      [ "$status" -eq 0 ]
      printf '%s' "$output" | jq -e --slurpfile c "$TIERS" --arg p "$p" --arg t "$t" '.rigor.P1 == ({tier: $t} + $c[0][$p][$t])' \
        || { echo "profile $p tier $t: $output"; false; }
    done
  done
}

@test "a user's model override still wins over the tier's models" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  "$VBW" config set model.dev opus > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.models.dev == "opus"'
}

@test "a phase planned before tiers existed counts as standard" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  edit_record '.phases[0] |= del(.tier, .reasons, .predicted)'
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.tier == "standard"'
}

@test "the workflows and the router pass the tier's models and QA tier through" {
  grep -q 'rigor' "$PLUGIN_ROOT/workflows/building.js"
  grep -q 'rigor' "$PLUGIN_ROOT/workflows/verifying.js"
  grep -q 'rigor' "$PLUGIN_ROOT/workflows/fixing.js"
  grep -q 'rigor' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}
