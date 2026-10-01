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

# One jq call for both: the project folder, and the session's transcript.
paths=$(printf '%s' "$input" | jq -r '(.workspace.project_dir // .cwd // ""), (.transcript_path // "")' 2> /dev/null)
root=${paths%%$'\n'*}
transcript=""
case "$paths" in *$'\n'*) transcript=${paths#*$'\n'} ;; esac
root=${root:-$PWD}

# Started in a subfolder: the project is the nearest folder up that holds .git
# (walked without a git process).
d=$root
while [ "$d" != / ] && [ -n "$d" ] && [ ! -e "$d/.git" ]; do d=$(dirname "$d"); done
[ ! -e "$d/.git" ] || root=$d
legacy=""
[ -f "$root/.vbw/record.json" ] || [ ! -d "$root/.vbw-planning" ] || legacy=1

# Workflow agents working right now: their transcripts sit next to the
# session's, and one written in the last minute is an agent at work. One find
# for all of them, however long the session.
agents=0
if [ -n "$transcript" ] && [ -d "${transcript%.jsonl}/subagents/workflows" ]; then
  agents=$(find "${transcript%.jsonl}/subagents/workflows" -name 'agent-*.jsonl' -mmin -1 2> /dev/null | wc -l | tr -d ' ')
  case "$agents" in "" | *[!0-9]*) agents=0 ;; esac
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
[ -n "$input" ] || input='{}'
# jq exits non-zero when an optional file is missing; only an empty render is a failure.
out=$(jq -nr --argjson cc "$input" --arg branch "$branch" --arg color "$color" --arg legacy "$legacy" --argjson agents "$agents" -f "$here/statusline.jq" \
  "$plugin/.claude-plugin/plugin.json" "$root/.vbw/record.json" "$end" \
  "$root/.vbw/runtime/next.json" "$end" "$root/.vbw/runtime/auto.json"  2> /dev/null)
if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '[VBW] status line unavailable\n'; fi
