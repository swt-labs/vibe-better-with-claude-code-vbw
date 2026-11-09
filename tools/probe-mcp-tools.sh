#!/usr/bin/env bash
# probe-mcp-tools.sh: how does Claude Code give a plugin agent MCP tools? (R241, #694, T207)
# Evidence level L2: a script drives headless `claude -p` sessions; Claude Code stands in
# for nothing a user does. Fixture: a throwaway plugin (one agent, reader.md, whose tools
# line changes per case; a PreToolUse hook that logs the hook input's agent_type) and a tiny
# stdio MCP server (read_note, write_note) registered in a scratch .mcp.json as "probe".
# Cases (one claude -p session each, asked to call read_note and report the tool result):
#   server_wildcard      tools: Read, mcp__probe__*
#   single_tool          tools: Read, mcp__probe__read_note
#   unconfigured_beside  tools: Read, mcp__nosuch__*, mcp__probe__*
#   all_servers_pool     tools: Read, mcp__*        (the pool entry the mechanism needs)
#   pool_double_star     tools: Read, mcp__*__*     (other forms of a pool of every MCP tool)
#   pool_dot_star        tools: Read, mcp__.*
#   agent_type           what a hook saw for an agent started as <plugin>:reader
#   foreign_agent        a Dynamic workflow of a second plugin calling agent() with
#                        agentType vbw:dev (a stub plugin named vbw) and <plugin>:reader
#                        (the reader call passes a schema, so the log shows the tool Claude
#                        Code gives a schema-returning agent)
#   inherit_omitted      no tools: line; asked to call read_note and list every tool it has
#   disallowed_honoured  no tools: line, disallowedTools: Write, Edit, NotebookEdit, Bash;
#                        asked to create proj/probe-written.txt with the Write tool
#   toolsearch_disallowed  no tools: line, disallowedTools: ToolSearch; the hook logs show whether
#                        the MCP schema was deferred (ToolSearch called first) or loaded up front
#   hook_every_tool      the probe plugin's PreToolUse entry has no matcher; an agent with
#                        tools omitted calls Read, Bash and read_note; the hook log must hold all
# Writes tools/probes/mcp-tools.json {probe, at, claude_version, cases, builtins,
# always_allowed, hook_matcher, hook_read_cpu_ms, mechanism, decision}. Only built-in tools
# and the probe server's own tools reach the file: other MCP tool names are scrubbed (D565).
# Usage: bash tools/probe-mcp-tools.sh [--model MODEL]   (default sonnet)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
model=sonnet
if [ "${1:-}" = "--model" ]; then model="${2:?usage: probe-mcp-tools.sh [--model MODEL]}"; fi
command -v claude > /dev/null || { echo "vbw: claude is not installed" >&2; exit 1; }
command -v node > /dev/null || { echo "vbw: node is needed for the probe's MCP server" >&2; exit 1; }

work="$here/.vbw/runtime/scratch/probe-mcp-tools"
rm -rf "$work"
mkdir -p "$work/plugin/.claude-plugin" "$work/plugin/agents" "$work/plugin/hooks" \
  "$work/wf/.claude-plugin" "$work/wf/workflows" \
  "$work/vbw/.claude-plugin" "$work/vbw/agents" "$work/proj" "$work/out"
hooklog="$work/hook.log"

