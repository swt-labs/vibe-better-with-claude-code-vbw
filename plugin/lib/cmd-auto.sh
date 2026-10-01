#!/usr/bin/env bash
# vbw auto on|off|status|gate: autonomous runs (build plan K6, probe G1).
# `on` arms this session (VBW_SESSION_ID, exported by the SessionStart hook);
# `gate` is the Stop hook of /vbw:vibe: while armed, it blocks the stop with
# the next step until a human gate, ship, or settings.autonomy_cap steps. It
# lets the session stop while a workflow runs (its result wakes the session)
# and ignores every other session. State lives in .vbw/runtime/auto.json.

cmd_auto() {
  local sub="${1:-}"
  case "$sub" in
    on|off|status|gate) [ $# -eq 1 ] || vbw_usage_error "usage: vbw auto $sub" ;;
    *) vbw_usage_error "usage: vbw auto on | off | status | gate" ;;
  esac
  # The gate reads its hook input before anything can fail.
  local input=""
  [ "$sub" = gate ] && input=$(cat)
  vbw_require_project
  local file="$VBW_RUNTIME/auto.json"
  case "$sub" in
    on)
      [ -n "${VBW_SESSION_ID:-}" ] || vbw_die "no session id: autonomy needs the VBW plugin's SessionStart hook (restart Claude Code)"
      auto_write "$file" "$(record_read | jq -c --arg s "$VBW_SESSION_ID" --arg at "$(vbw_now)" \
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
    gate) auto_gate "$file" "$input" ;;
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
  local file="$1" session next action steps cap
  [ -f "$file" ] || return 0
  session=$(printf '%s' "$2" | jq -r '.session_id // empty' 2> /dev/null || true)
  [ -n "$session" ] && [ "$session" = "$(jq -r .session "$file")" ] || return 0
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
