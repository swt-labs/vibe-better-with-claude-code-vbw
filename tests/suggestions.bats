#!/usr/bin/env bats
# R40 (docs/interview.md): when VBW proposes requirements and when it presents a
# plan for approval, it offers at most three suggestions matched to the user's
# level, each a yes or no the user may decline; an accepted one becomes a
# requirement or a recorded decision; a declined one is remembered in the
# project and never offered again. The declined list is the kernel's and runs for
# real; when and how many are offered is the suggest skill's text (L1).

load helper

SKILL="$PLUGIN_ROOT/skills/suggest/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

@test "R40: a declined suggestion is recorded in the project record by the kernel and never offered again" {
  vbw_run suggest decline "Add a dark mode?"
  [ "$status" -eq 0 ]
  jq -e '.schema == 1 and (.project.declined | length) == 1 and .project.declined[0].text == "Add a dark mode?" and (.project.declined[0].at | test("^[0-9]{4}-"))' .vbw/record.json
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == ["Add a dark mode?"]'
  vbw_run suggest list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Add a dark mode?"* ]]
}

@test "R40: declining the same text twice is deduplicated, even with other case or spacing" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  vbw_run suggest decline "Add a dark mode?"
  [ "$status" -eq 0 ]
  vbw_run suggest decline "  add A  DARK mode?  "
  [ "$status" -eq 0 ]
  jq -e '.project.declined | length == 1' .vbw/record.json
  "$VBW" suggest decline "Keep a changelog?" > /dev/null
  jq -e '.project.declined | length == 2' .vbw/record.json
}

@test "R40: a declined suggestion stays declined across sessions and milestones" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq '.requirements = [{id: "R1", text: "Visitors can read the page", proof: "auto", status: "proven", milestone: "M1"}]
    | .milestone.status = "shipped"
    | .shipped = [{id: "M1", title: "First milestone", at: "2026-01-01T00:00:00Z"}]' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" milestone start "Second" > /dev/null
  run env VBW_SESSION_ID=a-new-session "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == ["Add a dark mode?"]'
}

@test "R40: a record from an older VBW (nothing declined) is read: none declined" {
  cp "$BATS_TEST_DIRNAME/fixtures/records/v1.json" .vbw/record.json
  vbw_run suggest list
  [ "$status" -eq 0 ]
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.declined == []'
}

@test "R40: the declined list is written only through the kernel's validated write path" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq '.project.declined = ["a plain string, not an entry"]' .vbw/record.json > "$TEST_ROOT/bad.json"
  cp "$TEST_ROOT/bad.json" .vbw/record.json
  vbw_run suggest list
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
  vbw_run suggest decline ""
  [ "$status" -eq 2 ]
  vbw_run suggest nonsense
  [ "$status" -eq 2 ]
}

@test "R40: the record change is additive under project, so older VBWs still read the project" {
  "$VBW" suggest decline "Add a dark mode?" > /dev/null
  jq -e '.schema == 1 and (keys - ["schema","project","milestone","requirements","checks","phases","plans","fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"] == [])' .vbw/record.json
  jq -e '(.project | keys | sort) == ["declined","name"]' .vbw/record.json
}

@test "R40: the suggest skill offers at most three yes-or-no suggestions, only at spec proposal and plan approval" {
  [ -f "$SKILL" ]
  grep -qx 'name: suggest' "$SKILL"
  grep -qE '^description: .{20,}$' "$SKILL"
  grep -qiE 'at most three' "$SKILL"
  grep -qiE 'yes or no' "$SKILL"
  grep -qiE 'spec' "$SKILL"
  grep -qiE 'approval' "$SKILL"
  grep -qiE 'never (offer|ask|suggest)[^.]*(mid-run|mid-build|during a run|while)' "$SKILL"
  grep -qiE 'decline' "$SKILL"
  grep -qiE 'none (is|are) required|not required|never required' "$SKILL"
  [ "$(wc -w < "$SKILL")" -le 600 ]
}

@test "R40: an accepted suggestion becomes a requirement or a recorded decision, a declined one is recorded and not offered again" {
  grep -qF 'vbw spec add' "$SKILL"
  grep -qF 'vbw decide' "$SKILL"
  grep -qF 'vbw suggest decline' "$SKILL"
  grep -qiE 'declined' "$SKILL"
  grep -qiE 'never offer[^.]*again|not offer[^.]*again|never again' "$SKILL"
}

@test "R40: suggestions follow the user's level and depth, zero is valid, and none duplicates a requirement or decision" {
  grep -qiE 'level' "$SKILL"
  grep -qiE 'explanation depth' "$SKILL"
  grep -qiE 'neutral|no (interview )?answers' "$SKILL"
  grep -qiE 'zero|none worth|nothing worth|nothing to suggest' "$SKILL"
  grep -qiE 'duplicate' "$SKILL"
  grep -qF 'vbw show requirements' "$SKILL"
  grep -qF 'vbw show decisions' "$SKILL"
}

# step_text NAME: the router's text for step **NAME**, up to the next step.
step_text() {
  awk -v s="$1" 'index($0, "**" s "**") == 1 { on = 1; print; next } /^\*\*[A-Za-z]/ { on = 0 } /^## / { on = 0 } on' "$ROUTER"
}

@test "R40: the router offers suggestions at spec proposal and at plan approval, and nowhere else" {
  [ "$(grep -cF 'vbw:suggest' "$ROUTER")" -ge 2 ]
  step_text spec | grep -qF 'vbw:suggest'
  step_text approve | grep -qF 'vbw:suggest'
  local step
  for step in build fix qa prove run; do
    if step_text "$step" | grep -qF 'vbw:suggest'; then echo "suggestions offered at $step"; false; fi
  done
}
