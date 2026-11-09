#!/usr/bin/env bats
# R190, phase P148 (L1): the docs explain the step end time. docs/panel.md's
# 'Time left' section: which steps get an end time, the 3-step minimum, time per
# part, the 50-per-kind history, what 'later than usual' and 'N min late' mean,
# where the history lives and how to reset it; the status line docs show the
# short form; the README, where it describes the panel, names the end time;
# docs/next.md describes the step vbw next --json carries.

load helper

PANEL="$REPO_ROOT/docs/panel.md"
STATUSLINE="$REPO_ROOT/docs/statusline.md"
README="$REPO_ROOT/README.md"
NEXT="$REPO_ROOT/docs/next.md"

# section: docs/panel.md's 'Time left' section, its heading to the next one.
section() { sed -n '/^## Time left/,/^## /p' "$PANEL" | sed '$d'; }

@test "R190: docs/panel.md's Time left section names the steps that get an end time and shows the full wording" {
  local s
  s=$(section)
  [ -n "$s" ] || { echo "docs/panel.md has no '## Time left' section"; false; }
  for kind in planning build fix QA proof; do
    printf '%s\n' "$s" | grep -qi "$kind" || { echo "Time left does not name $kind"; false; }
  done
  printf '%s\n' "$s" | grep -qE 'about [0-9]+ min, until around [0-9]{2}:[0-9]{2}' || { echo "no example of the full wording"; false; }
  ! printf '%s\n' "$s" | grep -q 'min left in this step' || { echo "the old sentence is still described"; false; }
}

@test "R190: docs/panel.md explains the R270 rough-guess thresholds, time per part and the 50-per-kind history" {
  local s
  s=$(section)
  printf '%s\n' "$s" | grep -q 'fewer than 5' || { echo "no 5-run threshold"; false; }
  printf '%s\n' "$s" | grep -q '1\.5 times' || { echo "no 1.5 spread threshold"; false; }
  printf '%s\n' "$s" | grep -qiE 'per (plan|part|check)' || { echo "no time per part"; false; }
  printf '%s\n' "$s" | grep -qiE '50 (finished )?steps of each kind|latest 50 of each kind|50 per kind' || { echo "no 50-per-kind history"; false; }
  printf '%s\n' "$s" | grep -qi 'No end time yet' || { echo "no words for no basis"; false; }
}

@test "R190: docs/panel.md says what 'later than usual' and 'N min late' mean" {
  local s
  s=$(section)
  printf '%s\n' "$s" | grep -qi 'later than usual' || { echo "'later than usual' is not explained"; false; }
  printf '%s\n' "$s" | grep -qE '[0-9]+ min late' || { echo "'N min late' is not explained"; false; }
  printf '%s\n' "$s" | grep -qE '"until around [0-9]{2}:[0-9]{2}, later than usual"' || { echo "the later-than-usual wording is not shown"; false; }
  printf '%s\n' "$s" | grep -qE '"until around [0-9]{2}:[0-9]{2}, [0-9]+ min late"' || { echo "the N-min-late wording is not shown"; false; }
  printf '%s\n' "$s" | grep -qi 'own pace' || { echo "the move to the run's own pace is not explained"; false; }
}

@test "R190: docs/panel.md says where the history lives and how to reset it" {
  local s
  s=$(section)
  printf '%s\n' "$s" | grep -qF 'steps.json' || { echo "steps.json is not named"; false; }
  printf '%s\n' "$s" | grep -qF '.git/vbw/steps.json' || { echo "where the history lives is not said"; false; }
  printf '%s\n' "$s" | grep -qiE 'reset|delete|remove' || { echo "how to reset the history is not said"; false; }
}

@test "R190: the status line docs show the step with its clock time, the proof count and the late cases" {
  grep -qE 'until around [0-9]{2}:[0-9]{2}' "$STATUSLINE" || { echo "docs/statusline.md has no 'until around HH:MM'"; false; }
  grep -qE 'proving [0-9]+ of [0-9]+ checks' "$STATUSLINE" || { echo "no background proof example"; false; }
  grep -qi 'later than usual' "$STATUSLINE" || { echo "no 'later than usual'"; false; }
  grep -qE '[0-9]+ min late' "$STATUSLINE" || { echo "no 'N min late'"; false; }
}

@test "R190: the README names the step's end time where it describes the panel" {
  grep -qE 'until around [0-9]{2}:[0-9]{2}' "$README" || { echo "README.md does not mention the step's end time"; false; }
}

@test "R190: docs/next.md describes the step vbw next --json carries" {
  grep -qF 'step.say' "$NEXT" || grep -qF '"say"' "$NEXT" || { echo "docs/next.md does not describe step.say"; false; }
  grep -qiE 'no end time yet' "$NEXT" || { echo "docs/next.md does not show the no-basis sentence"; false; }
  # A proof's step carries the reason most units run again (R202), and its sentence ends with it.
  grep -qF '"reason": "plugin/lib/core.sh changed"' "$NEXT" || { echo "docs/next.md does not show step.why"; false; }
  grep -qF '; top reason: ' "$NEXT" || { echo "docs/next.md does not show the sentence's top reason"; false; }
}

@test "T173: docs/panel.md says a step far longer than its kind and size is left out of the estimates, and what that cannot catch" {
  local doc="$REPO_ROOT/docs/panel.md"
  tr '\n' ' ' < "$doc" | grep -Eq 'Idle time is not work.*more than 8 times the median seconds per part' || { echo "docs/panel.md does not state the idle rule"; false; }
  tr '\n' ' ' < "$doc" | grep -Eq 'A wait shorter than that +still counts' || { echo "docs/panel.md does not state what the rule cannot catch"; false; }
  ! grep -qF 'Time estimates absorb idle time' "$REPO_ROOT/docs/known-issues.md" || { echo "the fixed entry is still listed"; false; }
}
