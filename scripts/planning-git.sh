#!/usr/bin/env bash
set -euo pipefail

# planning-git.sh — Manage planning artifact git behavior from config.
#
# Usage:
#   planning-git.sh sync-ignore [CONFIG_FILE]
#   planning-git.sh commit-boundary <action> [CONFIG_FILE]
#   planning-git.sh push-after-phase [CONFIG_FILE]

COMMAND="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

read_config() {
  local config_file="$1"

  CFG_PLANNING_TRACKING="manual"
  CFG_AUTO_PUSH="never"

  if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
    CFG_PLANNING_TRACKING=$(jq -r '.planning_tracking // "manual"' "$config_file" 2>/dev/null || echo "manual")
    CFG_AUTO_PUSH=$(jq -r '.auto_push // "never"' "$config_file" 2>/dev/null || echo "never")
  fi
}

ensure_transient_ignore() {
  local planning_dir=".vbw-planning"
  local ignore_file="$planning_dir/.gitignore"

  [ -d "$planning_dir" ] || return 0

  cat > "$ignore_file" <<'EOF'
# VBW transient runtime artifacts
.execution-state.json
.execution-state.json.tmp
.context-*.md
.contracts/
.locks/
.token-state/

# Session & agent tracking
.vbw-session
.active-agent
.active-agent-count
.active-agent-count.lock/
.agent-pids

# Metrics & cost tracking
.metrics/
.cost-ledger.json

# Caching
.cache/

# Artifacts & events (v2/v3 feature-gated)
.artifacts/
.events/
.event-log.jsonl

# Snapshots & recovery
.snapshots/

# Logging & markers
.hook-errors.log
.compaction-marker
.session-log.jsonl
.session-log.jsonl.tmp
.notification-log.jsonl
.watchdog-pid
.watchdog.log
.claude-md-migrated
.tmux-mode-patched

# Baselines
.baselines/

# Codebase mapping
codebase/
EOF
}

sync_root_ignore() {
  local mode="$1"
  local root_ignore=".gitignore"

  if [ "$mode" = "ignore" ]; then
    if [ ! -f "$root_ignore" ]; then
      printf '.vbw-planning/\n' > "$root_ignore"
      return 0
    fi

    if ! grep -qx '\.vbw-planning/' "$root_ignore"; then
      printf '\n.vbw-planning/\n' >> "$root_ignore"
    fi
    return 0
  fi

  if [ "$mode" = "commit" ] && [ -f "$root_ignore" ]; then
    local tmp
    tmp=$(mktemp)
    awk '$0 != ".vbw-planning/"' "$root_ignore" > "$tmp"
    mv "$tmp" "$root_ignore"
  fi
}

push_if_configured() {
  local push_mode="$1"
  [ "$push_mode" = "always" ] || return 0

  # Skip if current branch has no upstream yet.
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    return 0
  fi

  git push
}

if [ -z "$COMMAND" ]; then
  echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
  exit 1
fi

case "$COMMAND" in
  sync-ignore)
    CONFIG_FILE="${ARG2:-.vbw-planning/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"
    sync_root_ignore "$CFG_PLANNING_TRACKING"

    if [ "$CFG_PLANNING_TRACKING" = "commit" ]; then
      ensure_transient_ignore
    fi
    ;;

  commit-boundary)
    ACTION="${ARG2:-}"
    CONFIG_FILE="${ARG3:-.vbw-planning/config.json}"

    if [ -z "$ACTION" ]; then
      echo "Usage: planning-git.sh commit-boundary <action> [CONFIG_FILE]" >&2
      exit 1
    fi

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_PLANNING_TRACKING" != "commit" ]; then
      exit 0
    fi

    ensure_transient_ignore

    if [ -d ".vbw-planning" ]; then
      git add .vbw-planning
    fi

    if [ -f "CLAUDE.md" ]; then
      git add CLAUDE.md
    fi

    if git diff --cached --quiet; then
      exit 0
    fi

    git commit -m "chore(vbw): $ACTION"
    push_if_configured "$CFG_AUTO_PUSH"
    ;;

  push-after-phase)
    CONFIG_FILE="${ARG2:-.vbw-planning/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_AUTO_PUSH" = "after_phase" ]; then
      # Skip if current branch has no upstream yet.
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push
      fi
    fi
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
    exit 1
    ;;
esac

exit 0