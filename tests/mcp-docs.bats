#!/usr/bin/env bats
# R241, R242 (#694, L1): docs/guards.md has one section on MCP tools for VBW's agents that
# says where the setting lives (record.settings.mcp, shared through the record), the exact
# command form, the read-only mark (a pure server in one word, a mixed server's tools by
# name), which roles get what, and that an MCP tool's writes are judged after the fact by
# the run's scope check ('changed X, which is not in the plan'), never before the call.
# docs/workflows.md's Agents section links to it.

load helper

GUARDS="$REPO_ROOT/docs/guards.md"
WORKFLOWS="$REPO_ROOT/docs/workflows.md"

section() { awk '/^## .*MCP/ { on = 1; print; next } /^## / { on = 0 } on' "$GUARDS"; }

@test "R241: docs/guards.md has an MCP section naming the setting's place, the command form and the read-only mark" {
  [ -n "$(section)" ] || { echo "docs/guards.md has no '## ... MCP ...' section"; false; }
  section | grep -q 'settings.mcp' || { echo "the section does not say the setting lives in record.settings.mcp"; false; }
  section | grep -q 'vbw config set mcp' || { echo "the section does not give the command"; false; }
  section | grep -q 'SERVER:read-only=TOOL' || { echo "the section does not give the mixed-server form"; false; }
  section | grep -qE 'SERVER:read-only([^=]|$)' || { echo "the section does not give the pure-server mark"; false; }
  section | grep -qi 'default' || { echo "the section does not say how the setting is removed"; false; }
}

@test "R242: the section says which roles get what, and that an MCP tool's writes are judged after the fact by the scope check, never before the call" {
  local role
  for role in Dev Debugger Docs Architect Lead Scout QA; do
    section | grep -q "$role" || { echo "the section does not name $role"; false; }
  done
  section | grep -qi 'never by a guess\|never guess' || { echo "the section does not say a reading role never gets a tool by a guess from its name"; false; }
  section | grep -qi 'after the fact' || { echo "the section does not say MCP writes are judged after the fact"; false; }
  section | grep -q 'which is not in the plan' || { echo "the section does not quote the scope check's words"; false; }
  section | grep -qi 'never before the call\|not before the call' || { echo "the section does not say the judgement is not before the call"; false; }
}

@test "R241: docs/workflows.md's Agents section links to the MCP section of docs/guards.md" {
  sed -n '/^## Agents/,/^## The project folder/p' "$WORKFLOWS" | grep -q 'MCP' || { echo "the Agents section does not mention MCP tools"; false; }
  sed -n '/^## Agents/,/^## The project folder/p' "$WORKFLOWS" | grep -q 'guards.md' || { echo "the Agents section does not link to docs/guards.md"; false; }
}
