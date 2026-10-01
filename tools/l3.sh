#!/usr/bin/env bash
# Drive an interactive Claude Code session for L3 user-path runs (AGENTS.md
# reporting standard): the real TUI in tmux, with the v2 plugin. The only
# input is what a user types; the screen is the only output.
#
#   tools/l3.sh start NAME DIR [MODEL]   start `claude` in DIR (auto mode, sandbox on)
#   tools/l3.sh type NAME TEXT           type TEXT and press Enter
#   tools/l3.sh keys NAME KEY...         press keys (tmux names: Down, Enter, Escape, ...)
#   tools/l3.sh wait NAME [SECONDS]      wait until Claude is idle (default 900 s), print the screen
#   tools/l3.sh screen NAME              print the screen
#   tools/l3.sh stop NAME                end the session
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Optional: VBW_TEST_CLAUDE_CONFIG_DIR runs against another Claude config dir.
[ -z "${VBW_TEST_CLAUDE_CONFIG_DIR:-}" ] || export CLAUDE_CONFIG_DIR="$VBW_TEST_CLAUDE_CONFIG_DIR"
cmd="${1:-}"
name="${2:-}"
[ -n "$cmd" ] && [ -n "$name" ] || { sed -n '6,13p' "$0" >&2; exit 2; }
session="vbw-l3-$name"

screen() { tmux capture-pane -t "$session" -p -S -60; }

case "$cmd" in
  start)
    dir="${3:?usage: tools/l3.sh start NAME DIR [MODEL]}"
    model="${4:-sonnet}"
    # Only what the test needs: VBW 1 off and the sandbox on. Never settings a
    # real user would not have (VBW turns workflows on itself).
    settings='{"enabledPlugins":{"vbw@vbw-marketplace":false},"sandbox":{"enabled":true}}'
    # A session launched from inside Claude Code inherits its PATH, which puts
    # that session's installed plugins' bin/ (an older vbw) ahead of the code
    # under test. Start from a PATH without any plugin cache.
    clean=""
    IFS=: read -r -a parts <<< "$PATH"
    for p in "${parts[@]}"; do
      case "$p" in */plugins/cache/*) ;; *) clean="${clean:+$clean:}$p" ;; esac
    done
    tmux kill-session -t "$session" 2> /dev/null || true
    tmux new-session -d -s "$session" -x 200 -y 60 -c "$dir" \
      "env PATH='$clean' claude --model $model --permission-mode auto --plugin-dir '$ROOT/plugin' --settings '$settings'"
    sleep 6
    # First run in a directory: accept the folder-trust dialog, as a user would.
    if screen | grep -q 'Yes, I trust this folder'; then
      tmux send-keys -t "$session" Down Enter
      sleep 5
    fi
    screen
    ;;
  type)
    text="${3:?usage: tools/l3.sh type NAME TEXT}"
    tmux send-keys -t "$session" -l "$text"
    sleep 1
    tmux send-keys -t "$session" Enter
    ;;
  keys)
    shift 2
    tmux send-keys -t "$session" "$@"
    ;;
  wait)
    limit="${3:-900}"
    last="" stable=0 waited=0
    while [ "$waited" -lt "$limit" ]; do
      sleep 5
      waited=$((waited + 5))
      now=$(screen)
      # Busy while Claude shows its interrupt hint or the screen still changes.
      if printf '%s' "$now" | grep -q 'esc to interrupt'; then stable=0
      elif [ "$now" = "$last" ]; then stable=$((stable + 5))
      else stable=0
      fi
      last=$now
      [ "$stable" -ge 15 ] && break
    done
    screen
    [ "$waited" -lt "$limit" ] || { echo "(l3: still busy after ${limit}s)" >&2; exit 1; }
    ;;
  screen) screen ;;
  stop)
    tmux send-keys -t "$session" -l "/exit"
    tmux send-keys -t "$session" Enter
    sleep 2
    tmux kill-session -t "$session" 2> /dev/null || true
    ;;
  *) sed -n '6,13p' "$0" >&2; exit 2 ;;
esac