# ---- the fixture ----
cat > "$work/plugin/.claude-plugin/plugin.json" << 'EOF'
{"name": "mcpprobe", "version": "0.0.1", "description": "throwaway probe plugin"}
EOF
cat > "$work/plugin/hooks/hooks.json" << 'EOF'
{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/log.sh\""}]}]}}
EOF
cat > "$work/plugin/hooks/log.sh" << EOF
#!/usr/bin/env bash
jq -c '{tool: .tool_name, agent_type: (.agent_type // null)}' >> "$hooklog"
exit 0
EOF
cat > "$work/wf/.claude-plugin/plugin.json" << 'EOF'
{"name": "wfprobe", "version": "0.0.1", "description": "throwaway workflow probe plugin"}
EOF
cat > "$work/vbw/.claude-plugin/plugin.json" << 'EOF'
{"name": "vbw", "version": "0.0.1", "description": "stub standing in for VBW's own plugin"}
EOF
cat > "$work/vbw/agents/dev.md" << 'EOF'
---
name: dev
description: Stub agent for the probe.
tools: Read
---
Reply with the single word STUB-DEV and nothing else.
EOF
cat > "$work/wf/workflows/foreign.js" << 'EOF'
export const meta = {
  name: 'foreign',
  description: 'Probe: which agents can a workflow of this plugin reach',
  whenToUse: 'Only the probe runs this',
  phases: [{ title: 'Probe', detail: 'two agent() calls' }],
}
const out = {}
for (const type of ['vbw:dev', 'mcpprobe:reader']) {
  try {
    const opts = { agentType: type, label: type }
    if (type === 'mcpprobe:reader') opts.schema = { type: 'object', properties: { line: { type: 'string' } }, required: ['line'] }
    const r = await agent('Reply with one short line: your agent type and the word REACHED.', opts)
    out[type] = 'reached: ' + String(typeof r === 'string' ? r : JSON.stringify(r)).slice(0, 200)
  } catch (e) {
    out[type] = 'refused: ' + String(e && e.message ? e.message : e).slice(0, 300)
  }
}
return out
EOF
cat > "$work/server.mjs" << 'EOF'
import { createInterface } from 'node:readline'
const send = m => process.stdout.write(JSON.stringify(m) + '\n')
const tools = [
  { name: 'read_note', description: 'Read the probe note', inputSchema: { type: 'object', properties: {} } },
  { name: 'write_note', description: 'Write the probe note', inputSchema: { type: 'object', properties: { text: { type: 'string' } } } },
]
createInterface({ input: process.stdin }).on('line', line => {
  let m
  try { m = JSON.parse(line) } catch { return }
  if (m.id === undefined) return
  if (m.method === 'initialize') send({ jsonrpc: '2.0', id: m.id, result: { protocolVersion: m.params.protocolVersion, capabilities: { tools: {} }, serverInfo: { name: 'probe', version: '0.0.1' } } })
  else if (m.method === 'tools/list') send({ jsonrpc: '2.0', id: m.id, result: { tools } })
  else if (m.method === 'tools/call') send({ jsonrpc: '2.0', id: m.id, result: { content: [{ type: 'text', text: m.params.name === 'read_note' ? 'NOTE-TOKEN-7731' : 'written' }] } })
  else send({ jsonrpc: '2.0', id: m.id, result: {} })
})
EOF
cat > "$work/proj/.mcp.json" << EOF
{"mcpServers": {"probe": {"command": "node", "args": ["$work/server.mjs"]}}}
EOF
settings='{"enabledPlugins":{"vbw@vbw-marketplace":false},"enableWorkflows":true,"enableAllProjectMcpServers":true}'

reader_body="Call the tool whose name ends in read_note (server probe) once, with no arguments. Reply with one line: RESULT: followed by the tool's exact text, or RESULT: NO-TOOL followed by the names of every tool you do have."
agent_file() { # TOOLS_LINE (empty: no tools: line) [EXTRA-FRONTMATTER-LINE [BODY]]
  {
    printf -- '---\nname: reader\ndescription: Probe agent. Calls the probe MCP server and reports what came back.\n'
    if [ -n "$1" ]; then printf 'tools: %s\n' "$1"; fi
    if [ -n "${2:-}" ]; then printf '%s\n' "$2"; fi
    printf -- '---\n%s\n' "${3:-$reader_body}"
  } > "$work/plugin/agents/reader.md"
}

# scrub: keep the probe server's tools (and the unconfigured nosuch entry) but no other MCP tool
# name, so a machine's other servers and claude.ai connectors never reach the committed file.
scrub() { perl -pe 's/mcp__(?!probe__|nosuch__)[A-Za-z0-9_.-]+/<other-mcp-tool>/g'; }

