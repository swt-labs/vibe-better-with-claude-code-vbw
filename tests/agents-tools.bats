#!/usr/bin/env bats
# R241 (#694, D561, L1): VBW's agents inherit the session's tools, MCP tools included, because
# no tools: pool entry gives every MCP tool (tools/probes/mcp-tools.json). So no agent file has
# a tools: allowlist; each names disallowedTools for every built-in tool the probe found
# outside its role (the read-only roles never get Write, Edit or NotebookEdit), and the tools
# guard (plugin/hooks/guard-tools.jq) refuses any call outside the role's own built-ins and
# the project's MCP setting. With no MCP setting each role's effective built-in tools are
# exactly today's: architect, qa: Read, Grep, Glob, Bash; lead: those plus Write, Edit,
# WebFetch; dev, debugger, docs: those plus Write, Edit; scout: those plus WebSearch,
# WebFetch. The guard's MCP judgement by role is tests/guard-tools.bats.

load helper
load fixture-helper

AGENTS="$PLUGIN_ROOT/agents"
PROBE="$REPO_ROOT/tools/probes/mcp-tools.json"
ROLES="architect lead dev qa scout debugger docs"

# own ROLE: today's built-in tools of the role, one per line.
own() {
  case "$1" in
    architect | qa) printf '%s\n' Read Grep Glob Bash ;;
    lead) printf '%s\n' Read Grep Glob Bash Write Edit WebFetch ;;
    dev | debugger | docs) printf '%s\n' Read Grep Glob Bash Write Edit ;;
    scout) printf '%s\n' Read Grep Glob Bash WebSearch WebFetch ;;
  esac
}
# front AGENT: the agent file's frontmatter.
front() { sed -n '2,/^---$/p' "$AGENTS/$1.md"; }
# disallowed AGENT: the agent's disallowedTools, one per line.
disallowed() { front "$1" | grep -m1 '^disallowedTools:' | sed 's/^disallowedTools: *//' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' || true; }

project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
setup_file() { fixture_build project project; }
setup() { fixture_copy project; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# answer TOOL ROLE: the tools guard's decision on vbw:ROLE calling TOOL ("allow" or the reason).
answer() {
  local cmd
  cmd=$(jq -r '[.hooks.PreToolUse[] | select(.hooks[0].command | contains("hooks/guard-tools.jq"))][0].hooks[0].command // empty' "$PLUGIN_ROOT/hooks/hooks.json")
  [ -n "$cmd" ] || { echo "no tools guard in hooks.json"; return 0; }
  jq -nc --arg t "$1" --arg a "vbw:$2" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: $d, tool_input: {}, agent_id: "a1", agent_type: $a}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJECT" sh -c "$cmd" \
    | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'
}

@test "R241: no agent file has a tools: allowlist and each names disallowedTools, so agents inherit the session's MCP tools" {
  local a
  for a in $ROLES; do
    ! front "$a" | grep -q '^tools:' || { echo "$a still has a tools: allowlist: $(front "$a" | grep '^tools:')"; false; }
    [ -n "$(disallowed "$a")" ] || { echo "$a names no disallowedTools"; false; }
  done
}

@test "R241: each agent's disallowedTools names every built-in the probe found outside its role and never one of its own; the read-only roles never get Write, Edit or NotebookEdit" {
  jq -e '(.builtins | type == "array") and (.always_allowed | type == "array")' "$PROBE" > /dev/null || { echo "the probe result at tools/probes/mcp-tools.json has no builtins and always_allowed lists"; false; }
  local a t
  for a in $ROLES; do
    for t in $(jq -r '.builtins[]' "$PROBE"); do
      if own "$a" | grep -qx "$t"; then
        ! disallowed "$a" | grep -qx "$t" || { echo "$a disallows its own tool $t"; false; }
      elif ! jq -e --arg t "$t" '.always_allowed | index($t)' "$PROBE" > /dev/null; then
        disallowed "$a" | grep -qx "$t" || { echo "$a does not disallow $t, a built-in outside its role"; false; }
      fi
    done
  done
  for a in architect qa scout; do
    for t in Write Edit NotebookEdit; do
      disallowed "$a" | grep -qx "$t" || { echo "the read-only $a does not disallow $t"; false; }
    done
  done
}

@test "R241: with no MCP setting the guard leaves every role exactly today's built-ins: its own are open, every other built-in the probe found is refused" {
  jq -e '(.builtins | type == "array") and (.always_allowed | type == "array")' "$PROBE" > /dev/null || { echo "the probe result at tools/probes/mcp-tools.json has no builtins and always_allowed lists"; false; }
  local a t r
  for a in $ROLES; do
    for t in $(own "$a"); do
      r=$(answer "$t" "$a")
      [ "$r" = allow ] || { echo "$a refused its own $t: $r"; false; }
    done
    for t in $(jq -r '(.builtins - .always_allowed)[]' "$PROBE"); do
      own "$a" | grep -qx "$t" && continue
      r=$(answer "$t" "$a")
      [ "$r" != allow ] || { echo "$a was given $t, which is not one of its tools today"; false; }
    done
  done
}
