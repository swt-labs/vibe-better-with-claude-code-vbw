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
# Writes tools/probes/mcp-tools.json {probe, at, claude_version, cases, tools_entry,
# mechanism, decision}; the decision id is added by hand after `vbw decide`.
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
    const r = await agent('Reply with one short line: your agent type and the word REACHED.', { agentType: type, label: type })
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

agent_file() { # TOOLS_LINE
  cat > "$work/plugin/agents/reader.md" << EOF
---
name: reader
description: Probe agent. Calls the probe MCP server's read_note and reports what came back.
tools: $1
---
Call the tool whose name ends in read_note (server probe) once, with no arguments. Reply with one line: RESULT: followed by the tool's exact text, or RESULT: NO-TOOL followed by the names of every tool you do have.
EOF
}

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
  jq -r '.result // "no result"' "$work/out/$name.json" 2> /dev/null || echo "no result"
}

ask_reader="Use the Agent tool once with subagent_type mcpprobe:reader and the prompt: call read_note and report the tool result. Then reply with that agent's reply, verbatim, on one line."

cases='{}'
add() { # NAME TOOLS_LINE RESULT
  cases=$(printf '%s' "$cases" | jq -c --arg n "$1" --arg t "$2" --arg r "$3" '. + {($n): {tools_line: $t, result: $r}}')
  printf '%-20s %-48s %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 140 | tr '\n' ' ')" >&2
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
agent_file 'Read, mcp__probe__*'
r=$(session foreign_agent "Call the Workflow tool with name wfprobe:foreign. Wait for it to finish, then reply with its returned result as JSON, verbatim." "$work/wf" "$work/vbw" "$work/plugin")
add foreign_agent 'Read, mcp__probe__*' "$r"

# ---- the verdicts, read from the sessions' words ----
honoured() { printf '%s' "$cases" | jq -e --arg n "$1" '.[$n].result | contains("NOTE-TOKEN-7731")' > /dev/null; }
entry=''
for c in all_servers_pool pool_double_star pool_dot_star; do
  if [ -z "$entry" ] && honoured "$c"; then entry=$(printf '%s' "$cases" | jq -r --arg n "$c" '.[$n].tools_line | split(", ") | last'); fi
done
if [ -n "$entry" ]; then mechanism='tools pool entry in every agent plus the MCP guard by role from record.settings.mcp'
else
  entry='mcp__<server>__*'
  mechanism='none: no tools-line form gave a pool of every MCP tool; only a whole named server (mcp__<server>__*) or one tool resolves'
fi

version=$(claude --version | head -1)
mkdir -p "$here/tools/probes"
jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg v "$version" --argjson c "$cases" --arg e "$entry" --arg m "$mechanism" \
  '{probe: "mcp-tools", at: $at, claude_version: $v, cases: $c, tools_entry: $e, mechanism: $m, decision: null}' \
  > "$here/tools/probes/mcp-tools.json"
echo "wrote tools/probes/mcp-tools.json" >&2
