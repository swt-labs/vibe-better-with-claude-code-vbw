#!/bin/bash
set -euo pipefail
# doctor-cleanup.sh — Runtime health scan and cleanup
#
# Usage:
#   doctor-cleanup.sh scan     # Report stale teams, orphans, dangling PIDs, stale markers
#   doctor-cleanup.sh cleanup  # Clean up reported issues
#
# Output format: {category}|{item}|{detail}

ACTION="${1:-scan}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-$(pwd)/.vbw-planning}"
LOG_FILE="$PLANNING_DIR/.hook-errors.log"

# Resolve CLAUDE_DIR
. "$SCRIPT_DIR/resolve-claude-dir.sh"

TEAMS_DIR="$CLAUDE_DIR/teams"
STALE_THRESHOLD_SECONDS=7200  # 2 hours

# Platform-specific stat command for modification time
get_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    stat -c %Y "$file" 2>/dev/null || echo "0"
  fi
}

# Logging helper (fail-silent)
log_action() {
  local msg="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] Doctor cleanup: $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- SCAN MODE ---
scan_stale_teams() {
  [ ! -d "$TEAMS_DIR" ] && return 0

  local now
  now=$(date +%s)

  for team_dir in "$TEAMS_DIR"/*; do
    [ ! -d "$team_dir" ] && continue

    local team_name
    team_name=$(basename "$team_dir")

    # Check for orphaned/configless team directories (no config.json = corrupted residual)
    if [ ! -f "$team_dir/config.json" ]; then
      echo "orphaned_team|$team_name|no config.json (ghost team residual)"
      continue
    fi

    local inbox_dir="$team_dir/inboxes"

    [ ! -d "$inbox_dir" ] && continue

    # Get most recent file in inboxes
    local inbox_mtime=0
    for inbox_file in "$inbox_dir"/*; do
      [ ! -e "$inbox_file" ] && continue
      local file_mtime
      file_mtime=$(get_mtime "$inbox_file")
      [ "$file_mtime" -gt "$inbox_mtime" ] && inbox_mtime=$file_mtime
    done

    # Check if stale
    local age=$((now - inbox_mtime))
    [ "$age" -lt "$STALE_THRESHOLD_SECONDS" ] && continue

    # Calculate age display
    local hours=$((age / 3600))
    local minutes=$(((age % 3600) / 60))
    echo "stale_team|$team_name|age: ${hours}h ${minutes}m"
  done
}

scan_orphaned_processes() {
  # Find processes with PPID=1 and comm containing "claude"
  ps -eo pid,ppid,comm 2>/dev/null | awk '$2 == 1 && $3 ~ /claude/ {print "orphan_process|" $1 "|" $3}' || true
}

scan_dangling_pids() {
  local pid_file="$PLANNING_DIR/.agent-pids"
  [ ! -f "$pid_file" ] && return 0

  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    # Validate numeric
    echo "$pid" | grep -qE '^[0-9]+$' || continue
    # Check if process exists
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "dangling_pid|$pid|dead"
    fi
  done < "$pid_file"
}

scan_stale_markers() {
  # Check watchdog PID
  local watchdog_pid_file="$PLANNING_DIR/.watchdog-pid"
  if [ -f "$watchdog_pid_file" ]; then
    local watchdog_pid
    watchdog_pid=$(cat "$watchdog_pid_file" 2>/dev/null)
    if [ -n "$watchdog_pid" ] && ! kill -0 "$watchdog_pid" 2>/dev/null; then
      echo "stale_marker|.watchdog-pid|dead process"
    fi
  fi

  # Check compaction marker age
  local compaction_marker="$PLANNING_DIR/.compaction-marker"
  if [ -f "$compaction_marker" ]; then
    local marker_mtime
    marker_mtime=$(get_mtime "$compaction_marker")
    local now
    now=$(date +%s)
    local age=$((now - marker_mtime))
    if [ "$age" -gt 60 ]; then
      echo "stale_marker|.compaction-marker|age: ${age}s"
    fi
  fi

  # Check active agent marker
  local active_agent_file="$PLANNING_DIR/.active-agent"
  if [ -f "$active_agent_file" ]; then
    echo "stale_marker|.active-agent|potentially stale"
  fi
}

scan_stale_worktrees() {
  local worktrees_dir
  worktrees_dir="$(pwd)/.vbw-worktrees"
  [ ! -d "$worktrees_dir" ] && return 0

  local now
  now=$(date +%s)

  for wt_dir in "$worktrees_dir"/*/; do
    [ ! -d "$wt_dir" ] && continue
    local wt_name
    wt_name=$(basename "$wt_dir")
    local wt_mtime
    wt_mtime=$(get_mtime "$wt_dir")
    local age=$((now - wt_mtime))
    if [ "$age" -gt "$STALE_THRESHOLD_SECONDS" ]; then
      local hours=$((age / 3600))
      local minutes=$(((age % 3600) / 60))
      echo "stale_worktree|$wt_name|age: ${hours}h ${minutes}m"
    fi
  done
}

# --- CLEANUP MODE ---
cleanup_stale_teams() {
  bash "$SCRIPT_DIR/clean-stale-teams.sh" 2>&1 | while IFS= read -r line; do
    log_action "$line"
  done
  log_action "stale teams cleanup completed"
}

cleanup_orphaned_processes() {
  local orphans
  orphans=$(scan_orphaned_processes)
  [ -z "$orphans" ] && return 0

  local count=0
  local _category _pid _comm
  echo "$orphans" | while IFS='|' read -r _category _pid _comm; do
    [ -z "$_pid" ] && continue

    # SIGTERM first
    if kill -TERM "$_pid" 2>/dev/null; then
      log_action "sent SIGTERM to orphan process $_pid ($_comm)"
      count=$((count + 1))
    fi
  done

  # Wait 2 seconds
  sleep 2

  # SIGKILL survivors
  echo "$orphans" | while IFS='|' read -r _category _pid _comm; do
    [ -z "$_pid" ] && continue
    if kill -0 "$_pid" 2>/dev/null; then
      kill -KILL "$_pid" 2>/dev/null && log_action "sent SIGKILL to survivor process $_pid ($_comm)"
    fi
  done

  log_action "orphaned processes cleanup completed"
}

cleanup_dangling_pids() {
  local pid_file="$PLANNING_DIR/.agent-pids"
  [ ! -f "$pid_file" ] && return 0

  local temp_file="${pid_file}.tmp"
  local pruned=0

  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    echo "$pid" | grep -qE '^[0-9]+$' || continue

    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid" >> "$temp_file"
    else
      pruned=$((pruned + 1))
    fi
  done < "$pid_file"

  if [ -f "$temp_file" ]; then
    mv "$temp_file" "$pid_file"
  else
    rm -f "$pid_file"
  fi

  log_action "pruned $pruned dead PIDs from .agent-pids"
}

cleanup_stale_markers() {
  local markers=(".watchdog-pid" ".compaction-marker" ".active-agent")
  local removed=0

  for marker in "${markers[@]}"; do
    local marker_file="$PLANNING_DIR/$marker"
    if [ -f "$marker_file" ]; then
      # Check if marker is actually stale (reuse scan logic)
      local is_stale=false

      case "$marker" in
        .watchdog-pid)
          local watchdog_pid
          watchdog_pid=$(cat "$marker_file" 2>/dev/null)
          [ -n "$watchdog_pid" ] && ! kill -0 "$watchdog_pid" 2>/dev/null && is_stale=true
          ;;
        .compaction-marker)
          local marker_mtime
          marker_mtime=$(get_mtime "$marker_file")
          local now
          now=$(date +%s)
          local age=$((now - marker_mtime))
          [ "$age" -gt 60 ] && is_stale=true
          ;;
        .active-agent)
          is_stale=true  # Always considered stale in cleanup
          ;;
      esac

      if [ "$is_stale" = true ]; then
        rm -f "$marker_file" 2>/dev/null && {
          log_action "removed stale marker: $marker"
          removed=$((removed + 1))
        }
      fi
    fi
  done

  log_action "stale markers cleanup completed: $removed removed"
}

