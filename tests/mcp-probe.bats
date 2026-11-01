#!/usr/bin/env bats
# R241 (#694, T207, L1): the mechanism that gives VBW's agents MCP tools is chosen from a
# recorded probe of how Claude Code resolves a plugin agent's `tools:` list with mcp__
# names. tools/probe-mcp-tools.sh drives headless `claude -p` sessions with a probe plugin
# and a stdio MCP server, one case each: a whole server as mcp__<server>__*, one tool as
# mcp__<server>__<tool>, an entry naming a server that is not configured beside entries that
# resolve, the agent_type a PreToolUse hook sees for an agent started as vbw:<role>, and
# whether a workflow's agent() call with agentType vbw:<role> can reach any agent but the
# plugin's own. It writes tools/probes/mcp-tools.json; a decision in the record names the
# script, its output and the mechanism chosen, with why the alternatives were not taken.
# These cases hold the script's shape and the committed result (L2 evidence, written by the
# run, never by hand); they run no Claude session.

load helper

SCRIPT="$REPO_ROOT/tools/probe-mcp-tools.sh"
RESULT="$REPO_ROOT/tools/probes/mcp-tools.json"

@test "R241: the probe script exists, is executable, drives headless claude -p sessions and names its five cases" {
  [ -x "$SCRIPT" ] || { echo "no executable tools/probe-mcp-tools.sh"; false; }
  grep -qE 'claude (-p|--print)' "$SCRIPT" || { echo "the probe does not drive claude -p"; false; }
  local case_
  for case_ in server_wildcard single_tool unconfigured_beside agent_type foreign_agent; do
    grep -q "$case_" "$SCRIPT" || { echo "the probe has no case $case_"; false; }
  done
  grep -q 'mcp__' "$SCRIPT"
  grep -q 'tools/probes/mcp-tools.json' "$SCRIPT" || { echo "the probe does not name where it writes its result"; false; }
}

@test "R241: the committed probe result holds the five cases, Claude Code's version, the tools entry and the mechanism chosen, with its decision" {
  [ -f "$RESULT" ] || { echo "the probe has not been run: no result at tools/probes/mcp-tools.json"; false; }
  jq -e '.probe == "mcp-tools" and (.at | type == "string" and . >= "2026-11-01")
    and (.claude_version | type == "string" and length > 0)
    and (.cases | type == "object")
    and ([.cases | keys[]] | contains(["server_wildcard", "single_tool", "unconfigured_beside", "agent_type", "foreign_agent"]))' "$RESULT" || { cat "$RESULT"; false; }
  jq -e '[.cases[] | (.tools_line | type == "string" and length > 0) and (.result | type == "string" and length > 0)] | all' "$RESULT" || { echo "a case lacks its tools_line or result"; cat "$RESULT"; false; }
  jq -e '(.tools_entry | type == "string" and startswith("mcp__"))
    and (.mechanism | type == "string" and length > 0)
    and (.decision | test("^D[0-9]+$"))' "$RESULT" || { cat "$RESULT"; false; }
}
