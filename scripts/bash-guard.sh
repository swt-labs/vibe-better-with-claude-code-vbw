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

  if [ -f "$PLANNING_DIR/.active-agent-roles" ] && awk '$1 == "scout" && ($2 ~ /^[0-9]+$/) && $2 > 0 { found=1 } END { exit found ? 0 : 1 }' "$PLANNING_DIR/.active-agent-roles" 2>/dev/null; then
    printf 'scout'
    return 0
  fi

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

command_has_command_substitution() {
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

    case "$ch" in
      "'")
        [ "$in_double" -eq 0 ] && in_single=1
        ;;
      '"')
        if [ "$in_double" -eq 1 ]; then
          in_double=0
        else
          in_double=1
        fi
        ;;
      "\\")
        escaped=1
        ;;
      '$')
        next="${command:$((i + 1)):1}"
        [ "$next" = "(" ] && return 0
        ;;
      '`')
        return 0
        ;;
    esac

    i=$((i + 1))
  done

  return 1
}

command_has_process_substitution() {
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
      "<"|">")
        next="${command:$((i + 1)):1}"
        [ "$next" = "(" ] && return 0
        ;;
    esac

    i=$((i + 1))
  done

  return 1
}

command_without_quoted_text() {
  local command="$1"
  local i=0 len ch out="" in_single=0 in_double=0 escaped=0

  len=${#command}
  while [ "$i" -lt "$len" ]; do
    ch="${command:$i:1}"

    if [ "$escaped" -eq 1 ]; then
      out="${out} "
      escaped=0
      i=$((i + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$ch" = "'" ] && in_single=0
      out="${out} "
      i=$((i + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$ch" = "\\" ]; then
        escaped=1
      elif [ "$ch" = '"' ]; then
        in_double=0
      fi
      out="${out} "
      i=$((i + 1))
      continue
    fi

    case "$ch" in
      "'")
        in_single=1
        out="${out} "
        ;;
      '"')
        in_double=1
        out="${out} "
        ;;
      "\\")
        escaped=1
        out="${out} "
        ;;
      *)
        out="${out}${ch}"
        ;;
    esac

    i=$((i + 1))
  done

  printf '%s' "$out"
}

command_has_unquoted_eval() {
  local command="$1"
  local masked

  masked=$(command_without_quoted_text "$command")
  echo "$masked" | grep -qE '(^|[[:space:];|&(){}])eval([[:space:];|&(){}]|$)'
}

is_shell_interpreter_token() {
  case "$1" in
    bash|sh|zsh|dash|ksh|fish)
      return 0
      ;;
  esac

  return 1
}

token_has_shell_c_option() {
  case "$1" in
    -c|--command|--command=*)
      return 0
      ;;
    --*)
      return 1
      ;;
    -*)
      echo "${1#-}" | grep -q 'c'
      return $?
      ;;
  esac

  return 1
}

segment_has_shell_c_invocation() {
  local segment="$1"
  local token saw_shell=0 skip_next_shell_option_arg=0

  for token in $segment; do
    if [ "$saw_shell" -eq 1 ]; then
      if [ "$skip_next_shell_option_arg" -eq 1 ]; then
        skip_next_shell_option_arg=0
        continue
      fi

      if token_has_shell_c_option "$token"; then
        return 0
      fi

      case "$token" in
        -o|-O|--init-file|--rcfile)
          skip_next_shell_option_arg=1
          continue
          ;;
        --init-file=*|--rcfile=*)
          continue
          ;;
        -*)
          continue
          ;;
        *)
          saw_shell=0
          ;;
      esac
    fi

    if is_shell_interpreter_token "$token"; then
      saw_shell=1
      skip_next_shell_option_arg=0
      continue
    fi
  done

  return 1
}

command_has_nested_shell_execution() {
  local command="$1"
  local masked segment segments

  masked=$(command_without_quoted_text "$command")
  masked=$(printf '%s' "$masked" | tr '(){}!' '     ')
  segments=$(printf '%s' "$masked" | tr ';|&' '\n')
  while IFS= read -r segment; do
    if segment_has_shell_c_invocation "$segment"; then
      return 0
    fi
  done <<< "$segments"

  return 1
}

curl_uses_get_query_mode() {
  local command="$1"
  echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)(--get([[:space:]]|$)|-[[:alnum:]]*G[[:alnum:]]*([[:space:]]|$))'
}

gh_api_uses_explicit_get() {
  local command="$1"
  echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--method(=|[[:space:]]+)[Gg][Ee][Tt]|-X[[:space:]]*[Gg][Ee][Tt]|-X[Gg][Ee][Tt])'
}

