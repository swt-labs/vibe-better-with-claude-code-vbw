#!/usr/bin/env bats
# R60: at every stop VBW ends with one plain line saying what it needs from the
# user now, or that it needs nothing. The router holds the rule (L1: the
# router's text and budget; the real-user scenarios show it in a session).

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

@test "R60: the router tells VBW to end every stop with one line of what it needs from the user, or nothing" {
  grep -qF 'What I need from you' "$ROUTER"
  grep -iE 'What I need from you' "$ROUTER" | grep -qiE 'nothing'
  grep -iE 'What I need from you' "$ROUTER" | grep -qiE 'every stop|each stop|at a stop'
}

@test "R60: the rule sits in the router's loop, where stops are described" {
  local loop rule
  loop=$(grep -n '^## Loop' "$ROUTER" | cut -d: -f1)
  rule=$(grep -n 'What I need from you' "$ROUTER" | head -1 | cut -d: -f1)
  [ -n "$loop" ] && [ -n "$rule" ] && [ "$rule" -gt "$loop" ]
}

@test "R60: the router stays within its 1,400-word budget" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
}
