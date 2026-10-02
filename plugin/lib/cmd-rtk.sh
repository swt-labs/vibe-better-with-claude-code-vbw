#!/usr/bin/env bash
# vbw rtk: the state of RTK (github.com/rtk-ai/rtk), the third-party tool that
# compresses command output through its own Claude Code hook. VBW only reports
# here; /vbw:rtk installs and removes RTK with RTK's own official commands
# (brew or cargo, then `rtk init -g`), each after the user agrees. VBW's guard
# judges the command inside `rtk ...`, so the two work together.

# shellcheck source=cmd-statusline.sh
. "$VBW_LIB/cmd-statusline.sh"

cmd_rtk() {
  [ $# -eq 0 ] || [ "$1" = status ] || vbw_usage_error "usage: vbw rtk [status]"
  local path version settings hook="no"
  path=$(command -v rtk 2> /dev/null || true)
  if [ -n "$path" ]; then
    version=$(rtk --version 2> /dev/null | head -n 1) || version=""
    printf 'rtk: installed (%s, %s)\n' "${version:-version unknown}" "$path"
  else
    printf 'rtk: not installed\n'
  fi
  settings=$(statusline_settings)
  # RTK's own rule (is_claude_hook_command): the rtk binary by name or path,
  # quoted or not, then exactly `hook claude`; or its older rtk-rewrite.sh.
  if [ -f "$settings" ] && jq -e '[.hooks.PreToolUse[]?.hooks[]?.command // empty]
      | any(.[]; test("^\\s*(\"([^\"]*/)?|([^\\s\"\\\\]|\\\\.)*/)?rtk(\\.exe)?\"?\\s+hook\\s+claude\\s*$")
                 or contains("rtk-rewrite.sh"))' "$settings" > /dev/null 2>&1; then
    hook="yes"
  fi
  printf 'claude hook: %s\n' "$([ "$hook" = yes ] && echo "on (rtk init -g)" || echo "off")"
  if command -v brew > /dev/null 2>&1; then printf 'install with: brew install rtk\n'
  elif command -v cargo > /dev/null 2>&1; then printf 'install with: cargo install --git https://github.com/rtk-ai/rtk\n'
  else printf 'install with: see https://github.com/rtk-ai/rtk (needs Homebrew or Cargo)\n'
  fi
}
