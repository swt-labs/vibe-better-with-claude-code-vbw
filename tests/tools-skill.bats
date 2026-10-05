#!/usr/bin/env bats
# R62 (docs/tools.md): /vbw:skills researches and proposes tools at any time,
# whatever the first answer was and from any state of a VBW project: it starts
# the tooling workflow with the project's stack, shows a short explained list,
# installs nothing until the user approves it, asks per approved tool whether it
# goes into this project or all the user's projects, and says plainly when
# nothing was found. The skill is a specification, so these tests hold its text
# to those rules (L1); the behavior itself is run in tests/l3-tools.bats's
# scenario.

load helper

SKILL="$PLUGIN_ROOT/skills/skills/SKILL.md"

front() { awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$SKILL"; }
text() { cat "$SKILL"; }

@test "R62: the skill starts the tooling workflow and may use it" {
  front | grep -E '^allowed-tools:' | grep -qF 'Workflow(vbw:tooling)'
  text | grep -qF 'vbw:tooling'
}

@test "R62: it works out the stack first (the map, else the manifest files) and passes it to the workflow" {
  text | grep -qF '.vbw/map.md'
  text | grep -qE 'package\.json|pyproject|Cargo\.toml'
  text | grep -qE '"stack"|stack:'
}

@test "R62: it runs at any time, whatever the first answer was, and records that the user wants tools" {
  text | grep -qiE 'any time|whatever (the|an) (earlier|first|previous) answer'
  text | grep -qF 'vbw tools'
  text | grep -qE 'vbw tools answer yes'
}

@test "R62: the four angles and what a shown item holds: what it is, why it fits, where it came from, with a link" {
  text | grep -qiE 'safety'
  text | grep -qiE 'quality|lint'
  text | grep -qiE 'test'
  text | grep -qiE 'what it is'
  text | grep -qiE 'why it fits'
  text | grep -qiE 'where it came from|source'
  text | grep -qiE 'link'
  text | grep -qiE 'explain.*(term|name)|(term|name).*explain'
}

@test "R62: the list is short (a handful, not a catalogue)" {
  text | grep -qiE 'handful|at most (5|6|six|five)|short list'
}

@test "R62: a pick from an untrusted source is shown with its plain warning and the user chooses: keep, drop or look further" {
  text | grep -qiE 'warning'
  text | grep -qiE 'keep'
  text | grep -qiE 'drop'
  text | grep -qiE 'look (further|more|again)'
}

@test "R62: nothing is installed, downloaded or changed until the user approves the list; declining or 'not yet' installs nothing; a partial approval installs only what was approved" {
  text | grep -qiE 'nothing is (installed|downloaded)|install(s|ed)? nothing|never install'
  text | grep -qiE 'not yet'
  text | grep -qiE 'only (the )?(approved|chosen|picked)|only what'
  text | grep -qF 'AskUserQuestion'
}

@test "R62: for each approved tool it asks whether it goes into this project only or into all the user's projects, and installs to that scope" {
  text | grep -qiE 'each (approved|chosen|picked)? ?(tool|item|pick)'
  text | grep -qiE 'this project'
  text | grep -qiE 'all (my |the |your )?projects'
  text | grep -qE 'npx skills add'
  text | grep -qE '(^|[^a-z])-g([^a-z]|$)'
}

@test "R62: when a Scout fails, finds nothing or the stack is unknown it says so plainly, shows what was found, installs nothing and does not stop the flow" {
  text | grep -qiE 'missing|note'
  text | grep -qiE 'plain(ly)?'
  text | grep -qiE 'no (error|stack)? ?trace|never (show|print) an? (error|stack)'
  text | grep -qiE 'unknown|cannot be determined|could not'
}

@test "R62: it ends every stop with one plain line saying what VBW needs now" {
  text | grep -qE 'I need your'
}

@test "R62: it keeps the user's words and no longer needs Node.js to search a registry by hand" {
  text | grep -qF 'vbw" interview'
  text | grep -qiE "level"
  ! text | grep -qiE 'the skills CLI needs Node\.js and stop'
}
