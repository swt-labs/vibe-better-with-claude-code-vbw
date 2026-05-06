#!/bin/bash
set -u
# PreToolUse hook: Block destructive Bash commands
# Exit 2 = block, Exit 0 = allow
# Fail-CLOSED: exit 2 on parse error (never allow unvalidated input through)

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate bash command" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 2
[ -z "$COMMAND" ] && exit 0  # No command = nothing to check

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -z "${VBW_PLANNING_DIR:-}" ] && [ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
  # shellcheck source=lib/vbw-config-root.sh
  if source "$SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
    find_vbw_root "$SCRIPT_DIR" >/dev/null 2>&1 || true
  fi
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
DEFAULT_PATTERNS="$PLUGIN_ROOT/config/destructive-commands.txt"
LOCAL_PATTERNS="$PLANNING_DIR/destructive-commands.local.txt"

normalize_agent_role() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"

  case "$lower" in
    vbw-scout|vbw-scout-[0-9]*|scout|scout-[0-9]*|team-scout|team-scout-[0-9]*)
      printf 'scout'
      return 0
      ;;
    vbw-lead|vbw-lead-[0-9]*|lead|lead-[0-9]*|team-lead|team-lead-[0-9]*)
      printf 'lead'
      return 0
      ;;
    vbw-dev|vbw-dev-[0-9]*|dev|dev-[0-9]*|team-dev|team-dev-[0-9]*)
      printf 'dev'
      return 0
      ;;
    vbw-qa|vbw-qa-[0-9]*|qa|qa-[0-9]*|team-qa|team-qa-[0-9]*)
      printf 'qa'
      return 0
      ;;
    vbw-debugger|vbw-debugger-[0-9]*|debugger|debugger-[0-9]*|team-debugger|team-debugger-[0-9]*)
      printf 'debugger'
      return 0
      ;;
    vbw-architect|vbw-architect-[0-9]*|architect|architect-[0-9]*|team-architect|team-architect-[0-9]*)
      printf 'architect'
      return 0
      ;;
    vbw-docs|vbw-docs-[0-9]*|docs|docs-[0-9]*|team-docs|team-docs-[0-9]*)
      printf 'docs'
      return 0
      ;;
  esac

  return 1
}