# session NAME PROMPT [PLUGIN-DIR...]: one headless session in the scratch project; prints the reply.
session() {
  local name="$1" prompt="$2" d; local -a dirs=()
  shift 2
  for d in "$@"; do dirs+=(--plugin-dir "$d"); done
  # The prompt goes in on stdin: --plugin-dir and --allowedTools take several values and would swallow it.
  printf '%s\n' "$prompt" > "$work/out/$name.prompt"
  (cd "$work/proj" && claude -p --model "$model" --permission-mode auto --max-turns 12 ${dirs[@]+"${dirs[@]}"} \
    --settings "$settings" --allowedTools "Agent,Task,Workflow,mcp__probe__*" \
    --output-format json < "$work/out/$name.prompt" > "$work/out/$name.json" 2> "$work/out/$name.err") || true
  cp "$hooklog" "$work/out/$name.hooks" 2> /dev/null || true
  jq -r '.result // "no result"' "$work/out/$name.json" 2> /dev/null || echo "no result"
}

ask_reader="Use the Agent tool once with subagent_type mcpprobe:reader and the prompt: call read_note and report the tool result. Then reply with that agent's reply, verbatim, on one line."

cases='{}'
add() { # NAME TOOLS_LINE RESULT
  local r
  r=$(printf '%s' "$3" | scrub)
  cases=$(printf '%s' "$cases" | jq -c --arg n "$1" --arg t "$2" --arg r "$r" '. + {($n): {tools_line: $t, result: $r}}')
  printf '%-20s %-48s %s\n' "$1" "$2" "$(printf '%s' "$r" | head -c 140 | tr '\n' ' ')" >&2
}
run_tools_case() { # NAME TOOLS_LINE
  local r
  agent_file "$2"
  : > "$hooklog"
  r=$(session "$1" "$ask_reader" "$work/plugin")
  add "$1" "$2" "$r"
}

run_tools_case server_wildcard 'Read, mcp__probe__*'
run_tools_case single_tool 'Read, mcp__probe__read_note'
run_tools_case unconfigured_beside 'Read, mcp__nosuch__*, mcp__probe__*'
run_tools_case all_servers_pool 'Read, mcp__*'
run_tools_case pool_double_star 'Read, mcp__*__*'
run_tools_case pool_dot_star 'Read, mcp__.*'

# agent_type: the last case's hook log, read per call (a fresh run with the pool line).
agent_file 'Read, mcp__probe__*'
: > "$hooklog"
session agent_type "$ask_reader" "$work/plugin" > /dev/null
seen=$(jq -rs '[.[] | select(.tool | test("read_note"))] | map(.agent_type) | unique | join(",")' "$hooklog" 2> /dev/null || true)
allseen=$(jq -rs 'map("\(.tool)=\(.agent_type)") | join("; ")' "$hooklog" 2> /dev/null || true)
add agent_type 'Read, mcp__probe__*' "hook agent_type for the read_note call: ${seen:-none}; every call: ${allseen:-none}"

# foreign_agent: a workflow of the second plugin, a stub plugin named vbw, and the probe plugin.
# The workflow's reader call passes a schema; the hook log shows the tool that agent is given.
agent_file 'Read, mcp__probe__*'
: > "$hooklog"
r=$(session foreign_agent "Call the Workflow tool with name wfprobe:foreign. Wait for it to finish, then reply with its returned result as JSON, verbatim." "$work/wf" "$work/vbw" "$work/plugin")
add foreign_agent 'Read, mcp__probe__*' "$r"

# inherit_omitted: no tools: line. Does the agent get the session's MCP tool, and which tools does it list?
agent_file '' '' "Call the tool whose name ends in read_note (server probe) once, with no arguments. Then reply with one line: RESULT: followed by the tool's exact text, or RESULT: NO-TOOL if you could not call it; then on the same line TOOLS: followed by the exact names of every tool you have, separated by commas, including tools listed as deferred or not yet loaded, by name."
: > "$hooklog"
r=$(session inherit_omitted "$ask_reader" "$work/plugin")
inherit_raw="$r"
add inherit_omitted '(no tools: line)' "$r"

