#!/usr/bin/env bash
# vbw statusline status | on | off (docs/statusline.md): the VBW status line,
# a core part of VBW. A plugin cannot set the main status line (only agent
# defaults), so /vbw:init turns it on in the user's settings.json. A status line
# the user had before is saved first, and `off` brings it back.
#
# The setting cannot name the plugin's directory: it changes with every update
# and ${CLAUDE_PLUGIN_ROOT} is not substituted in settings. So the command
# finds the newest installed VBW's scripts/vbw-statusline.sh in the plugin
# cache. It is the same command VBW 1 used, so updating needs no settings
# change. This is the one place VBW looks into the plugin cache (standards
# test exception, build plan K4).

VBW_STATUSLINE_CMD='bash -c '"'"'for _d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do [ -z "$_d" ] && continue; f=$(ls -1 "$_d"/plugins/cache/vbw-marketplace/vbw/*/scripts/vbw-statusline.sh 2>/dev/null | sort -V | tail -1 || true); [ -f "$f" ] && exec bash "$f"; done'"'"' '

# The user's settings file: $CLAUDE_CONFIG_DIR, else ~/.config/claude-code if
# present, else ~/.claude (the same resolution Claude Code uses).
statusline_settings() {
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    printf '%s/settings.json\n' "$CLAUDE_CONFIG_DIR"
  elif [ -d "$HOME/.config/claude-code" ]; then
    printf '%s/.config/claude-code/settings.json\n' "$HOME"
  else
    printf '%s/.claude/settings.json\n' "$HOME"
  fi
}

cmd_statusline() {
  local sub="${1:-status}" settings current
  case "$sub" in
    status|on|off) [ $# -le 1 ] || vbw_usage_error "usage: vbw statusline status | on | off" ;;
    *) vbw_usage_error "usage: vbw statusline status | on | off" ;;
  esac
  settings=$(statusline_settings)
  current=""
  if [ -f "$settings" ]; then
    current=$(jq -r '.statusLine | if type == "object" then .command // "" elif type == "string" then . else "" end' "$settings" 2> /dev/null) \
      || vbw_die "cannot read $settings (not valid JSON)"
  fi
  case "$sub" in
    status)
      if [ -z "$current" ]; then printf 'off: no status line is set (vbw statusline on)\n'
      elif printf '%s' "$current" | grep -q 'vbw-statusline\.sh'; then printf 'on: the VBW status line\n'
      else printf 'another status line is set (vbw statusline on switches to VBW and keeps it)\n'
      fi
      ;;
    on)
      if printf '%s' "$current" | grep -q 'vbw-statusline\.sh'; then
        printf 'on: the VBW status line\n'
        return 0
      fi
      if [ -n "$current" ]; then
        # Keep the user's own status line so that `off` can bring it back.
        jq '.statusLine' "$settings" > "$(statusline_backup)"
      fi
      statusline_write "$settings" '.statusLine = {type: "command", command: $cmd}'
      if [ -n "$current" ]; then
        printf 'on: the VBW status line replaced yours, which is saved (vbw statusline off brings it back)\n'
      else
        printf 'on: the VBW status line\n'
      fi
      ;;
    off)
      if printf '%s' "$current" | grep -q 'vbw-statusline\.sh'; then
        local backup
        backup=$(statusline_backup)
        if [ -f "$backup" ]; then
          statusline_write "$settings" '.statusLine = $prev[0]' --slurpfile prev "$backup"
          rm -f "$backup"
          printf 'off: your previous status line is back\n'
        else
          statusline_write "$settings" 'del(.statusLine)'
          printf 'off: the VBW status line was removed\n'
        fi
      else
        printf 'the VBW status line is not set; nothing changed\n'
      fi
      ;;
  esac
}

# Where the user's own status line is kept while VBW's is on.
statusline_backup() {
  printf '%s/vbw-statusline-previous.json\n' "$(dirname "$(statusline_settings)")"
}

# statusline_write SETTINGS FILTER [JQ OPTIONS...]: apply FILTER to the settings
# atomically, keeping every other setting.
statusline_write() {
  local file="$1" filter="$2" dir tmp
  shift 2
  dir=$(dirname "$file")
  mkdir -p "$dir"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "$dir/settings.XXXXXX") || vbw_die "cannot write $dir"
  if ! jq --arg cmd "$VBW_STATUSLINE_CMD" ${1+"$@"} "$filter" "$file" > "$tmp"; then
    rm -f "$tmp"
    vbw_die "cannot update $file"
  fi
  mv "$tmp" "$file"
}
