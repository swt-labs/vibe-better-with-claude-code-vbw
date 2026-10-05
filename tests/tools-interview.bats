#!/usr/bin/env bats
# R62 (docs/tools.md): once the interview knows what is being built, VBW asks
# one plain yes/no question for permission to look for tools, once per project.
# The question explains each term in a few words; on no nothing is searched or
# installed and the flow goes on; on yes the same research as /vbw:skills runs.
# The interview skill is a specification, so these tests hold its text to those
# rules (L1), and `vbw interview` still comes first.

load helper

SKILL="$PLUGIN_ROOT/skills/interview/SKILL.md"

# section: the tools section, from its heading to the next "## " heading or the end.
section() { awk '/^## .*[Tt]ools/ { f = 1; print; next } f && /^## / { exit } f' "$SKILL"; }

@test "R62: the interview skill has a tools section, after what and for whom, the follow-ups and the keep question" {
  [ -n "$(section)" ]
  local tools keep what follow
  tools=$(grep -nE '^## .*[Tt]ools' "$SKILL" | head -1 | cut -d: -f1)
  keep=$(grep -nE '^## Keep' "$SKILL" | head -1 | cut -d: -f1)
  what=$(grep -nE '^## What and for whom' "$SKILL" | head -1 | cut -d: -f1)
  follow=$(grep -nE '^## Follow-ups' "$SKILL" | head -1 | cut -d: -f1)
  [ "$tools" -gt "$what" ] && [ "$tools" -gt "$follow" ] && [ "$tools" -gt "$keep" ]
}

@test "R62: it asks one plain yes/no question with AskUserQuestion and explains each kind of tool in a few words" {
  section | grep -qF 'AskUserQuestion'
  section | grep -qiE 'yes'
  section | grep -qiE '(^|[^a-z])no([^a-z]|$)'
  section | grep -qiE 'skills'
  section | grep -qiE 'scanner|code-safety'
  section | grep -qiE 'linter'
  section | grep -qiE 'formatter'
  section | grep -qiE 'test framework|testing'
  section | grep -qiE 'explain'
}

@test "R62: it reads the remembered state and asks only once: an existing answer, yes or no, means it is not asked again" {
  section | grep -qF 'vbw tools'
  section | grep -qiE 'once'
  section | grep -qiE 'already|not asked again|never again|skip'
}

@test "R62: the answer is recorded as soon as it is given, yes or no" {
  section | grep -qF 'vbw tools answer yes'
  section | grep -qF 'vbw tools answer no'
}

@test "R62: on no nothing is searched on the web, no Scout is started, nothing is installed, and the flow continues" {
  section | grep -qiE 'no scout|nothing is searched|does not search|never search'
  section | grep -qiE 'nothing is installed|install nothing'
  section | grep -qiE 'continue|go on|carry on|unchanged'
}

@test "R62: on yes it hands over to the same research and proposal as /vbw:skills" {
  section | grep -qE '/vbw:skills|vbw:skills|vbw:tooling'
}

@test "R62: it ends with one plain line saying what VBW needs now" {
  section | grep -qE 'I need your yes or no to look for tools'
}

@test "R62: the interview still reads its answers first and keeps 'keep' as the last of the interview's own questions" {
  grep -qF 'vbw" interview' "$SKILL"
  grep -qE '^## Keep' "$SKILL"
  [ "$(grep -c 'The interview is complete only after' "$SKILL")" -ge 1 ]
}