detect_agent_role() {
  local candidate role

  for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
    [ -z "$candidate" ] && continue
    if role=$(normalize_agent_role "$candidate"); then
      printf '%s' "$role"
      return 0
    fi
  done

  if [ -f "$PLANNING_DIR/.active-agent" ]; then
    candidate=$(cat "$PLANNING_DIR/.active-agent" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    if [ -n "$candidate" ] && role=$(normalize_agent_role "$candidate"); then
      printf '%s' "$role"
      return 0
    fi
  fi

  return 1
}

ACTIVE_AGENT_ROLE=""
if ACTIVE_AGENT_ROLE=$(detect_agent_role); then
  :
else
  ACTIVE_AGENT_ROLE=""
fi

# Build combined pattern from all sources
PATTERNS=""
for PFILE in "$DEFAULT_PATTERNS" "$LOCAL_PATTERNS"; do
  [ -f "$PFILE" ] || continue
  # Strip comments and empty lines, join with |
  FILE_PATTERNS=$(grep -v '^\s*#' "$PFILE" | grep -v '^\s*$' | tr '\n' '|' | sed 's/|$//')
  [ -n "$FILE_PATTERNS" ] && {
    [ -n "$PATTERNS" ] && PATTERNS="$PATTERNS|$FILE_PATTERNS" || PATTERNS="$FILE_PATTERNS"
  }
done

log_block_event() {
  local matched="$1"
  local preview matched_esc agent ts

  if [ -d "$PLANNING_DIR" ]; then
    preview=$(echo "$COMMAND" | head -c 40)
    agent="${ACTIVE_AGENT_ROLE:-${VBW_ACTIVE_AGENT:-unknown}}"
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
    preview=$(echo "$preview" | sed 's/"/\\"/g')
    matched_esc=$(echo "$matched" | sed 's/"/\\"/g')
    printf '{"event":"bash_guard_block","command_preview":"%s","pattern_matched":"%s","agent":"%s","timestamp":"%s"}\n' \
      "$preview" "$matched_esc" "$agent" "$ts" >> "$PLANNING_DIR/.event-log.jsonl" 2>/dev/null
  fi
}

block_scout_command() {
  local reason="$1"
  echo "Blocked: Scout Bash is read-only ($reason)" >&2
  log_block_event "scout:$reason"
  exit 2
}

has_shell_file_write_redirection() {
  local command="$1"
  local i=0 len ch next in_single=0 in_double=0 escaped=0

  len=${#command}
  while [ "$i" -lt "$len" ]; do
    ch="${command:$i:1}"

    if [ "$escaped" -eq 1 ]; then
      escaped=0
      i=$((i + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$ch" = "'" ] && in_single=0
      i=$((i + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$ch" = "\\" ]; then
        escaped=1
      elif [ "$ch" = '"' ]; then
        in_double=0
      fi
      i=$((i + 1))
      continue
    fi

    case "$ch" in
      "'")
        in_single=1
        ;;
      '"')
        in_double=1
        ;;
      "\\")
        escaped=1
        ;;
      ">")
        return 0
        ;;
      "<")
        next="${command:$((i + 1)):1}"
        [ "$next" = "<" ] && return 0
        ;;
    esac

    i=$((i + 1))
  done

  return 1
}

check_scout_command() {
  local command="$1"
  local matched=""

  if [ -n "$PATTERNS" ] && echo "$command" | grep -iqE "$PATTERNS"; then
    matched=$(echo "$command" | grep -ioE "$PATTERNS" | head -1)
    block_scout_command "destructive command detected: $matched"
  fi

  if has_shell_file_write_redirection "$command"; then
    block_scout_command "shell file write/redirection"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])tee([[:space:]]|$)'; then
    block_scout_command "tee can write files"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])((npm|pnpm|yarn|bun)([[:space:]]+(--prefix|--dir|--cwd|-C)(=|[[:space:]]+)[^[:space:];|&]+|[[:space:]]+--[[:alnum:]-]+(=[^[:space:];|&]+)?)*[[:space:]]+(install|i|ci|add|update|upgrade|remove|uninstall)|pip3?[[:space:]]+install|bundle[[:space:]]+install|gem[[:space:]]+install|cargo[[:space:]]+(install|update|add)|go[[:space:]]+get|brew[[:space:]]+(install|upgrade|uninstall)|apt(-get)?[[:space:]]+(install|upgrade|remove)|composer[[:space:]]+(install|update|require|remove))([[:space:]]|$)'; then
    block_scout_command "package or dependency mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])(rm|mv|cp|mkdir|rmdir|touch|chmod|chown|ln|install|truncate)([[:space:]]|$)'; then
    block_scout_command "filesystem mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])sed[[:space:]][^;|&]*(--in-place(=|[[:space:]]|$)|-[^[:space:];|&]*i([^[:alnum:]]|$))|(^|[[:space:];|&])perl[[:space:]][^;|&]*-[^[:space:];|&]*p?i([^[:alnum:]]|$)'; then
    block_scout_command "in-place edit command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:];|&]+|[[:space:]]+(--no-pager|--bare|--literal-pathspecs|--[[:alnum:]-]+(=[^[:space:];|&]+)?))*[[:space:]]+(add|commit|push|reset|checkout|switch|merge|rebase|cherry-pick|tag|branch|clean|stash|restore|rm|mv|pull|fetch)([[:space:]]|$)'; then
    block_scout_command "git state mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])((systemctl|service|launchctl)[[:space:]]+(start|stop|restart|reload)|brew[[:space:]]+services[[:space:]]+(start|stop|restart)|docker([[:space:]]+compose)?[[:space:]]+(up|down|rm|rmi|volume|system|network))([[:space:]]|$)'; then
    block_scout_command "service/container mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])curl([^;|&]*)(-X[[:space:]]*(POST|PUT|PATCH|DELETE)|-X(POST|PUT|PATCH|DELETE)|--request(=|[[:space:]]+)(POST|PUT|PATCH|DELETE)|--data($|[=[:space:]-])|--data-[[:alnum:]-]+(=|[[:space:]]|$)|--json(=|[[:space:]]|$)|-d($|[[:space:]]|[^[:space:];|&])|--form(=|[[:space:]]|$)|-F($|[[:space:]]|[^[:space:];|&])|-T($|[[:space:]]|[^[:space:];|&])|--upload-file(=|[[:space:]]|$))'; then
    block_scout_command "mutating curl request"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])curl([^;|&]*)(-[[:alnum:]]*o[[:alnum:]]*($|[[:space:]]|[^[:space:];|&])|--output(=|[[:space:]]|$)|--output-dir(=|[[:space:]]|$)|--remote-name([[:space:]]|$))|(^|[[:space:];|&])wget([[:space:]]|$)'; then
    block_scout_command "local output file command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:]/])\.env($|[[:space:]/.;|&])|\.env\.[^[:space:];|&]*|id_(rsa|dsa|ed25519)|\.(pem|p12|pfx)($|[[:space:];|&])|private[-_]?key|credentials(\.json)?|secrets?(\.(json|ya?ml|txt))?|(^|[[:space:]/])\.git($|/|[[:space:];|&])'; then
    block_scout_command "sensitive file read"
  fi
}

if [ "$ACTIVE_AGENT_ROLE" = "scout" ]; then
  check_scout_command "$COMMAND"
fi

# --- Override checks for the generic destructive-command classifier ---

# Env var override
[ "${VBW_ALLOW_DESTRUCTIVE:-0}" = "1" ] && exit 0

# Config override: bash_guard=false disables generic destructive classifier.
if [ -f "$PLANNING_DIR/config.json" ]; then
  GUARD=$(jq -r '.bash_guard // true' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "$GUARD" = "false" ] && exit 0
fi

# No patterns loaded = nothing to check
[ -z "$PATTERNS" ] && exit 0

# --- Match ---

if echo "$COMMAND" | grep -iqE "$PATTERNS"; then
  # Extract which pattern matched (for logging)
  MATCHED=$(echo "$COMMAND" | grep -ioE "$PATTERNS" | head -1)
  echo "Blocked: destructive command detected ($MATCHED)" >&2
  echo "Hint: Use VBW_ALLOW_DESTRUCTIVE=1 to override, or run outside VBW." >&2
  echo "See: config/destructive-commands.txt for the full blocklist." >&2
  log_block_event "$MATCHED"

  exit 2
fi

exit 0
