#!/usr/bin/env bats
# R241 (#694, T207, D561, L1): the mechanism that gives VBW's agents MCP tools is chosen from a
# recorded probe of how Claude Code resolves a plugin agent's tools. tools/probe-mcp-tools.sh
# drives headless `claude -p` sessions with a probe plugin and a stdio MCP server, one case
# each: a whole server as mcp__<server>__*, one tool as mcp__<server>__<tool>, an entry naming
# a server that is not configured beside entries that resolve, the agent_type a PreToolUse
# hook sees, whether a workflow's agent() reaches an agent not the plugin's own, and, for
# D561 (no pool entry gives every MCP tool, so agents drop the tools: allowlist): an agent
# with tools: omitted inherits the session's MCP tools, disallowedTools is honoured by a
# plugin agent, a hook with the matcher omitted reaches every tool an agent calls, and which
# tools Claude Code gives every agent whatever its tools line. It writes
# tools/probes/mcp-tools.json; decision D561 in the record names the mechanism. These cases
# hold the script's shape and the committed result (L2 evidence, written by the run, never by
# hand); they run no Claude session.

load helper

SCRIPT="$REPO_ROOT/tools/probe-mcp-tools.sh"
RESULT="$REPO_ROOT/tools/probes/mcp-tools.json"
CASES='["server_wildcard", "single_tool", "unconfigured_beside", "agent_type", "foreign_agent", "inherit_omitted", "disallowed_honoured", "hook_every_tool"]'

@test "R241: the probe script exists, is executable, drives headless claude -p sessions and names its cases" {
  [ -x "$SCRIPT" ] || { echo "no executable tools/probe-mcp-tools.sh"; false; }
  grep -qE 'claude (-p|--print)' "$SCRIPT" || { echo "the probe does not drive claude -p"; false; }
  local case_
  for case_ in $(jq -rn --argjson c "$CASES" '$c[]'); do
    grep -q "$case_" "$SCRIPT" || { echo "the probe has no case $case_"; false; }
  done
  grep -q 'disallowedTools' "$SCRIPT" || { echo "the probe writes no agent with disallowedTools"; false; }
  grep -q 'tools/probes/mcp-tools.json' "$SCRIPT" || { echo "the probe does not name where it writes its result"; false; }
}

@test "R241: the committed probe result holds every case, Claude Code's version, and names decision D561, which the record holds" {
  [ -f "$RESULT" ] || { echo "the probe has not been run: no result at tools/probes/mcp-tools.json"; false; }
  jq -e --argjson c "$CASES" '.probe == "mcp-tools" and (.at | type == "string" and . >= "2026-11-01")
    and (.claude_version | type == "string" and length > 0)
    and (.cases | type == "object") and (.cases | keys as $k | $c | all(.[]; . as $n | $k | any(. == $n)))' "$RESULT" || { cat "$RESULT"; false; }
  jq -e '[.cases[] | (.tools_line | type == "string" and length > 0) and (.result | type == "string" and length > 0)] | all' "$RESULT" || { echo "a case lacks its tools_line or result"; cat "$RESULT"; false; }
  jq -e '.decision == "D561" and (.mechanism | type == "string" and test("disallowedTools"))' "$RESULT" || { jq '{decision, mechanism}' "$RESULT"; false; }
  jq -e '[.decisions[] | select(.id == "D561")] | length == 1 and (.[0].text | test("disallowedTools"))' "$REPO_ROOT/.vbw/record.json" > /dev/null \
    || { echo "the record holds no decision D561 on disallowedTools"; false; }
}

@test "R241: the result supports D561: tools omitted inherits the MCP tool, disallowedTools is honoured, an omitted matcher reaches every tool, and the hook's cost on a Read call is measured" {
  [ -f "$RESULT" ] || { echo "no probe result"; false; }
  jq -e '.cases.inherit_omitted.result // "" | contains("NOTE-TOKEN-7731")' "$RESULT" || { jq .cases.inherit_omitted "$RESULT"; false; }
  jq -e '.cases.disallowed_honoured | (.tools_line | test("disallowedTools")) and (.result | startswith("RESULT: NOT-WRITTEN"))' "$RESULT" || { jq .cases.disallowed_honoured "$RESULT"; false; }
  jq -e 'has("hook_matcher") and .hook_matcher == null and (.cases.hook_every_tool.result | startswith("RESULT: ALL"))' "$RESULT" || { jq '{hook_matcher, hook_every_tool: .cases.hook_every_tool}' "$RESULT"; false; }
  jq -e '(.builtins | type == "array" and (contains(["Read", "Bash", "Write", "Edit", "WebFetch", "WebSearch"])) and all(.[]; startswith("mcp__") | not) and all(.[]; test("^[A-Z][A-Za-z0-9]*$")))
    and (.always_allowed | type == "array" and all(.[]; type == "string" and (startswith("mcp__") | not)))
    and (.hook_read_cpu_ms | type == "number" and . > 0 and . <= 20)' "$RESULT" || { jq '{builtins, always_allowed, hook_read_cpu_ms}' "$RESULT"; false; }
}

@test "R241: the probe result names no MCP tool but the probe's own (D565: Grep and Glob may be absent; a machine's other servers and connectors stay out of the file)" {
  [ -f "$RESULT" ] || { echo "no probe result"; false; }
  jq -e '[.. | strings | scan("mcp__[A-Za-z0-9][A-Za-z0-9_.-]*?__") | select(test("^mcp__(probe|nosuch)__") | not)] | length == 0' "$RESULT" > /dev/null \
    || { jq '[.. | strings | scan("mcp__[A-Za-z0-9][A-Za-z0-9_.-]*?__") | select(test("^mcp__(probe|nosuch)__") | not)] | unique' "$RESULT"; false; }
}
