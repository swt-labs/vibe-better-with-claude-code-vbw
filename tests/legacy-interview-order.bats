#!/usr/bin/env bats
# R67 (docs/interview.md, docs/convert.md): with a VBW 1 folder and no interview
# yet, the interview comes first: its greeting and level question, then the
# old-folder step. vbw next says the interview is due at the convert step too,
# and the router interviews before spec or convert work. Found by the L3
# "legacy" scenario on 2026-10-06, where the old-folder question came first.

load helper

setup() {
  vbw_setup
  vbw_git_project
  mkdir -p .vbw-planning/phases/01-a
  printf '# Project\n' > .vbw-planning/PROJECT.md
  printf 'plan\n' > .vbw-planning/phases/01-a/01-01-PLAN.md
  git add -A && git commit -q -m "chore: VBW 1 plan"
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
}

teardown() { vbw_teardown; }

next_json() { "$VBW" next --json < /dev/null; }

@test "R67: a project with a VBW 1 folder and no interview is asked the interview at the convert step, from the level" {
  run next_json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.action == "convert" and .profile.ask == true and .profile.interviewed == false and .profile.pending == "level"'
}

@test "R67: once the interview is done, the convert step no longer asks for it" {
  "$VBW" interview set level never > /dev/null
  "$VBW" interview set depth "plain words" > /dev/null
  "$VBW" interview set involvement "decide and tell me" > /dev/null
  "$VBW" interview keep private > /dev/null
  next_json | jq -e '.action == "convert" and .profile.ask == false'
}

@test "R67: the router interviews before spec or convert work, not only before spec" {
  grep -qF '`profile.ask` true: follow `vbw:interview` before any spec or convert work' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}