scout_git_segments_are_readonly() {
  local command="$1"
  local segment segments

  segments=$(printf '%s' "$command" | tr ';|&' '\n')
  while IFS= read -r segment; do
    if echo "$segment" | grep -qE '^[[:space:]]*git[[:space:]]+'; then
      if ! echo "$segment" | grep -qE '^[[:space:]]*git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:]]+|[[:space:]]+(--no-pager|--bare|--literal-pathspecs|--[[:alnum:]-]+(=[^[:space:]]+)?))*[[:space:]]+(status|log|show|diff|ls-files|grep|rev-parse|cat-file|ls-tree|blame|describe)([[:space:]]|$)'; then
        return 1
      fi
    fi
  done <<< "$segments"

  return 0
}

scout_gh_segments_are_readonly() {
  local command="$1"
  local segment segments

  segments=$(printf '%s' "$command" | tr ';|&' '\n')
  while IFS= read -r segment; do
    if echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+'; then
      if echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+api([[:space:]]|$)'; then
        continue
      fi
      if ! echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+((auth[[:space:]]+status|status)([[:space:]]|$)|issue[[:space:]]+(view|list|status)([[:space:]]|$)|pr[[:space:]]+(view|list|status|checks|diff)([[:space:]]|$)|repo[[:space:]]+(view|list)([[:space:]]|$)|release[[:space:]]+(view|list)([[:space:]]|$)|run[[:space:]]+(view|list)([[:space:]]|$)|workflow[[:space:]]+(view|list)([[:space:]]|$)|search[[:space:]]+(issues|prs|repos|code)([[:space:]]|$))'; then
        return 1
      fi
    fi
  done <<< "$segments"

  return 0
}

check_scout_command() {
  local command="$1"
  local matched=""

  if [ -n "$PATTERNS" ] && echo "$command" | grep -iqE "$PATTERNS"; then
    matched=$(echo "$command" | grep -ioE "$PATTERNS" | head -1)
    block_scout_command "destructive command detected: $matched"
  fi

  if command_has_command_substitution "$command"; then
    block_scout_command "command substitution"
  fi

  if command_has_process_substitution "$command"; then
    block_scout_command "process substitution"
  fi

  if command_has_unquoted_eval "$command"; then
    block_scout_command "eval command"
  fi

  if command_has_nested_shell_execution "$command"; then
    block_scout_command "nested shell execution"
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

  if echo "$command" | grep -qE '(^|[[:space:];|&])git([^;|&]*)[[:space:]]+diff([^;|&]*)(--output(=|[[:space:]]|$))'; then
    block_scout_command "git output file command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])git[[:space:]]+' && ! scout_git_segments_are_readonly "$command"; then
    block_scout_command "git state mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:];|&]+|[[:space:]]+(--no-pager|--bare|--literal-pathspecs|--[[:alnum:]-]+(=[^[:space:];|&]+)?))*[[:space:]]+(add|commit|push|reset|checkout|switch|merge|rebase|cherry-pick|tag|branch|clean|stash|restore|rm|mv|pull|fetch)([[:space:]]|$)'; then
    block_scout_command "git state mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])((systemctl|service|launchctl)[[:space:]]+(start|stop|restart|reload)|brew[[:space:]]+services[[:space:]]+(start|stop|restart)|docker([[:space:]]+compose)?[[:space:]]+(up|down|rm|rmi|volume|system|network))([[:space:]]|$)'; then
    block_scout_command "service/container mutation command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)([[:space:]]-X[[:space:]]*([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|[[:space:]]-X([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|--request(=|[[:space:]]+)([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|--data($|[=[:space:]])|--data-(ascii|raw|binary)(=|[[:space:]]|$)|--json(=|[[:space:]]|$)|[[:space:]]-[[:alnum:]]*d($|[[:space:]]|[^[:space:];|&])|--form(=|[[:space:]]|$)|[[:space:]]-[[:alnum:]]*F($|[[:space:]]|[^[:space:];|&])|[[:space:]]-[[:alnum:]]*T($|[[:space:]]|[^[:space:];|&])|--upload-file(=|[[:space:]]|$))'; then
    block_scout_command "mutating curl request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)--data-urlencode(=|[[:space:]]|$)' && ! curl_uses_get_query_mode "$command"; then
    block_scout_command "mutating curl request"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])curl([^;|&]*)([[:space:]]-[[:alnum:]]*o[[:alnum:]]*($|[[:space:]]|[^[:space:];|&])|--output(=|[[:space:]]|$)|--output-dir(=|[[:space:]]|$)|--remote-name([[:space:]]|$))|(^|[[:space:];|&])wget([[:space:]]|$)'; then
    block_scout_command "local output file command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--method(=|[[:space:]]+)([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|-X[[:space:]]*([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|-X([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee]))'; then
    block_scout_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--input(=|[[:space:]]|$))'; then
    block_scout_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--field(=|[[:space:]]|$)|--raw-field(=|[[:space:]]|$)|-f($|[[:space:]]|[^[:space:];|&])|-F($|[[:space:]]|[^[:space:];|&]))' && ! gh_api_uses_explicit_get "$command"; then
    block_scout_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+' && ! scout_gh_segments_are_readonly "$command"; then
    block_scout_command "mutating gh command"
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