# disallowed_honoured: no tools: line, disallowedTools names the writers; asked to write a file.
agent_file '' 'disallowedTools: Write, Edit, NotebookEdit, Bash' "Create the file proj/probe-written.txt containing the word hello, using the Write tool. Reply with one line: RESULT: WRITTEN if you wrote it, or RESULT: NOT-WRITTEN followed by why not."
rm -f "$work/proj/probe-written.txt" "$work/proj/proj/probe-written.txt"
: > "$hooklog"
r=$(session disallowed_honoured "Use the Agent tool once with subagent_type mcpprobe:reader and the prompt: create the file proj/probe-written.txt with the Write tool. Then reply with that agent's reply, verbatim, on one line." "$work/plugin")
writes=$(jq -rs '[.[] | select(.agent_type == "mcpprobe:reader" and (.tool | IN("Write", "Edit", "NotebookEdit")))] | length' "$hooklog" 2> /dev/null || echo 1)
if [ ! -e "$work/proj/probe-written.txt" ] && [ ! -e "$work/proj/proj/probe-written.txt" ] && [ "$writes" = 0 ]; then
  add disallowed_honoured 'disallowedTools: Write, Edit, NotebookEdit, Bash' "RESULT: NOT-WRITTEN ${r:-no reply}"
else
  add disallowed_honoured 'disallowedTools: Write, Edit, NotebookEdit, Bash' "RESULT: WRITTEN file present: $([ -e "$work/proj/probe-written.txt" ] && echo yes || echo no); agent write calls: $writes; reply: ${r:-no reply}"
fi

# toolsearch_disallowed: inherit_omitted's agent with disallowedTools: ToolSearch. The measure is
# the agent's first-turn input tokens from its transcript, not what the agent says or calls:
# without ToolSearch Claude Code cannot defer tools, so every inherited MCP schema loads up front.
# The size depends on the host's MCP servers; the claim is only that without exceeds with.
agent_file '' 'disallowedTools: ToolSearch' "Call the tool whose name ends in read_note (server probe) once, with no arguments. Then reply with one line: RESULT: followed by the tool's exact text, or RESULT: NO-TOOL if you could not call it."
: > "$hooklog"
r=$(session toolsearch_disallowed "$ask_reader" "$work/plugin")
add toolsearch_disallowed 'disallowedTools: ToolSearch' "$r"
# first_turn NAME: the probe agent's first-turn input tokens (uncached, cache written, cache read)
# in that case's session, from its subagent transcript under the Claude config dir; 0 if none.
first_turn() {
  local sid dir
  sid=$(jq -r '.session_id // empty' "$work/out/$1.json" 2> /dev/null || true)
  dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$work/proj" | tr '/.' '--')/$sid/subagents"
  [ -n "$sid" ] && [ -d "$dir" ] || { echo 0; return; }
  find "$dir" -name 'agent-*.jsonl' -print0 | xargs -0 cat | jq -s '[.[] | select(.type == "assistant") | .message.usage
    | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)][0] // 0'
}
deferral=$(jq -nc --argjson w "$(first_turn inherit_omitted)" --argjson o "$(first_turn toolsearch_disallowed)" \
  '{first_turn_input_tokens_with_toolsearch: $w, first_turn_input_tokens_without_toolsearch: $o,
    without_exceeds_with: ($w > 0 and $o > $w),
    note: "same agent and prompt; the sizes depend on the MCP servers of the machine that ran the probe"}')
printf '%-20s %s\n' deferral "$deferral" >&2

# hook_every_tool: the probe plugin's PreToolUse entry has no matcher; an agent with tools omitted
# calls Read, Bash and read_note; the log must hold each with agent_type mcpprobe:reader.
agent_file '' '' "Do three things in order: use the Read tool on the file .mcp.json; use the Bash tool to run: echo bash-ran; call the tool whose name ends in read_note (server probe). Then reply with one line: RESULT: DONE."
: > "$hooklog"
session hook_every_tool "Use the Agent tool once with subagent_type mcpprobe:reader and the prompt: read .mcp.json, run echo bash-ran with Bash, and call read_note. Then reply with that agent's reply, verbatim." "$work/plugin" > /dev/null
got=$(jq -rs '[.[] | select(.agent_type == "mcpprobe:reader" and (.tool | IN("Read", "Bash", "mcp__probe__read_note"))) | "\(.tool)=\(.agent_type)"] | unique | join(", ")' "$hooklog" 2> /dev/null || true)
missing=$(jq -rs '. as $l | [("Read", "Bash", "mcp__probe__read_note") | select(. as $t | $l | any(.[]; .tool == $t and .agent_type == "mcpprobe:reader") | not)] | join(", ")' "$hooklog" 2> /dev/null || echo "log unreadable")
if [ -z "$missing" ]; then add hook_every_tool '(no tools: line; hook matcher omitted)' "RESULT: ALL $got"
else add hook_every_tool '(no tools: line; hook matcher omitted)' "RESULT: MISSED $missing (seen: ${got:-none})"; fi

