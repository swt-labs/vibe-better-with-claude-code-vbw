# shellcheck shell=sh
# The reader of a file or Bash guard's answer (docs/guards.md, "How a command is read"; R254).
# Sourced, in POSIX sh, by the guard commands in hooks.json after the guard's jq in a pipe
# (jq ... | { . read.sh; }), so that no process starts for it. The guard prints either nothing,
# one decision (a deny JSON line), or a request, and always ends with the line vbw-guard-done.
# - The end line missing (jq failed, was not found, or ran past its time limit): exit 1. The
#   command's fail-closed handler then answers: blocked during a run, silent otherwise.
# - A decision: printed as it is.
# - A request: line 1 vbw-read, line 2 the hook input as one JSON line, then one line
#   target<TAB>absolute path<TAB>refusal per write target (one inside the hook's own folder too, since a project nested there is its own). The
#   refusal is what the target gets when no project holds it (R177: refused under the hook's
#   own run), or empty. Each target is walked up to the nearest folder holding
#   .vbw/record.json beside .git; with none, the refusal (if any) is the answer. Otherwise
#   one second pass per such project (guard-read.jq) judges all its targets by that project's
#   record and lease, exactly as a write from inside it, and its decision is the answer. A
#   project whose pass fails while its run is open (.vbw/runtime/run-open) is refused as a
#   failed guard is: the message of the command, exit 4, which the command turns into exit 2.
# - A script line (R255), script<TAB>start<TAB>interpreter<TAB>path as written<TAB>absolute
#   path<TAB>working folder<TAB>mode, per script file the call runs by name that the command does not
#   write (the last field, the mode, is text when the command names the path twice, then the
#   second pass takes the script from the command that writes it and nothing is looked up, else
#   file): committed and unchanged since the run's start commit (the start field, - or a value
#   that is no commit id standing for HEAD) it is the project's own and runs unread (two git
#   calls: ls-files --error-unmatch, then diff --quiet); a folder is no script; any other is
#   read by one pass of guard-read.jq in the hook's own project (--rawfile script), or, with
#   no readable file at the path, refused as unreadable (--arg missing 1). The git lookup and
#   the read happen on this path only. The hook command's variables p (project), s (session
#   folder), r (record), g (glance) and o (run open) are the guard's own.
# Prints only the answer. The whole reader is parameter expansion, tests, read and printf.

vbw_nl='
'
vbw_tab='	'
vbw_hook='' vbw_deny='' vbw_reqs='' vbw_scripts='' vbw_read=0 vbw_done=0
while IFS= read -r vbw_line; do
  case $vbw_line in
    vbw-guard-done) vbw_done=1; break ;;
    vbw-read) vbw_read=1; IFS= read -r vbw_hook || exit 1 ;;
    "target$vbw_tab"*) vbw_reqs=$vbw_reqs$vbw_line$vbw_nl ;;
    "script$vbw_tab"*) vbw_scripts=$vbw_scripts${vbw_line#script"$vbw_tab"}$vbw_nl ;;
    *) vbw_deny=$vbw_line ;;
  esac
done
[ "$vbw_done" = 1 ] || exit 1
if [ "$vbw_read" != 1 ]; then
  [ -z "$vbw_deny" ] || printf '%s\n' "$vbw_deny"
  exit 0
fi

