#!/usr/bin/env bash
# vbw auto on SESSION_ID | off [SESSION_ID] | status | gate: autonomous runs (build plan K6, G1).
# `on SESSION_ID` arms one session (/vbw:vibe passes ${CLAUDE_SESSION_ID});
# `gate` is the Stop hook of /vbw:vibe: while armed, it blocks the stop with
# the next step until a human gate, ship, or settings.autonomy_cap steps. It
# lets the session stop while a workflow runs (its result wakes the session)
# and ignores every other session. One state file per session
# (.vbw/runtime/auto.SESSION.json): a session only ever touches its own.

cmd_auto() {
  local sub="${1:-}" sid=""
  case "$sub" in
    on) [ $# -eq 2 ] && [[ "$2" =~ ^[A-Za-z0-9_-]+$ ]] || vbw_usage_error "usage: vbw auto on SESSION_ID"; sid="$2" ;;
    off|status)
      [ $# -le 2 ] || vbw_usage_error "usage: vbw auto $sub [SESSION_ID]"
      sid="${2:-$(vbw_session)}"
      [[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || vbw_usage_error "vbw auto $sub needs a SESSION_ID (or run it inside a Claude Code session)" ;;
    gate) [ $# -eq 1 ] || vbw_usage_error "usage: vbw auto gate" ;;
    *) vbw_usage_error "usage: vbw auto on SESSION_ID | off [SESSION_ID] | status [SESSION_ID] | gate" ;;
  esac
  # The gate reads its hook input before anything can fail.
  local input=""
  [ "$sub" = gate ] && input=$(cat)
  vbw_require_project
  local file="$VBW_RUNTIME/auto.$sid.json"
  case "$sub" in
    on)
      auto_write "$file" "$(record_read | jq -c --arg s "$sid" --arg at "$(vbw_now)" \
        '{session: $s, steps: 0, cap: .settings.autonomy_cap, armed_at: $at}')"
      jq -r '"autonomous run armed for this session (at most \(.cap) steps; it stops at the first decision that needs you)"' "$file"
      ;;
    off)
      rm -f "$file"
      printf 'autonomous run off\n'
      ;;
    status)
      if [ -f "$file" ]; then jq -r '"armed: step \(.steps) of \(.cap), since \(.armed_at)"' "$file"; else printf 'off\n'; fi
      ;;
    gate) auto_gate "$input" ;;
  esac
}

auto_write() {
  local tmp
  tmp=$(mktemp "$VBW_RUNTIME/auto.XXXXXX") || vbw_die "cannot write $VBW_RUNTIME"
  printf '%s\n' "$2" > "$tmp"
  mv "$tmp" "$1"
}

# Prints a Stop hook decision, or nothing (the stop proceeds).
auto_gate() {
  local file session next action steps cap
  session=$(printf '%s' "$1" | jq -r '.session_id // empty' 2> /dev/null || true)
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
  file="$VBW_RUNTIME/auto.$session.json"
  [ -f "$file" ] || return 0
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  next=$(cmd_next --json)
  action=$(printf '%s' "$next" | jq -r .action)
  [ "$action" = run ] && return 0
  if printf '%s' "$next" | jq -e .gate > /dev/null; then
    rm -f "$file"
    printf '%s' "$next" | jq -c '{systemMessage: "VBW autonomous run stopped: this step needs you. \(.action): \(.instruction)"}'
    return 0
  fi
  steps=$(( $(jq -r .steps "$file") + 1 ))
  cap=$(jq -r .cap "$file")
  if [ "$steps" -gt "$cap" ]; then
    rm -f "$file"
    jq -nc --argjson c "$cap" '{systemMessage: "VBW autonomous run stopped after \($c) steps (settings.autonomy_cap). Run /vbw:vibe --auto to continue."}'
    return 0
  fi
  auto_write "$file" "$(jq -c --argjson n "$steps" '.steps = $n' "$file")"
  printf '%s' "$next" | jq -c --argjson n "$steps" --argjson c "$cap" \
    '{decision: "block", reason: "VBW autonomous run, step \($n) of \($c). Next: \(.action): \(.instruction). Do this step now as /vbw:vibe describes, then stop."}'
}
