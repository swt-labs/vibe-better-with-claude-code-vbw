#!/usr/bin/env bash
# vbw doctor: everything VBW needs, one line each, with the fix for anything
# wrong. Exit 0 when nothing is wrong (warnings allowed), 1 otherwise. Changes
# nothing.

# shellcheck source=cmd-statusline.sh
. "$VBW_LIB/cmd-statusline.sh"
# shellcheck source=sessions.sh
. "$VBW_LIB/sessions.sh"

VBW_MIN_CLAUDE=2.1.286
# The marketplace VBW is installed from (the name in marketplace.json).
VBW_MARKETPLACE=vbw-marketplace

cmd_doctor() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw doctor"
  DOCTOR_FAILED=0
  doctor_tools
  doctor_path
  doctor_claude
  doctor_updates
  doctor_sessions
  doctor_statusline
  if VBW_ROOT=$(git rev-parse --show-toplevel 2> /dev/null); then
    doctor_project
  else
    doctor_line info "not inside a git repository: project checks skipped"
  fi
  [ "$DOCTOR_FAILED" -eq 0 ]
}

# doctor_line ok|warn|fail|info MESSAGE [FIX]
doctor_line() {
  local mark
  case "$1" in ok) mark="✓" ;; warn) mark="!" ;; fail) mark="✗"; DOCTOR_FAILED=1 ;; *) mark="·" ;; esac
  printf '%s %s\n' "$mark" "$2"
  [ -z "${3:-}" ] || printf '    fix: %s\n' "$3"
}

doctor_tools() {
  local v
  if vbw_jq_floor; then doctor_line ok "jq $VBW_JQ_VERSION"
  else doctor_line fail "$VBW_JQ_MSG" "$VBW_JQ_FIX"
  fi
  v=$(git --version 2> /dev/null | awk '{print $3}')
  if [ -n "$v" ]; then doctor_line ok "git $v"; else doctor_line fail "git is missing" "install git"; fi
  # VBW commits as the user: without a name and email, git may refuse (or
  # guess one from the machine name).
  if [ -n "$v" ]; then
    if [ -n "$(git config user.name 2> /dev/null)" ] && [ -n "$(git config user.email 2> /dev/null)" ]; then
      doctor_line ok "git knows who you are ($(git config user.name))"
    else
      doctor_line warn "git has no name or email set: VBW's commits may fail" "git config --global user.name \"Your Name\" && git config --global user.email you@example.com"
    fi
  fi
}

