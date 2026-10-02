#!/usr/bin/env bash
# The VBW status line (docs/statusline.md): four lines rendered by one jq
# program from Claude Code's JSON, the project's record and VBW's runtime
# state. This path is the one the statusLine setting looks for in the newest
# installed VBW, so an update switches the status line over by itself.
# No network, no temporary files, and no git process: the branch is read from
# .git/HEAD directly. It never fails: a broken render prints a single line.

here="$(cd "$(dirname "$0")" && pwd)"
plugin="$here/.."

# Claude Code may not send data on the first render: read with a timeout so
# the script never blocks (a lesson from VBW 1), then close stdin.
input=""
while IFS= read -t 1 -r line; do input="$input$line"; done 2> /dev/null
input="$input${line:-}"
exec 0< /dev/null

# One jq call for all: the project folder, the session's transcript and its id
# (a safe token only: it names a file).
paths=$(printf '%s' "$input" | jq -r '(.workspace.project_dir // .cwd // ""), (.transcript_path // ""), (.session_id // "" | if test("^[A-Za-z0-9_-]+$") then . else "" end)' 2> /dev/null)
root=${paths%%$'\n'*}
rest=${paths#*$'\n'}
transcript=${rest%%$'\n'*}
sid=${rest#*$'\n'}
[ "$rest" != "$paths" ] || { transcript=""; sid=""; }
[ "$sid" != "$rest" ] || sid=""
root=${root:-$PWD}

# Started in a subfolder: the project is the nearest folder up that holds .git
# (walked without a git process).
d=$root
while [ "$d" != / ] && [ -n "$d" ] && [ ! -e "$d/.git" ]; do d=$(dirname "$d"); done
[ ! -e "$d/.git" ] || root=$d
legacy=""
[ -f "$root/.vbw/record.json" ] || [ ! -d "$root/.vbw-planning" ] || legacy=1

# Workflow agents working right now: their transcripts sit next to the
# session's, and one written in the last minute is an agent at work. Its
# .meta.json beside it names its role, label and model. One find, and one jq
# only while agents work.
agents='[]'
if [ -n "$transcript" ] && [ -d "${transcript%.jsonl}/subagents/workflows" ]; then
  metas=()
  while IFS= read -r f; do
    [ -f "${f%.jsonl}.meta.json" ] && metas+=("${f%.jsonl}.meta.json")
  done < <(find "${transcript%.jsonl}/subagents/workflows" -name 'agent-*.jsonl' -mmin -1 2> /dev/null)
  if [ ${#metas[@]} -gt 0 ]; then
    # Steady order: by role (the team's order), then label.
    agents=$(jq -cs 'map({role: (.agentType // "" | sub("^vbw:"; "")), label: (.description // ""), model: (.model // "")})
      | sort_by((.role as $r | ["architect", "lead", "dev", "qa", "scout", "debugger", "docs"] | index($r) // 9), .label)' "${metas[@]}" 2> /dev/null) || agents='[]'
  fi
fi

# The branch, without a git process: .git is a directory, or a file pointing
# at a worktree's git directory.
branch=""
gitdir="$root/.git"
if [ -f "$gitdir" ]; then
  read -r gitdir < "$gitdir"
  gitdir=${gitdir#gitdir: }
  case "$gitdir" in /*) ;; *) gitdir="$root/$gitdir" ;; esac
fi
if [ -f "$gitdir/HEAD" ]; then
  read -r head < "$gitdir/HEAD"
  case "$head" in
    "ref: refs/heads/"*) branch=${head#ref: refs/heads/} ;;
    *) branch=${head:0:7} ;;
  esac
fi

color=1
[ -z "${NO_COLOR:-}" ] || color=""

end="$plugin/hooks/end.json"
# Autonomy is per session: only this session's file counts.
auto="$root/.vbw/runtime/auto.${sid:-none}.json"
[ -n "$input" ] || input='{}'
# jq exits non-zero when an optional file is missing; only an empty render is a failure.
out=$(jq -nr --argjson cc "$input" --arg branch "$branch" --arg color "$color" --arg legacy "$legacy" --argjson agents "$agents" --slurpfile profiles "$plugin/lib/profiles.json" -f "$here/statusline.jq" \
  "$plugin/.claude-plugin/plugin.json" "$root/.vbw/record.json" "$end" \
  "$root/.vbw/runtime/next.json" "$end" "$auto" 2> /dev/null)
if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '[VBW] status line unavailable\n'; fi