# Each target: its project, or the refusal when none holds it.
vbw_groups=
vbw_rest=$vbw_reqs
while [ -n "$vbw_rest" ]; do
  vbw_line=${vbw_rest%%"$vbw_nl"*}
  vbw_rest=${vbw_rest#*"$vbw_nl"}
  vbw_line=${vbw_line#target"$vbw_tab"}
  vbw_t=${vbw_line%%"$vbw_tab"*}
  vbw_d=$vbw_t vbw_p=''
  while [ "$vbw_d" != / ]; do
    case $vbw_d in */*) vbw_d=${vbw_d%/*}; vbw_d=${vbw_d:-/} ;; *) vbw_d=/ ;; esac
    if [ -f "$vbw_d/.vbw/record.json" ] && [ -e "$vbw_d/.git" ]; then vbw_p=$vbw_d; break; fi
  done
  if [ -n "$vbw_p" ] && [ "$vbw_p" = "${p:-}" ]; then
    :
  elif [ -n "$vbw_p" ]; then
    vbw_groups=$vbw_groups$vbw_p$vbw_tab$vbw_t$vbw_nl
  else
    vbw_fb=${vbw_line#*"$vbw_tab"}
    [ -z "$vbw_fb" ] || { printf '%s\n' "$vbw_fb"; exit 0; }
  fi
done

# One second pass for each project, with its targets.
vbw_seen=$vbw_nl
vbw_rest=$vbw_groups
while [ -n "$vbw_rest" ]; do
  vbw_line=${vbw_rest%%"$vbw_nl"*}
  vbw_rest=${vbw_rest#*"$vbw_nl"}
  vbw_p=${vbw_line%%"$vbw_tab"*}
  case $vbw_seen in *"$vbw_nl$vbw_p$vbw_nl"*) continue ;; esac
  vbw_seen=$vbw_seen$vbw_p$vbw_nl
  set --
  vbw_scan=$vbw_groups
  while [ -n "$vbw_scan" ]; do
    vbw_line=${vbw_scan%%"$vbw_nl"*}
    vbw_scan=${vbw_scan#*"$vbw_nl"}
    if [ "${vbw_line%%"$vbw_tab"*}" = "$vbw_p" ]; then set -- "$@" "${vbw_line#*"$vbw_tab"}"; fi
  done
  vbw_g=/dev/null vbw_o=0
  vbw_gl=$vbw_p/.vbw/runtime/glance.json
  if [ -f "$vbw_gl" ] && [ -r "$vbw_gl" ] && [ "$vbw_gl" -nt "$vbw_p/.vbw/record.json" ]; then vbw_g=$vbw_gl; fi
  if [ -e "$vbw_p/.vbw/runtime/run-open" ]; then vbw_o=1; fi
  if vbw_out=$(printf '%s\n' "$vbw_hook" | jq -nrc --rawfile glance "$vbw_g" --arg root "$vbw_p" --arg dir "$vbw_p" --arg open "$vbw_o" \
      -f "${CLAUDE_PLUGIN_ROOT}/hooks/guard-read.jq" - "$vbw_p/.vbw/record.json" "${CLAUDE_PLUGIN_ROOT}/hooks/end.json" --args "$@" 2> /dev/null); then
    [ -z "$vbw_out" ] || { printf '%s\n' "$vbw_out"; exit 0; }
  elif [ "$vbw_o" = 1 ]; then
    echo "VBW guard: the guard failed while a run is open, so this call is blocked. Next: run vbw doctor to see why, then retry" >&2
    exit 4
  fi
done

# Each script file: the project's own committed and unchanged ones run unread; the others are read.
vbw_rest=$vbw_scripts
while [ -n "$vbw_rest" ]; do
  vbw_line=${vbw_rest%%"$vbw_nl"*}
  vbw_rest=${vbw_rest#*"$vbw_nl"}
  vbw_start=${vbw_line%%"$vbw_tab"*} vbw_line=${vbw_line#*"$vbw_tab"}
  vbw_int=${vbw_line%%"$vbw_tab"*} vbw_line=${vbw_line#*"$vbw_tab"}
  vbw_wr=${vbw_line%%"$vbw_tab"*} vbw_line=${vbw_line#*"$vbw_tab"}
  vbw_abs=${vbw_line%%"$vbw_tab"*} vbw_line=${vbw_line#*"$vbw_tab"}
  vbw_cwd=${vbw_line%%"$vbw_tab"*} vbw_mode=${vbw_line#*"$vbw_tab"}
  case $vbw_start in '' | *[!0-9a-fA-F]*) vbw_start=HEAD ;; esac
  # Under .vbw/runtime a file is the agents' own scratch work (git ignores it): read without a lookup.
  if [ "$vbw_mode" != text ] && [ "${vbw_abs#"${p:-.}"/.vbw/runtime/}" = "$vbw_abs" ]; then
    [ -d "$vbw_abs" ] && continue
    if git -C "${p:-.}" ls-files -z --error-unmatch -- "$vbw_abs" > /dev/null 2>&1 \
      && git -C "${p:-.}" diff --quiet "$vbw_start" -- "$vbw_abs" > /dev/null 2>&1; then
      continue
    fi
  fi
  set -- --arg interp "$vbw_int" --arg written "$vbw_wr" --arg abs "$vbw_abs" --arg cwd "$vbw_cwd" --arg mode "$vbw_mode"
  if [ -f "$vbw_abs" ] && [ -r "$vbw_abs" ]; then set -- "$@" --rawfile script "$vbw_abs"; else set -- "$@" --arg missing 1; fi
  if vbw_out=$(printf '%s\n' "$vbw_hook" | jq -nrc --rawfile glance "${g:-/dev/null}" --arg root "${p:-.}" --arg dir "${s:-.}" --arg open "${o:-0}" "$@" \
      -f "${CLAUDE_PLUGIN_ROOT}/hooks/guard-read.jq" - "${r:-/dev/null}" "${CLAUDE_PLUGIN_ROOT}/hooks/end.json" 2> /dev/null); then
    [ -z "$vbw_out" ] || { printf '%s\n' "$vbw_out"; exit 0; }
  elif [ "${o:-0}" = 1 ]; then
    echo "VBW guard: the guard failed while a run is open, so this call is blocked. Next: run vbw doctor to see why, then retry" >&2
    exit 4
  fi
done
exit 0