# The loaded plugin: the folder the session start recorded for this session
# while it still holds a VBW plugin, else the plugin of this kernel. The vbw on
# PATH should be that plugin's.
doctor_path() {
  local loaded=$VBW_PLUGIN rec="" recfile on_path pv lv
  recfile=$(sessions_record_path "${CLAUDE_CODE_SESSION_ID:-}") && rec=$(head -n 1 "$recfile" 2> /dev/null || true)
  [ -z "$rec" ] || [ ! -f "$rec/.claude-plugin/plugin.json" ] || loaded=$rec
  lv=$(jq -r '.version // "unknown"' "$loaded/.claude-plugin/plugin.json" 2> /dev/null || echo unknown)
  if ! on_path=$(command -v vbw 2> /dev/null) || [ -z "$on_path" ]; then
    doctor_line warn "no vbw on PATH (the loaded plugin is $loaded, version $lv)" "run $loaded/bin/vbw, or put $loaded/bin on PATH"
    return 0
  fi
  pv=$(jq -r '.version // "unknown"' "${on_path%/*}/../.claude-plugin/plugin.json" 2> /dev/null || echo unknown)
  if [ "$(cd "${on_path%/*}/.." 2> /dev/null && pwd -P)" = "$(cd "$loaded" 2> /dev/null && pwd -P)" ]; then
    doctor_line ok "vbw on PATH: $on_path (version $pv), the loaded plugin's"
  else
    doctor_line warn "vbw on PATH is $on_path (version $pv), not the loaded plugin's: $loaded (version $lv)" "run $loaded/bin/vbw, or put $loaded/bin first on PATH"
  fi
}

doctor_claude() {
  local v settings=() f wf=""
  v=$(claude --version 2> /dev/null | awk '{print $1}') || v=""
  if [ -z "$v" ]; then doctor_line warn "Claude Code version unknown (the claude command is not on PATH here)"
  elif version_at_least "$v" "$VBW_MIN_CLAUDE"; then doctor_line ok "Claude Code $v"
  else doctor_line fail "Claude Code $v is older than VBW needs ($VBW_MIN_CLAUDE)" "update Claude Code"
  fi
  # Workflows: off by default on the Pro plan; the setting wins when present.
  if [ -n "${CLAUDE_CODE_DISABLE_WORKFLOWS:-}" ]; then
    doctor_line fail "workflows are disabled (CLAUDE_CODE_DISABLE_WORKFLOWS)" "unset CLAUDE_CODE_DISABLE_WORKFLOWS"
    return 0
  fi
  settings=("$(statusline_settings)")
  [ -z "${VBW_ROOT:-}" ] || settings+=("$VBW_ROOT/.claude/settings.json" "$VBW_ROOT/.claude/settings.local.json")
  for f in "${settings[@]}"; do
    [ -f "$f" ] || continue
    jq -e '.disableWorkflows == true' "$f" > /dev/null 2>&1 && wf=off
    [ "$wf" = off ] || ! jq -e '.enableWorkflows == true' "$f" > /dev/null 2>&1 || wf=on
  done
  local mode=""
  for f in "${settings[@]}"; do
    [ -f "$f" ] || continue
    mode=$(jq -r '.permissions.defaultMode // empty' "$f" 2> /dev/null || true)
    [ -z "$mode" ] || break
  done
  case "$mode" in
    auto) doctor_line ok "Claude Code starts in auto permission mode" ;;
    bypassPermissions) doctor_line ok "Claude Code starts in bypassPermissions mode" ;;
    *) doctor_line warn "Claude Code starts in ${mode:-manual} permission mode (a session switched to auto mode with Shift+Tab is fine; in manual mode every agent step asks you first)" "to start in auto mode, set permissions.defaultMode to \"auto\" in $(statusline_settings)" ;;
  esac
  case "$wf" in
    on) doctor_line ok "workflows enabled" ;;
    off) doctor_line fail "workflows are disabled in your settings (disableWorkflows)" "remove disableWorkflows, then turn on Dynamic workflows in /config" ;;
    *) doctor_line warn "workflows: Claude Code's default (off on some plans)" "vbw workflows on" ;;
  esac
}

# env_truthy VALUE: how Claude Code reads an on/off variable: 1, true, yes or on.
env_truthy() {
  case "$1" in 1 | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Oo][Nn]) return 0 ;; esac
  return 1
}

# Does a new VBW reach the user, and are they told (docs/update.md)? VBW makes no
# network call to find out: that is Claude Code's auto-update of this marketplace,
# off by default for a third-party one. Its state is the marketplace's autoUpdate in
# the settings files (the highest precedence wins: local, then shared project, then
# user), else the one in known_marketplaces.json, else off. DISABLE_UPDATES,
# DISABLE_AUTOUPDATER and CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC switch the whole
# pass off unless FORCE_AUTOUPDATE_PLUGINS is set. Says nothing when Claude Code
# knows no such marketplace here (a working tree loaded with --plugin-dir).
doctor_updates() {
  local files=() f root v state="" listed=0 blocked="" how
  files=("$(statusline_settings)")
  root=$(git rev-parse --show-toplevel 2> /dev/null) || root=""
  [ -z "$root" ] || files+=("$root/.claude/settings.json" "$root/.claude/settings.local.json")
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    v=$(jq -r --arg m "$VBW_MARKETPLACE" '.extraKnownMarketplaces[$m] | if type == "object" then (.autoUpdate | if type == "boolean" then tostring else "none" end) else "absent" end' "$f" 2> /dev/null) || continue
    case "$v" in
      true | false) state=$v; listed=1 ;;
      none) listed=1 ;;
    esac
  done
  f="${CLAUDE_CODE_PLUGIN_CACHE_DIR:-$(vbw_claude_dir)/plugins}/known_marketplaces.json"
  if [ -f "$f" ]; then
    v=$(jq -r --arg m "$VBW_MARKETPLACE" 'if type == "object" and (.[$m] | type) == "object" then (.[$m].autoUpdate | if type == "boolean" then tostring else "none" end) else "absent" end' "$f" 2> /dev/null) || v=absent
    case "$v" in
      true | false) [ -n "$state" ] || state=$v; listed=1 ;;
      none) listed=1 ;;
    esac
  fi
  [ "$listed" -eq 1 ] || return 0
  if ! env_truthy "${FORCE_AUTOUPDATE_PLUGINS:-}"; then
    if env_truthy "${DISABLE_UPDATES:-}"; then blocked=DISABLE_UPDATES
    elif env_truthy "${DISABLE_AUTOUPDATER:-}"; then blocked=DISABLE_AUTOUPDATER
    elif [ -n "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" ]; then blocked=CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
    fi
  fi
  how="/plugin, Marketplaces tab, $VBW_MARKETPLACE, Enable auto-update"
  if [ -n "$blocked" ]; then
    how="unset $blocked, or set FORCE_AUTOUPDATE_PLUGINS=1 to keep Claude Code's plugin updates on; /vbw:update updates by hand"
    [ "$state" = true ] || how="unset $blocked, or set FORCE_AUTOUPDATE_PLUGINS=1; then turn it on in Claude Code ($VBW_MARKETPLACE: /plugin, Marketplaces tab, Enable auto-update). /vbw:update updates by hand"
    doctor_line warn "auto-update is off for VBW's marketplace ($VBW_MARKETPLACE): $blocked is set, which switches off Claude Code's plugin updates too, so nothing tells you a new VBW is out" "$how"
  elif [ "$state" = true ]; then
    doctor_line ok "auto-update is on for VBW's marketplace ($VBW_MARKETPLACE): Claude Code updates VBW in the background and tells you with \"Plugin updated: vbw · Run /reload-plugins to apply\""
  else
    doctor_line warn "auto-update is off for VBW's marketplace ($VBW_MARKETPLACE): Claude Code does not fetch a new VBW and nothing tells you one is out" "update by hand with /vbw:update, or have Claude Code do it: $how"
  fi
}

doctor_sessions() {
  local dir n
  dir="$(vbw_claude_dir)/sessions"
  if [ -d "$dir" ] && [ -r "$dir" ]; then
    n=$(sessions_registry | jq 'length' 2> /dev/null || echo 0)
    doctor_line ok "session names: Claude Code's list of chats ($dir) is readable, $n entries"
  else
    doctor_line info "session names: Claude Code's list of chats ($dir) not found: run holders are shown by their id"
  fi
}

doctor_statusline() {
  local state
  state=$(cmd_statusline status 2> /dev/null)
  case "$state" in
    *"an older VBW status line"*) doctor_line warn "the VBW status line was set by an older VBW" "vbw statusline on" ;;
    *"refreshed on events only"*) doctor_line warn "the VBW status line refreshes on events only, so it can look frozen while a workflow runs" "vbw statusline on" ;;
    on:*) doctor_line ok "VBW status line" ;;
    *) doctor_line warn "the VBW status line is not on" "vbw statusline on" ;;
  esac
}

doctor_project() {
  VBW_DIR="$VBW_ROOT/.vbw"
  VBW_RECORD="$VBW_DIR/record.json"
  [ ! -d "$VBW_ROOT/.vbw-planning" ] \
    || doctor_line info "VBW 1 project data (.vbw-planning/) is here; VBW 2 does not use it"
  if [ ! -f "$VBW_RECORD" ]; then
    doctor_line info "not a VBW project yet (/vbw:init)"
    return 0
  fi
  local v n
  if n=$(record_newer_schema "$VBW_RECORD"); then
    doctor_line fail "this project needs a newer VBW: its record was written with schema $n, this VBW reads up to schema $VBW_SCHEMA_MAX" "update VBW with /vbw:update"
    return 0
  elif v=$(record_violation "$VBW_RECORD"); then
    doctor_line ok "the plan of record is valid"
    local dbranch
    if dbranch=$(git -C "$VBW_ROOT" symbolic-ref --short -q HEAD 2> /dev/null) && [ -n "$dbranch" ]; then
      doctor_line info "the next VBW commit lands on branch $dbranch"
    else
      doctor_line info "the next VBW commit lands on detached HEAD at $(git -C "$VBW_ROOT" rev-parse HEAD 2> /dev/null | cut -c1-12)"
    fi
  else doctor_line fail "the plan of record is corrupt: $v" "restore .vbw/record.json from git (git checkout -- .vbw/record.json)"
  fi
  # shellcheck source=cmd-spec.sh
  . "$VBW_LIB/cmd-spec.sh"
  if spec_parse > /dev/null 2>&1; then doctor_line ok "the spec is valid"
  else doctor_line fail "the spec has errors" "vbw spec check shows them"
  fi
  local hid hidden fix='remove that line, or change it to .vbw/runtime/'
  hidden=$(cd "$VBW_ROOT" && record_hidden) || true
  if [ -n "$hidden" ]; then
    while IFS= read -r hid; do
      [ -z "$hid" ] || doctor_line fail "${hid%: "$fix"}" "$fix"
    done <<< "$hidden"
  fi
  doctor_big_ignored
  [ -n "$v" ] && return 0
  if jq -e '.lease != null' "$VBW_RECORD" > /dev/null; then
    doctor_line warn "a run is open ($(jq -r .lease.run "$VBW_RECORD"))" "if no VBW workflow is running: vbw run end"
  fi
  if contract_approved "$(contract_hash "$(cat "$VBW_RECORD")")"; then doctor_line ok "the contract is approved"
  elif jq -e '(.checks | length) > 0' "$VBW_RECORD" > /dev/null; then
    doctor_line info "the contract is not approved (yet, or since it changed): VBW asks with the approval menu after you review it"
  fi
  doctor_guard
}

# Large git-ignored folders the Clean copy section does not list yet (R253).
doctor_big_ignored() {
  local line name listed=''
  # shellcheck source=proofcopy.sh
  . "$VBW_LIB/proofcopy.sh"
  if [ -f "$VBW_RECORD" ]; then
    listed=$(jq -r '(.project.leave_out // [])[] | sub("/+$"; "")' "$VBW_RECORD" 2> /dev/null) || listed=''
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%% (*}
    if [ -n "$listed" ] && printf '%s\n' "$listed" | grep -qxF "${name%/}"; then continue; fi
    doctor_line info "large git-ignored folder $line is copied into every proof copy" "list $name under Clean copy in .vbw/spec.md, then vbw spec sync"
  done < <(proofcopy_big_ignored 2> /dev/null)
}

# The guard works with this jq: it must deny a destructive command here.
doctor_guard() {
  local out g=/dev/null d="${VBW_RECORD%/*}/runtime/glance.json"
  if [ -f "$VBW_RECORD" ] && [ -f "$d" ] && [ -r "$d" ] && [ "$d" -nt "$VBW_RECORD" ]; then g=$d; fi
  out=$(jq -nc --arg d "$VBW_ROOT" '{tool_name: "Bash", cwd: $d, tool_input: {command: "git reset --hard"}}' \
    | jq -nc --rawfile glance "$g" --arg root "$VBW_ROOT" -f "$VBW_PLUGIN/hooks/guard-bash.jq" - "$VBW_RECORD" "$VBW_PLUGIN/hooks/end.json" 2> /dev/null)
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1; then doctor_line ok "the guards work"
  else doctor_line fail "the guards do not work with this jq" "update jq, then run vbw doctor again"
  fi
}
