#!/usr/bin/env bats
# R61 (words, L1): the router asks for approval with a choice, built from what
# vbw show contract prints; /vbw:approve still works; the docs describe the
# choice, the Approve-first order, and that typing the command still works; the
# prompts stay within their budgets.

load helper

ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"

approve_step() { sed -n '/^\*\*approve\*\*/,/^\*\*build\*\*/p' "$ROUTER"; }

@test "R61: the router's approve step asks with AskUserQuestion, Approve first and Not yet second, from the question vbw show contract prints" {
  local s
  s=$(approve_step)
  [ -n "$s" ]
  [[ "$s" == *AskUserQuestion* ]]
  [[ "$s" == *"approval question"* ]]
  [[ "$s" == *Approve*"Not yet"* ]]
  [[ "$s" == *"/vbw:approve"* ]]
  [[ "$s" == *"cannot approve"* ]]
}

@test "R61: the router tells Claude what to do with each answer: Approve continues, Not yet asks what to change, own words are what to change" {
  local s
  s=$(approve_step)
  [[ "$s" == *"what to change"* ]]
  [[ "$s" == *"own words"* ]]
}

@test "R61: the prompts stay within their budgets: router 1,400 words, every skill 2,000, all prompts 16k tokens" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  local f total=0 w
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md; do
    w=$(wc -w < "$f"); total=$((total + w))
    [ "$w" -le 2000 ] || [ "$f" = "$ROUTER" ] || { echo "$f has $w words"; false; }
  done
  [ "$total" -le 11400 ]
}

@test "R61: the help lists the approval choice next to /vbw:approve" {
  grep -E '/vbw:approve' "$PLUGIN_ROOT/skills/help/SKILL.md" | grep -qi 'choice\|Enter'
}

@test "R61: docs/proof.md describes the choice, that Approve comes first so Enter approves, Not yet, own words, and that /vbw:approve still works" {
  local d="$REPO_ROOT/docs/proof.md"
  grep -q 'Approve' "$d"
  grep -q 'Not yet' "$d"
  grep -qi 'Enter' "$d"
  grep -qi 'own words' "$d"
  grep -q '/vbw:approve' "$d"
  grep -qi 'fingerprint' "$d"
}

@test "R61: docs/guards.md explains the answer hook and why the model cannot approve through it" {
  local d="$REPO_ROOT/docs/guards.md"
  grep -q 'AskUserQuestion' "$d"
  grep -qi 'PostToolUse' "$d"
  grep -qi 'cannot' "$d"
}

@test "R61: the README says approval is a choice where Enter approves, and /vbw:approve still works" {
  grep -qi 'Enter' "$REPO_ROOT/README.md"
  grep -q '/vbw:approve' "$REPO_ROOT/README.md"
}
