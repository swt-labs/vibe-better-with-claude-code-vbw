# PreToolUse guard for every tool a VBW agent calls (docs/guards.md; inputs in common.jq).
# One entry with the matcher omitted (tools/probes/mcp-tools.json, hook_matcher null: the
# hook reaches every tool an agent calls, D561). The agents drop the tools: allowlist so they
# inherit the session's MCP tools; this guard holds each role to its own built-in tools and
# the project's MCP setting (record.settings.mcp). Only VBW agents are judged; the hook
# command passes nothing on for the main session, which reads no project file.

include "common" {search: "./"};

# The tools Claude Code gives every agent whatever its tools (the probe's always_allowed,
# tools/probes/mcp-tools.json, written by tools/probe-mcp-tools.sh): never refused.
def always_allowed: "^(StructuredOutput|SubagentHandback)$";
def reading: "^(architect|lead|scout|qa)$";
def own_list: {
  architect: "Read, Grep, Glob, Bash",
  qa: "Read, Grep, Glob, Bash",
  lead: "Read, Grep, Glob, Bash, Write, Edit, WebFetch",
  dev: "Read, Grep, Glob, Bash, Write, Edit",
  debugger: "Read, Grep, Glob, Bash, Write, Edit",
  docs: "Read, Grep, Glob, Bash, Write, Edit",
  scout: "Read, Grep, Glob, Bash, WebSearch, WebFetch"
};
def entry_text: .server + (if .read_only == false then "" elif .read_only == true then ":read-only" else ":read-only=" + (.read_only | join(",")) end);

guard_context(false) as $g
| $g.hook
| (((.agent_type // "") | capture("^vbw:(?<r>architect|lead|dev|qa|scout|debugger|docs)$").r) // null) as $role
| .tool_name as $t
| if $role == null or ($g.project | not) then empty
  elif ($t | test(always_allowed)) then empty
  elif ($t | startswith("mcp__")) then
    ($g.record.settings.mcp // []) as $mcp
    | ([$mcp[] | select(. as $m | $t | startswith("mcp__" + $m.server + "__"))] | max_by(.server | length)) as $e
    | ([$mcp[] | entry_text]) as $texts
    | (($texts | join(" ")) as $all | if $all == "" then "" else $all + " " end) as $prefix
    | if $e == null then
        ($t | ltrimstr("mcp__") | split("__")[0]) as $server
        | "\($t): this project's MCP setting names no server \($server) for VBW's agents (mcp: \(if $texts == [] then "none" else $texts | join(" ") end))\nNext: the user adds it with vbw config set mcp \"\($prefix)\($server)\" for the writing agents (dev, debugger, docs) or \"\($prefix)\($server):read-only\" for every agent; as the \($role), work without it meanwhile"
      elif ($role | test(reading) | not) or $e.read_only == true or ($e.read_only | type == "array" and index($t | ltrimstr("mcp__" + $e.server + "__")) != null) then empty
      else
        "\($t) is not marked read-only, so the \($role) (a reading agent: architect, lead, scout, qa) may not call it; VBW never guesses from a name such as read_, get_ or search_\nNext: the user marks it with vbw config set mcp \"... \($e.server):read-only\" (the whole server) or \"... \($e.server):read-only=<tool>\" (this tool); meanwhile work without it"
      end
  elif ($t | test("^(" + (own_list[$role] | gsub(", "; "|")) + ")$")) then empty
  else
    "\($t) is not one of the \($role)'s tools (\(own_list[$role])): VBW refuses a tool it does not give the role, a new Claude Code tool included\nNext: as the \($role), do the work with your own tools"
  end
| deny
