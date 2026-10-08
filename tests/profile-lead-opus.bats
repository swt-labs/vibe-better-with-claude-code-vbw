#!/usr/bin/env bats
# R119 (L1): in the balanced profile the Lead also runs on Opus, and every role
# other than the Architect and the Lead runs on Sonnet: in vbw config models, in
# the planning workflow started with those models, in the panel's team table
# and in the documents that describe the profile. The quality and budget
# profiles keep their models, and a user's own per-role model still wins.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
PLANNING="$PLUGIN_ROOT/workflows/planning.js"
PROFILES="$PLUGIN_ROOT/lib/profiles.json"
BALANCED='{"architect": "opus", "lead": "opus", "dev": "sonnet", "qa": "sonnet", "scout": "sonnet", "debugger": "sonnet", "docs": "sonnet"}'

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

@test "R119: vbw config models in the balanced profile: Architect and Lead on Opus, every other role on Sonnet" {
  "$VBW" config set profile balanced > /dev/null
  vbw_run config models
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --argjson b "$BALANCED" '. == $b' || { echo "$output"; false; }
  # balanced is also the default of a new project.
  "$VBW" config set profile quality > /dev/null
  "$VBW" config set profile balanced > /dev/null
  jq -e --argjson b "$BALANCED" '.balanced == $b' "$PROFILES"
}

@test "R119: the planning workflow started with the balanced models runs the Architect and the Lead on Opus, nothing else" {
  command -v node > /dev/null || skip "node is not installed"
  "$VBW" config set profile balanced > /dev/null
  local models out
  models=$("$VBW" config models < /dev/null)
  out=$(node "$RUN" "$PLANNING" "$(jq -nc --argjson m "$models" '{requirements: [{id: "R1", proof: "auto", text: "One"}], models: $m, session: "s1"}')" \
    '{"architect (decide)": {"decisions": []}, "architect (scope)": {"phases": [{"id": "P1", "title": "T", "reqs": ["R1"], "goal": "g", "criteria": ["c"]}], "notes": []}, "lead": {"applied": true, "summary": "planned", "blockers": []}, "close run": {"ended": true, "recorded": true, "report": "ok"}}')
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.agentType == "vbw:lead")] | length == 2 and all(.[]; .opts.model == "opus")' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.agentType != "vbw:lead" and .opts.agentType != "vbw:architect") | .opts.model] | all(. == "sonnet")' || { echo "$out"; false; }
}

@test "R119: the quality and budget profiles give every role the same model as before" {
  "$VBW" config set profile quality > /dev/null
  vbw_run config models
  printf '%s' "$output" | jq -e '. == {architect: "opus", lead: "opus", dev: "opus", qa: "sonnet", scout: "sonnet", debugger: "opus", docs: "sonnet"}' || { echo "$output"; false; }
  "$VBW" config set profile budget > /dev/null
  vbw_run config models
  printf '%s' "$output" | jq -e '. == {architect: "sonnet", lead: "sonnet", dev: "sonnet", qa: "sonnet", scout: "haiku", debugger: "sonnet", docs: "sonnet"}' || { echo "$output"; false; }
}

@test "R119: a user's own per-role model still wins over the balanced default" {
  "$VBW" config set profile balanced > /dev/null
  "$VBW" config set model.lead sonnet > /dev/null
  "$VBW" config set model.dev claude-opus-5-5 > /dev/null
  vbw_run config models
  printf '%s' "$output" | jq -e '.lead == "sonnet" and .dev == "claude-opus-5-5" and .architect == "opus" and .qa == "sonnet"' || { echo "$output"; false; }
  "$VBW" config set model.lead default > /dev/null
  vbw_run config models
  printf '%s' "$output" | jq -e '.lead == "opus"' || { echo "$output"; false; }
}

@test "R119: the panel's team table matches plugin/lib/profiles.json and shows the Lead on Opus" {
  command -v node > /dev/null || skip "node is not installed"
  local out
  out=$(cd "$PLUGIN_ROOT/hooks" && node --input-type=module -e '
    import { teamModel } from "./panel-mission-record.js"
    const out = {}
    for (const p of ["quality", "balanced", "budget"]) {
      const m = teamModel({ record: { settings: { profile: p } } })
      out[p] = Object.fromEntries(m.rows.map((r) => [r.role, r.model]))
    }
    process.stdout.write(JSON.stringify(out))')
  printf '%s' "$out" | jq -e --slurpfile lib "$PROFILES" --argjson b "$BALANCED" '. == $lib[0] and .balanced == $b' || { echo "$out"; false; }
}

@test "R119: README, the config and profile skills and docs/record.md show the Lead on Opus in balanced" {
  local line f
  for f in "$REPO_ROOT/README.md" "$PLUGIN_ROOT/skills/profile/SKILL.md"; do
    line=$(grep -E '\| *\*{0,2}Standard\*{0,2} *\|' "$f")
    printf '%s' "$line" | grep -q 'balanced' || { echo "$f: $line"; false; }
    printf '%s' "$line" | grep -qE 'Opus for the Architect and the Lead' || { echo "$f: $line"; false; }
  done
  line=$(grep -E '`balanced` \(default' "$PLUGIN_ROOT/skills/config/SKILL.md")
  printf '%s' "$line" | grep -qE 'Opus for (the )?Architect and (the )?Lead' || { echo "$line"; false; }
  line=$(grep -E '`settings`' "$REPO_ROOT/docs/record.md")
  printf '%s' "$line" | grep -qE 'Opus for the Architect and the Lead' || { echo "$line"; false; }
}
