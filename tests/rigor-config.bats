#!/usr/bin/env bats
# R27: the tier is chosen automatically by default; vbw config rigor
# auto|express|standard|deep sets the mode, and a forced value overrides the
# computed tier.

load helper
load rigor-helper

teardown() { vbw_teardown; }

tier_of() { jq -r '.phases[0].tier' .vbw/record.json; }

@test "with no setting the mode is auto, and the config listing says so" {
  rigor_project 1
  vbw_run config rigor
  [ "$status" -eq 0 ]
  [ "$output" = auto ]
  vbw_run config
  [[ "$output" == *"rigor: auto"* ]]
}

@test "vbw config rigor sets each of auto, express, standard and deep" {
  rigor_project 1
  local m
  for m in express standard deep auto; do
    vbw_run config rigor "$m"
    [ "$status" -eq 0 ]
    vbw_run config rigor
    [ "$output" = "$m" ] || { echo "mode $m reads as $output"; false; }
  done
  "$VBW" config rigor deep > /dev/null
  jq -e '.settings.rigor == "deep"' .vbw/record.json
}

@test "an invalid mode is refused with the allowed list and the setting stays" {
  rigor_project 1
  "$VBW" config rigor standard > /dev/null
  vbw_run config rigor extreme
  [ "$status" -ne 0 ]
  [[ "$output" == *"auto, express, standard or deep"* ]]
  vbw_run config rigor
  [ "$output" = standard ]
}

@test "a forced mode overrides the computed tier when planning, up or down" {
  rigor_project 1
  "$VBW" config rigor deep > /dev/null
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = deep ]
  jq -e '.phases[0].reasons | any(.[]; test("forced"))' .vbw/record.json
  "$VBW" config rigor express > /dev/null
  run rigor_apply "$(rigor_doc 1 "" src/payments/charge.js)"
  [ "$status" -eq 0 ]
  [ "$(tier_of)" = express ]
}

@test "changing the mode re-tiers phases whose work has not started, and auto computes again" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  [ "$(tier_of)" = express ]
  "$VBW" config rigor deep > /dev/null
  [ "$(tier_of)" = deep ]
  "$VBW" config rigor auto > /dev/null
  [ "$(tier_of)" = express ]
}

@test "a phase whose work has started keeps its tier when the mode changes" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  edit_record '.plans[0].status = "done"'
  "$VBW" config rigor deep > /dev/null
  [ "$(tier_of)" = express ]
}

@test "changing the mode never makes the approved contract need approving again" {
  rigor_flow_setup
  "$VBW" approve > /dev/null
  vbw_run show contract
  [[ "$output" == *"(approved)"* ]]
  "$VBW" config rigor deep > /dev/null
  vbw_run show contract
  [[ "$output" == *"(approved)"* ]]
}