# ---- the verdicts, read from the sessions' words ----
every=$(printf '%s' "$cases" | jq -r '.hook_every_tool.result | startswith("RESULT: ALL")')
if [ "$every" = true ]; then matcher=null; else matcher='"set"'; fi

# builtins: the tool names (never mcp__, one name each, deferred ones included) inherit_omitted's agent listed.
builtins=$(printf '%s' "$inherit_raw" | jq -Rsc '[capture("TOOLS:(?<t>.*)"; "s").t | split(",")[] | sub("^.*: "; "") | gsub("^[ `\"(]+|[ `\".)]+$"; "") | select(test("^[A-Z][A-Za-z0-9]*$"))] | unique' 2> /dev/null || echo '[]')
[ -n "$builtins" ] || builtins='[]'

# always_allowed: every tool other than Read that an agent with 'tools: Read ...' or the
# schema-returning agent called (hook log) or listed (NO-TOOL replies), no MCP tool.
{ for n in server_wildcard single_tool unconfigured_beside all_servers_pool pool_double_star pool_dot_star agent_type foreign_agent; do
    [ -f "$work/out/$n.hooks" ] && jq -r 'select(.agent_type != null) | .tool' "$work/out/$n.hooks"
  done
  printf '%s' "$cases" | jq -r '.[] | .result | select(contains("NO-TOOL")) | sub(".*NO-TOOL"; "") | split(",")[]'
} 2> /dev/null | tr -d ' `".' | grep -vx 'Read' | grep -v '^$' | grep -v '^mcp__' | sort -u > "$work/always.txt" || true
always=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$work/always.txt")

# hook_read_cpu_ms: CPU ms per call over 100 runs (sh and jq startup included, as
# tools/bench-hooks.sh's cpu_pair measures) of the main-session path: sh -c running a jq program
# that passes the hook input on only when agent_type matches a VBW agent, fed a Read input.
printf '%s\n' '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"README.md"},"session_id":"s"}' > "$work/read-input.json"
hookcmd="jq -c 'select((.agent_type // \"\") | test(\"^vbw:(architect|lead|dev|qa|scout|debugger|docs)\$\"))'"
runs=100
: > "$work/times.log"
for ((i = 0; i < runs; i++)); do
  times >> "$work/times.log"
  sh -c "$hookcmd" < "$work/read-input.json" > /dev/null 2>&1 || true
  times >> "$work/times.log"
done
cpu=$(awk -v runs="$runs" '
  function sec(s) { sub(/s$/, "", s); split(s, p, "m"); return p[1] * 60 + p[2] }
  NR % 2 == 0 { t[++n] = sec($1) + sec($2) }
  END { for (k = 1; k + 1 <= n; k += 2) sum += t[k + 1] - t[k]; printf "%.1f", sum * 1000 / runs }' "$work/times.log")

mechanism="D561: the agents drop the tools: allowlist and inherit the session's MCP tools; each names disallowedTools for the built-ins outside its role (honoured by a plugin agent); one PreToolUse tools guard, matcher omitted, sees every tool by agent_type and refuses what the role may not use"

version=$(claude --version | head -1)
mkdir -p "$here/tools/probes"
jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg v "$version" --argjson c "$cases" --argjson b "$builtins" --argjson a "$always" \
  --argjson m "$matcher" --argjson cpu "$cpu" --argjson def "$deferral" --arg mech "$mechanism" \
  '{probe: "mcp-tools", at: $at, claude_version: $v, cases: $c, builtins: $b, always_allowed: $a, hook_matcher: $m, deferral: $def, hook_read_cpu_ms: $cpu, mechanism: $mech, decision: "D561"}' \
  | jq --arg root "$here" --arg home "${HOME:-}" -f "$here/tools/mask-paths.jq" > "$here/tools/probes/mcp-tools.json"
echo "wrote tools/probes/mcp-tools.json" >&2
