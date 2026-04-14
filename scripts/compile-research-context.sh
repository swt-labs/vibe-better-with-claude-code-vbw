#!/usr/bin/env bash
# compile-research-context.sh — Discover and return relevant standalone research
# for debug/fix sessions. Research injection is optional: if no match is found
# or the research is too stale, outputs nothing and debug/fix proceed as today.
#
# Usage:
#   compile-research-context.sh <planning-dir> [description]
#   compile-research-context.sh <planning-dir> --file <path>
#
# Output:
#   stdout: Research file content (with optional staleness warning), or empty
#   stderr: File path when matched, skip messages when stale/no-match
#
# Exit: Always 0 (caller uses empty stdout to detect no-research)

set -euo pipefail

# ── Staleness thresholds (tunable) ───────────────────────
STALE_WARN_THRESHOLD=10   # 1..WARN = inject with warning; >WARN = skip entirely

PLANNING_DIR="${1:-}"
if [ -z "$PLANNING_DIR" ]; then
  echo "Usage: compile-research-context.sh <planning-dir> [description]" >&2
  exit 0
fi
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse arguments ──────────────────────────────────────
EXPLICIT_FILE=""
DESCRIPTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      EXPLICIT_FILE="${2:-}"
      if [ -z "$EXPLICIT_FILE" ]; then
        echo "[research] --file requires a path argument" >&2
        exit 0
      fi
      shift 2
      ;;
    *)
      if [ -n "$DESCRIPTION" ]; then
        DESCRIPTION="${DESCRIPTION} $1"
      else
        DESCRIPTION="$1"
      fi
      shift
      ;;
  esac
done

# ── Staleness check ─────────────────────────────────────
# Returns: 0=fresh, 1=warn, 2=skip
check_staleness() {
  local file="$1"
  local base_commit
  base_commit=$(awk '
    /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
    in_fm && index($0, "base_commit:") == 1 {
      val = substr($0, length("base_commit:") + 1)
      sub(/^[[:space:]]*/, "", val)
      print val
      exit
    }
  ' "$file")

  if [ -z "$base_commit" ]; then
    return 2  # No base_commit = treat as stale
  fi

  if [ "$base_commit" = "unknown" ]; then
    echo "unknown" >&2  # Migrated file — original commit not tracked
    return 1  # Warn but still inject (migrated files should be usable)
  fi

  # Verify the commit exists
  if ! git rev-parse --verify "$base_commit^{commit}" > /dev/null 2>&1; then
    return 2  # Invalid commit = treat as stale
  fi

  # Count commits since base_commit, excluding .vbw-planning/ changes
  local commit_count
  commit_count=$(git log --oneline "${base_commit}..HEAD" -- :/ ':!.vbw-planning' 2>/dev/null | wc -l | tr -d ' ')

  if [ "$commit_count" -eq 0 ]; then
    return 0  # Fresh
  elif [ "$commit_count" -le "$STALE_WARN_THRESHOLD" ]; then
    echo "$commit_count" >&2  # Pass count via stderr for warning message
    return 1  # Warn but inject
  else
    echo "$commit_count" >&2  # Pass count via stderr for skip message
    return 2  # Too stale (> STALE_WARN_THRESHOLD)
  fi
}

# ── Emit research content ───────────────────────────────
emit_research() {
  local file="$1"
  local staleness_status commit_count_str

  # Capture stderr from staleness check (contains commit count)
  commit_count_str=$(check_staleness "$file" 2>&1; echo "EXIT:$?") || true
  staleness_status="${commit_count_str##*EXIT:}"
  commit_count_str="${commit_count_str%EXIT:*}"
  commit_count_str=$(echo "$commit_count_str" | tr -d '[:space:]')

  case "$staleness_status" in
    0)
      # Fresh — emit content as-is
      echo "[research] Using fresh research: $(basename "$file")" >&2
      cat "$file"
      ;;
    1)
      # Warn — emit with staleness warning prepended
      local base_commit_short
      base_commit_short=$(awk '
        /^---$/ { if (!started) { started=1; in_fm=1; next } if (in_fm) exit }
        in_fm && index($0, "base_commit:") == 1 {
          val = substr($0, length("base_commit:") + 1)
          sub(/^[[:space:]]*/, "", val)
          print val
          exit
        }
      ' "$file" | head -c 8)
      if [ "$commit_count_str" = "unknown" ] || [ "$base_commit_short" = "unknown" ]; then
        echo "⚠ Staleness unknown — this research was migrated without a base commit. Verify findings against current code."
      else
        echo "⚠ ${commit_count_str} commits have landed since this research was created (${base_commit_short}..HEAD). Verify findings against current code."
      fi
      echo ""
      echo "[research] Using research with staleness warning: $(basename "$file") (${commit_count_str} commits since)" >&2
      cat "$file"
      ;;
    2|*)
      # Too stale — skip
      echo "[research] Skipping stale research ($(basename "$file")): ${commit_count_str:-unknown} commits since base_commit" >&2
      ;;
  esac
}

# ── Explicit file override ──────────────────────────────
if [ -n "$EXPLICIT_FILE" ]; then
  if [ ! -f "$EXPLICIT_FILE" ]; then
    echo "[research] Specified file not found: $EXPLICIT_FILE" >&2
    exit 0
  fi
  # Explicit override bypasses staleness checks
  echo "[research] Using explicitly specified research: $(basename "$EXPLICIT_FILE")" >&2
  cat "$EXPLICIT_FILE"
  exit 0
fi

# ── Discovery ────────────────────────────────────────────
# List completed research files
RESEARCH_LIST=$(bash "$SCRIPT_DIR/research-session-state.sh" list "$PLANNING_DIR" --status complete 2>/dev/null || echo "")

if [ -z "$RESEARCH_LIST" ]; then
  exit 0
fi

# Keyword matching against description (required for all file counts)
if [ -z "$DESCRIPTION" ]; then
  # No description to match against — output nothing (no recency fallback)
  exit 0
fi

# Extract significant words from description (3+ chars, lowercase)
DESC_WORDS=$(printf '%s' "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | awk 'length >= 3' | sort -u)

if [ -z "$DESC_WORDS" ]; then
  exit 0
fi

# Score each file by keyword hits in title
BEST_FILE=""
BEST_SCORE=0

while IFS= read -r line; do
  file=$(echo "$line" | jq -r '.file')
  title=$(echo "$line" | jq -r '.title')
  title_lower=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')

  score=0
  while IFS= read -r word; do
    [ -z "$word" ] && continue
    case "$title_lower" in
      *"$word"*) score=$((score + 1)) ;;
    esac
  done <<< "$DESC_WORDS"

  if [ "$score" -gt "$BEST_SCORE" ]; then
    BEST_SCORE=$score
    BEST_FILE=$file
  fi
done <<< "$RESEARCH_LIST"

# Require 2+ keyword hits — no recency fallback
if [ "$BEST_SCORE" -ge 2 ] && [ -n "$BEST_FILE" ] && [ -f "$BEST_FILE" ]; then
  emit_research "$BEST_FILE"
fi

exit 0
