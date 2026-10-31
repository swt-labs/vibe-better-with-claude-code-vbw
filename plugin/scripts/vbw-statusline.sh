#!/usr/bin/env bash
# The VBW status line (docs/statusline.md): four lines rendered by one jq
# program from Claude Code's JSON, the project's record and VBW's runtime
# state. This path is the one the statusLine setting looks for in the newest
# installed VBW, so an update switches the status line over by itself.
# No network and no git process: the branch is read from .git/HEAD directly.
# The one file it writes is the session's cost side file (.vbw/runtime/
# cost.SESSION.json, R173), through a temporary name and a rename. It never
# fails: a broken render prints a single line.
#
# Where the VBW plugin is turned off (R184: enabledPlugins["vbw@vbw-marketplace"]
# false in the project's .claude/settings.local.json, then its .claude/
# settings.json, then the user's settings.json; the first file that sets it
# decides, nothing decided means on) it prints nothing, writes nothing and exits
# 3. It does the same outside any VBW project (no .vbw folder at or above the
# folder). Exit 3 is the hand-back signal the statusLine setting reads to run the
# user's earlier status line (plan P134.2); the setting needs no rewrite. This script itself never runs that
# saved status line or any other command read from a file (D356).

# The statusLine setting runs this file by sourcing it in a subshell of its own
# bash (a bash process of its own would cost more than the hand-back path should),
# and it also runs on its own (`bash vbw-statusline.sh`): either way its exit status
# is its answer (nothing in it changes the caller's shell), and its folder is
# BASH_SOURCE, not $0.
# Folders are cut with parameter expansion, never a dirname or pwd process: the
# status line runs every few seconds, and each process costs CPU (budget: 60 ms a
# call). Nothing here changes folder, so the script's own folder is used as given.
case "${BASH_SOURCE[0]}" in */*) here=${BASH_SOURCE[0]%/*} ;; *) here=. ;; esac
plugin="$here/.."

# Claude Code may not send data on the first render: read with a timeout so
# the script never blocks (a lesson from VBW 1), then close stdin.
input=""
while IFS= read -t 1 -r line; do input="$input$line"; done 2> /dev/null
input="$input${line:-}"
exec 0< /dev/null

cdir=${CLAUDE_CONFIG_DIR:-}
if [ -z "$cdir" ]; then
  if [ -d "$HOME/.config/claude-code" ]; then cdir="$HOME/.config/claude-code"; else cdir="$HOME/.claude"; fi
fi

# vbw_project_of DIR: sets root to the project of a session started in DIR, the
# nearest folder up that holds .git (walked without a git process), or DIR itself
# when no folder up holds one, or, from a submodule with no record of its own,
# the VBW project above it: the rule every part of VBW shares.
# shellcheck source-path=SCRIPTDIR source=../hooks/project.sh
. "$plugin/hooks/project.sh"

# The project's two settings files are read in the same jq call as the input
# when the project is the one this process runs in, which is nearly always: one
# jq decides on or off, and the hand-back path starts nothing else. A session
# whose project is another folder reads that project's files in a second call.
vbw_project_of "${PWD:-.}"
guessed=$root
pl=(--arg pl "")
ps=(--arg ps "")
[ ! -f "$guessed/.claude/settings.local.json" ] || pl=(--rawfile pl "$guessed/.claude/settings.local.json")
[ ! -f "$guessed/.claude/settings.json" ] || ps=(--rawfile ps "$guessed/.claude/settings.json")

# One jq call for all, one value a line. What enabledPlugins["vbw@vbw-marketplace"]
# says is "true", "false", or "" when a file says nothing or is not valid JSON (it
# decides nothing, and the next file still counts; first, so input jq cannot read
# never loses it): first the user's settings.json, then the settings files of the
# folder this process runs in (the local file, then the project file; the first
# that sets it decides). Then the project folder, the session's transcript and its
# id (a safe token only: it names a file).
ucfg=(--arg ucfg "")
[ ! -f "$cdir/settings.json" ] || ucfg=(--rawfile ucfg "$cdir/settings.json")
paths=$(printf '%s' "$input" | jq -nr "${ucfg[@]}" "${pl[@]}" "${ps[@]}" 'def verdict: try (fromjson | .enabledPlugins["vbw@vbw-marketplace"] | select(type == "boolean") | tostring) catch empty;
  (($ucfg | verdict) // ""), ([($pl | verdict), ($ps | verdict)] | .[0] // ""),
  ((try input catch {}) | (.workspace.project_dir // .cwd // ""), (.transcript_path // ""), (.session_id // "" | if test("^[A-Za-z0-9_-]+$") then . else "" end))' 2> /dev/null)
take() { case "$rest" in *$'\n'*) val=${rest%%$'\n'*}; rest=${rest#*$'\n'} ;; *) val=$rest; rest= ;; esac; }
rest=$paths
take; uverdict=$val
take; pverdict=$val
take; root=$val
take; transcript=$val
take; sid=$val
root=${root:-$PWD}

# Outside any VBW project (no .vbw folder at or above the folder Claude Code
# reports, else the one this runs in): hand back before any other work.
vbw_vbw_above "$root"
[ -n "$vbwdir" ] || exit 3

# Started in a subfolder: the project is the nearest folder up that holds .git.
vbw_project_of "$root"

# On or off, before any other work: the project's .claude/settings.local.json,
# then its .claude/settings.json, then the user's (read above); the first that
# sets it decides. When the project is where this process runs, its files were
# read above. Otherwise the files that exist are read by one more jq (raw lines
# grouped by file, so a file that is not valid JSON decides nothing and the next
# one still counts); no project file, no jq.
verdict=$uverdict
if [ "$root" = "$guessed" ]; then
  [ -z "$pverdict" ] || verdict=$pverdict
else
  cfgs=()
  for f in "$root/.claude/settings.local.json" "$root/.claude/settings.json"; do
    [ -f "$f" ] && cfgs+=("$f")
  done
  if [ ${#cfgs[@]} -gt 0 ]; then
    v=$(jq -nRr 'reduce inputs as $l ([]; if length > 0 and .[-1][0] == input_filename then .[-1][1] += $l + "\n" else . + [[input_filename, $l + "\n"]] end)
      | [.[] | (.[1] | try (fromjson | .enabledPlugins["vbw@vbw-marketplace"] | select(type == "boolean")) catch empty)] | .[0] | if . == null then "" else tostring end' "${cfgs[@]}" 2> /dev/null)
    [ -z "$v" ] || verdict=$v
  fi
fi
if [ "$verdict" = false ]; then
  # Off for the installed VBW, but not for a copy loaded with --plugin-dir:
  # when the session's record (R185) names this very plugin, VBW is on. With no
  # record there is nothing to compare and no folder is resolved.
  p=""
  [ -z "$sid" ] || { read -r p < "$cdir/vbw/sessions/$sid"; } 2> /dev/null || p=""
  [ -n "$p" ] || exit 3
  own=$(cd "$plugin" 2> /dev/null && pwd -P) || own=""
  p=$(cd "$p" 2> /dev/null && pwd -P) || p=""
  if [ -z "$own" ] || [ "$p" != "$own" ]; then exit 3; fi
fi

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

# The record, or its small glance (record.sh) unless the record is newer: same
# four lines, without parsing a record of megabytes. bash's -nt, no extra
# process. "Not older" is tested as "record not newer", because bash 3.2 compares
# file times in whole seconds and a glance written in the record's second is
# not newer than it.
recfile="$root/.vbw/record.json"
glance="$root/.vbw/runtime/glance.json"
[ ! -f "$glance" ] || [ "$recfile" -nt "$glance" ] || recfile="$glance"

end="$plugin/hooks/end.json"
# Autonomy is per session: only this session's file counts.
auto="$root/.vbw/runtime/auto.${sid:-none}.json"
[ -n "$input" ] || input='{}'
# jq exits non-zero when an optional file is missing; only an empty render is a failure.
# The running step's note (R190) is one more input of the same call. A proof's
# note counts only while its process lives: the render names the pid first
# ({"step_pid":N}); a dead one is rendered again without the note (rare).
# Who leads (R192): while a lease is open (.vbw/runtime/run-open, no jq to know),
# one jq pass over Claude Code's list of chats (<cdir>/sessions/*.json, a file that
# is not valid JSON skipped) gives {sessionId: name} of each id's newest entry. No
# lease open, no pass; a missing or empty folder gives {}.
registry_args=()
if [ -e "$root/.vbw/runtime/run-open" ]; then
  n=0
  for f in "$cdir"/sessions/*.json; do
    [ -f "$f" ] && { registry_args+=(--rawfile "f$n" "$f"); n=$((n + 1)); }
  done
fi
# Each file is its own variable ($ARGS.named), so a file that is cut off without a
# final newline cannot run into the next file's first line.
if [ ${#registry_args[@]} -gt 0 ]; then
  registry() {
    jq -n ${registry_args[@]+"${registry_args[@]}"} '[$ARGS.named[] | try fromjson catch empty
      | select(type == "object" and (.sessionId | type) == "string" and (.name | type) == "string")]
      | group_by(.sessionId) | map(sort_by(.updatedAt // 0) | last | {key: .sessionId, value: .name}) | from_entries' 2> /dev/null || echo '{}'
  }
else
  registry() { echo '{}'; }
fi
render() {
  jq -nr --slurpfile registry <(registry) --argjson cc "$input" --arg branch "$branch" --arg color "$color" --arg legacy "$legacy" --arg sid "$sid" --argjson deadpid "$1" --argjson agents "$agents" --slurpfile profiles "$plugin/lib/profiles.json" -f "$here/statusline.jq" \
    "$plugin/.claude-plugin/plugin.json" "$recfile" "$end" \
    "$root/.vbw/runtime/next.json" "$end" "$root/.vbw/runtime/step.json" "$end" "$auto" 2> /dev/null
}
out=$(render 0)
case "$out" in
  '{"step_pid":'*)
    pid=${out%%$'\n'*}
    out=${out#*$'\n'}
    pid=${pid#'{"step_pid":'}
    pid=${pid%'}'}
    if ! kill -0 "$pid" 2> /dev/null; then out=$(render "$pid"); fi ;;
esac
# The cost record is the render's last line when Claude Code sent a cost: split
# it off and store it atomically. A failed write is skipped quietly.
last=${out##*$'\n'}
case "$last" in
  '{"session":'*)
    if [ "$out" = "$last" ]; then out=""; else out=${out%$'\n'*}; fi
    if [ -n "$sid" ] && [ -f "$root/.vbw/record.json" ]; then
      side="$root/.vbw/runtime/cost.$sid.json"
      { { [ -d "$root/.vbw/runtime" ] || mkdir -p "$root/.vbw/runtime"; } && printf '%s\n' "$last" > "$side.$$" && mv -f "$side.$$" "$side"; } 2> /dev/null || rm -f "$side.$$" 2> /dev/null
    fi ;;
esac
if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '[VBW] status line unavailable\n'; fi
