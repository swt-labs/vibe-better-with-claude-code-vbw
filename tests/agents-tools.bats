#!/usr/bin/env bats
# R241 (#694, L1): each agent's tools are pinned from plugin/agents/*.md. The built-in tools
# are exactly today's (architect, qa: Read, Grep, Glob, Bash; lead: those plus Write, Edit,
# WebFetch; dev, debugger, docs: those plus Write, Edit; scout: those plus WebSearch,
# WebFetch), so a change to any agent's tools fails here. Beside them every agent lists one
# MCP entry, the same in all seven: the pool the probe (tools/probes/mcp-tools.json,
# tools_entry) showed Claude Code honours in a plugin agent's tools list. Which of those
# tools an agent may call is the MCP guard's judgement by role (tests/guard-mcp.bats): with
# no setting every call is refused, so the effective tool set stays today's.

load helper

AGENTS="$PLUGIN_ROOT/agents"

# tools AGENT: the agent's tools, one per line, in the file's order.
tools() { grep -m1 '^tools:' "$AGENTS/$1.md" | sed 's/^tools: *//' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$'; }
builtin() { tools "$1" | grep -v '^mcp__'; }
mcp_entry() { tools "$1" | grep '^mcp__'; }

@test "R241: the built-in tools of every agent are exactly today's" {
  [ "$(builtin architect | tr '\n' ' ')" = "Read Grep Glob Bash " ] || { echo "architect: $(builtin architect | tr '\n' ' ')"; false; }
  [ "$(builtin qa | tr '\n' ' ')" = "Read Grep Glob Bash " ] || { echo "qa: $(builtin qa | tr '\n' ' ')"; false; }
  [ "$(builtin lead | tr '\n' ' ')" = "Read Grep Glob Bash Write Edit WebFetch " ] || { echo "lead: $(builtin lead | tr '\n' ' ')"; false; }
  local a
  for a in dev debugger docs; do
    [ "$(builtin "$a" | tr '\n' ' ')" = "Read Grep Glob Bash Write Edit " ] || { echo "$a: $(builtin "$a" | tr '\n' ' ')"; false; }
  done
  [ "$(builtin scout | tr '\n' ' ')" = "Read Grep Glob Bash WebSearch WebFetch " ] || { echo "scout: $(builtin scout | tr '\n' ' ')"; false; }
}

@test "R241: every agent lists exactly one MCP entry, the same in all seven, and it is the pool entry the probe showed Claude Code honours" {
  local a entry first=""
  for a in architect lead dev qa scout debugger docs; do
    entry=$(mcp_entry "$a")
    [ "$(printf '%s\n' "$entry" | grep -c .)" -eq 1 ] || { echo "$a lists $(printf '%s\n' "$entry" | grep -c .) MCP entries, not one: $(tools "$a" | tr '\n' ' ')"; false; }
    [ -z "$first" ] && first=$entry
    [ "$entry" = "$first" ] || { echo "$a's MCP entry ($entry) differs from architect's ($first)"; false; }
  done
  local probe="$REPO_ROOT/tools/probes/mcp-tools.json"
  [ -f "$probe" ] || { echo "no probe result at tools/probes/mcp-tools.json"; false; }
  [ "$(jq -r '.tools_entry' "$probe")" = "$first" ] || { echo "the agents list $first, the probe showed $(jq -r '.tools_entry' "$probe")"; false; }
}

@test "R241: no agent uses disallowedTools, so the pool is always the tools line and nothing leaks in with a Claude Code update" {
  ! grep -l '^disallowedTools:' "$AGENTS"/*.md || { echo "an agent uses disallowedTools"; false; }
}
