#!/bin/bash
set -u
# PreToolUse hook: Block access to sensitive files
# Exit 2 = block tool call, Exit 0 = allow
# Fail-CLOSED: exit 2 on any parse error (never allow unvalidated input through)

# Verify jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate file path" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' 2>/dev/null) || exit 2

if [ -z "$FILE_PATH" ]; then
  exit 2
fi

# Sensitive file patterns
# Directory patterns use (^|/) anchoring so they match only as path components,
# not as substrings of unrelated directory names (e.g. "corvex-build/" != "build/").
if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|(^|/)node_modules/|(^|/)\.git/|(^|/)dist/|(^|/)build/'; then
  echo "Blocked: sensitive file ($FILE_PATH)" >&2
  exit 2
fi

# Block GSD's .planning/ directory when VBW is actively running.
# Only enforce when VBW markers are present (session or agent), so GSD can
# still write to its own directory when VBW is not the active caller.
# Stale marker protection: ignore markers older than 24h to avoid false positives
# from crashed sessions that didn't clean up.
is_marker_fresh() {
  local marker="$1"
  [ ! -f "$marker" ] && return 1
  local now marker_mtime age
  now=$(date +%s)
  if [ "$(uname)" = "Darwin" ]; then
    marker_mtime=$(stat -f %m "$marker" 2>/dev/null || echo 0)
  else
    marker_mtime=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
  fi
  age=$((now - marker_mtime))
  [ "$age" -lt 86400 ]
}

derive_project_root() {
  local path="$1"
  local marker_dir="$2"
  local root

  root="${path%%/$marker_dir/*}"
  if [ -z "$root" ] || [ "$root" = "$path" ]; then
    root="."
  fi

  printf '%s' "$root"
}

if echo "$FILE_PATH" | grep -qF '.planning/' && ! echo "$FILE_PATH" | grep -qF '.vbw-planning/'; then
  GSD_ROOT=$(derive_project_root "$FILE_PATH" ".planning")
  if is_marker_fresh "$GSD_ROOT/.vbw-planning/.active-agent" || is_marker_fresh "$GSD_ROOT/.vbw-planning/.vbw-session"; then
    echo "Blocked: .planning/ is managed by GSD, not VBW ($FILE_PATH)" >&2
    exit 2
  fi
fi

# .vbw-planning/ is VBW's own directory — never block VBW from its own state.
# Previous marker-based isolation (.gsd-isolation + .active-agent + .vbw-session)
# caused false blocks: orchestrator after team deletion, agents before markers set,
# Read calls before prompt-preflight runs. GSD isolation is enforced by CLAUDE.md
# instructions + the .planning/ block above (which prevents VBW from touching GSD).
# Removed: self-blocking of .vbw-planning/ (v1.21.13).

exit 0
