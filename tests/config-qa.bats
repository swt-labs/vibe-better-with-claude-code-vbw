#!/usr/bin/env bats
# R36: vbw config set model.qa refuses a model weaker than Sonnet (Haiku) and
# says QA needs Sonnet or stronger; sonnet, opus and default are still accepted.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

@test "model.qa haiku is a usage error that says QA needs Sonnet or stronger and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config set model.qa haiku
  [ "$status" -ne 0 ]
  [[ "$output" == *"Sonnet or stronger"* ]]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "any value naming Haiku is refused for model.qa, whatever its case" {
  local v
  for v in Haiku HAIKU claude-haiku-4-5 my-Haiku-model; do
    vbw_run config set model.qa "$v"
    [ "$status" -ne 0 ] || { echo "$v accepted"; false; }
    [[ "$output" == *"Sonnet or stronger"* ]]
  done
  jq -e '.settings | has("models") | not' .vbw/record.json
}

@test "model.qa accepts sonnet, opus and a full non-Haiku id; default removes the override" {
  local v
  for v in sonnet opus claude-opus-5-5; do
    vbw_run config set model.qa "$v"
    [ "$status" -eq 0 ]
    jq -e --arg v "$v" '.settings.models.qa == $v' .vbw/record.json
  done
  vbw_run config set model.qa default
  [ "$status" -eq 0 ]
  jq -e '.settings | has("models") | not' .vbw/record.json
}

@test "the other roles still accept haiku" {
  local r
  for r in dev scout lead architect debugger docs; do
    vbw_run config set "model.$r" haiku
    [ "$status" -eq 0 ]
    jq -e --arg r "$r" '.settings.models[$r] == "haiku"' .vbw/record.json
  done
}

@test "a refused set leaves an existing valid model.qa override as it was" {
  "$VBW" config set model.qa opus > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config set model.qa haiku
  [ "$status" -ne 0 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  jq -e '.settings.models.qa == "opus"' .vbw/record.json
}

@test "the config header and the config skill document the QA restriction; the kernel stays within 3,000 lines" {
  local root="$BATS_TEST_DIRNAME/.."
  head -15 "$root/plugin/lib/cmd-config.sh" | grep -qi "qa.*haiku\|haiku.*qa"
  grep -qi "model.qa.*\(Sonnet or stronger\|never\|refus\)" "$root/plugin/skills/config/SKILL.md"
  [ "$(cat "$root"/plugin/bin/vbw "$root"/plugin/lib/*.sh | wc -l)" -le 3000 ]
}
