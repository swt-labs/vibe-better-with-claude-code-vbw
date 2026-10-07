#!/usr/bin/env bats
# R101 (L1): in the balanced profile the Architect runs on Opus and every other
# role on Sonnet; QA is never below Sonnet in any profile, also after profile
# changes. The other profiles keep their models.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

@test "R101: the balanced profile gives the Architect Opus and every other role Sonnet" {
  "$VBW" config set profile balanced > /dev/null
  run "$VBW" config models < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '. == {architect: "opus", lead: "sonnet", dev: "sonnet", qa: "sonnet", scout: "sonnet", debugger: "sonnet", docs: "sonnet"}' || { echo "$output"; false; }
}

@test "R101: balanced is the default profile of a new project and shows the same models" {
  run "$VBW" config models < /dev/null
  printf '%s' "$output" | jq -e '.architect == "opus" and .dev == "sonnet"' || { echo "$output"; false; }
}

@test "R101: the quality and budget profiles keep their models" {
  "$VBW" config set profile quality > /dev/null
  run "$VBW" config models < /dev/null
  printf '%s' "$output" | jq -e '. == {architect: "opus", lead: "opus", dev: "opus", qa: "sonnet", scout: "sonnet", debugger: "opus", docs: "sonnet"}'
  "$VBW" config set profile budget > /dev/null
  run "$VBW" config models < /dev/null
  printf '%s' "$output" | jq -e '.architect == "sonnet" and .scout == "haiku" and .qa == "sonnet"'
}

@test "R101: QA stays on Sonnet or stronger through every profile change and a Haiku override" {
  local p
  for p in quality budget balanced budget quality balanced; do
    "$VBW" config set profile "$p" > /dev/null
    run "$VBW" config models < /dev/null
    printf '%s' "$output" | jq -e '.qa | IN("sonnet", "opus")' || { echo "$p: $output"; false; }
  done
  run "$VBW" config set model.qa haiku < /dev/null
  [ "$status" -ne 0 ]
  jq '.settings.models = {qa: "haiku"}' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  run "$VBW" config models < /dev/null
  printf '%s' "$output" | jq -e '.qa == "sonnet"'
}

@test "R101: the config skill and the README describe balanced with the Architect on Opus" {
  grep -E 'balanced' "$PLUGIN_ROOT/skills/config/SKILL.md" | grep -qi 'architect'
  grep -E '`balanced`: ' "$REPO_ROOT/README.md" | grep -qi 'architect'
}
