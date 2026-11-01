#!/usr/bin/env bats
# R242 (#694, L1): the MCP guard (plugin/hooks/guard-mcp.jq, PreToolUse on mcp__ tools)
# gives VBW's agents the project's named MCP tools by role, from record.settings.mcp
# (D555, D556): Dev, Debugger and Docs may call every named tool; Architect, Lead, Scout
# and QA only a tool the user marked read-only (its server as a whole, or the tool by name),
# never by a guess from its name. A refusal names the agent's role and `vbw config set mcp`
# as the next step. The main session is never judged, nor an agent that is not VBW's, and
# outside a VBW project the hook is inert. Fixtures: a pure server (github, marked read-only
# as a whole), a mixed server (ctx: read-only tools search and get_context) and a server
# named without a mark (playwright: writers only).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

# mcp_setting JSON: the record holds the MCP setting as vbw config set mcp stores it.
mcp_setting() {
  jq --argjson m "$1" '.settings.mcp = $m' .vbw/record.json > "$TEST_ROOT/m.json" && cp "$TEST_ROOT/m.json" .vbw/record.json
}
FULL='[{"server": "github", "read_only": true}, {"server": "ctx", "read_only": ["search", "get_context"]}, {"server": "playwright", "read_only": false}]'

# mcp_call TOOL [AGENT_TYPE] [PROJECT_DIR]: the guard's decision on an MCP tool call.
mcp_call() {
  local t="$1" a="${2:-}" d="${3:-$PROJECT}"
  jq -nc --arg t "$t" --arg a "$a" --arg d "$d" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: $d, tool_input: {query: "x"}}
     + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)' \
    | HOOK_PROJECT_DIR="$d" vbw_hook PreToolUse "$t"
}
# reason TOOL [AGENT_TYPE] [PROJECT_DIR]: the refusal's reason, or "allow".
reason() { mcp_call "$@" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'; }
# names_role REASON ROLE: the reason names the role as a word.
names_role() { printf '%s\n' "$1" | grep -qE "(^|[^a-z])$2([^a-z]|$)"; }

@test "R242: with no MCP setting, every agent's MCP call is refused: the effective tool set is today's, and the refusal names the role and vbw config set mcp" {
  local role r
  for role in architect lead dev qa scout debugger docs; do
    r=$(reason mcp__github__get_issue "vbw:$role")
    [ "$r" != allow ] || { echo "allowed with no setting: $role"; false; }
    names_role "$r" "$role" || { echo "the refusal does not name the role $role: $r"; false; }
    [[ "$r" == *"vbw config set mcp"* && "$r" == *"Next:"* ]] || { echo "the refusal does not give vbw config set mcp as the next step: $r"; false; }
  done
}

@test "R242: a server the setting names without a mark is open to Dev, Debugger and Docs and closed to Architect, Lead, Scout and QA" {
  mcp_setting "$FULL"
  local role r
  for role in dev debugger docs; do
    [ "$(reason mcp__playwright__click "vbw:$role")" = allow ] || { echo "refused for the writing role $role: $(reason mcp__playwright__click "vbw:$role")"; false; }
  done
  for role in architect lead scout qa; do
    r=$(reason mcp__playwright__click "vbw:$role")
    [ "$r" != allow ] || { echo "allowed for the reading role $role"; false; }
    names_role "$r" "$role" || { echo "the refusal does not name the role $role: $r"; false; }
    [[ "$r" == *"read-only"* && "$r" == *"vbw config set mcp"* ]] || { echo "the refusal does not say the tool is not marked read-only, with vbw config set mcp next: $r"; false; }
  done
}

@test "R242: a pure server marked read-only as a whole is open to every role" {
  mcp_setting "$FULL"
  local role
  for role in architect lead dev qa scout debugger docs; do
    [ "$(reason mcp__github__get_issue "vbw:$role")" = allow ] || { echo "refused: $role on the read-only server: $(reason mcp__github__get_issue "vbw:$role")"; false; }
    [ "$(reason mcp__github__create_issue "vbw:$role")" = allow ] || { echo "the whole-server mark does not cover every tool for $role"; false; }
  done
}

@test "R242: a mixed server opens only its listed read-only tools to the reading roles; its other tools stay the writers'" {
  mcp_setting "$FULL"
  local role r
  for role in architect lead scout qa; do
    [ "$(reason mcp__ctx__search "vbw:$role")" = allow ] || { echo "a listed read-only tool refused for $role"; false; }
    [ "$(reason mcp__ctx__get_context "vbw:$role")" = allow ] || { echo "a listed read-only tool refused for $role"; false; }
    r=$(reason mcp__ctx__run_command "vbw:$role")
    [ "$r" != allow ] || { echo "an unlisted tool of the mixed server allowed for $role"; false; }
    names_role "$r" "$role" && [[ "$r" == *"vbw config set mcp"* ]] || { echo "$r"; false; }
  done
  for role in dev debugger docs; do
    [ "$(reason mcp__ctx__run_command "vbw:$role")" = allow ] || { echo "the mixed server's writing tool refused for $role"; false; }
  done
}

@test "R242: a tool whose name suggests reading (read_*, get_*, search_*) but carries no mark is refused for the reading roles: never a guess from the name" {
  mcp_setting "$FULL"
  local tool role r
  for tool in mcp__playwright__read_page mcp__playwright__get_text mcp__playwright__search_dom mcp__ctx__read_file mcp__ctx__get_output mcp__ctx__search_output; do
    for role in architect lead scout qa; do
      r=$(reason "$tool" "vbw:$role")
      [ "$r" != allow ] || { echo "guessed from the name: $tool allowed for $role"; false; }
      [[ "$r" == *"vbw config set mcp"* ]] || { echo "$r"; false; }
    done
  done
}

@test "R242: a server the setting does not name is refused for every role, naming the server and the setting as the next step" {
  mcp_setting "$FULL"
  local role r
  for role in architect lead dev qa scout debugger docs; do
    r=$(reason mcp__memory__create_entities "vbw:$role")
    [ "$r" != allow ] || { echo "an unnamed server allowed for $role"; false; }
    [[ "$r" == *"memory"* && "$r" == *"vbw config set mcp"* ]] || { echo "$r"; false; }
  done
  # The server name is matched whole: a server named 'git' does not open 'github'.
  mcp_setting '[{"server": "git", "read_only": true}]'
  [ "$(reason mcp__github__get_issue vbw:qa)" != allow ] || { echo "a server prefix opened another server"; false; }
}

@test "R242: the main session and an agent that is not VBW's are never judged, and outside a VBW project the hook is inert" {
  mcp_setting "$FULL"
  run mcp_call mcp__playwright__click
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the main session was judged: $output"; false; }
  run mcp_call mcp__playwright__click "my-plugin:reviewer"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "another plugin's agent was judged: $output"; false; }
  run mcp_call mcp__playwright__click "qa"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "an agent named like a role but not VBW's was judged: $output"; false; }
  mkdir -p "$TEST_ROOT/plain" && git -C "$TEST_ROOT/plain" init -q
  run mcp_call mcp__playwright__click vbw:qa "$TEST_ROOT/plain"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the hook answered outside a VBW project: $output"; false; }
}

@test "R242: the hook is a PreToolUse entry on mcp__ tools in hooks.json, runs jq itself, and the bench measures it as its own guard case" {
  jq -e '[.hooks.PreToolUse[] | select(.matcher | test("mcp__"))] | length == 1' "$PLUGIN_ROOT/hooks/hooks.json" > /dev/null || { echo "hooks.json has no PreToolUse entry for mcp__ tools"; false; }
  jq -r '.hooks.PreToolUse[] | select(.matcher | test("mcp__")) | .hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json" | grep -q 'hooks/guard-mcp.jq' || { echo "the mcp__ entry does not run guard-mcp.jq"; false; }
  run env VBW_BENCH_ONLY='guard (nosuchcase' bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 2 ] || { echo "the bench did not list its cases for an unknown selector:"; echo "$output"; false; }
  [[ "$output" == *"guard (mcp)"* ]] || { echo "the bench has no 'guard (mcp)' case:"; echo "$output"; false; }
}
