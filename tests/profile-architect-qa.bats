#!/usr/bin/env bats
# R101 (L1): in the balanced profile the Architect runs on Opus, in vbw config
# models and in the planning workflow started with those models; QA is never
# below Sonnet in any profile or rigor tier, and a request to put QA below
# Sonnet is refused with a message naming the allowed models, the setting
# unchanged.

load helper
load rigor-helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
PLANNING="$PLUGIN_ROOT/workflows/planning.js"

teardown() { vbw_teardown; }

project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

@test "R101: the balanced profile gives the Architect Opus in vbw config models" {
  project
  "$VBW" config set profile balanced > /dev/null
  vbw_run config models
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.architect == "opus"' || { echo "$output"; false; }
}

@test "R101: the planning workflow started with the balanced models runs the Architect on Opus" {
  command -v node > /dev/null || skip "node is not installed"
  project
  "$VBW" config set profile balanced > /dev/null
  local models out
  models=$("$VBW" config models < /dev/null)
  out=$(node "$RUN" "$PLANNING" "$(jq -nc --argjson m "$models" '{requirements: [{id: "R1", proof: "auto", text: "One"}], models: $m, session: "s1"}')" \
    '{"architect (decide)": {"decisions": []}, "architect (scope)": {"phases": [{"id": "P1", "title": "T", "reqs": ["R1"], "goal": "g", "criteria": ["c"]}], "notes": []}, "lead": {"applied": true, "summary": "planned", "blockers": []}, "close run": {"ended": true, "recorded": true, "report": "ok"}}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.agentType == "vbw:architect")] | length == 2 and all(.[]; .opts.model == "opus")' || { echo "$out"; false; }
}

@test "R101: QA is Sonnet or Opus in every profile and every rigor tier, in vbw config models and vbw next" {
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  local p t
  for p in quality balanced budget; do
    "$VBW" config set profile "$p" > /dev/null
    vbw_run config models
    printf '%s' "$output" | jq -e '.qa | IN("sonnet", "opus")' || { echo "$p: $output"; false; }
    for t in express standard deep; do
      edit_record ".phases[0].tier = \"$t\""
      vbw_run next --json
      [ "$status" -eq 0 ]
      printf '%s' "$output" | jq -e '.rigor.P1.models.qa | IN("sonnet", "opus")' || { echo "$p $t: $output"; false; }
    done
  done
}

@test "R101: model.qa haiku is refused with a message naming the allowed models, and the setting is unchanged" {
  project
  "$VBW" config set model.qa opus > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config set model.qa haiku
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qi 'sonnet' || { echo "$output"; false; }
  printf '%s' "$output" | grep -qi 'opus' || { echo "$output"; false; }
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run config models
  printf '%s' "$output" | jq -e '.qa == "opus"' || { echo "$output"; false; }
}
