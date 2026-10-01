#!/usr/bin/env bash
# vbw workflows status | on: Claude Code's Dynamic workflows, which VBW's
# planning, building and fixing run on. They are off by default on some plans,
# so setting up a project turns them on in the user's settings.json, like the
# status line. A user who turned them off on purpose (disableWorkflows) is told,
# never overridden. Claude Code reloads the setting in the running session.

# shellcheck source=cmd-statusline.sh
. "$VBW_LIB/cmd-statusline.sh"

cmd_workflows() {
  local sub="${1:-status}" settings state
  case "$sub" in
    status|on) [ $# -le 1 ] || vbw_usage_error "usage: vbw workflows status | on" ;;
    *) vbw_usage_error "usage: vbw workflows status | on" ;;
  esac
  settings=$(statusline_settings)
  state=default
  if [ -f "$settings" ]; then
    state=$(jq -r 'if .disableWorkflows == true then "disabled" elif .enableWorkflows == true then "on" else "default" end' "$settings" 2> /dev/null) \
      || vbw_die "cannot read $settings (not valid JSON)"
  fi
  [ -z "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ] || state=disabled
  case "$sub:$state" in
    *:on) printf 'on: Dynamic workflows are enabled\n' ;;
    *:disabled) printf 'off: Dynamic workflows are disabled on purpose (disableWorkflows or CLAUDE_CODE_DISABLE_WORKFLOWS); VBW needs them to plan and build\n' ;;
    status:default) printf 'default: Claude Code decides (off on some plans; vbw workflows on turns them on)\n' ;;
    on:default)
      statusline_write "$settings" '.enableWorkflows = true'
      printf 'on: Dynamic workflows turned on in %s (VBW plans and builds with them)\n' "$settings"
      ;;
  esac
}
