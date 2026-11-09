#!/usr/bin/env bash
# SessionStart: in a VBW project (the project of the session's folder, found as
# the guards and the kernel find it, holds .vbw/record.json), tell the model
# where the project stands and what comes next, in one line. Started in a
# subfolder of the project: also name the project folder, which VBW's paths are
# relative to. Never a resume directive (ledger D289).
#
# Also, in every session: remove VBW 1's command copies (build plan K15). And in a
# VBW project, after VBW was updated: offer /vbw:whats-new once (docs/update.md).

# Without jq VBW can neither build its answer nor run its kernel (and the VBW 1
# reload notice below needs jq too): end quietly, like the per-tool-call hooks.
command -v jq > /dev/null 2>&1 || exit 0

dir=${CLAUDE_PROJECT_DIR:-$PWD}
# shellcheck source-path=SCRIPTDIR source=project.sh
. "${0%/*}/project.sh"
vbw_project_of "$dir"
vbw="${0%/*}/../bin/vbw"

# VBW 1 copied its commands to <claude-dir>/commands/vbw/. User commands take
# precedence over plugin skills, so those copies would run VBW 1 instead of
# /vbw:init, /vbw:vibe and the rest (ledger D290). Only the config directory
# this session uses can shadow its commands, so only that one is cleaned
# ($CLAUDE_CONFIG_DIR, else ~/.config/claude-code if present, else ~/.claude).
# Remove only VBW's own copies (frontmatter "name: vbw:..."), and the directory
# once empty.
removed=0
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  claude_dir=$CLAUDE_CONFIG_DIR
elif [ -d "$HOME/.config/claude-code" ]; then
  claude_dir="$HOME/.config/claude-code"
else
  claude_dir="$HOME/.claude"
fi
if [ -d "$claude_dir/commands/vbw" ]; then
  for f in "$claude_dir/commands/vbw"/*.md; do
    [ -f "$f" ] || continue
    if awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && /^---$/ { exit 1 } /^name: vbw:/ { found = 1; exit } END { exit !found }' "$f"; then
      rm -f "$f" && removed=$((removed + 1))
    fi
  done
  rmdir "$claude_dir/commands/vbw" 2> /dev/null || true
fi

context="" notice=""

# version_ok V: V is a plain dotted version, X.Y.Z (VBW's versions are).
version_ok() {
  [[ $1 =~ ^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$ ]]
}

# version_newer A B: A is a higher version than B, compared as numbers
# (2.0.100 is higher than 2.0.41). Both pass version_ok.
version_newer() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  [ $((10#$a1)) -ne $((10#$b1)) ] && { [ $((10#$a1)) -gt $((10#$b1)) ]; return; }
  [ $((10#$a2)) -ne $((10#$b2)) ] && { [ $((10#$a2)) -gt $((10#$b2)) ]; return; }
  [ $((10#$a3)) -gt $((10#$b3)) ]
}

# Which copy of VBW is this? A copy loaded with claude --plugin-dir is named
# vbw@inline, so Claude Code gives its hooks a plugin data folder named
# vbw-inline; an installed copy gets vbw-vbw-marketplace (probe, R185).
plugin=${CLAUDE_PLUGIN_ROOT:-}
[ -n "$plugin" ] || plugin=$(cd "${0%/*}/.." 2> /dev/null && pwd) || plugin=${0%/*}/..
kernel=$plugin/bin/vbw
kversion=$(jq -r '.version // empty' "$plugin/.claude-plugin/plugin.json" 2> /dev/null || true)
loaded=0
[ "${CLAUDE_PLUGIN_DATA##*/}" != "vbw-inline" ] || loaded=1

# The hook's input arrives on stdin as one JSON line; Claude Code may leave
# the pipe open, so never wait for its end.
input=""
IFS= read -r -t 1 input || true
sid=$(printf '%s' "$input" | jq -r '.session_id // "" | if test("^[A-Za-z0-9_-]+$") then . else "" end' 2> /dev/null || true)

# The loop's own session resumed (T156; source resume): its earlier process was gone and nothing drove
# the loop. An away mark, unless one is there, tells the loop's next step to leave the time since the
# item's last step out of the item's time (docs/loop.md, The time budget).
if [ -n "$sid" ] && [ -f "$root/.vbw/runtime/loop.$sid" ] && [ ! -e "$root/.vbw/runtime/loop-away.$sid" ] \
  && [ "$(printf '%s' "$input" | jq -r '.source // empty' 2> /dev/null || true)" = resume ]; then
  { : > "$root/.vbw/runtime/loop-away.$sid"; } 2> /dev/null || true
fi

# Every start, by a loaded copy or an installed one, puts the loaded copy's bin/
# first on PATH for the session (the env file is read before each Bash tool
# command; one line, quoted for sh, bash and zsh) and records the copy's folder
# for the session id (the status line and doctor read it). Afterwards the env
# file holds exactly one VBW PATH line (R285): earlier ones of any copy go (the
# unmarked ones of 2.1.28 and older too: export PATH='<folder>/bin':"$PATH" where
# the folder holds vbw), every other line stays byte for byte and in order, and
# the file is replaced atomically from a name in its own folder. Records older
# than 7 days go.
sessions=$claude_dir/vbw/sessions
if [ -d "$sessions" ]; then
  find "$sessions" -type f -mtime +7 -exec rm -f {} + 2> /dev/null || true
fi

