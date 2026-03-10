#!/usr/bin/env bash
# clean-stale-teams.sh — Clean stale agent team directories
#
# Scans ~/.claude/teams/ for directories with inboxes older than 2 hours.
# Removes stale teams atomically (mv to temp, then rm).
# Called from session-start.sh to prevent state pollution from dead sessions.

set -euo pipefail

# Resolve CLAUDE_DIR
. "$(dirname "$0")/resolve-claude-dir.sh"

TEAMS_DIR="$CLAUDE_DIR/teams"
TASKS_DIR="$CLAUDE_DIR/tasks"
STALE_THRESHOLD_SECONDS=7200  # 2 hours
PLANNING_DIR="${VBW_PLANNING_DIR:-$(pwd)/.vbw-planning}"
LOG_FILE="$PLANNING_DIR/.hook-errors.log"

# Graceful exit if teams directory doesn't exist
if [ ! -d "$TEAMS_DIR" ]; then
  exit 0
fi

# Temporary directory for atomic cleanup
TEMP_DIR="/tmp/vbw-stale-teams-$$"
mkdir -p "$TEMP_DIR"

# Logging helper (fail-silent)
log_cleanup() {
  local msg="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Counters
teams_cleaned=0
tasks_cleaned=0

# Platform-specific stat command for modification time
get_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    stat -c %Y "$file" 2>/dev/null || echo "0"
  fi
}

# Current timestamp
NOW=$(date +%s)

# Pass 1: Immediately clean configless team directories (orphaned/corrupted).
# These are definitively dead — no config.json means TeamDelete left residuals
# or the orchestrator rm'd config before TeamDelete. No time threshold needed.
for team_dir in "$TEAMS_DIR"/*; do
  [ ! -d "$team_dir" ] && continue

  team_name=$(basename "$team_dir")

  # Only target VBW-owned teams
  case "$team_name" in vbw-*) ;; *) continue ;; esac

  # If config.json exists, this is a live or stale-but-intact team — skip (handled in pass 2)
  [ -f "$team_dir/config.json" ] && continue

  # Configless directory — orphaned residual. Clean immediately.
  if mv "$team_dir" "$TEMP_DIR/$team_name" 2>/dev/null; then
    teams_cleaned=$((teams_cleaned + 1))
    log_cleanup "Orphaned team cleanup (no config.json): $team_name"
  fi

  # Also remove paired tasks directory if it exists
  if [ -d "$TASKS_DIR/$team_name" ]; then
    if mv "$TASKS_DIR/$team_name" "$TEMP_DIR/${team_name}-tasks" 2>/dev/null; then
      tasks_cleaned=$((tasks_cleaned + 1))
      log_cleanup "Orphaned tasks cleanup: $team_name (paired with configless team)"
    fi
  fi
done

# Pass 2: Clean stale VBW teams (have config.json but inbox older than threshold)
# Same vbw-* scope as pass 1 — VBW should not remove other plugins' teams.
for team_dir in "$TEAMS_DIR"/*; do
  [ ! -d "$team_dir" ] && continue

  team_name=$(basename "$team_dir")

  # Only target VBW-owned teams
  case "$team_name" in vbw-*) ;; *) continue ;; esac

  inbox_dir="$team_dir/inboxes"

  # Skip if no inboxes directory
  [ ! -d "$inbox_dir" ] && continue

  # Get most recent file in inboxes
  inbox_mtime=0
  for inbox_file in "$inbox_dir"/*; do
    [ ! -e "$inbox_file" ] && continue
    file_mtime=$(get_mtime "$inbox_file")
    [ "$file_mtime" -gt "$inbox_mtime" ] && inbox_mtime=$file_mtime
  done

  # Skip if inbox has recent activity
  age=$((NOW - inbox_mtime))
  [ "$age" -lt "$STALE_THRESHOLD_SECONDS" ] && continue

  # Calculate stale duration in hours
  stale_hours=$((age / 3600))

  # Stale team detected — atomic cleanup
  if mv "$team_dir" "$TEMP_DIR/$team_name" 2>/dev/null; then
    teams_cleaned=$((teams_cleaned + 1))
    log_cleanup "Stale team cleanup: $team_name (stale for ${stale_hours}h)"
  fi

  # Also remove paired tasks directory if it exists
  tasks_dir="$TASKS_DIR/$team_name"
  if [ -d "$tasks_dir" ]; then
    if mv "$tasks_dir" "$TEMP_DIR/${team_name}-tasks" 2>/dev/null; then
      tasks_cleaned=$((tasks_cleaned + 1))
      log_cleanup "Stale tasks cleanup: $team_name (paired with team)"
    fi
  fi
done

# Remove temp directory
rm -rf "$TEMP_DIR" 2>/dev/null || true

# Log summary
if [ "$teams_cleaned" -gt 0 ] || [ "$tasks_cleaned" -gt 0 ]; then
  log_cleanup "Summary: $teams_cleaned teams cleaned, $tasks_cleaned tasks removed"
fi

exit 0
