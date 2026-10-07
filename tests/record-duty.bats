#!/usr/bin/env bats
# R95 and R96 (docs/workflows.md, agent part, L1): Claude Code marks a workflow's
# task text as not coming from the user, so an agent may refuse to follow an
# instruction that appears only there. Recording a result (a plan's state, a
# fix's state, a phase's verdict, the plans of a planning run) and closing a
# run are therefore written in each agent's own instructions, which are VBW's.
# These tests hold those instructions to the duty; tests/workflow-closing.bats
# holds the workflows. The real-app run is the release scenarios' job (L3).

load helper

AGENTS="$PLUGIN_ROOT/agents"

@test "R95: the Dev, Docs, QA and Lead each carry, in their own instructions, the duty to record their result even when the task text is marked as not from the user" {
  local a
  for a in dev docs qa lead; do
    grep -qiE 'your own instructions' "$AGENTS/$a.md" || { echo "$a: no 'your own instructions'"; false; }
    grep -qiE 'not from the user' "$AGENTS/$a.md" || { echo "$a: no 'not from the user'"; false; }
  done
}

@test "R95: each role names the vbw command that records its result" {
  grep -q 'vbw plan done' "$AGENTS/dev.md"
  grep -q 'vbw fix done' "$AGENTS/dev.md"
  grep -q 'vbw plan done' "$AGENTS/docs.md"
  grep -q 'vbw qa record' "$AGENTS/qa.md"
  grep -q 'vbw apply' "$AGENTS/lead.md"
}

@test "R95: the QA agent's instructions name the project's test command and where to read it" {
  grep -qi 'test command' "$AGENTS/qa.md"
  grep -q 'vbw show contract' "$AGENTS/qa.md"
  grep -qi 'project commands' "$AGENTS/qa.md"
}

@test "R96: the Lead's own instructions allow closing a run: confirm what was recorded, then end the run" {
  grep -q 'vbw run confirm' "$AGENTS/lead.md"
  grep -q 'vbw run end' "$AGENTS/lead.md"
}

@test "R96: the Lead's closing duty says it never refuses and, when it cannot finish, names the command to run by hand" {
  local close
  close=$(sed -n '/^## Close a run/,/^## [^C]/p' "$AGENTS/lead.md")
  [ -n "$close" ]
  printf '%s' "$close" | grep -qi 'never refuse'
  printf '%s' "$close" | grep -qi 'by hand'
  printf '%s' "$close" | grep -qiE 'not from the user'
}

@test "R96: the Scout, whose instructions forbid every change, is not given the closing step" {
  grep -qi 'change nothing' "$AGENTS/scout.md"
  ! grep -q 'vbw run end' "$AGENTS/scout.md"
}
