#!/usr/bin/env bats
# R35: in every profile and rigor tier, QA agents run on Sonnet or a stronger
# model, never Haiku; other roles keep the models their profile gives them.

load helper
load rigor-helper

teardown() { vbw_teardown; }

TIERS="$BATS_TEST_DIRNAME/../plugin/lib/tiers.json"
PROFILES="$BATS_TEST_DIRNAME/../plugin/lib/profiles.json"
SL="$BATS_TEST_DIRNAME/../plugin/scripts/vbw-statusline.sh"

planned_project() {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
}

next_models() { # PROFILE TIER: the P1 rigor models of vbw next --json
  edit_record ".settings.profile = \"$1\" | .phases[0].tier = \"$2\""
  vbw_run next --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -c '.rigor.P1.models'
}

@test "no profile and no tier cell gives QA Haiku, in the tables or in vbw next" {
  jq -e 'all(.[]; .qa != "haiku")' "$PROFILES"
  jq -e 'all(.[][]; .models.qa | IN("sonnet", "opus", "default"))' "$TIERS"
  planned_project
  local p t
  for p in quality balanced budget; do
    for t in express standard deep; do
      next_models "$p" "$t" | jq -e '.qa | IN("sonnet", "opus", "default")' || { echo "$p $t"; false; }
    done
  done
}

@test "the budget profile shows QA on Sonnet in vbw config models and in the status line" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  "$VBW" config set profile budget > /dev/null
  vbw_run config models
  echo "$output" | jq -e '.qa == "sonnet"'
  run bash -c 'jq -nc --arg d "$1" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [[ "${lines[1]}" != *"haiku ● qa"* ]]
  [[ "${lines[1]}" == *"● qa"* ]]
  [[ "${lines[1]}" == *"haiku ● scout"* ]]
}

@test "other roles keep their models: budget scout on haiku, express dev on haiku, the rest as before" {
  jq -e '.quality == {architect: "opus", lead: "opus", dev: "opus", qa: "sonnet", scout: "sonnet", debugger: "opus", docs: "sonnet"}
    and .balanced == {architect: "opus", lead: "sonnet", dev: "sonnet", qa: "sonnet", scout: "sonnet", debugger: "sonnet", docs: "sonnet"}
    and (.budget | del(.qa)) == {architect: "sonnet", lead: "sonnet", dev: "sonnet", scout: "haiku", debugger: "sonnet", docs: "sonnet"}' "$PROFILES"
  jq -e '(.quality | map_values(.models.dev)) == {express: "sonnet", standard: "opus", deep: "opus"}
    and (.balanced | map_values(.models.dev)) == {express: "sonnet", standard: "sonnet", deep: "sonnet"}
    and (.budget | map_values(.models.dev)) == {express: "haiku", standard: "sonnet", deep: "sonnet"}' "$TIERS"
}

@test "a record that already holds a Haiku QA override gets Sonnet in vbw next" {
  planned_project
  local v
  for v in haiku Haiku claude-haiku-4-5; do
    edit_record ".settings.profile = \"balanced\" | .phases[0].tier = \"standard\" | .settings.models = {qa: \"$v\"}"
    vbw_run next --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.rigor.P1.models.qa == "sonnet"' || { echo "$v: $output"; false; }
  done
}

@test "a QA override to opus or a full non-Haiku id is honoured, and the dev override still wins" {
  planned_project
  edit_record '.settings.profile = "budget" | .phases[0].tier = "express" | .settings.models = {qa: "opus", dev: "opus"}'
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.models == {dev: "opus", qa: "opus"}'
  edit_record '.settings.models = {qa: "claude-opus-5-5", dev: "claude-opus-5-5"}'
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.models == {dev: "claude-opus-5-5", qa: "claude-opus-5-5"}'
}

@test "a forced rigor and an escalation never lower QA below Sonnet" {
  planned_project
  "$VBW" config set profile budget > /dev/null
  local m
  for m in express standard deep auto; do
    "$VBW" config rigor "$m" > /dev/null
    vbw_run next --json
    echo "$output" | jq -e '.rigor.P1.models.qa | IN("sonnet", "opus", "default")' || { echo "$m: $output"; false; }
  done
  edit_record '.phases[0].tier = "deep" | .phases[0].escalations = [{at: "2026-10-04T10:00:00Z", from: "express", to: "deep", reason: "a Dev blocked"}]'
  vbw_run next --json
  echo "$output" | jq -e '.rigor.P1.models.qa | IN("sonnet", "opus", "default")'
}

@test "the status line shows the effective QA model: a Haiku override reads Sonnet, an opus one Opus" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  edit_record '.settings.models = {qa: "haiku"}'
  run bash -c 'jq -nc --arg d "$1" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [[ "${lines[1]}" != *"haiku"* ]]
  edit_record '.settings.models = {qa: "opus"}'
  run bash -c 'jq -nc --arg d "$1" "{workspace: {project_dir: \$d}}" | NO_COLOR=1 bash "$2"' _ "$PROJECT" "$SL"
  [[ "${lines[1]}" == *"● architect ● qa"* ]]
}

@test "the docs say QA never uses Haiku, and the budget profile no longer lists Haiku for QA" {
  local root="$BATS_TEST_DIRNAME/.."
  grep -qi "QA never" "$root/plugin/skills/config/SKILL.md"
  grep -qi "QA never" "$root/docs/rigor.md"
  run grep -q "Haiku for QA" "$root/plugin/skills/config/SKILL.md" "$root/plugin/skills/profile/SKILL.md"
  [ "$status" -eq 1 ]
}
