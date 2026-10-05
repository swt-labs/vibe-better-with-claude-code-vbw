#!/usr/bin/env bats
# R65 (docs/convert.md): the interview's old-folder step. Right after the level
# answer, when a project has a VBW 1 folder and no recorded choice, VBW shows the
# kernel's review in plain words, recommends converting or starting fresh with the
# recommended option first, and asks. The skills are specifications, so these
# tests hold their text to those rules (L1); the real-app run is its own check.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
CONVERT="$PLUGIN_ROOT/skills/convert/SKILL.md"

# section: the old-folder section: from its "## ...VBW 1..." heading to the next "## " heading.
section() { awk '/^## .*VBW 1/ { f = 1; print; next } f && /^## / { exit } f' "$SKILL"; }

@test "R65: the interview skill has an old-folder section, and reads the review with its other facts" {
  [ -n "$(section)" ]
  grep -qF 'vbw" legacy review' "$SKILL"
}

@test "R65: it comes right after the level answer and before any other question; no folder or a recorded choice skips it silently" {
  section | grep -qiE 'level'
  section | grep -qiE 'before (any|the) (other|next|depth)|before (the )?(depth|any other)'
  section | grep -qE '"legacy": ?false|legacy false|no (VBW 1 )?folder'
  section | grep -qiE 'silent|no message|say nothing|nothing is said'
  section | grep -qiE 'choice|asked'
  section | grep -qiE 'skip'
}

@test "R65: the review is shown to the user, in plain words at their level and depth, built from the kernel's four facts" {
  section | grep -qiE 'show|tell'
  section | grep -qiE 'level'
  section | grep -qiE 'depth|plain'
  section | grep -qiE 'finished'
  section | grep -qiE 'recent|last used'
  section | grep -qiE 'match'
  section | grep -qiE 'half'
}

@test "R65: the numbers and the recommendation come from the kernel, never from the model's guess" {
  section | grep -qiE 'kernel|vbw legacy review'
  section | grep -qiE 'recommendation'
  section | grep -qiE 'reasons'
  section | grep -qiE 'never (guess|invent|change|overrule)|do not (guess|invent|change)|not (a )?guess'
}

@test "R65: what could not be read is said, and converting is never recommended for it" {
  section | grep -qiE 'notes|could not (be )?read|cannot (be )?read'
  section | grep -qiE 'never recommend'
}

@test "R65: the choice is a question with AskUserQuestion: the recommended option first marked Recommended, the other second, each with a short trade-off" {
  section | grep -qF 'AskUserQuestion'
  section | grep -qF '(Recommended)'
  section | grep -qiE 'first'
  section | grep -qiE 'second|other'
  section | grep -qiE 'trade-?off'
  section | grep -qiE 'convert'
  section | grep -qiE 'start fresh|fresh'
}

@test "R65: the user may pick either option whatever was recommended, or answer in their own words" {
  section | grep -qiE 'either|whatever (was|is) recommended|regardless'
  section | grep -qiE 'own words|free text|other'
}

@test "R65: picking convert records the choice and runs the existing conversion; the old folder stays and the result is reported" {
  section | grep -qF 'vbw legacy choose convert'
  section | grep -qE 'vbw:convert|/vbw:convert'
  section | grep -qiE 'stays|left in place|untouched|keeps'
  section | grep -qiE 'report|tell'
}

@test "R65: picking start fresh records it, converts nothing, leaves the folder untouched and the interview goes on" {
  section | grep -qF 'vbw legacy choose fresh'
  section | grep -qiE 'no conversion|nothing is converted|converts nothing|do not convert|never convert'
  section | grep -qiE 'untouched|unchanged|leave'
  section | grep -qiE 'go on|carry on|continue'
}

@test "R65: the question is asked once per project, and the review can still be run on demand" {
  section | grep -qiE 'once'
  section | grep -qiE 'on demand|any time|later'
  grep -qF 'vbw legacy review' "$CONVERT"
}

@test "R65: it reads files only: no command found in the old folder is run, nothing is written, no network" {
  section | grep -qiE 'only read|reads? (files )?only|read-only'
  section | grep -qiE 'never run|run no|no command'
}

@test "R65: it is one extra interview step" {
  section | grep -qiE 'one (extra )?step|one extra'
}

@test "R65: the router's convert step defers to this step instead of a fixed recommendation" {
  local step
  step=$(awk '/^\*\*convert\*\*/ { f = 1; print; next } f && /^\*\*[a-z]/ { exit } f' "$ROUTER")
  [ -n "$step" ]
  [[ "$step" == *"vbw:interview"* || "$step" == *"legacy review"* ]]
  [[ "$step" != *'"Convert it (Recommended)"'* ]]
}

@test "R65: the prompts stay within their budgets: the step 190 words, the interview 900, the router 1,400, every skill 2,000, all prompts 11,400" {
  [ "$(section | wc -w)" -le 190 ]
  [ -n "$(section)" ]
  [ "$(wc -w < "$SKILL")" -le 900 ]
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  local f total=0 w
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md; do
    w=$(wc -w < "$f"); total=$((total + w))
    [ "$w" -le 2000 ] || [ "$f" = "$ROUTER" ] || { echo "$f has $w words"; false; }
  done
  [ "$total" -le 11400 ]
}
