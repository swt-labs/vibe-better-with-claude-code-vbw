#!/usr/bin/env bats
# R242 (#694, D561, L1): the tools guard (plugin/hooks/guard-tools.jq, one PreToolUse entry with
# the matcher omitted, so it sees every tool a VBW agent calls) holds each VBW agent to its
# role's built-in tools and the project's MCP setting, record.settings.mcp (D555, D556): Dev,
# Debugger and Docs may call every named MCP tool; Architect, Lead, Scout and QA only a tool
# the user marked read-only (its server as a whole, or the tool by name), never by a guess
# from its name. A built-in outside the role, or a tool VBW does not know (one a Claude Code
# update adds), is refused, not leaked; the tools Claude Code gives every agent whatever its
# tools (tools/probes/mcp-tools.json, always_allowed) are never refused. A refusal names the
# agent's role and the next step. The main session is never judged, for any tool and whatever
# the record holds, nor an agent that is not VBW's, and outside a VBW project the hook is
# inert. Fixtures: a pure server (github, marked read-only as a whole), a mixed server (ctx:
# read-only tools search and get_context) and a server named without a mark (playwright:
# writers only).

load helper
load fixture-helper

PROBE="$REPO_ROOT/tools/probes/mcp-tools.json"

project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
setup_file() { fixture_build project project; }
setup() { fixture_copy project; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# mcp_setting VALUE: the project's MCP setting, set through the kernel (a schema-7 record).
mcp_setting() { "$VBW" config set mcp "$1" > /dev/null; }
FULL='github:read-only ctx:read-only=search,get_context playwright'

# tools_hook: the hooks.json command of the PreToolUse entry that runs guard-tools.jq.
tools_hook() { jq -r '[.hooks.PreToolUse[] | select(.hooks[0].command | contains("hooks/guard-tools.jq"))][0].hooks[0].command // empty' "$PLUGIN_ROOT/hooks/hooks.json"; }

# tool_call TOOL [AGENT_TYPE] [PROJECT_DIR]: the tools guard's answer on a call, run as
# Claude Code runs it (sh -c, the hook input on stdin).
tool_call() {
  local t="$1" a="${2:-}" d="${3:-$PROJECT}" cmd
  cmd=$(tools_hook)
  [ -n "$cmd" ] || { echo "no PreToolUse entry runs hooks/guard-tools.jq" >&2; return 3; }
  jq -nc --arg t "$t" --arg a "$a" --arg d "$d" \
    '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: $t, cwd: $d, tool_input: {query: "x", file_path: "README.md", command: "ls"}}
     + (if $a == "" then {} else {agent_id: "a1", agent_type: $a} end)' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$d" sh -c "$cmd"
}
# reason TOOL [AGENT_TYPE] [PROJECT_DIR]: the refusal's reason, "allow" for no answer, or why there is none.
reason() {
  local out
  out=$(tool_call "$@") || { echo "no tools guard"; return 0; }
  printf '%s' "$out" | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'
}
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
  mcp_setting 'git:read-only'
  [ "$(reason mcp__github__get_issue vbw:qa)" != allow ] || { echo "a server prefix opened another server"; false; }
}

@test "R242: a tool outside the role's own (another role's built-in, or one VBW does not know) is refused naming the role; the tools Claude Code gives every agent are never refused" {
  mcp_setting "$FULL"
  local pair tool role r
  for pair in Write:qa Edit:architect NotebookEdit:scout WebSearch:dev WebFetch:docs Agent:lead TodoWrite:debugger FutureTool:dev FutureTool:qa; do
    tool=${pair%%:*} role=${pair#*:}
    r=$(reason "$tool" "vbw:$role")
    [ "$r" != allow ] || { echo "$tool was given to the $role"; false; }
    names_role "$r" "$role" && [[ "$r" == *"$tool"* && "$r" == *"Next:"* ]] || { echo "the refusal of $tool for the $role does not name both, with a next step: $r"; false; }
  done
  [ -f "$PROBE" ] && jq -e '.always_allowed | type == "array"' "$PROBE" > /dev/null || { echo "the probe result has no always_allowed list"; false; }
  for tool in $(jq -r '.always_allowed[]' "$PROBE"); do
    for role in architect lead dev qa scout debugger docs; do
      [ "$(reason "$tool" "vbw:$role")" = allow ] || { echo "$tool, which Claude Code gives every agent, was refused for the $role"; false; }
    done
  done
}

@test "R242: the main session (any tool, even with a corrupt record) and an agent that is not VBW's are never judged, and outside a VBW project the hook is inert" {
  [ -n "$(tools_hook)" ] || { echo "no PreToolUse entry runs hooks/guard-tools.jq"; false; }
  mcp_setting "$FULL"
  local tool
  for tool in mcp__playwright__click Read Bash Write FutureTool; do
    run tool_call "$tool"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the main session's $tool was judged: $output"; false; }
  done
  run tool_call mcp__playwright__click "my-plugin:reviewer"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "another plugin's agent was judged: $output"; false; }
  run tool_call FutureTool "qa"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "an agent named like a role but not VBW's was judged: $output"; false; }
  printf '{not json' > .vbw/record.json
  for tool in Read mcp__playwright__click; do
    run tool_call "$tool"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "with a corrupt record the main session's $tool got an answer: $output"; false; }
  done
  # a run open and the record corrupt: the main session's call is still not blocked (the
  # hook command reads no project file for it)
  mkdir -p .vbw/runtime && : > .vbw/runtime/run-open
  run tool_call Read
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "with a run open and a corrupt record the main session was blocked ($status): $output"; false; }
  run tool_call Read "my-plugin:reviewer"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "with a run open and a corrupt record another plugin's agent was blocked ($status): $output"; false; }
  rm -f .vbw/runtime/run-open
  mkdir -p "$TEST_ROOT/plain" && git -C "$TEST_ROOT/plain" init -q
  run tool_call FutureTool vbw:qa "$TEST_ROOT/plain"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the hook answered outside a VBW project: $output"; false; }
}

@test "R242: the hook is one PreToolUse entry with the matcher omitted, as the probe showed reaches every tool, runs guard-tools.jq, and the bench measures it as its own guard cases" {
  jq -e '[.hooks.PreToolUse[] | select(.hooks[0].command | contains("hooks/guard-tools.jq"))] | length == 1 and (.[0] | has("matcher") | not)' "$PLUGIN_ROOT/hooks/hooks.json" > /dev/null \
    || { echo "hooks.json has not exactly one PreToolUse entry for guard-tools.jq with the matcher omitted"; false; }
  jq -e 'has("hook_matcher") and .hook_matcher == null' "$PROBE" > /dev/null || { echo "the probe did not show an omitted matcher reaching every tool"; false; }
  run env VBW_BENCH_ONLY='guard (nosuchcase' VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 2 ] || { echo "the bench did not list its cases for an unknown selector:"; echo "$output"; false; }
  [[ "$output" == *"guard (tools)"* && "$output" == *"guard (tools, main session)"* ]] || { echo "the bench has no 'guard (tools)' and 'guard (tools, main session)' cases:"; echo "$output"; false; }
}