cleanup_stale_worktrees() {
  local worktrees_dir
  worktrees_dir="$(pwd)/.vbw-worktrees"
  [ ! -d "$worktrees_dir" ] && return 0

  local stale
  stale=$(scan_stale_worktrees)
  [ -z "$stale" ] && return 0

  local _category _wt_name _detail
  echo "$stale" | while IFS='|' read -r _category _wt_name _detail; do
    [ -z "$_wt_name" ] && continue
    # Parse phase and plan from name (format: {phase}-{plan})
    local wt_phase wt_plan
    wt_phase=$(echo "$_wt_name" | cut -d'-' -f1)
    wt_plan=$(echo "$_wt_name" | cut -d'-' -f2)
    bash "$SCRIPT_DIR/worktree-cleanup.sh" "$wt_phase" "$wt_plan" 2>/dev/null && \
      log_action "cleaned stale worktree: $_wt_name ($_detail)" || \
      log_action "failed to clean worktree: $_wt_name (fail-silent)"
  done

  log_action "stale worktrees cleanup completed"
}

# --- MAIN ---
case "$ACTION" in
  scan)
    scan_stale_teams
    scan_orphaned_processes
    scan_dangling_pids
    scan_stale_markers
    scan_stale_worktrees
    ;;
  cleanup)
    log_action "cleanup started"

    # Collect counts before cleanup
    teams_count=$(scan_stale_teams | wc -l | tr -d ' ')
    orphan_count=$(scan_orphaned_processes | wc -l | tr -d ' ')
    pid_count=$(scan_dangling_pids | wc -l | tr -d ' ')
    marker_count=$(scan_stale_markers | wc -l | tr -d ' ')
    worktree_count=$(scan_stale_worktrees | wc -l | tr -d ' ')

    cleanup_stale_teams
    cleanup_orphaned_processes
    cleanup_dangling_pids
    cleanup_stale_markers
    cleanup_stale_worktrees

    log_action "cleanup complete: teams=$teams_count, orphans=$orphan_count, pids=$pid_count, markers=$marker_count, worktrees=$worktree_count"
    ;;
  *)
    echo "Usage: $0 {scan|cleanup}" >&2
    exit 1
    ;;
esac

exit 0
