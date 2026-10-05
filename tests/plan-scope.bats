#!/usr/bin/env bats
# R50 (docs/next.md, docs/workflows.md): before planning, VBW asks the user only
# about decisions for the milestone being planned, never about requirements of
# shipped milestones. The kernel hands the planning workflow the active
# milestone's requirements (vbw next --json, top-level requirements); the
# workflow puts exactly those in front of the Architect. The workflow runs here
# with stubbed agents, so no model is called (L1).

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
PROFILE='{"level":"never","depth":"plain with technical terms explained","involvement":"options with a recommendation"}'

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# M3 and M4 shipped; M8 active. R18, R29 and R30 belong to the shipped ones.
setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Bench\n\n## Requirements\n\n- R18 [auto] The benchmark runs\n- R29 [auto] The benchmark is recorded\n- R30 [auto] The benchmark is published\n- R47 [auto] QA checks only changed phases\n- R48 [auto] QA says why\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.shipped = [{id: "M3", title: "Benchmark", at: "2026-10-03T09:00:00Z"}, {id: "M4", title: "Rigor", at: "2026-10-03T10:00:00Z"}]
    | .milestone = {id: "M8", title: "Smarter QA", status: "active"}
    | (.requirements[] | select(.id == "R18" or .id == "R29")).milestone = "M3"
    | (.requirements[] | select(.id == "R30")).milestone = "M4"
    | (.requirements[] | select(.id == "R47" or .id == "R48")).milestone = "M8"'
}

teardown() { vbw_teardown; }

ids() { jq -c '[.requirements[].id]'; }

# plan_run RESPONSES [ARGS_EXTRA]: run planning.js with the kernel's requirements.
plan_run() {
  local args
  args=$("$VBW" next --json < /dev/null | jq -c --argjson p "$PROFILE" --argjson x "${2:-{\}}" '{requirements: .requirements, profile: $p} + $x')
  node "$RUN" "$PLUGIN_ROOT/workflows/planning.js" "$args" "$1"
}

@test "R50: vbw next --json carries only the active milestone's requirements, with their text, and no shipped id" {
  vbw_run next --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | ids)" = '["R47","R48"]' ]
  printf '%s' "$output" | jq -e 'all(.requirements[]; (.text | length) > 0 and .proof != null)'
  if printf '%s' "$output" | jq -c '.requirements' | grep -qwE 'R(18|29|30)'; then false; fi
}

@test "R50: a requirement carried over to the active milestone counts as active" {
  edit_record '(.requirements[] | select(.id == "R18")).milestone = "M8"'
  [ "$("$VBW" next --json < /dev/null | ids)" = '["R18","R47","R48"]' ]
}

@test "R50: a requirement with no milestone is reported by name, never silently dropped" {
  edit_record 'del((.requirements[] | select(.id == "R48")).milestone)'
  vbw_run next --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"R48"* ]]
}

@test "R50: the Architect's decision step is given the active requirements and no shipped one" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(plan_run '{"architect (decide)": {"decisions": []}}')
  printf '%s' "$out" | jq -e '.calls[0].opts.label == "architect (decide)"'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'R47'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'QA says why'
  if printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -qwE 'R(18|29|30)'; then false; fi
  if printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'benchmark'; then false; fi
}

@test "R50: a decision for an active requirement is still asked" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(plan_run '{"architect (decide)": {"decisions": [{"question": "Where is the QA record kept?", "why_it_matters": "who can see it", "options": [{"label": "In the project", "tradeoff": "shared"}, {"label": "On this machine", "tradeoff": "private"}], "recommended": "In the project"}]}}')
  printf '%s' "$out" | jq -e '.result.status == "needs_decisions" and (.result.decisions | length) == 1 and (.calls | length) == 1'
}

@test "R50: a milestone with only technical changes returns no decision and planning goes on without a user round" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(plan_run '{"architect (decide)": {"decisions": []}, "architect (scope)": {"phases": [{"id": "P1", "title": "T", "reqs": ["R47"], "goal": "g", "criteria": ["c"]}], "notes": []}, "lead": {"applied": true, "summary": "planned", "blockers": []}}')
  printf '%s' "$out" | jq -e '.result.status == "planned" and ([.calls[].opts.label] == ["architect (decide)", "architect (scope)", "lead"])'
}

@test "R50: the scoping step, after the user decided, also sees only the active requirements" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(plan_run '{"architect (scope)": {"phases": [{"id": "P1", "title": "T", "reqs": ["R47"], "goal": "g", "criteria": ["c"]}], "notes": []}, "lead": {"applied": true, "summary": "planned", "blockers": []}}' '{"decided": true}')
  printf '%s' "$out" | jq -e '.calls[0].opts.label == "architect (scope)"'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'R48'
  if printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -qwE 'R(18|29|30)'; then false; fi
}

@test "R50: without the requirements, planning stops and says so instead of letting the Architect read every requirement" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(node "$RUN" "$PLUGIN_ROOT/workflows/planning.js" "{\"profile\": $PROFILE}" '{}')
  printf '%s' "$out" | jq -e '.result.status == "blocked" and (.calls | length) == 0 and (.result.summary | test("requirements"))'
}

@test "R50: the decision step still passes a schema and carries the user's level, explanation depth and involvement" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local out
  out=$(plan_run '{"architect (decide)": {"decisions": []}}')
  printf '%s' "$out" | jq -e '.calls[0].opts.schema.properties.decisions.type == "array"'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'The user.s level: never'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'plain with technical terms explained'
  printf '%s' "$out" | jq -r '.calls[0].prompt' | grep -q 'options with a recommendation'
}

@test "R50: the Architect reads only the requirements its task lists, and the router hands them to the planning workflow" {
  if grep -q 'vbw show requirements' "$PLUGIN_ROOT/agents/architect.md"; then false; fi
  grep -qiE 'requirements (your task|the task|in your task)' "$PLUGIN_ROOT/agents/architect.md"
  [ "$(grep -c '"requirements"' "$PLUGIN_ROOT/skills/vibe/SKILL.md")" -ge 2 ]
}