# write_path_line FILE LINE MARK: FILE without any VBW PATH line, then LINE.
write_path_line() {
  local file=$1 line=$2 mark=$3 l d tmp
  tmp=$(mktemp "${file}.vbw.XXXXXX") || return 1
  {
    if [ -f "$file" ]; then
      while IFS= read -r l || [ -n "$l" ]; do
        case $l in
          *"$mark") continue ;;
          "export PATH='"*"/bin':\"\$PATH\"")
            d=${l#"export PATH='"}
            d=${d%%"'"*}
            [ ! -x "$d/vbw" ] || continue
            ;;
        esac
        printf '%s\n' "$l"
      done < "$file"
    fi
    printf '%s\n' "$line"
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

q="'"
mark=' # vbw-session-path'
pathline="export PATH='${plugin//$q/$q\\$q$q}/bin':\"\$PATH\"$mark"
if [ -n "${CLAUDE_ENV_FILE:-}" ] && write_path_line "$CLAUDE_ENV_FILE" "$pathline" "$mark" 2> /dev/null; then
  :
elif [ "$loaded" -eq 1 ]; then
  notice="VBW could not put this loaded copy first on PATH (Claude Code gave no writable env file), so a plain vbw may run an installed release. Run ${kernel} instead."
  context="${context}VBW could not put the loaded copy first on PATH: run ${kernel} instead of vbw in this session. Tell the user once. "
fi
if [ -n "$sid" ]; then
  { mkdir -p "$sessions" && printf '%s\n' "$plugin" > "$sessions/$sid"; } 2> /dev/null || true
fi
[ "$removed" -eq 0 ] || context="${context}VBW removed $removed outdated VBW 1 command copies that would have run instead of the VBW 2 commands. Tell the user once: run /reload-skills now (or restart Claude Code) before using any /vbw: command, because this session loaded the old copies. "

if [ -f "$root/.vbw/record.json" ]; then
  # One kernel call: vbw next refreshes the glance, whose project line has the
  # words of vbw status line 1 (never vbw status, which runs vbw next again).
  next=$(cd "$root" && "$vbw" next 2>&1 < /dev/null)
  newer=$?
  next=$(printf '%s\n' "$next" | head -n 1)
  state=$next
  if [ "$newer" -eq 4 ]; then
    # Written by a newer VBW: nothing works until VBW is updated (exit 4). The kernel's own
    # line names both versions and the fix; the hook adds no wording of its own (R272).
    line=${state#vbw: }
    context="${context}${line}. Tell the user once; VBW cannot work on this project until then."
    notice="${notice:+$notice }$line"
    case $line in *"/vbw:update"*) ;; *) notice="$notice (/vbw:update)" ;; esac
  else
    # VBW's status line set by an older VBW (an old command or no refresh interval): update it
    # (only VBW's own line; `on` keeps every other setting).
    case $("$vbw" statusline status 2> /dev/null) in
      *"refreshed on events only"* | *"an older VBW status line"*) "$vbw" statusline on > /dev/null 2>&1 || true ;;
    esac
    state=$(jq -r '"\(.project.name) · \(.milestone.id) \(.milestone.title) (\(.milestone.status))"' "$root/.vbw/runtime/glance.json" 2> /dev/null || true)
    context="${context}VBW project ($state). Next: $next. Continue with /vbw:vibe. The vbw command is on PATH (vbw help); this session's kernel is ${kernel}${kversion:+ (version $kversion)}."
    [ "${dir%/}" = "${root%/}" ] || context="${context} This session started in ${dir#"${root%/}"/}, a subfolder of the project at $root: VBW's paths (.vbw/, plan files) are relative to $root."
    # After an update (docs/update.md), offer /vbw:whats-new once. No network
    # call: the plugin's version is compared with the highest version this
    # clone's sessions have seen, kept in the clone's git folder (shared by its
    # worktrees). The first session in a clone only records; a copy loaded with
    # claude --plugin-dir is a working tree, so it neither offers nor records.
    if [ "$loaded" -eq 0 ] && version_ok "$kversion"; then
      seen_dir=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2> /dev/null || true)
      if [ -n "$seen_dir" ]; then
        seen_file=$seen_dir/vbw/seen-version
        seen=""
        { IFS= read -r seen < "$seen_file"; } 2> /dev/null || seen=""
        if ! version_ok "$seen"; then
          { mkdir -p "$seen_dir/vbw" && printf '%s\n' "$kversion" > "$seen_file"; } 2> /dev/null || true
        elif version_newer "$kversion" "$seen"; then
          notice="${notice:+$notice }VBW updated from $seen to $kversion. /vbw:whats-new shows what changed."
          context="${context} VBW was updated from $seen to $kversion since this project last started a session. The user was just shown a notice that /vbw:whats-new shows what changed; do not repeat it."
          { printf '%s\n' "$kversion" > "$seen_file"; } 2> /dev/null || true
        fi
      fi
    fi
  fi
elif [ -d "$root/.vbw-planning" ]; then
  context="${context}This project has a VBW 1 plan (.vbw-planning/). Tell the user once: VBW 2 leaves it untouched, and /vbw:vibe or /vbw:convert brings it into VBW 2 through a few questions."
fi

# The copies were loaded before this hook ran, so this session still has them:
# the user must reload before typing a /vbw: command. A systemMessage reaches
# the user at once; the context alone would wait for their first prompt.
[ "$removed" -eq 0 ] || notice="VBW 2 removed the old VBW 1 commands. Type /reload-skills (or restart Claude Code) before using any /vbw: command.${notice:+ $notice}"

[ -z "$context" ] || jq -n --arg c "$context" --arg n "$notice" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}} + (if $n == "" then {} else {systemMessage: $n} end)'
